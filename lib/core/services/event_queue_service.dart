import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:geocercas_app/core/models/geofence_event.dart';
import 'package:geocercas_app/core/services/notification_service.dart';
import 'package:geocercas_app/core/services/friendly_messages.dart';
import 'package:geocercas_app/core/services/e2e_encryption_service.dart';

/// Cola de eventos con persistencia local y cifrado
class EventQueueService {
  static final EventQueueService _instance = EventQueueService._internal();
  factory EventQueueService() => _instance;
  EventQueueService._internal();

  late Box<Map> _eventBox;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  //  Clave de cifrado
  final encrypt.Key _encryptionKey = encrypt.Key.fromUtf8('my32lengthsupersecretnooneknows1');
  final encrypt.IV _iv = encrypt.IV.fromLength(16);

  /// Inicializar de la base de datos local
  Future<void> init() async {
    _eventBox = await Hive.openBox<Map>('geofence_events');
    debugPrint('Cola de eventos inicializada: ${_eventBox.length} eventos pendientes');
  }

  /// Evento SOS con prioridad máxima y notifica a observadores
  Future<void> sendSOS({
    required String objectiveId,
    required double latitude,
    required double longitude,
    double accuracy = 0.0,
    double velocity = 0.0,
    String? message,
  }) async {
    final eventId = 'sos_${DateTime.now().millisecondsSinceEpoch}';
    final encryptedPayload = _encryptLocation(latitude, longitude);
    
    final eventData = {
      'id': eventId,
      'objective_id': objectiveId,
      'geofence_id': 'sos_manual',
      'geofence_name': 'SOS Manual',
      'severity': 'critical',
      'event_type': 'sos',
      'explanation': ' Botón SOS activado manualmente por el usuario. ${message ?? "Solicitud de auxilio inmediato."}',
      'encrypted_location': encryptedPayload,
      'latitude': latitude,
      'longitude': longitude,
      'hdop': accuracy,
      'velocity': velocity,
      'timestamp': DateTime.now().toIso8601String(),
      'sync_status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
      'priority': 0,
      'is_sos': true,
    };
    
    await _eventBox.put(eventId, eventData);
    debugPrint('SOS encolado con prioridad máxima: $eventId');
    
    // Activar estado SOS en Firestore
    try {
      await _firestore.collection('users').doc(objectiveId).update({
        'sos_active': true,
        'sos_activated_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      debugPrint('Estado SOS activado para $objectiveId');
    } catch (e) {
      debugPrint('Error al activar estado SOS: $e');
    }
    
    // Notificar a todos los observadores
    await _notifyObserversOfSOS(
      objectiveId: objectiveId,
      latitude: latitude,
      longitude: longitude,
    );
    
    // Sincronizar evento con Firestore
    await syncPendingEvents();
  }
  /// Cifra coordenadas para almacenamiento local
  String _encryptLocation(double latitude, double longitude) {
    final encrypter = encrypt.Encrypter(encrypt.AES(_encryptionKey));
    final payload = jsonEncode({'latitude': latitude, 'longitude': longitude});
    final encrypted = encrypter.encrypt(payload, iv: _iv);
    return encrypted.base64;
  }

  ///  Enviar SOS a todos los observadores vinculados
  Future<void> _notifyObserversOfSOS({
    required String objectiveId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final linksSnapshot = await _firestore
          .collection('monitoring_links')
          .where('objective_id', isEqualTo: objectiveId)
          .where('status', isEqualTo: 'active')
          .get();

      if (linksSnapshot.docs.isEmpty) {
        debugPrint('No hay observadores vinculados para notificar SOS');
        return;
      }

      debugPrint('Enviando SOS a ${linksSnapshot.docs.length} observadores...');

      for (final linkDoc in linksSnapshot.docs) {
        final observerUid = linkDoc.data()['observer_id'] as String;
        
        try {
          final observerDoc = await _firestore.collection('users').doc(observerUid).get();
          final targetToken = observerDoc.data()?['fcm_token'] as String?;
          
          if (targetToken != null && targetToken.isNotEmpty) {
            final title = FriendlyMessages.getPushTitle('sos', 'critical');
            final body = FriendlyMessages.getPushBody('', 'sos', 'critical');
            
            await NotificationService.sendPushNotification(
              targetToken: targetToken,
              title: title,
              body: body,
              data: {
                'type': 'sos_alert',
                'objective_id': objectiveId,
                'latitude': latitude.toString(),
                'longitude': longitude.toString(),
                'priority': 'critical',
              },
            );
            debugPrint('SOS enviado a observador $observerUid');
          } else {
            debugPrint('Observador $observerUid no tiene token FCM');
          }
        } catch (e) {
          debugPrint('Error al notificar observador $observerUid: $e');
        }
      }
    } catch (e) {
      debugPrint('Error general al notificar SOS: $e');
    }
  }

  ///  Enviar alerta a los observadores
  Future<void> notifyObserversOfAlert({
    required String objectiveId,
    required String severity,
    required String geofenceName,
    required String explanation,
    required double latitude,
    required double longitude,
    required String eventType,
  }) async {
    try {
      final linksSnapshot = await _firestore
          .collection('monitoring_links')
          .where('objective_id', isEqualTo: objectiveId)
          .where('status', isEqualTo: 'active')
          .get();

      if (linksSnapshot.docs.isEmpty) return;

      final title = FriendlyMessages.getPushTitle(eventType, severity);
      final body = FriendlyMessages.getPushBody(geofenceName, eventType, severity);

      for (final linkDoc in linksSnapshot.docs) {
        final observerUid = linkDoc.data()['observer_id'] as String;
        
        try {
          final observerDoc = await _firestore.collection('users').doc(observerUid).get();
          final targetToken = observerDoc.data()?['fcm_token'] as String?;
          
          if (targetToken != null && targetToken.isNotEmpty) {
            await NotificationService.sendPushNotification(
              targetToken: targetToken,
              title: title,
              body: body,
              data: {
                'type': severity == 'critical' ? 'alert_critical' : 'alert_preventive',
                'objective_id': objectiveId,
                'geofence_name': geofenceName,
                'latitude': latitude.toString(),
                'longitude': longitude.toString(),
              },
            );
          }
        } catch (e) {
          debugPrint('Error al notificar alerta a $observerUid: $e');
        }
      }
      
      // Notificar al objetivo sobre entrada a zona riesgosa
      if (eventType.startsWith('entry_') && eventType.endsWith('_risk')) {
        await _notifyObjectiveOfRiskZone(
          objectiveId: objectiveId,
          severity: severity,
          geofenceName: geofenceName,
          explanation: explanation,
          latitude: latitude,
          longitude: longitude,
          eventType: eventType,
        );
      }
    } catch (e) {
      debugPrint('Error general al notificar alerta: $e');
    }
  }

  Future<void> _notifyObjectiveOfRiskZone({
    required String objectiveId,
    required String severity,
    required String geofenceName,
    required String explanation,
    required double latitude,
    required double longitude,
    required String eventType,
  }) async {
    try {
      final objectiveDoc = await _firestore.collection('users').doc(objectiveId).get();
      final targetToken = objectiveDoc.data()?['fcm_token'] as String?;
      
      if (targetToken == null || targetToken.isEmpty) {
        debugPrint('El objetivo $objectiveId no tiene token FCM registrado');
        return;
      }

      final title = severity == 'critical'
          ? ' ¡Atención! Zona de Riesgo'
          : ' Precaución - Zona de Riesgo';
      
      final body = 'Has ingresado a "$geofenceName", una zona identificada como de riesgo. '
          'Mantente alerta y considera cambiar tu ruta si es posible.';

      await NotificationService.sendPushNotification(
        targetToken: targetToken,
        title: title,
        body: body,
        data: {
          'type': 'objective_risk_zone_entry',
          'objective_id': objectiveId,
          'geofence_name': geofenceName,
          'severity': severity,
          'latitude': latitude.toString(),
          'longitude': longitude.toString(),
        },
      );
      
      debugPrint('Notificación de zona riesgosa enviada al objetivo $objectiveId');
    } catch (e) {
      debugPrint('Error al notificar al objetivo sobre zona riesgosa: $e');
    }
  }

  /// Agrega un evento a la cola local
  Future<void> enqueueEvent(GeofenceEvent event) async {
    final eventId = event.id;
    final encryptedPayload = _encryptPayload(event);
    
    await _eventBox.put(eventId, {
      'id': eventId,
      'objective_id': event.objectiveId,
      'geofence_id': event.geofenceId,
      'geofence_name': event.geofenceName,
      'severity': event.severity.name,
      'event_type': event.eventType,
      'explanation': event.explanation,
      'encrypted_location': encryptedPayload, 
      'hdop': event.hdop,
      'velocity': event.velocity,
      'timestamp': event.timestamp.toIso8601String(),
      'sync_status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
      'priority': _getPriority(event.severity), // 1=crítico, 2=preventivo, 3=informativo
    });
    
    debugPrint('Evento encolado: ${event.severity.name} - ${event.geofenceName}');
  }

  /// Sincroniza eventos pendientes con Firestore
  Future<void> syncPendingEvents() async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('Usuario no autenticado, no se puede sincronizar');
      return;
    }

    final pendingEvents = _eventBox.values
        .where((event) => event['sync_status'] == 'pending')
        .toList()
      ..sort((a, b) {
        final priorityA = (a['priority'] as num?)?.toInt() ?? 1;
        final priorityB = (b['priority'] as num?)?.toInt() ?? 1;
        return priorityA.compareTo(priorityB);
      });

    if (pendingEvents.isEmpty) {
      debugPrint('No hay eventos pendientes de sincronización');
      return;
    }

    debugPrint('Sincronizando ${pendingEvents.length} eventos...');

    int successCount = 0;
    int failCount = 0;

    for (final eventData in pendingEvents) {
      try {
        final eventId = eventData['id'] as String;
        final objectiveId = eventData['objective_id'] as String;
        
        //  1. Manejo de coordenadas nulas
        final latRaw = eventData['latitude'];
        final lngRaw = eventData['longitude'];
        
        if (latRaw == null || lngRaw == null) {
          debugPrint('Evento sin coordenadas válidas, eliminando de la cola: $eventId');
          // Eliminar evento corrupto
          await _eventBox.delete(eventId); 
          failCount++;
          continue;
        }
        
        //  2. Cast a double
        final latitude = (latRaw as num).toDouble();
        final longitude = (lngRaw as num).toDouble();
        
        //  3. Cifrar coordenadas
        final encryptedLocation = E2EEncryptionService().encryptLocation(
          objectiveId: objectiveId,
          latitude: latitude,
          longitude: longitude,
        );

        //  4. Subir a Firestore  
        await _firestore.collection('events').doc(eventId).set({
          'objective_id': objectiveId,
          'geofence_id': eventData['geofence_id'],
          'geofence_name': eventData['geofence_name'],
          'severity': eventData['severity'],
          'event_type': eventData['event_type'],
          'explanation': eventData['explanation'],
          
          // Coordenadas cifradas
          'encrypted_location': encryptedLocation,
          
          'hdop': (eventData['hdop'] as num?)?.toDouble() ?? 0.0,
          'velocity': (eventData['velocity'] as num?)?.toDouble() ?? 0.0,
          'timestamp': Timestamp.fromDate(DateTime.parse(eventData['timestamp'] as String)),
          'sync_status': 'synced',
          'synced_at': FieldValue.serverTimestamp(),
          'priority': (eventData['priority'] as num?)?.toInt() ?? 1,
        });

        //  5. Marcar como sincronizado localmente
        await _eventBox.put(eventId, {
          ...eventData,
          'sync_status': 'synced',
        });
        
        successCount++;
        debugPrint('Evento sincronizado con cifrado E2E: $eventId');
      } catch (e, stackTrace) {
        debugPrint('Error al sincronizar evento: $e');
        debugPrint('Stack: $stackTrace');
        failCount++;
      }
    }

    debugPrint('Sincronización completada: $successCount exitosos, $failCount fallidos');
  }
  /// Obtiene eventos locales para visualización
  List<GeofenceEvent> getLocalEvents({int limit = 50}) {
    final events = _eventBox.values
        .map((data) => _mapToEvent(data))
        .where((event) => event != null)
        .cast<GeofenceEvent>()
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp)); 
    
    return events.take(limit).toList();
  }

  String _encryptPayload(GeofenceEvent event) {
    final encrypter = encrypt.Encrypter(encrypt.AES(_encryptionKey));
    final payload = jsonEncode({
      'latitude': event.latitude,
      'longitude': event.longitude,
    });
    final encrypted = encrypter.encrypt(payload, iv: _iv);
    return encrypted.base64;
  }

  Map<String, double> _decryptPayload(String encryptedPayload) {
    final encrypter = encrypt.Encrypter(encrypt.AES(_encryptionKey));
    final decrypted = encrypter.decrypt64(encryptedPayload, iv: _iv);
    final payload = jsonDecode(decrypted) as Map<String, dynamic>;
    return {
      'latitude': payload['latitude'] as double,
      'longitude': payload['longitude'] as double,
    };
  }

  int _getPriority(EventSeverity severity) {
    switch (severity) {
      case EventSeverity.critical: return 1;
      case EventSeverity.preventive: return 2;
      case EventSeverity.informative: return 3;
    }
  }

  GeofenceEvent? _mapToEvent(Map data) {
    try {
      //  Verificar que el payload cifrado exista y sea válido
      final encryptedPayload = data['encrypted_location'] as String?;
      if (encryptedPayload == null || encryptedPayload.isEmpty) {
        debugPrint('Evento sin payload cifrado: ${data['id']}');
        return null;
      }

      //  Intentar descifrar con manejo de errores
      Map<String, double> decryptedLocation;
      try {
        decryptedLocation = _decryptPayload(encryptedPayload);
      } catch (e) {
        debugPrint('Error al descifrar evento ${data['id']}: $e');
        debugPrint('Payload corrupto o clave incompatible');
        
        //  Eliminar evento corrupto de la base de datos
        _eventBox.delete(data['id']);
        debugPrint('️Evento corrupto eliminado: ${data['id']}');
        
        return null;
      }
      
      return GeofenceEvent(
        id: data['id'] as String,
        objectiveId: data['objective_id'] as String,
        geofenceId: data['geofence_id'] as String,
        geofenceName: data['geofence_name'] as String,
        severity: EventSeverity.values.firstWhere(
          (e) => e.name == data['severity'],
          orElse: () => EventSeverity.informative,
        ),
        eventType: data['event_type'] as String,
        explanation: data['explanation'] as String,
        latitude: decryptedLocation['latitude']!,
        longitude: decryptedLocation['longitude']!,
        hdop: (data['hdop'] as num).toDouble(),
        velocity: (data['velocity'] as num).toDouble(),
        timestamp: DateTime.parse(data['timestamp'] as String),
        syncStatus: data['sync_status'] as String? ?? 'pending',
      );
    } catch (e) {
      debugPrint('Error al mapear evento ${data['id']}: $e');
      return null;
    }
  }
  /// Limpia eventos con objective_id inválido
  Future<void> cleanInvalidEvents() async {
    int deletedCount = 0;
    
    for (final key in _eventBox.keys) {
      final eventData = _eventBox.get(key);
      if (eventData != null) {
        final objectiveId = eventData['objective_id'] as String?;
        if (objectiveId == null || objectiveId == 'current_user' || objectiveId.isEmpty) {
          await _eventBox.delete(key);
          deletedCount++;
        }
      }
    }
    
    debugPrint('Limpiados $deletedCount eventos inválidos de Hive');
  }
}