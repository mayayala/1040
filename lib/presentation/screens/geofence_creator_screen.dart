import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocercas_app/data/services/geofence_service.dart';

class GeofenceCreatorScreen extends StatefulWidget {
  final String objectiveId;
  final String objectiveName;
  final Map<String, dynamic>? existingGeofence;
  final bool forceHomeName;

  const GeofenceCreatorScreen({
    super.key,
    required this.objectiveId,
    required this.objectiveName,
    this.existingGeofence,
    this.forceHomeName = false,
  });

  @override
  State<GeofenceCreatorScreen> createState() => _GeofenceCreatorScreenState();
}

class _GeofenceCreatorScreenState extends State<GeofenceCreatorScreen> {
  String _geofenceType = 'polygon';
  final List<LatLng> _points = [];
  LatLng? _circleCenter;
  double _circleRadius = 100.0;
  final _nameController = TextEditingController();
  final MapController _mapController = MapController();
  bool _isSaving = false;
  String _selectedRisk = 'medium';
  double _currentZoom = 15.0;
  
  double _calculatedArea = 0.0;
  LatLng? _calculatedCenter;

  @override
  void initState() {
    super.initState();
    if (widget.existingGeofence != null) {
      _loadExistingData();
    } else if (widget.forceHomeName) {
      // Primera geocerca: "Casa"
      _nameController.text = 'Casa';
      // Por defecto Riesgo bajo
      _selectedRisk = 'low'; 
    }
  }

  void _loadExistingData() {
    final gf = widget.existingGeofence!;
    _nameController.text = gf['name'] ?? '';
    _selectedRisk = gf['risk_level'] ?? 'medium';
    _geofenceType = gf['type'] ?? 'polygon';
    
    if (_geofenceType == 'circle') {
      final center = gf['center'];
      if (center != null) {
        _circleCenter = LatLng(center.latitude, center.longitude);
        _circleRadius = (gf['radius'] as num?)?.toDouble() ?? 100.0;
      }
    } else {
      final verticesData = List<Map<String, dynamic>>.from(gf['vertices'] ?? []);
      setState(() {
        _points.addAll(verticesData.map((v) => LatLng(
              (v['lat'] as num).toDouble(),
              (v['lng'] as num).toDouble(),
            )));
        _updateCalculatedMetrics();
      });
    }
  }

  void _updateCalculatedMetrics() {
    if (_points.length >= 3) {
      final verticesData = _points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
      final centroid = _calculateCentroid(verticesData);
      final area = _calculateArea(verticesData);
      
      setState(() {
        _calculatedCenter = centroid;
        _calculatedArea = area;
      });
    } else {
      setState(() {
        _calculatedCenter = null;
        _calculatedArea = 0.0;
      });
    }
  }

  LatLng _calculateCentroid(List<Map<String, double>> vertices) {
    if (vertices.length < 3) {
      final avgLat = vertices.map((v) => v['lat']!).reduce((a, b) => a + b) / vertices.length;
      final avgLng = vertices.map((v) => v['lng']!).reduce((a, b) => a + b) / vertices.length;
      return LatLng(avgLat, avgLng);
    }

    double signedArea = 0.0;
    double cx = 0.0;
    double cy = 0.0;
    final n = vertices.length;

    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final xi = vertices[i]['lat']!;
      final yi = vertices[i]['lng']!;
      final xj = vertices[j]['lat']!;
      final yj = vertices[j]['lng']!;
      
      final cross = xi * yj - xj * yi;
      signedArea += cross;
      cx += (xi + xj) * cross;
      cy += (yi + yj) * cross;
    }

    signedArea /= 2.0;
    
    if (signedArea.abs() < 1e-10) {
      final avgLat = vertices.map((v) => v['lat']!).reduce((a, b) => a + b) / n;
      final avgLng = vertices.map((v) => v['lng']!).reduce((a, b) => a + b) / n;
      return LatLng(avgLat, avgLng);
    }
    
    cx /= (6.0 * signedArea);
    cy /= (6.0 * signedArea);

