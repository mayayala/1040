import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocercas_app/data/services/geofence_service.dart';
import 'package:geocercas_app/data/services/location_service.dart';

class ObjectiveOwnMapScreen extends StatefulWidget {
  const ObjectiveOwnMapScreen({super.key});

  @override
  State<ObjectiveOwnMapScreen> createState() => _ObjectiveOwnMapScreenState();
}

class _ObjectiveOwnMapScreenState extends State<ObjectiveOwnMapScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocationService _locationService = LocationService();
  final MapController _mapController = MapController();

  LatLng? _currentPosition;
  double? _accuracy;
  double _currentZoom = 15.0;
  
  List<Map<String, dynamic>> _geofences = [];
  StreamSubscription? _geofencesSubscription;
  StreamSubscription<Position>? _locationSubscription;

  @override
  void initState() {
    super.initState();
    _listenToMyLocation();
    _listenToGeofences();
  }

  @override
  void dispose() {
    _geofencesSubscription?.cancel();
    _locationSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _listenToMyLocation() {
    _locationSubscription = _locationService.locationStream.listen(
      (position) {
        if (mounted) {
          setState(() {
            _currentPosition = LatLng(position.latitude, position.longitude);
            _accuracy = position.accuracy;
          });
        }
      },
      onError: (error) {
        debugPrint('Error en stream de ubicación: $error');
      },
    );
  }

  void _listenToGeofences() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    _geofencesSubscription = GeofenceService()
        .getActiveGeofences(userId)
        .listen((geofences) {
      if (mounted) {
        setState(() => _geofences = geofences);
      }
    });
  }

  void _centerOnMyLocation() {
    if (_currentPosition != null) {
      _mapController.move(_currentPosition!, _currentZoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Ubicación'),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Centrar en mi ubicación',
            onPressed: _centerOnMyLocation,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Mapa
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
              
              // Geocercas
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
              
              // Ubicacion Actual
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition!,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withValues(alpha: 0.5),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),

              if (_currentPosition != null && _accuracy != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _currentPosition!,
                      radius: _accuracy! / 2,
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderColor: Colors.blue.withValues(alpha: 0.3),
                      borderStrokeWidth: 1,
                    ),
                  ],
                ),
            ],
          ),

          // Centrar Posicion
          Positioned(
            right: 12,
            bottom: 100,
            child: Container(
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
                  onTap: _centerOnMyLocation,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.my_location, size: 24),
                  ),
                ),
              ),
            ),
          ),

          // Informacion de la ubicacion
          if (_currentPosition != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Card(
                    elevation: 4,
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.location_on, color: Colors.blue, size: 20),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Mi ubicación actual',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ),
                              if (_accuracy != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '±${_accuracy!.toStringAsFixed(0)}m',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                          Text(
                            'Lng: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                          if (_geofences.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Divider(height: 1),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.place, size: 16, color: colorScheme.primary),
                                const SizedBox(width: 4),
                                Text(
                                  '${_geofences.length} geocerca(s) activa(s)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Sin datos de ubicación
          if (_currentPosition == null)
            Center(
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                child: const Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        'Obteniendo tu ubicación...',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Asegúrate de tener los permisos de ubicación activados',
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
}