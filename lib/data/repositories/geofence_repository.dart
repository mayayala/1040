import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocercas_app/data/models/geofence.dart';

/// Repositorio para gestión de geocercas y vínculos de monitoreo
class GeofenceRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Obtiene las geocercas de un usuario
  Future<List<Geofence>> getUserGeofences(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('geofences')
          .where('owner_id', isEqualTo: userId)
          .get();
      
      return snapshot.docs.map((doc) => Geofence.fromFirestore(doc)).toList();
    } catch (e) {
      return [];
    }
  }

  // VÍNCULOS DE MONITOREO
  
  /// Obtiene los observadores de un objetivo
  Future<List<QueryDocumentSnapshot>> getObserversForObjectives(List<String> objectiveIds) async {
    if (objectiveIds.isEmpty) return [];
    
    try {
      final snapshot = await _firestore
          .collection('monitoring_links')
          .where('objective_id', whereIn: objectiveIds)
          .where('status', isEqualTo: 'active')
          .get();
      
      return snapshot.docs;
    } catch (e) {
      return [];
    }
  }

  /// Obtiene los objetivos de un observador
  Future<List<QueryDocumentSnapshot>> getObjectivesForObserver(String observerId) async {
    try {
      final snapshot = await _firestore
          .collection('monitoring_links')
          .where('observer_id', isEqualTo: observerId)
          .where('status', isEqualTo: 'active')
          .get();
      
      return snapshot.docs;
    } catch (e) {
      return [];
    }
  }
}