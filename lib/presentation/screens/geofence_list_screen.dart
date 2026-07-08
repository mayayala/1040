import 'package:flutter/material.dart';
import 'package:geocercas_app/data/services/geofence_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'geofence_creator_screen.dart';

class GeofenceListScreen extends StatelessWidget {
  final String objectiveId;
  final String objectiveName;

  const GeofenceListScreen({
    super.key,
    required this.objectiveId,
    required this.objectiveName,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Geocercas de $objectiveName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_location_alt),
            tooltip: 'Crear nueva geocerca',
            onPressed: () => _navigateToCreator(context),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: GeofenceService().getActiveGeofences(objectiveId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final geofences = snapshot.data ?? [];

          if (geofences.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.location_off_outlined, size: 64, color: colorScheme.primary),
                    const SizedBox(height: 16),
                    Text('Sin geocercas creadas', 
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('Toca el botón + para crear tu primera geocerca.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => _navigateToCreator(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Crear geocerca'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: geofences.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final gf = geofences[index];
              return _buildGeofenceCard(context, gf);
            },
          );
        },
      ),
    );
  }

  Widget _buildGeofenceCard(BuildContext context, Map<String, dynamic> gf) {
    final risk = gf['risk_level'] as String? ?? 'medium';
    final name = gf['name'] as String? ?? 'Sin nombre';
    final verticesCount = (gf['vertices'] as List?)?.length ?? 0;
    
    Color riskColor;
    String riskLabel;
    IconData riskIcon;
    switch (risk) {
      case 'low':
        riskColor = Colors.green;
        riskLabel = 'Bajo';
        riskIcon = Icons.check_circle_outline;
        break;
      case 'high':
        riskColor = Colors.red;
        riskLabel = 'Alto';
        riskIcon = Icons.error_outline;
        break;
      default:
        riskColor = Colors.orange;
        riskLabel = 'Medio';
        riskIcon = Icons.warning_amber_outlined;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: riskColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(riskIcon, color: riskColor, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, 
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          )),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Chip(
                        label: Text(riskLabel, style: const TextStyle(fontSize: 11)),
                        backgroundColor: riskColor.withValues(alpha: 0.15),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),
                      if (gf['type'] == 'circle') ...[
                        Icon(Icons.circle_outlined, size: 14, color: Colors.grey),
                        const SizedBox(width: 2),
                        Text('${(gf['radius'] as num?)?.toStringAsFixed(0) ?? '?'}m', 
                            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      ] else ...[
                        Icon(Icons.polyline, size: 14, color: Colors.grey),
                        const SizedBox(width: 2),
                        Text('$verticesCount vértices', 
                            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) => _handleMenuAction(context, value, gf),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Editar'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'view',
                  child: Row(children: [
                    Icon(Icons.map_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Ver en mapa'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Eliminar', style: TextStyle(color: Colors.red)),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handleMenuAction(BuildContext context, String action, Map<String, dynamic> gf) {
    switch (action) {
      case 'edit':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GeofenceCreatorScreen(
              objectiveId: objectiveId,
              objectiveName: objectiveName,
              existingGeofence: gf,
            ),
          ),
        );
        break;
      case 'view':
        _showGeofenceOnMap(context, gf);
        break;
      case 'delete':
        _confirmDelete(context, gf);
        break;
    }
  }

  void _showGeofenceOnMap(BuildContext context, Map<String, dynamic> gf) {
    final verticesData = List<Map<String, dynamic>>.from(gf['vertices'] ?? []);
    final points = verticesData
        .map((v) => LatLng((v['lat'] as num).toDouble(), (v['lng'] as num).toDouble()))
        .toList();
    
    if (points.isEmpty) return;

    // Centrar el mapa
    double avgLat = points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    double avgLng = points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
    final center = LatLng(avgLat, avgLng);

    final risk = gf['risk_level'] as String? ?? 'medium';
    final name = gf['name'] as String? ?? 'Sin nombre';
    
    Color riskColor;
    switch (risk) {
      case 'low': riskColor = Colors.green; break;
      case 'high': riskColor = Colors.red; break;
      default: riskColor = Colors.orange;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.location_on, color: riskColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(name, style: Theme.of(context).textTheme.titleLarge),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 15,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.umsa.geocercas',
                  ),
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: points,
                        color: riskColor.withValues(alpha: 0.3),
                        borderColor: riskColor,
                        borderStrokeWidth: 3,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Map<String, dynamic> gf) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar geocerca?'),
        content: Text('Se eliminará "${gf['name']}" de forma permanente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await GeofenceService().deleteGeofence(gf['id']);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(' Geocerca eliminada'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _navigateToCreator(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GeofenceCreatorScreen(
          objectiveId: objectiveId,
          objectiveName: objectiveName,
        ),
      ),
    );
  }
}