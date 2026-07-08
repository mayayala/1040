import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocercas_app/data/services/link_service.dart';
import 'package:geocercas_app/core/services/e2e_encryption_service.dart';

class AllObjectivesMapScreen extends StatefulWidget {
  const AllObjectivesMapScreen({super.key});

  @override
  State<AllObjectivesMapScreen> createState() => _AllObjectivesMapScreenState();
}

class _AllObjectivesMapScreenState extends State<AllObjectivesMapScreen> {
  final LinkService _linkService = LinkService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  final MapController _mapController = MapController();
  double _currentZoom = 13.0;
  
  // Lista de objetivos con sus ubicaciones
  List<_ObjectiveMarker> _objectiveMarkers = [];
  bool _isLoading = true;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadAllObjectives();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadAllObjectives() async {
    setState(() => _isRefreshing = true);
    
    final observerUid = _auth.currentUser?.uid;
    debugPrint('[MAPA GENERAL] UID del observador: $observerUid');
    
    if (observerUid == null) {
      debugPrint('[MAPA GENERAL] Usuario no autenticado');
      setState(() => _isRefreshing = false);
      return;
    }

    try {
      debugPrint('[MAPA GENERAL] Iniciando escucha de getActiveObjectives...');
      
      _linkService.getActiveObjectives().listen((objectives) async {
        debugPrint('[MAPA GENERAL] Stream emitió ${objectives.length} objetivos crudos');
        
        final markers = <_ObjectiveMarker>[];
        final bounds = <LatLng>[];

        for (final obj in objectives) {
          final objectiveUid = obj['objective_uid'] as String?;
          final displayName = obj['displayName'] as String?;
          
          debugPrint('Procesando: $displayName ($objectiveUid)');
          
          if (objectiveUid == null || displayName == null) {
            debugPrint('Datos incompletos, saltando...');
            continue;
          }
          
          final userDoc = await _firestore.collection('users').doc(objectiveUid).get();
          
          if (!userDoc.exists) {
            debugPrint('Documento del usuario no existe en Firestore');
            continue;
          }
          
          final userData = userDoc.data();
          final encryptedLocation = userData?['encrypted_last_location'] as String?;
          
          if (encryptedLocation != null && encryptedLocation.isNotEmpty) {
            final location = E2EEncryptionService().decryptLocation(
              objectiveId: objectiveUid,
              encryptedData: encryptedLocation,
            );
            
            if (location != null) {
              final position = LatLng(location['latitude']!, location['longitude']!);
              markers.add(_ObjectiveMarker(
                uid: objectiveUid,
                name: displayName,
                position: position,
                isLive: userData?['live_mode_active'] == true,
                lastUpdate: userData?['last_location_timestamp'] as Timestamp?,
              ));
              bounds.add(position);
              debugPrint('Ubicación descifrada y agregada al mapa');
            } else {
              debugPrint('Falló el descifrado de la ubicación');
            }
          } else {
            debugPrint('No hay encrypted_last_location (el objetivo aún no ha enviado ubicación)');
          }
        }

        if (mounted) {
          setState(() {
            _objectiveMarkers = markers;
            _isLoading = false;
            _isRefreshing = false;
          });
          debugPrint('️ [MAPA GENERAL] Renderizando ${markers.length} marcadores');

          if (bounds.isNotEmpty) {
            _fitBounds(bounds);
          }
          
          if (mounted && _isRefreshing == false) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Mapa actualizado: ${markers.length} objetivo(s) con ubicación'),
                duration: const Duration(seconds: 2),
                backgroundColor: markers.isEmpty ? Colors.orange : Colors.green,
              ),
            );
          }
        }
      });
    } catch (e, stackTrace) {
      debugPrint('[MAPA GENERAL] Error fatal al cargar objetivos: $e');
      debugPrint('Stack: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  void _fitBounds(List<LatLng> points) {
    if (points.isEmpty) return;
    
    // Si hay un solo punto, centrar con zoom fijo
    if (points.length == 1) {
      _mapController.move(points.first, 15.0);
      setState(() => _currentZoom = 15.0);
      return;
    }
    
    // Calcular bounds (esquina suroeste y noreste)
    double minLat = points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    double maxLat = points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    double minLng = points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    double maxLng = points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
    
    // Calcular el centro del bounds
    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    final center = LatLng(centerLat, centerLng);
    
    // Calcular el span (distancia) en latitud y longitud
    final latSpan = maxLat - minLat;
    final lngSpan = maxLng - minLng;
    final maxSpan = latSpan > lngSpan ? latSpan : lngSpan;
    
    // Calcular zoom apropiado basado en el span
    double calculatedZoom;
    if (maxSpan < 0.01) {
      calculatedZoom = 16.0; 
    } else if (maxSpan < 0.05) {
      calculatedZoom = 14.0; 
    } else if (maxSpan < 0.2) {
      calculatedZoom = 12.0; 
    } else if (maxSpan < 0.5) {
      calculatedZoom = 10.0; 
    } else {
      calculatedZoom = 8.0; 
    }
    calculatedZoom = calculatedZoom.clamp(1.0, 19.0);
    
    // Mover el mapa con animación suave
    setState(() => _currentZoom = calculatedZoom);
    _mapController.move(center, calculatedZoom);
    
    debugPrint('️ Mapa ajustado: center=($centerLat, $centerLng), zoom=$calculatedZoom');
  }

  void _zoomIn() {
    setState(() => _currentZoom = (_currentZoom + 2).clamp(1.0, 19.0));
    if (_objectiveMarkers.isNotEmpty) {
      final center = _calculateCenter(_objectiveMarkers.map((m) => m.position).toList());
      _mapController.move(center, _currentZoom);
    }
  }

  void _zoomOut() {
    setState(() => _currentZoom = (_currentZoom - 2).clamp(1.0, 19.0));
    if (_objectiveMarkers.isNotEmpty) {
      final center = _calculateCenter(_objectiveMarkers.map((m) => m.position).toList());
      _mapController.move(center, _currentZoom);
    }
  }

  /// Calcula el punto central de una lista de coordenadas
  LatLng _calculateCenter(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(-16.5000, -68.1500);
    final avgLat = points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final avgLng = points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
    return LatLng(avgLat, avgLng);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSmallScreen = MediaQuery.of(context).size.width < 360;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Todos mis Objetivos'),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _loadAllObjectives,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(-16.5000, -68.1500),
              initialZoom: _currentZoom,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.umsa.geocercas',
                maxNativeZoom: 19,
              ),
              MarkerLayer(
                markers: _objectiveMarkers.map((obj) => Marker(
                  point: obj.position,
                  width: 120,
                  height: 130,
                  alignment: Alignment.topCenter,
                  child: _buildObjectiveMarker(obj, isSmallScreen),
                )).toList(),
              ),
            ],
          ),

          // Botones del Zoom
          Positioned(
            right: 12,
            top: 100,
            child: Column(
              children: [
                _buildZoomButton(Icons.add, _zoomIn),
                const SizedBox(height: 8),
                _buildZoomButton(Icons.remove, _zoomOut),
                const SizedBox(height: 8),
                _buildZoomButton(Icons.center_focus_strong, () {
                  if (_objectiveMarkers.isNotEmpty) {
                    _fitBounds(_objectiveMarkers.map((m) => m.position).toList());
                  }
                }, tooltip: 'Centrar todos'),
              ],
            ),
          ),

          // Leyenda de objetivo
          Positioned(
            top: 12,
            left: 12,
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12, height: 12,
                      decoration: const BoxDecoration(
                        color: Colors.green, shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('En vivo', style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                    const SizedBox(width: 12),
                    Container(
                      width: 12, height: 12,
                      decoration: BoxDecoration(
                        color: Colors.grey[400], shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('Offline', style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                  ],
                ),
              ),
            ),
          ),

          // Sin Objetivos
          if (!_isLoading && _objectiveMarkers.isEmpty)
            Center(
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline, size: 48, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'Sin objetivos vinculados',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Agrega objetivos desde la lista para verlos en el mapa',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onPressed, {String? tooltip}) {
    final button = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, size: 24),
          ),
        ),
      ),
    );
    
    if (tooltip != null && tooltip.isNotEmpty) {
      return Tooltip(
        message: tooltip,
        child: button,
      );
    }
    
    return button;
  }

  Widget _buildObjectiveMarker(_ObjectiveMarker obj, bool isSmallScreen) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Indicador de estado
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: obj.isLive ? Colors.green : Colors.grey,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const SizedBox(width: 8, height: 8),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: obj.isLive ? Colors.red : Colors.grey[700],
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: Icon(
            Icons.person_pin_circle,
            color: Colors.white,
            size: isSmallScreen ? 24 : 32,
          ),
        ),
        const SizedBox(height: 4),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4),
              ],
            ),
            child: Text(
              obj.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isSmallScreen ? 10 : 12,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

class _ObjectiveMarker {
  final String uid;
  final String name;
  final LatLng position;
  final bool isLive;
  final Timestamp? lastUpdate;

  _ObjectiveMarker({
    required this.uid,
    required this.name,
    required this.position,
    required this.isLive,
    this.lastUpdate,
  });
}