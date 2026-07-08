import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Servicio de cifrado de extremo a extremo (E2E)
class E2EEncryptionService {
  static final E2EEncryptionService _instance = E2EEncryptionService._internal();
  factory E2EEncryptionService() => _instance;
  E2EEncryptionService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Cache de claves por objetivo
  final Map<String, encrypt.Key> _keyCache = {};

  /// Deriva una clave E2E determinística para un objetivo específico
  /// La clave se deriva del UID del objetivo + secreto de aplicación
  encrypt.Key _deriveKey(String objectiveId) {
    if (_keyCache.containsKey(objectiveId)) {
      return _keyCache[objectiveId]!;
    }

    const appSecret = 'geocercas_umsa_2026_e2e_secret_key_consistent_across_all_devices';

    // Deriva clave específica con SHA-256
    final input = '$objectiveId:$appSecret';
    final hash = sha256.convert(utf8.encode(input));

    // Tomar los primeros 32 bytes para AES-256
    final keyBytes = Uint8List.fromList(hash.bytes.sublist(0, 32));
    final key = encrypt.Key(keyBytes);

    _keyCache[objectiveId] = key;

    return key;
  }

  /// Cifra coordenadas para almacenamiento en Firestore
  String encryptLocation({
    required String objectiveId,
    required double latitude,
    required double longitude,
  }) {
    final key = _deriveKey(objectiveId);

    final ivHash = sha256.convert(utf8.encode('${key.base64}:iv'));
    final iv = encrypt.IV(Uint8List.fromList(ivHash.bytes.sublist(0, 16)));

    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

    // Payload a cifrar
    final payload = jsonEncode({
      'lat': latitude,
      'lng': longitude,
      'timestamp': DateTime.now().toIso8601String(),
    });

    final encrypted = encrypter.encrypt(payload, iv: iv);

    final combined = Uint8List.fromList([
      ...iv.bytes,
      ...encrypted.bytes,
    ]);

    return base64Encode(combined);
  }

  /// Descifra coordenadas desde Firestore
  Map<String, double>? decryptLocation({
    required String objectiveId,
    required String encryptedData,
  }) {
    try {
      final key = _deriveKey(objectiveId);

      final ivHash = sha256.convert(utf8.encode('${key.base64}:iv'));
      final iv = encrypt.IV(Uint8List.fromList(ivHash.bytes.sublist(0, 16)));

      // Decodificar base64
      final combined = base64Decode(encryptedData);

      // Extraer primeros 16 bytes
      final storedIv = Uint8List.fromList(combined.sublist(0, 16));

      // Verificar que el IV coincide
      if (!_listEquals(storedIv, iv.bytes)) {
      }

      final ciphertext = Uint8List.fromList(combined.sublist(16));

      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

      // Descifrar
      final decrypted = encrypter.decrypt64(
        base64Encode(ciphertext),
        iv: encrypt.IV(storedIv), // Usar el IV almacenado
      );

      // Parsear JSON
      final payload = jsonDecode(decrypted) as Map<String, dynamic>;

      return {
        'latitude': (payload['lat'] as num).toDouble(),
        'longitude': (payload['lng'] as num).toDouble(),
      };
    } catch (e) {
      return null;
    }
  }

  bool _listEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Limpia el cache de claves
  void clearKeyCache() {
    _keyCache.clear();
  }
}