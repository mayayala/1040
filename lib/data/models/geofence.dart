import 'package:cloud_firestore/cloud_firestore.dart';

class Geofence {
  final String id;
  final String ownerId;
  final String name;
  final GeoPoint center;
  final double nominalRadius;
  final String riskLevel;
  final Map<String, dynamic> scheduleRules;
  final bool isActive;
  final DateTime createdAt;

  Geofence({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.center,
    required this.nominalRadius,
    required this.riskLevel,
    required this.scheduleRules,
    required this.isActive,
    required this.createdAt,
  });

  /// Factory para crear desde Firestore 
  factory Geofence.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Geofence(
      id: doc.id,
      ownerId: data['owner_id'] ?? '',
      name: data['name'] ?? '',
      center: data['center'] ?? const GeoPoint(0, 0),
      nominalRadius: (data['nominal_radius'] ?? 100).toDouble(),
      riskLevel: data['risk_level'] ?? 'medium',
      scheduleRules: data['schedule_rules'] ?? {},
      isActive: data['is_active'] ?? true,
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'owner_id': ownerId,
      'name': name,
      'center': center,
      'nominal_radius': nominalRadius,
      'risk_level': riskLevel,
      'schedule_rules': scheduleRules,
      'is_active': isActive,
      'created_at': Timestamp.fromDate(createdAt),
    };
  }

  Geofence copyWith({
    String? id,
    String? ownerId,
    String? name,
    GeoPoint? center,
    double? nominalRadius,
    String? riskLevel,
    Map<String, dynamic>? scheduleRules,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return Geofence(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      name: name ?? this.name,
      center: center ?? this.center,
      nominalRadius: nominalRadius ?? this.nominalRadius,
      riskLevel: riskLevel ?? this.riskLevel,
      scheduleRules: scheduleRules ?? this.scheduleRules,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}