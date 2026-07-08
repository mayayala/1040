import 'package:cloud_firestore/cloud_firestore.dart';

enum EventSeverity {
  critical,   
  preventive, 
  informative 
}

class GeofenceEvent {
  final String id;
  final String objectiveId;
  final String geofenceId;
  final String geofenceName;
  final EventSeverity severity;
  final String eventType; 
  final String explanation; 
  final double latitude;
  final double longitude;
  final double hdop;
  final double velocity;
  final DateTime timestamp;
  final String syncStatus; 

  GeofenceEvent({
    required this.id,
    required this.objectiveId,
    required this.geofenceId,
    required this.geofenceName,
    required this.severity,
    required this.eventType,
    required this.explanation,
    required this.latitude,
    required this.longitude,
    required this.hdop,
    required this.velocity,
    required this.timestamp,
    this.syncStatus = 'pending',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'objective_id': objectiveId,
      'geofence_id': geofenceId,
      'geofence_name': geofenceName,
      'severity': severity.name,
      'event_type': eventType,
      'explanation': explanation,
      'location': GeoPoint(latitude, longitude),
      'hdop': hdop,
      'velocity': velocity,
      'timestamp': Timestamp.fromDate(timestamp),
      'sync_status': syncStatus,
    };
  }
}