import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocercas_app/core/models/geofence_event.dart';
import 'package:geocercas_app/core/services/event_queue_service.dart';
import 'package:geocercas_app/core/services/e2e_encryption_service.dart';

class AlertHistoryScreen extends StatefulWidget {
  final String? objectiveId;
  final String? objectiveName;

  const AlertHistoryScreen({
    super.key,
    this.objectiveId,
    this.objectiveName,
  });

  @override
  State<AlertHistoryScreen> createState() => _AlertHistoryScreenState();
}

class _AlertHistoryScreenState extends State<AlertHistoryScreen> {
  List<GeofenceEvent> _events = [];
  bool _isLoading = true;
  String _sourceLabel = '';

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    
    final allEvents = <GeofenceEvent>[];
    final eventQueue = EventQueueService();

    // Eventos locales
    try {
      final localEvents = eventQueue.getLocalEvents(limit: 200);
      final filteredLocal = widget.objectiveId != null
          ? localEvents.where((e) => e.objectiveId == widget.objectiveId).toList()
          : localEvents;
      allEvents.addAll(filteredLocal);
      debugPrint('Cargados ${filteredLocal.length} eventos locales');
    } catch (e) {
      debugPrint('Error al cargar eventos locales: $e');
    }

    // Decifra las coordenadas
    try {
      Query query = FirebaseFirestore.instance
          .collection('events')
          .orderBy('timestamp', descending: true)
          .limit(100);
      
      if (widget.objectiveId != null) {
        query = FirebaseFirestore.instance
            .collection('events')
            .where('objective_id', isEqualTo: widget.objectiveId)
            .orderBy('timestamp', descending: true)
            .limit(100);
      }
      
      final snapshot = await query.get();
      
      final firestoreEvents = snapshot.docs.map((doc) {
        final rawData = doc.data();
        if (rawData == null) return null;
        
        final data = rawData as Map<String, dynamic>;
        final objectiveId = data['objective_id'] as String? ?? '';
        
        final encryptedLocation = data['encrypted_location'] as String?;
        Map<String, double>? location;
        
        if (encryptedLocation != null && encryptedLocation.isNotEmpty) {
          location = E2EEncryptionService().decryptLocation(
            objectiveId: objectiveId,
            encryptedData: encryptedLocation,
          );
        }
        
        return GeofenceEvent(
          id: doc.id,
          objectiveId: objectiveId,
          geofenceId: data['geofence_id'] as String? ?? '',
          geofenceName: data['geofence_name'] as String? ?? 'Sin nombre',
          severity: EventSeverity.values.firstWhere(
            (e) => e.name == data['severity'],
            orElse: () => EventSeverity.informative,
          ),
          eventType: data['event_type'] as String? ?? 'unknown',
          explanation: data['explanation'] as String? ?? '',
          latitude: location?['latitude'] ?? 0.0,
          longitude: location?['longitude'] ?? 0.0,
          hdop: (data['hdop'] as num?)?.toDouble() ?? 0.0,
          velocity: (data['velocity'] as num?)?.toDouble() ?? 0.0,
          timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
          syncStatus: 'synced',
        );
      })
      .whereType<GeofenceEvent>()
      .toList();
      
      allEvents.addAll(firestoreEvents);
      debugPrint('Cargados ${firestoreEvents.length} eventos de Firestore (descifrados)');
    } catch (e) {
      debugPrint('Error al cargar eventos de Firestore: $e');

      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('events')
            .limit(100)
            .get();
        
        final firestoreEvents = snapshot.docs.map((doc) {
          final rawData = doc.data();
          if (rawData == null) return null;
          
          final data = rawData as Map<String, dynamic>;
          final objectiveId = data['objective_id'] as String? ?? '';
          
          final encryptedLocation = data['encrypted_location'] as String?;
          Map<String, double>? location;
          
          if (encryptedLocation != null && encryptedLocation.isNotEmpty) {
            location = E2EEncryptionService().decryptLocation(
              objectiveId: objectiveId,
              encryptedData: encryptedLocation,
            );
          }
          
          return GeofenceEvent(
            id: doc.id,
            objectiveId: objectiveId,
            geofenceId: data['geofence_id'] as String? ?? '',
            geofenceName: data['geofence_name'] as String? ?? 'Sin nombre',
            severity: EventSeverity.values.firstWhere(
              (e) => e.name == data['severity'],
              orElse: () => EventSeverity.informative,
            ),
            eventType: data['event_type'] as String? ?? 'unknown',
            explanation: data['explanation'] as String? ?? '',
            latitude: location?['latitude'] ?? 0.0,
            longitude: location?['longitude'] ?? 0.0,
            hdop: (data['hdop'] as num?)?.toDouble() ?? 0.0,
            velocity: (data['velocity'] as num?)?.toDouble() ?? 0.0,
            timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
            syncStatus: 'synced',
          );
        })
        .whereType<GeofenceEvent>()
        .toList();
        
        final filtered = widget.objectiveId != null
            ? firestoreEvents.where((e) => e.objectiveId == widget.objectiveId).toList()
            : firestoreEvents;
        allEvents.addAll(filtered);
        debugPrint('Cargados ${filtered.length} eventos de Firestore (fallback)');
      } catch (e2) {
        debugPrint('Error secundario Firestore: $e2');
      }
    }

    // Eliminar duplicados y ordena
    final uniqueEvents = <String, GeofenceEvent>{};
    for (final event in allEvents) {
      uniqueEvents[event.id] = event;
    }
    
    final sortedEvents = uniqueEvents.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (!mounted) return;
    
    setState(() {
      _events = sortedEvents;
      _isLoading = false;
      _sourceLabel = '${sortedEvents.length} evento(s)';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.objectiveName != null 
            ? 'Alertas de ${widget.objectiveName}' 
            : 'Historial de Alertas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEvents,
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sincronizar eventos pendientes',
            onPressed: () async {
              await EventQueueService().syncPendingEvents();
              if (!mounted) return;
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text(' Sincronización completada')),
              );
              _loadEvents();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('Sin alertas registradas',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          widget.objectiveId != null
                              ? 'Aún no hay alertas para este objetivo. Mueve el dispositivo dentro de una geocerca para generar eventos.'
                              : 'Las alertas aparecerán aquí cuando el sistema detecte eventos.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _loadEvents,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.grey[700]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _sourceLabel,
                              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _events.length,
                        itemBuilder: (context, index) {
                          return _buildEventCard(context, _events[index]);
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildEventCard(BuildContext context, GeofenceEvent event) {
    Color severityColor;
    IconData severityIcon;
    String severityLabel;

    switch (event.severity) {
      case EventSeverity.critical:
        severityColor = Colors.red;
        severityIcon = Icons.error_outline;
        severityLabel = 'CRÍTICO';
        break;
      case EventSeverity.preventive:
        severityColor = Colors.orange;
        severityIcon = Icons.warning_amber_outlined;
        severityLabel = 'PREVENTIVO';
        break;
      case EventSeverity.informative:
        severityColor = Colors.blue;
        severityIcon = Icons.info_outline;
        severityLabel = 'INFORMATIVO';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: severityColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(severityIcon, color: severityColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.geofenceName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              )),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Chip(
                            label: Text(severityLabel, style: const TextStyle(fontSize: 10)),
                            backgroundColor: severityColor.withValues(alpha: 0.15),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 8),
                          Text(_formatTimestamp(event.timestamp),
                              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: event.syncStatus == 'synced' ? Colors.green.shade50 : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    event.syncStatus == 'synced' ? Icons.cloud_done : Icons.cloud_upload,
                    color: event.syncStatus == 'synced' ? Colors.green : Colors.orange,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, size: 16, color: Colors.grey[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(event.explanation,
                        style: TextStyle(fontSize: 12, color: Colors.grey[800])),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${event.latitude.toStringAsFixed(6)}, ${event.longitude.toStringAsFixed(6)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.speed, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text('${event.velocity.toStringAsFixed(1)} m/s',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ],
            ),
            if (event.eventType.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.category, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(event.eventType,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    if (difference.inMinutes < 1) return 'Ahora';
    if (difference.inMinutes < 60) return 'hace ${difference.inMinutes}min';
    if (difference.inHours < 24) return 'hace ${difference.inHours}h';
    return '${timestamp.day}/${timestamp.month}/${timestamp.year} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}