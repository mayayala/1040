import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocercas_app/data/services/geofence_service.dart';
import 'package:geocercas_app/core/services/decision_engine.dart';
import 'package:geocercas_app/core/services/event_queue_service.dart';
import 'package:geocercas_app/core/services/e2e_encryption_service.dart';
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionStream;
  Timer? _periodicUpdateTimer;
  bool _isTracking = false;
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final EventQueueService _eventQueue = EventQueueService();

  final _locationController = StreamController<Position>.broadcast();
  Stream<Position> get locationStream => _locationController.stream;

  LatLng? _lastKnownPosition;
  DateTime? _lastLocationUpdate;
  bool _isSOSActive = false;

  StreamSubscription? _geofencesSubscription;
  List<Map<String, dynamic>> _activeGeofences = [];
  bool _hasSavedInitialLocation = false; 

  Future<LocationPermission> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    }
    return await Geolocator.checkPermission();
  }

  Future<void> startBackgroundTracking() async {
    if (_isTracking) {
      debugPrint('startBackgroundTracking: Ya está rastreando, omitiendo.');
      return;
    }

    final permission = await requestPermission();
    debugPrint('Permiso de ubicación obtenido: $permission');
    
    if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
      debugPrint('Permiso de ubicación denegado o no disponible: $permission');
      throw Exception('Permiso de ubicación denegado');
    }

    await _eventQueue.init();

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10, // Requiere moverse 10m para emitir
      ),
    ).listen((Position position) {
      debugPrint('Geolocator stream emitió: ${position.latitude}, ${position.longitude}');
      _handleLocationUpdate(position);
    }, onError: (error) {
      debugPrint('Error en Geolocator stream: $error');
    });

    _startPeriodicUpdateTimer();
    _startGeofenceListener();

    _isTracking = true;
    debugPrint('Rastreo de ubicación adaptativo iniciado correctamente');
  }

  // Revisar cada 1 minuto si es necesario forzar una actualización
  void _startPeriodicUpdateTimer() {
    _periodicUpdateTimer?.cancel();
    _periodicUpdateTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      await _checkAndForceUpdate();
    });
  }

  Future<void> _checkAndForceUpdate() async {
    debugPrint('_checkAndForceUpdate: Verificando si es necesario forzar actualización...');
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('_checkAndForceUpdate: Usuario no autenticado');
      return;
    }

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final userData = userDoc.data();
    if (userData == null) {
      debugPrint('_checkAndForceUpdate: Datos de usuario no encontrados');
      return;
    }

    final isObjective = (userData['role_tags'] as List?)?.contains('objective') == true;
    if (!isObjective) return;

    final isLiveModeActive = userData['live_mode_active'] == true;
    final isSOSActive = userData['sos_active'] == true;
    
    int requiredIntervalSeconds = 300;
    
    if (isSOSActive) {
      requiredIntervalSeconds = 60;
      debugPrint('Modo SOS activo: intervalo de 60s');
    } else if (isLiveModeActive) {
      requiredIntervalSeconds = 60;
      debugPrint('Modo En Vivo activo: intervalo de 60s');
    } else {
      final isInRiskZone = _activeGeofences.any((gf) {
        final risk = gf['risk_level'] as String? ?? 'low';
        return _isInsideGeofence(_lastKnownPosition, gf) && (risk == 'medium' || risk == 'high');
      });
      
      if (isInRiskZone) {
        requiredIntervalSeconds = 120;
        debugPrint('Zona de riesgo detectada: intervalo de 120s');
      }
    }

    final now = DateTime.now();
    if (_lastLocationUpdate == null || 
        now.difference(_lastLocationUpdate!).inSeconds >= requiredIntervalSeconds) {
      
      debugPrint('Forzando actualización de ubicación (última fue hace ${_lastLocationUpdate == null ? 'N/A' : now.difference(_lastLocationUpdate!).inSeconds}s)');
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
        );
        debugPrint('Ubicación forzada obtenida: ${position.latitude}, ${position.longitude}');
        
        await _saveEncryptedLocationNow(position);
        
        _lastLocationUpdate = now;
        _lastKnownPosition = LatLng(position.latitude, position.longitude);
        
        _handleLocationUpdate(position);
      } catch (e) {
        debugPrint('Error al forzar actualización: $e');
      }
    } else {
      debugPrint('_checkAndForceUpdate: Aún no es tiempo (faltan ${requiredIntervalSeconds - now.difference(_lastLocationUpdate!).inSeconds}s)');
    }
  }

  void _handleLocationUpdate(Position position) {
    debugPrint('_handleLocationUpdate: Enviando posición al stream local');
    if (!_locationController.isClosed) {
      _locationController.add(position);
    }

    if (position.accuracy < 50.0) {
      _lastKnownPosition = LatLng(position.latitude, position.longitude);
    }

    _lastLocationUpdate = DateTime.now();

    if (!_hasSavedInitialLocation && position.accuracy < 50.0) {
      _hasSavedInitialLocation = true;
      debugPrint('Primera ubicación válida guardada en Firestore');
      _saveEncryptedLocationNow(position);
    }

    _runDecisionEngine(position);
  }

  void _startGeofenceListener() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    _geofencesSubscription?.cancel();
    _geofencesSubscription = GeofenceService().getActiveGeofences(userId).listen((geofences) {
      _activeGeofences = geofences;
      debugPrint('Geocercas activas actualizadas: ${geofences.length}');
    });
  }

  void _runDecisionEngine(Position position) {
    final objectiveId = _auth.currentUser?.uid;
    if (objectiveId == null) return;

    final currentPos = LatLng(position.latitude, position.longitude);
    final now = DateTime.now();

    // 1. PREPARAR CONTEXTO PARA EL MODELO ML
    
    // Variables temporales de tiempo
    final isNight = now.hour >= 22 || now.hour <= 5;
    final isRushHour = (now.hour >= 7 && now.hour <= 9) || (now.hour >= 17 && now.hour <= 19);

    // Variables de análisis de geocercas
    double currentZoneRisk = 0.0;
    double calculatedDistanceFromHome = 0.0;
    bool homeGeofenceFound = false;

    for (var gf in _activeGeofences) {
      final name = (gf['name'] as String? ?? '').toLowerCase();
      final centerData = gf['center'];

      // A. Evaluar riesgo de la zona actual si el usuario está dentro
      if (_isInsideGeofence(currentPos, gf)) {
         final risk = gf['risk_level'] as String? ?? 'low';
         if (risk == 'high') currentZoneRisk = 1.0;
         else if (risk == 'medium' && currentZoneRisk < 1.0) currentZoneRisk = 0.5;
      }

      // B.  NUEVO: Buscar la geocerca de la casa para calcular la distancia
      // Compara si el nombre es exactamente 'casa' o contiene la palabra 'casa' (ej. "Casa de la abuela")
      if (!homeGeofenceFound && (name == 'casa' || name.contains('casa')) && centerData != null) {
        final homeCenter = LatLng(centerData.latitude, centerData.longitude);
        // Calculamos la distancia real en metros desde la posición actual hasta el centro de la casa
        calculatedDistanceFromHome = GeofenceService.calculateDistance(currentPos, homeCenter);
        homeGeofenceFound = true; 
      }
    }

    // Si el usuario no tiene ninguna geocerca llamada "Casa" configurada aún,
    // el valor por defecto se mantendrá seguro en 0.0 para no alterar los scores del árbol.

    // ALIMENTAR EL HISTORIAL DE DECISIÓN CON LOS DATOS REALES CALCULADOS
    DecisionEngine.updatePositionHistory(
      currentPos, 
      now,
      speed: position.speed,
      accuracy: position.accuracy,
      altitude: position.altitude,
      zoneRisk: currentZoneRisk,
      isNight: isNight,
      isRushHour: isRushHour,
      distanceFromHome: calculatedDistanceFromHome,
    );
    
    // 2. EVALUAR EL MOTOR HÍBRIDO
    final events = DecisionEngine.evaluate(
      objectiveId: objectiveId,
      position: position,
      activeGeofences: _activeGeofences,
      isSOSActive: _isSOSActive,
    );

    for (final event in events) {
      debugPrint('EVENTO: ${event.severity.name.toUpperCase()} | ${event.geofenceName}');
      debugPrint('XAI: ${event.explanation}');
      _eventQueue.enqueueEvent(event);
      _trySyncEvents();
    }
  }
  
  void _trySyncEvents() {
    _eventQueue.syncPendingEvents();
  }

  bool _isInsideGeofence(LatLng? position, Map<String, dynamic> geofence) {
    if (position == null) return false;
    final type = geofence['type'] as String? ?? 'polygon';
    
    if (type == 'circle') {
      final center = geofence['center'];
      final radius = geofence['radius'];
      if (center == null || radius == null) return false;
      final centerLatLng = LatLng(center.latitude, center.longitude);
      final distance = GeofenceService.calculateDistance(position, centerLatLng);
      return distance <= (radius as num).toDouble();
    } else if (type == 'polygon') {
      final verticesData = List<Map<String, dynamic>>.from(geofence['vertices'] ?? []);
      if (verticesData.length < 3) return false;
      final vertices = verticesData.map((v) => LatLng(
        (v['lat'] as num).toDouble(),
        (v['lng'] as num).toDouble(),
      )).toList();
      return GeofenceService.isPointInPolygon(position, vertices);
    }
    return false;
  }

  Future<void> stopBackgroundTracking() async {
    if (!_isTracking) return;
    await _positionStream?.cancel();
    _periodicUpdateTimer?.cancel();
    await _geofencesSubscription?.cancel();
    _positionStream = null;
    _periodicUpdateTimer = null;
    _geofencesSubscription = null;
    _isTracking = false;
    debugPrint('Rastreo de ubicación detenido');
  }
  Future<void> _saveEncryptedLocationNow(Position position) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final encryptedLocation = E2EEncryptionService().encryptLocation(
        objectiveId: user.uid,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      await _firestore.collection('users').doc(user.uid).update({
        'encrypted_last_location': encryptedLocation,
        'last_location_timestamp': FieldValue.serverTimestamp(),
        'last_accuracy': position.accuracy,
        'updated_at': FieldValue.serverTimestamp(),
      });
      debugPrint('Ubicación inicial cifrada guardada en Firestore');
    } catch (e) {
      debugPrint('Error al guardar ubicación inicial: $e');
    }
  }
  bool get isTracking => _isTracking;

  void dispose() {
    _locationController.close();
    stopBackgroundTracking();
  }
}