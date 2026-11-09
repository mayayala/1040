import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:encrypt/encrypt.dart' as legacy;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:geocercas_app/core/models/geofence_event.dart';
import 'package:geocercas_app/core/services/e2e_encryption_service.dart';
import 'package:geocercas_app/core/services/location_cipher.dart';

class EventQueueService {
  static final _instance = EventQueueService._();
  factory EventQueueService() => _instance;
  EventQueueService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  late Box<Map> _box;
  late SecretKey _localKey;
  Future<void>? _initialization;
  Future<void>? _sync;
  Timer? _retry;
  int _retrySeconds = 15;

  Future<void> init() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    _box = await Hive.openBox<Map>('geofence_events');
    const keyName = 'offline_location_aes_v2';
    var encoded = await _storage.read(key: keyName);
    if (encoded == null) {
      final random = Random.secure();
      encoded = base64Encode(List.generate(32, (_) => random.nextInt(256)));
      await _storage.write(key: keyName, value: encoded);
    }
    _localKey = SecretKey(base64Decode(encoded));
    // No se elimina un evento antiguo si falla la lectura o la migración.
    for (final entry in _box.toMap().entries) {
      final data = entry.value;
      if (data['local_cipher_version'] == 2) continue;
      try {
        final coords = _legacyLocation(data);
        final uid = data['objective_id'] as String;
        final id = data['id'] as String;
        final needsPrefix = data['sync_status'] == 'pending' && !id.startsWith('$uid:');
        final newId = needsPrefix ? '$uid:$id' : id;
        await _box.put(entry.key, await _sealedRecord({...data, 'id': newId, 'local_key': entry.key}, coords));
      } catch (_) {
        debugPrint('Evento anterior conservado: requiere revisión de formato');
      }
    }
    Connectivity().onConnectivityChanged.listen((status) {
      if (status != ConnectivityResult.none) {
        _retry?.cancel();
        _retrySeconds = 15;
        unawaited(syncPendingEvents());
      }
    });
  }

  Future<void> sendSOS({
    required String objectiveId,
    required double latitude,
    required double longitude,
    double accuracy = 0.0,
    double velocity = 0.0,
    String? message,
  }) async {
    await enqueueEvent(GeofenceEvent(
      id: '',
      objectiveId: objectiveId,
      geofenceId: 'sos_manual',
      geofenceName: 'SOS Manual',
      severity: EventSeverity.critical,
      eventType: 'sos',
      explanation: message ?? 'Solicitud manual de auxilio.',
      latitude: latitude,
      longitude: longitude,
      hdop: accuracy,
      velocity: velocity,
      timestamp: DateTime.now(),
    ));
  }

  Future<void> enqueueEvent(GeofenceEvent event) async {
    await init();
    if (_auth.currentUser?.uid != event.objectiveId) {
      throw StateError('La sesión cambió antes de guardar el evento');
    }
    final id = '${event.objectiveId}:${_db.collection('events').doc().id}';
    final data = <String, dynamic>{
      'id': id,
      'local_key': id,
      'objective_id': event.objectiveId,
      'geofence_id': event.geofenceId,
      'geofence_name': event.geofenceName,
      'severity': event.severity.name,
      'event_type': event.eventType,
      'explanation': event.explanation,
      'hdop': event.hdop,
      'velocity': event.velocity,
      'timestamp': event.timestamp.toIso8601String(),
      'sync_status': 'pending',
      'priority': event.eventType == 'sos' ? 0 : event.severity.index + 1,
    };
    await _box.put(id, await _sealedRecord(data, {
      'latitude': event.latitude, 'longitude': event.longitude,
    }));
    unawaited(syncPendingEvents());
  }

  Future<Map<dynamic, dynamic>> _sealedRecord(
    Map data, Map<String, double> coords,
  ) async {
    final uid = data['objective_id'] as String;
    final id = data['id'] as String;
    final payload = await LocationCipher.seal(
      key: _localKey, latitude: coords['latitude']!, longitude: coords['longitude']!,
      aad: LocationCipher.context('offline-v2', [uid, id]),
    );
    return <dynamic, dynamic>{
      ...data, 'encrypted_location': payload, 'local_cipher_version': 2,
    }..removeWhere((key, _) => key == 'latitude' || key == 'longitude');
  }

  Future<Map<String, double>> _coords(Map data) async {
    if (data['local_cipher_version'] != 2) return _legacyLocation(data);
    return LocationCipher.open(
      key: _localKey, payload: data['encrypted_location'] as String,
      aad: LocationCipher.context('offline-v2', [
        data['objective_id'] as String, data['id'] as String,
      ]),
    );
  }

  // Únicamente para leer y migrar colas de instalaciones anteriores.
  Map<String, double> _legacyLocation(Map data) {
    final lat = data['latitude'];
    final lng = data['longitude'];
    if (lat is num && lng is num) {
      return {'latitude': lat.toDouble(), 'longitude': lng.toDouble()};
    }
    final encrypter = legacy.Encrypter(legacy.AES(
      legacy.Key.fromUtf8('my32lengthsupersecretnooneknows1'),
    ));
    final text = encrypter.decrypt64(
      data['encrypted_location'] as String, iv: legacy.IV.fromLength(16),
    );
    final decoded = jsonDecode(text) as Map<String, dynamic>;
    return {
      'latitude': (decoded['latitude'] as num).toDouble(),
      'longitude': (decoded['longitude'] as num).toDouble(),
    };
  }

  Future<void> syncPendingEvents() {
    return _sync ??= _flush().whenComplete(() => _sync = null);
  }

  Future<void> _flush() async {
    try {
      await init();
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      final attempted = <String>{};
      var failed = false;
      // Si se encola otro evento mientras se sincroniza, se toma en la siguiente vuelta.
      while (_auth.currentUser?.uid == uid) {
        final pending = _box.values.where((event) =>
            event['objective_id'] == uid && event['sync_status'] == 'pending' &&
            event['id'] is String && !attempted.contains(event['id'])).toList()
          ..sort((a, b) {
            final priority = (a['priority'] is num ? a['priority'] as num : 3)
                .compareTo(b['priority'] is num ? b['priority'] as num : 3);
            return priority != 0 ? priority :
                (a['timestamp'] as String? ?? '').compareTo(b['timestamp'] as String? ?? '');
          });
        if (pending.isEmpty) break;
        for (final data in pending) {
          if (_auth.currentUser?.uid != uid) return;
          final id = data['id'] as String;
          attempted.add(id);
          final localKey = data['local_key'] ?? id;
          late Map<String, double> coords;
          late DateTime timestamp;
          try {
            coords = await _coords(data);
            timestamp = DateTime.parse(data['timestamp'] as String);
          } catch (_) {
            await _box.put(localKey, {...data, 'sync_status': 'needs_review'});
            continue;
          }
          try {
            final ref = _db.collection('events').doc(id);
            final encrypted = await E2EEncryptionService().encryptLocation(
              objectiveId: uid, recordId: id,
              latitude: coords['latitude']!, longitude: coords['longitude']!,
            );
            await _db.runTransaction((tx) async {
              final previous = await tx.get(ref);
              if (_auth.currentUser?.uid != uid) throw StateError('La sesión cambió');
              if (previous.exists) {
                if (previous.data()?['objective_id'] != uid) {
                  throw StateError('El identificador pertenece a otro usuario');
                }
                return;
              }
              tx.set(ref, {
                'objective_id': uid,
                'geofence_id': data['geofence_id'],
                'geofence_name': data['geofence_name'],
                'severity': data['severity'],
                'event_type': data['event_type'],
                'explanation': data['explanation'],
                'encrypted_location': encrypted,
                'hdop': data['hdop'],
                'velocity': data['velocity'],
                'timestamp': Timestamp.fromDate(timestamp),
                'sync_status': 'synced',
                'synced_at': FieldValue.serverTimestamp(),
                'priority': data['priority'],
              });
              if (data['event_type'] == 'sos') {
                tx.update(_db.collection('users').doc(uid), {
                  'sos_active': true,
                  'sos_activated_at': FieldValue.serverTimestamp(),
                  'updated_at': FieldValue.serverTimestamp(),
                });
              }
            });
            await _box.put(localKey, {...data, 'sync_status': 'synced'});
          } catch (_) {
            failed = true;
            debugPrint('Evento pendiente conservado; se reintentará la sincronización');
            // Un fallo de red o permisos no debe multiplicar intentos en toda la cola.
            break;
          }
        }
        if (failed) break;
      }
      if (failed) {
        _scheduleRetry();
      } else {
        _retry?.cancel();
        _retrySeconds = 15;
      }
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(Duration(seconds: _retrySeconds), () {
      unawaited(syncPendingEvents());
    });
    _retrySeconds = min(_retrySeconds * 2, 300);
  }

  Future<List<GeofenceEvent>> getLocalEvents({int limit = 50}) async {
    await init();
    final uid = _auth.currentUser?.uid;
    if (uid == null) return [];
    final records = _box.values.where((data) => data['objective_id'] == uid).toList()
      ..sort((a, b) => (b['timestamp'] as String? ?? '').compareTo(a['timestamp'] as String? ?? ''));
    final result = <GeofenceEvent>[];
    for (final data in records) {
      if (result.length >= limit || _auth.currentUser?.uid != uid) break;
      try {
        final coords = await _coords(data);
        result.add(GeofenceEvent(
          id: data['id'] as String,
          objectiveId: uid,
          geofenceId: data['geofence_id'] as String,
          geofenceName: data['geofence_name'] as String,
          severity: EventSeverity.values.byName(data['severity'] as String),
          eventType: data['event_type'] as String,
          explanation: data['explanation'] as String,
          latitude: coords['latitude']!,
          longitude: coords['longitude']!,
          hdop: (data['hdop'] as num).toDouble(),
          velocity: (data['velocity'] as num).toDouble(),
          timestamp: DateTime.parse(data['timestamp'] as String),
          syncStatus: data['sync_status'] as String? ?? 'pending',
        ));
      } catch (_) {
        debugPrint('Evento local no legible; se conserva para revisión');
      }
    }
    return result;
  }
}
