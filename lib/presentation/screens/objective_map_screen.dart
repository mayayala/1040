import 'dart:async'; 
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocercas_app/data/services/geofence_service.dart';
import 'package:geocercas_app/core/services/e2e_encryption_service.dart';

class ObjectiveMapScreen extends StatefulWidget {
  final String objectiveUid;
  final String objectiveName;

  const ObjectiveMapScreen({
    super.key,
    required this.objectiveUid,
    required this.objectiveName,
  });

  @override
  State<ObjectiveMapScreen> createState() => _ObjectiveMapScreenState();
}

class _ObjectiveMapScreenState extends State<ObjectiveMapScreen> {
  final MapController _mapController = MapController();
  
  LatLng? _currentPosition;
  double? _accuracy;
  DateTime? _lastUpdate;
  bool _isLiveModeActive = false;
  double _currentZoom = 15.0;
  List<Map<String, dynamic>> _geofences = [];
  StreamSubscription? _geofencesSubscription;
  StreamSubscription? _locationSubscription;

  @override
  void initState() {
    super.initState();
    _listenToObjectiveLocationRealtime();
    _listenToGeofences();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel(); 
    _geofencesSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _listenToObjectiveLocationRealtime() {
    _locationSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.objectiveUid)
        .snapshots()
        .listen((userDoc) {
      if (!userDoc.exists || !mounted) return;
      
      final data = userDoc.data()!;
      final encryptedLocation = data['encrypted_last_location'] as String?;
      
      if (encryptedLocation == null || encryptedLocation.isEmpty) {
        debugPrint('Aún no hay ubicación cifrada disponible');
        return;
      }
      
      // Descifrar la ubicación
      final location = E2EEncryptionService().decryptLocation(
        objectiveId: widget.objectiveUid,
        encryptedData: encryptedLocation,
      );
      
      if (location == null) {
        debugPrint('No se pudo descifrar la ubicación');
        return;
      }
      
      final latLng = LatLng(location['latitude']!, location['longitude']!);
      final accuracy = (data['last_accuracy'] as num?)?.toDouble() ?? 0.0;
      final timestamp = (data['last_location_timestamp'] as Timestamp?)?.toDate();
      final isLive = data['live_mode_active'] == true;
      
      if (mounted) {
        setState(() {
          _currentPosition = latLng;
          _accuracy = accuracy;
          _lastUpdate = timestamp ?? DateTime.now();
          _isLiveModeActive = isLive;
        });
        _mapController.move(latLng, _currentZoom);
        
        debugPrint('Mapa actualizado en tiempo real: ${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}');
      }
    });
  }

  void _listenToGeofences() {
    _geofencesSubscription = GeofenceService()
        .getActiveGeofences(widget.objectiveUid)
        .listen((geofences) {
      if (mounted) {
        setState(() => _geofences = geofences);
      }
    });
  }

  void _zoomIn() {
    setState(() => _currentZoom = (_currentZoom + 2).clamp(1.0, 19.0));
    if (_currentPosition != null) {
      _mapController.move(_currentPosition!, _currentZoom);
    }
  }

