import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';

class LinkService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Objetivos activos vinculados al observador 
  Stream<List<Map<String, dynamic>>> getActiveObjectives() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return _firestore
        .collection('monitoring_links')
        .where('observer_id', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .asyncMap((snapshot) async {
      final objectives = <Map<String, dynamic>>[];
      
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final objectiveUid = data['objective_id'] as String;
        
        try {
          final userDoc = await _firestore.collection('users').doc(objectiveUid).get();
          if (userDoc.exists) {
            final userData = userDoc.data()!;
            objectives.add({
              'link_id': doc.id,
              'objective_uid': objectiveUid,
              'displayName': userData['displayName'] ?? 'Usuario',
              'email': userData['email'] ?? '',
              'status': data['status'],
              'created_at': data['created_at'],
              'last_seen': userData['last_sync'],
              'live_mode_active': userData['live_mode_active'] ?? false,
            });
          }
        } catch (e) {
          debugPrint('Error al cargar objetivo $objectiveUid: $e');
        }
      }
      return objectives;
    });
  }

  /// Solicitudes pendientes recibidas por el usuario (como Objetivo)
  Stream<List<Map<String, dynamic>>> getPendingRequests() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return _firestore
        .collection('monitoring_links')
        .where('objective_id', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .asyncMap((snapshot) async {
      final requests = <Map<String, dynamic>>[];
      
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final observerUid = data['observer_id'] as String;
        
        try {
          final result = await FirebaseFunctions.instance
              .httpsCallable('getPendingObserver').call({'linkId': doc.id});
          final contact = result.data as Map;
          requests.add({
            'link_id': doc.id,
            'observer_uid': observerUid,
            'observer_name': contact['displayName'] ?? 'Usuario',
            'observer_email': contact['email'] ?? '',
            'requested_at': data['created_at'],
          });
        } catch (_) {
          requests.add({
            'link_id': doc.id,
            'observer_uid': observerUid,
            'observer_name': 'Solicitud pendiente',
            'observer_email': '',
            'requested_at': data['created_at'],
          });
        }
      }
      return requests;
    });
  }

  /// Observadores activos vinculados al objetivo actual
  Stream<List<Map<String, dynamic>>> getActiveObservers() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return _firestore
        .collection('monitoring_links')
        .where('objective_id', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .asyncMap((snapshot) async {
      final observers = <Map<String, dynamic>>[];
      
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final observerUid = data['observer_id'] as String;
        
        try {
          final userDoc = await _firestore.collection('users').doc(observerUid).get();
          if (userDoc.exists) {
            final userData = userDoc.data()!;
            observers.add({
              'link_id': doc.id,
              'observer_uid': observerUid,
              'displayName': userData['displayName'] ?? 'Usuario',
              'email': userData['email'] ?? '',
              'status': data['status'],
              'created_at': data['created_at'],
              'accepted_at': data['accepted_at'],
              'live_mode_active': userData['live_mode_active'] ?? false,
            });
          }
        } catch (e) {
          debugPrint('Error al cargar observador $observerUid: $e');
        }
      }
      return observers;
    });
  }

/// Envía solicitud de vínculo a un usuario por email
  Future<void> sendLinkRequest(String targetEmail) async {
    final observerUid = _auth.currentUser?.uid;
    if (observerUid == null) throw Exception('Usuario no autenticado');

    final result = await FirebaseFunctions.instance
        .httpsCallable('lookupObjective').call({'email': targetEmail.trim().toLowerCase()});
    final objectiveUid = (result.data as Map)['uid'] as String;
    if (objectiveUid == observerUid) {
      throw StateError('No puedes monitorearte a ti mismo');
    }
    final ref = _firestore.collection('monitoring_links').doc('$objectiveUid:$observerUid');
    await _firestore.runTransaction((tx) async {
      final existing = await tx.get(ref);
      if (existing.exists) throw StateError('Ya existe una solicitud o vínculo');
      tx.set(ref, {
        'observer_id': observerUid,
        'objective_id': objectiveUid,
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> acceptLinkRequest(String linkId) async {
    await _firestore.collection('monitoring_links').doc(linkId).update({
      'status': 'active',
      'accepted_at': FieldValue.serverTimestamp(),
    });
  }

  /// Rechaza una solicitud de vínculo
  Future<void> rejectLinkRequest(String linkId) async {
    await _firestore.collection('monitoring_links').doc(linkId).update({
      'status': 'revoked',
      'revoked_at': FieldValue.serverTimestamp(),
    });
    debugPrint('Vínculo $linkId rechazado');
  }

  /// Revoca un vínculo activo
  Future<void> revokeLink(String linkId) async {
    await _firestore.collection('monitoring_links').doc(linkId).update({
      'status': 'revoked',
      'revoked_at': FieldValue.serverTimestamp(),
    });
    debugPrint('Vínculo $linkId revocado');
  }

  /// Activa/Desactiva modo en vivo para un objetivo específico
  Future<void> toggleLiveMode(String objectiveUid, bool isActive) async {
    await _firestore.collection('users').doc(objectiveUid).update({
      'live_mode_active': isActive,
      'updated_at': FieldValue.serverTimestamp(),
    });
    debugPrint('Modo en vivo ${isActive ? 'ACTIVADO' : 'DESACTIVADO'} para $objectiveUid');
  }

  /// Obtiene el estado de un vínculo específico
  Future<String?> getLinkStatus(String observerUid, String objectiveUid) async {
    final snapshot = await _firestore
        .collection('monitoring_links')
        .where('observer_id', isEqualTo: observerUid)
        .where('objective_id', isEqualTo: objectiveUid)
        .limit(1)
        .get();
    
    if (snapshot.docs.isNotEmpty) {
      return snapshot.docs.first.data()['status'] as String?;
    }
    return null;
  }

  ///  Desactiva el estado de emergencia SOS de un objetivo
  Future<void> deactivateSOS(String objectiveUid) async {
    final observerUid = _auth.currentUser?.uid;
    if (observerUid == null) throw Exception('Usuario no autenticado');

    // Verificar que el observador tiene vínculo activo con el objetivo
    final linkSnapshot = await _firestore
        .collection('monitoring_links')
        .where('observer_id', isEqualTo: observerUid)
        .where('objective_id', isEqualTo: objectiveUid)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();

    if (linkSnapshot.docs.isEmpty) {
      throw Exception('No tienes permiso para desactivar el SOS de este objetivo');
    }

    final batch = _firestore.batch();
    batch.update(_firestore.collection('users').doc(objectiveUid), {
      'sos_active': false,
      'sos_deactivated_at': FieldValue.serverTimestamp(),
      'sos_deactivated_by': observerUid,
      'updated_at': FieldValue.serverTimestamp(),
    });
    batch.set(_firestore.collection('events').doc(), {
      'objective_id': objectiveUid,
      'observer_id': observerUid,
      'geofence_id': 'sos_resolved',
      'geofence_name': 'SOS Resuelto',
      'severity': 'informative',
      'event_type': 'sos_resolved',
      'explanation': 'El observador desactivó la alerta SOS.',
      'hdop': 0.0,
      'velocity': 0.0,
      'timestamp': FieldValue.serverTimestamp(),
      'sync_status': 'synced',
      'priority': 3,
    });
    await batch.commit();
  }

  /// Verifica si un objetivo tiene SOS activo
  Stream<bool> isSOSActive(String objectiveUid) {
    return _firestore
        .collection('users')
        .doc(objectiveUid)
        .snapshots()
        .map((doc) => doc.data()?['sos_active'] == true);
  }
}