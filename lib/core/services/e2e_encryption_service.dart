import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geocercas_app/core/services/location_cipher.dart';

/// Cifrado por destinatario. Las claves privadas permanecen en almacenamiento
/// seguro; Firebase conserva las claves públicas y los sobres cifrados.
class E2EEncryptionService {
  static final _instance = E2EEncryptionService._();
  factory E2EEncryptionService() => _instance;
  E2EEncryptionService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final _agreement = X25519();
  final _localKeys = <String, Future<SimpleKeyPairData>>{};
  final _registeredKeys = <String, String>{};

  Future<SimpleKeyPairData> _key(String uid) async {
    if (_auth.currentUser?.uid != uid) throw StateError('Sesión no válida');
    final future = _localKeys.putIfAbsent(uid, () => _loadOrCreate(uid));
    try {
      return await future;
    } catch (_) {
      if (identical(_localKeys[uid], future)) _localKeys.remove(uid);
      rethrow;
    }
  }

  Future<SimpleKeyPairData> _loadOrCreate(String uid) async {
    final storageKey = 'location_x25519_v2_$uid';
    final raw = await _storage.read(key: storageKey);
    if (raw != null) {
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      return SimpleKeyPairData(
        base64Decode(saved['private'] as String),
        publicKey: SimplePublicKey(
          base64Decode(saved['public'] as String), type: KeyPairType.x25519,
        ),
        type: KeyPairType.x25519,
      );
    }
    final pair = await (await _agreement.newKeyPair()).extract();
    await _storage.write(key: storageKey, value: jsonEncode({
      'private': base64Encode(pair.bytes),
      'public': base64Encode(pair.publicKey.bytes),
    }));
    return pair;
  }

  Future<void> registerDeviceKey() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final pair = await _key(uid);
    final publicKey = base64Encode(pair.publicKey.bytes);
    if (_registeredKeys[uid] == publicKey) return;
    final ref = _db.collection('location_public_keys').doc(uid);
    await _db.runTransaction((tx) async {
      final current = await tx.get(ref);
      if (_auth.currentUser?.uid != uid) throw StateError('La sesión cambió');
      if (!current.exists) {
        tx.set(ref, {'key': publicKey});
      } else if (current.data()?['key'] != publicKey) {
        throw StateError('La cuenta ya tiene una clave en otro dispositivo');
      }
    });
    _registeredKeys[uid] = publicKey;
  }

  Future<String> encryptLocation({
    required String objectiveId,
    required String recordId,
    required double latitude,
    required double longitude,
  }) async {
    final pair = await _key(objectiveId);
    await registerDeviceKey();
    const server = GetOptions(source: Source.server);
    final links = await _db.collection('monitoring_links')
        .where('objective_id', isEqualTo: objectiveId)
        .where('status', isEqualTo: 'active').get(server);
    final recipients = {objectiveId, ...links.docs
        .where((doc) => doc.id == '$objectiveId:${doc.data()['observer_id']}')
        .map((doc) => doc.data()['observer_id']).whereType<String>()};
    final boxes = <String, String>{};
    for (final uid in recipients) {
      final publicKey = uid == objectiveId
          ? pair.publicKey.bytes
          : await _publicKey(uid, serverOnly: true);
      if (publicKey == null) {
        throw StateError('Falta la clave de un destinatario vinculado');
      }
      final key = await LocationCipher.recipientKey(
        local: pair, remotePublic: publicKey,
        objectiveId: objectiveId, recipientId: uid, recordId: recordId,
      );
      boxes[uid] = await LocationCipher.seal(
        key: key, latitude: latitude, longitude: longitude,
        aad: LocationCipher.context('location-v2', [objectiveId, uid, recordId]),
      );
    }
    if (_auth.currentUser?.uid != objectiveId) throw StateError('La sesión cambió');
    return jsonEncode({'v': 2, 'boxes': boxes});
  }

  Future<List<int>?> _publicKey(String uid, {bool serverOnly = false}) async {
    final doc = await _db.collection('location_public_keys').doc(uid)
        .get(serverOnly ? const GetOptions(source: Source.server) : null);
    final encoded = doc.data()?['key'];
    return encoded is String ? base64Decode(encoded) : null;
  }

  Future<Map<String, double>?> decryptLocation({
    required String objectiveId,
    required String recordId,
    required String encryptedData,
  }) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return null;
      final data = jsonDecode(encryptedData) as Map<String, dynamic>;
      if (data['v'] != 2) return null;
      final payload = (data['boxes'] as Map<String, dynamic>)[uid];
      if (payload is! String) return null;
      final pair = await _key(uid);
      final remote = uid == objectiveId ? pair.publicKey.bytes : await _publicKey(objectiveId);
      if (remote == null || _auth.currentUser?.uid != uid) return null;
      final key = await LocationCipher.recipientKey(
        local: pair, remotePublic: remote,
        objectiveId: objectiveId, recipientId: uid, recordId: recordId,
      );
      return await LocationCipher.open(
        key: key, payload: payload,
        aad: LocationCipher.context('location-v2', [objectiveId, uid, recordId]),
      );
    } catch (_) {
      return null;
    }
  }
}