  void _zoomOut() {
    setState(() => _currentZoom = (_currentZoom - 2).clamp(1.0, 19.0));
    if (_currentPosition != null) {
      _mapController.move(_currentPosition!, _currentZoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentLat = _currentPosition?.latitude;
    final currentLng = _currentPosition?.longitude;
    final currentAccuracy = _accuracy;
    final lastUpdateTime = _lastUpdate;
    
    final isSmallScreen = MediaQuery.of(context).size.width < 360;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.objectiveName,
              style: TextStyle(fontSize: isSmallScreen ? 14 : 16, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            if (_isLiveModeActive)
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 4),
                  Text('En vivo', style: TextStyle(fontSize: 11, color: Colors.green)),
                ],
              ),
          ],
        ),
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Mapa con Geocercas
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition ?? const LatLng(-16.5000, -68.1500),
              initialZoom: _currentZoom,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.umsa.geocercas',
                maxNativeZoom: 19,
              ),
              
              //  Capa de geocercas 
              if (_geofences.isNotEmpty) ...[
                PolygonLayer(
                  polygons: _geofences
                      .where((gf) => gf['type'] == 'polygon')
                      .map((gf) {
                        final verticesData = List<Map<String, dynamic>>.from(gf['vertices'] ?? []);
                        final points = verticesData
                            .map((v) => LatLng(
                                  (v['lat'] as num).toDouble(),
                                  (v['lng'] as num).toDouble(),
                                ))
                            .toList();
                        
                        final risk = gf['risk_level'] as String? ?? 'medium';
                        final name = gf['name'] as String? ?? '';
                        
                        Color color;
                        switch (risk) {
                          case 'low': color = Colors.green; break;
                          case 'high': color = Colors.red; break;
                          default: color = Colors.orange;
                        }
                        
                        return Polygon(
                          points: points,
                          color: color.withValues(alpha: 0.2),
                          borderColor: color,
                          borderStrokeWidth: 2,
                          label: name,
                          labelStyle: const TextStyle(
                            color: Colors.black,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList(),
                ),
                
                CircleLayer(
                  circles: _geofences
                      .where((gf) => gf['type'] == 'circle')
                      .map((gf) {
                        final center = gf['center'];
                        if (center == null) return null;
                        
                        final risk = gf['risk_level'] as String? ?? 'medium';
                        final radius = (gf['radius'] as num?)?.toDouble() ?? 100.0;
                        
                        Color color;
                        switch (risk) {
                          case 'low': color = Colors.green; break;
                          case 'high': color = Colors.red; break;
                          default: color = Colors.orange;
                        }
                        
                        return CircleMarker(
                          point: LatLng(center.latitude, center.longitude),
                          radius: radius,
                          color: color.withValues(alpha: 0.2),
                          borderColor: color,
                          borderStrokeWidth: 2,
                        );
                      })
                      .whereType<CircleMarker>()
                      .toList(),
                ),
                
                MarkerLayer(
                  markers: _geofences
                      .where((gf) => gf['type'] == 'circle')
                      .map((gf) {
                        final center = gf['center'];
                        if (center == null) return null;
                        
                        final name = gf['name'] as String? ?? '';
                        
                        return Marker(
                          point: LatLng(center.latitude, center.longitude),
                          width: 120,
                          height: 30,
                          alignment: Alignment.center,
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
                              name,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      })
                      .whereType<Marker>()
                      .toList(),
                ),
              ],
              
              MarkerLayer(
                markers: _currentPosition != null
                    ? [
                        Marker(
                          point: _currentPosition!,
                          width: 120,
                          height: 100,
                          alignment: Alignment.topCenter,
                          child: _buildObjectiveMarker(isSmallScreen),
                        ),
                      ]
                    : [],
              ),
              
              if (_currentPosition != null && _accuracy != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _currentPosition!,
                      radius: _accuracy! / 2,
                      color: Colors.blue.withValues(alpha: 0.2),
                      borderColor: Colors.blue.withValues(alpha: 0.5),
                      borderStrokeWidth: 1,
                    ),
                  ],
                ),
            ],
          ),

          // Botones de Zoom
          Positioned(
            right: 12,
            top: 100,
            child: Column(
              children: [
                _buildZoomButton(Icons.add, _zoomIn),
                const SizedBox(height: 8),
                _buildZoomButton(Icons.remove, _zoomOut),
              ],
            ),
          ),

          // Estado del Objetivo
          if (currentLat != null && currentLng != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: Card(
                      elevation: 4,
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.location_on, color: Colors.red, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Última ubicación',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            _buildInfoRow('Lat:', currentLat.toStringAsFixed(6), false),
                            _buildInfoRow('Lng:', currentLng.toStringAsFixed(6), false),
                            if (currentAccuracy != null)
                              _buildInfoRow('Precisión:', '±${currentAccuracy.toStringAsFixed(1)}m', false),
                            if (lastUpdateTime != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Actualizado: ${_getTimeAgo(lastUpdateTime)}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          if (_currentPosition == null)
            Center(
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_off_outlined, size: 48, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'Esperando ubicación...',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'El objetivo aún no ha compartido su ubicación',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onPressed) {
    return Container(
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
  }

  Widget _buildObjectiveMarker(bool isSmallScreen) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.red,
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 4),
            ],
          ),
          child: LimitedBox(
            maxWidth: 140,
            child: Text(
              widget.objectiveName,
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

  Widget _buildInfoRow(String label, String value, bool isSmallScreen) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isSmallScreen ? 10 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: isSmallScreen ? 10 : 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    
    if (difference.inSeconds < 60) {
      return 'hace ${difference.inSeconds}s';
    } else if (difference.inMinutes < 60) {
      return 'hace ${difference.inMinutes}min';
    } else if (difference.inHours < 24) {
      return 'hace ${difference.inHours}h';
    } else {
      return 'hace ${difference.inDays}d';
    }
  }
}