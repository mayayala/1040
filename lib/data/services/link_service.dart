import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geocercas_app/core/services/notification_service.dart';

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
          final userDoc = await _firestore.collection('users').doc(observerUid).get();
          if (userDoc.exists) {
            final userData = userDoc.data()!;
            requests.add({
              'link_id': doc.id,
              'observer_uid': observerUid,
              'observer_name': userData['displayName'] ?? 'Usuario',
              'observer_email': userData['email'] ?? '',
              'requested_at': data['created_at'],
            });
          }
        } catch (e) {
          debugPrint('Error al cargar solicitante $observerUid: $e');
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

    // 1. Buscar UID del objetivo por email
    final usersQuery = await _firestore
        .collection('users')
        .where('email', isEqualTo: targetEmail.trim().toLowerCase())
        .limit(1)
        .get();

    if (usersQuery.docs.isEmpty) {
      throw Exception('No existe un usuario con este correo');
    }

    final objectiveUid = usersQuery.docs.first.id;
    if (objectiveUid == observerUid) {
      throw Exception('No puedes monitorearte a ti mismo');
    }

    // 2. Verificar que no exista un vínculo previo
    final existingLink = await _firestore
        .collection('monitoring_links')
        .where('observer_id', isEqualTo: observerUid)
        .where('objective_id', isEqualTo: objectiveUid)
        .limit(1)
        .get();

    if (existingLink.docs.isNotEmpty) {
      final status = existingLink.docs.first.data()['status'];
      if (status == 'active') {
        throw Exception('Ya estás monitoreando a este usuario');
      } else if (status == 'pending') {
        throw Exception('Ya enviaste una solicitud a este usuario');
      } else if (status == 'revoked') {
        throw Exception('Este vínculo fue revocado anteriormente');
      }
    }

    // 3. Crear vínculo con estado 'pending'
    await _firestore.collection('monitoring_links').add({
      'observer_id': observerUid,
      'objective_id': objectiveUid,
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
      'requested_by_email': _auth.currentUser?.email,
    });

    // Enviar Notificacion
    try {
      final objectiveDoc = await _firestore.collection('users').doc(objectiveUid).get();
      final targetToken = objectiveDoc.data()?['fcm_token'] as String?; 
      
      if (targetToken != null && targetToken.isNotEmpty) {
        final observerName = _auth.currentUser?.displayName ?? 'Un usuario'; 
        
        await NotificationService.sendPushNotification(
          targetToken: targetToken, 
          title: ' Nueva solicitud de vínculo',
          body: '$observerName quiere monitorear tu ubicación.',
          data: {
            'type': 'link_request',
            'link_id': 'pending',
          },
        );
        debugPrint('Notificación push enviada al objetivo');
      } else {
        debugPrint('El objetivo no tiene token FCM registrado aún');
      }
    } catch (e) {
      debugPrint('Error al enviar notificación push: $e');
    }

    debugPrint('Solicitud de vínculo enviada a $targetEmail');
  }

/// Acepta una solicitud de vínculo (desde el lado del objetivo)
  Future<void> acceptLinkRequest(String linkId) async {
    // 1. Leer datos del vínculo para saber a quién notificar
    final linkDoc = await _firestore.collection('monitoring_links').doc(linkId).get();
    if (!linkDoc.exists) throw Exception('Vínculo no encontrado');
    
    final data = linkDoc.data()!;
    final observerUid = data['observer_id'] as String;
    final objectiveUid = data['objective_id'] as String;

    // 2. Actualizar estado a 'active'
    await linkDoc.reference.update({
      'status': 'active',
      'accepted_at': FieldValue.serverTimestamp(),
    });

    // Enviar Notificacion
    try {
      final observerDoc = await _firestore.collection('users').doc(observerUid).get();
      final targetToken = observerDoc.data()?['fcm_token'] as String?; 
      
      if (targetToken != null && targetToken.isNotEmpty) {
        final objectiveName = _auth.currentUser?.displayName ?? 'El objetivo'; 
        
        await NotificationService.sendPushNotification(
          targetToken: targetToken,
          title: ' Solicitud Aceptada',
          body: '$objectiveName ha aceptado tu solicitud. Ya puedes monitorearlo.',
          data: {
            'type': 'link_accepted',
            'objective_uid': objectiveUid,
          },
        );
        debugPrint('Notificación push enviada al observador');
      } else {
        debugPrint('El observador no tiene token FCM registrado aún');
      }
    } catch (e) {
      debugPrint('Error al enviar notificación push: $e');
    }

    debugPrint('Vínculo $linkId aceptado');
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

    // 1. Desactivar estado SOS en Firestore
    await _firestore.collection('users').doc(objectiveUid).update({
      'sos_active': false,
      'sos_deactivated_at': FieldValue.serverTimestamp(),
      'sos_deactivated_by': observerUid,
      'updated_at': FieldValue.serverTimestamp(),
    });

    // 2. Registrar evento de resolución en el historial
    final eventDoc = await _firestore.collection('events').add({
      'objective_id': objectiveUid,
      'observer_id': observerUid,
      'geofence_id': 'sos_resolved',
      'geofence_name': 'SOS Resuelto',
      'severity': 'informative',
      'event_type': 'sos_resolved',
      'explanation': ' Emergencia SOS desactivada por el observador. Situación controlada.',
      'hdop': 0.0,
      'velocity': 0.0,
      'timestamp': FieldValue.serverTimestamp(),
      'sync_status': 'synced',
      'priority': 1,
    });

    // 3. Notificar al objetivo que el SOS fue desactivado
    try {
      final objectiveDoc = await _firestore.collection('users').doc(objectiveUid).get();
      final objectiveToken = objectiveDoc.data()?['fcm_token'] as String?;
      final observerDoc = await _firestore.collection('users').doc(observerUid).get();
      final observerName = observerDoc.data()?['displayName'] ?? 'Tu observador';

      if (objectiveToken != null && objectiveToken.isNotEmpty) {
        await NotificationService.sendPushNotification(
          targetToken: objectiveToken,
          title: ' SOS Desactivado',
          body: '$observerName ha confirmado que la emergencia fue resuelta.',
          data: {
            'type': 'sos_resolved',
            'observer_name': observerName,
          },
        );
      }
    } catch (e) {
      debugPrint('Error al notificar al objetivo: $e');
    }

    debugPrint('SOS desactivado para $objectiveUid por $observerUid');
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