    return LatLng(cx, cy);
  }

  double _calculateArea(List<Map<String, double>> vertices) {
    if (vertices.length < 3) return 0.0;
    
    double area = 0.0;
    final n = vertices.length;
    
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final xi = vertices[i]['lat']!;
      final yi = vertices[i]['lng']!;
      final xj = vertices[j]['lat']!;
      final yj = vertices[j]['lng']!;
      area += (xi * yj - xj * yi);
    }
    
    final latPromedio = vertices.map((v) => v['lat']!).reduce((a, b) => a + b) / n;
    final factorConversion = 111320.0 * 111320.0 * cos(latPromedio * pi / 180);
    
    return (area.abs() / 2.0) * factorConversion;
  }

  String _formatArea(double areaM2) {
    if (areaM2 < 1000000) {
      return '${areaM2.toStringAsFixed(areaM2 < 100 ? 1 : 0)} m²';
    } else {
      final km2 = areaM2 / 1000000;
      return '${km2.toStringAsFixed(2)} km²';
    }
  }

  void _zoomIn() {
    setState(() => _currentZoom = (_currentZoom + 1).clamp(1.0, 19.0));
    _mapController.move(_mapController.camera.center, _currentZoom);
  }

  void _zoomOut() {
    setState(() => _currentZoom = (_currentZoom - 1).clamp(1.0, 19.0));
    _mapController.move(_mapController.camera.center, _currentZoom);
  }

  bool get _canSave {
    if (_nameController.text.isEmpty) return false;
    if (_geofenceType == 'circle') {
      return _circleCenter != null && _circleRadius > 0;
    } else {
      return _points.length >= 3;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingGeofence != null;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Geocerca' : 'Crear Geocerca'),
        actions: [
          if (_canSave)
            TextButton(
              onPressed: _isSaving ? null : _saveGeofence,
              child: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('GUARDAR', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                TextField(
                  controller: _nameController,
                  readOnly: widget.forceHomeName,
                  decoration: InputDecoration(
                    labelText: 'Nombre de la geocerca *',
                    hintText: 'Ej: Casa, Colegio, Parque...',
                    prefixIcon: const Icon(Icons.label_outline),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _nameController.text.isNotEmpty && !widget.forceHomeName
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _nameController.clear()),
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (widget.forceHomeName)
                  const Padding(
                    padding: EdgeInsets.only(top: 4.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'El nombre de esta geocerca no se puede modificar',
                        style: TextStyle(fontSize: 11, color: Colors.blue),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'polygon', label: Text('Poligonal'), icon: Icon(Icons.polyline)),
                    ButtonSegment(value: 'circle', label: Text('Circular'), icon: Icon(Icons.circle_outlined)),
                  ],
                  selected: {_geofenceType},
                  onSelectionChanged: isEditing ? null : (Set<String> newSelection) {
                    setState(() {
                      _geofenceType = newSelection.first;
                      _points.clear();
                      _circleCenter = null;
                      _calculatedCenter = null;
                      _calculatedArea = 0.0;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedRisk,
                        decoration: const InputDecoration(
                          labelText: 'Nivel de riesgo',
                          prefixIcon: Icon(Icons.warning_amber_outlined),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'low', child: Text(' Bajo')),
                          DropdownMenuItem(value: 'medium', child: Text(' Medio')),
                          DropdownMenuItem(value: 'high', child: Text(' Alto')),
                        ],
                        onChanged: (v) => setState(() => _selectedRisk = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          if (_geofenceType == 'polygon') ...[
                            Text('${_points.length}', 
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                            Text('vértices', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                            if (_calculatedArea > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                _formatArea(_calculatedArea),
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.primary),
                              ),
                              Text('área', style: TextStyle(fontSize: 9, color: colorScheme.onSurfaceVariant)),
                            ],
                          ] else ...[
                            Text('${_circleRadius.toStringAsFixed(0)}m', 
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                            Text('radio', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (_geofenceType == 'circle' && _circleCenter != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.radio_button_checked, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Slider(
                          value: _circleRadius,
                          min: 10,
                          max: 2000,
                          divisions: 199,
                          label: '${_circleRadius.toStringAsFixed(0)}m',
                          onChanged: (v) => setState(() => _circleRadius = v),
                        ),
                      ),
                      Text('${_circleRadius.toStringAsFixed(0)}m', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
                if (_geofenceType == 'circle' && _circleCenter == null)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.blue),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Toca el mapa para establecer el centro del círculo',
                            style: TextStyle(fontSize: 12, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _getInitialCenter(),
                    initialZoom: _currentZoom,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                    onTap: (tapPosition, latLng) {
                      setState(() {
                        if (_geofenceType == 'polygon') {
                          _points.add(latLng);
                          _updateCalculatedMetrics();
                        } else {
                          _circleCenter = latLng;
                        }
                      });
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https:tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.umsa.geocercas',
                    ),
                    if (_geofenceType == 'polygon') ..._buildPolygonLayers()
                    else ..._buildCircleLayers(),
                  ],
                ),
                Positioned(
                  right: 12,
                  top: 100,
                  child: Column(
                    children: [
                      _buildZoomButton(Icons.add, _zoomIn),
                      const SizedBox(height: 8),
                      _buildZoomButton(Icons.remove, _zoomOut),
                      const SizedBox(height: 8),
                      _buildZoomButton(Icons.my_location, () {
                        final center = _getInitialCenter();
                        _mapController.move(center, 15.0);
                        setState(() => _currentZoom = 15.0);
                      }, tooltip: 'Centrar'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: Row(
              children: [
                if (_geofenceType == 'polygon')
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _points.isEmpty ? null : () {
                        setState(() {
                          _points.removeLast();
                          _updateCalculatedMetrics();
                        });
                      },
                      icon: const Icon(Icons.undo),
                      label: const Text('Deshacer'),
                    ),
                  ),
                if (_geofenceType == 'circle' && _circleCenter != null) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _circleCenter = null;
                          _circleRadius = 100.0;
                        });
                      },
                      icon: const Icon(Icons.clear),
                      label: const Text('Reiniciar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _canSave ? _saveGeofence : null,
                    icon: const Icon(Icons.check),
                    label: Text(isEditing ? 'Actualizar' : 'Guardar'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  LatLng _getInitialCenter() {
    if (_geofenceType == 'polygon' && _points.isNotEmpty) return _points.first;
    if (_geofenceType == 'circle' && _circleCenter != null) return _circleCenter!;
    return const LatLng(-16.5000, -68.1500);
  }

  List<Widget> _buildPolygonLayers() {
    final layers = <Widget>[];
    final riskColor = _getRiskColor(_selectedRisk);
    
    if (_points.isNotEmpty) {
      layers.add(PolygonLayer(
        polygons: [
          Polygon(
            points: _points,
            color: riskColor.withValues(alpha: 0.25),
            borderColor: riskColor,
            borderStrokeWidth: 3,
          ),
        ],
      ));
    }
    
    if (_points.isNotEmpty) {
      layers.add(MarkerLayer(
        markers: _points.asMap().entries.map((entry) {
          final index = entry.key;
          final p = entry.value;
          return Marker(
            point: p,
            width: 28,
            height: 28,
            alignment: Alignment.center,
            child: Container(
              decoration: BoxDecoration(
                color: riskColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          );
        }).toList(),
      ));
    }
    
    final isCreating = widget.existingGeofence == null;
    if (_calculatedCenter != null && isCreating) {
      layers.add(MarkerLayer(
        markers: [
          Marker(
            point: _calculatedCenter!,
            width: 24,
            height: 24,
            alignment: Alignment.center,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: riskColor, width: 3),
              ),
              child: const Icon(Icons.flag, size: 14, color: Colors.black),
            ),
          ),
        ],
      ));
    }
    
    return layers;
  }

  List<Widget> _buildCircleLayers() {
    final layers = <Widget>[];
    final riskColor = _getRiskColor(_selectedRisk);
    
    if (_circleCenter != null) {
      layers.add(CircleLayer(
        circles: [
          CircleMarker(
            point: _circleCenter!,
            radius: _circleRadius,
            color: riskColor.withValues(alpha: 0.25),
            borderColor: riskColor,
            borderStrokeWidth: 3,
          ),
        ],
      ));
      layers.add(MarkerLayer(
        markers: [
          Marker(
            point: _circleCenter!,
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: Container(
              decoration: BoxDecoration(
                color: riskColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
              ),
              child: const Icon(Icons.flag, color: Colors.white, size: 20),
            ),
          ),
        ],
      ));
    }
    return layers;
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onPressed, {String? tooltip}) {
    final button = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(padding: const EdgeInsets.all(12), child: Icon(icon, size: 24)),
        ),
      ),
    );
    if (tooltip != null) return Tooltip(message: tooltip, child: button);
    return button;
  }

  Color _getRiskColor(String risk) {
    switch (risk) {
      case 'low': return Colors.green;
      case 'medium': return Colors.orange;
      case 'high': return Colors.red;
      default: return Colors.blue;
    }
  }

  Future<void> _saveGeofence() async {
    if (!_canSave) return;
    setState(() => _isSaving = true);

    try {
      final service = GeofenceService();

      if (_geofenceType == 'circle') {
        final centerGeo = GeoPoint(_circleCenter!.latitude, _circleCenter!.longitude);
        if (widget.existingGeofence != null) {
          await service.updateGeofence(
            geofenceId: widget.existingGeofence!['id'],
            name: _nameController.text.trim(),
            riskLevel: _selectedRisk,
            radius: _circleRadius,
          );
          await FirebaseFirestore.instance.collection('geofences')
              .doc(widget.existingGeofence!['id'])
              .update({'center': centerGeo});
        } else {
          await service.createGeofence(
            objectiveId: widget.objectiveId,
            name: _nameController.text.trim(),
            type: 'circle',
            riskLevel: _selectedRisk,
            center: centerGeo,
            radius: _circleRadius,
          );
        }
      } else {
        final verticesData = _points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
        if (widget.existingGeofence != null) {
          await service.updateGeofence(
            geofenceId: widget.existingGeofence!['id'],
            name: _nameController.text.trim(),
            riskLevel: _selectedRisk,
            vertices: verticesData,
          );
        } else {
          await service.createGeofence(
            objectiveId: widget.objectiveId,
            name: _nameController.text.trim(),
            type: 'polygon',
            riskLevel: _selectedRisk,
            vertices: verticesData,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.existingGeofence != null ? ' Geocerca actualizada' : ' Geocerca creada'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}