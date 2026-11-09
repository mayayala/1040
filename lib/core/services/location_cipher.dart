import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// El identificador del registro y el destinatario se autentican con AES-GCM.
class LocationCipher {
  static final _aes = AesGcm.with256bits();
  static final _agreement = X25519();
  static final _kdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static Future<SecretKey> recipientKey({
    required SimpleKeyPairData local,
    required List<int> remotePublic,
    required String objectiveId,
    required String recipientId,
    required String recordId,
  }) async {
    if (remotePublic.length != 32) {
      throw const FormatException('Clave pública inválida');
    }
    final shared = await _agreement.sharedSecretKey(
      keyPair: local,
      remotePublicKey: SimplePublicKey(remotePublic, type: KeyPairType.x25519),
    );
    if ((await shared.extractBytes()).every((byte) => byte == 0)) {
      throw const FormatException('Clave compartida inválida');
    }
    return _kdf.deriveKey(
      secretKey: shared,
      info: context('recipient-v2', [objectiveId, recipientId, recordId]),
    );
  }

  static List<int> context(String protocol, List<String> ids) =>
      utf8.encode(jsonEncode([protocol, ...ids]));

  static Future<String> seal({
    required SecretKey key,
    required double latitude,
    required double longitude,
    required List<int> aad,
  }) async {
    if (!_valid(latitude, longitude)) {
      throw const FormatException('Coordenadas inválidas');
    }
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode({'lat': latitude, 'lng': longitude})),
      secretKey: key, nonce: _aes.newNonce(), aad: aad,
    );
    return base64Encode(box.concatenation());
  }

  static Future<Map<String, double>> open({
    required SecretKey key,
    required String payload,
    required List<int> aad,
  }) async {
    final box = SecretBox.fromConcatenation(
      base64Decode(payload), nonceLength: 12, macLength: 16,
    );
    final bytes = await _aes.decrypt(box, secretKey: key, aad: aad);
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final lat = (data['lat'] as num).toDouble();
    final lng = (data['lng'] as num).toDouble();
    if (!_valid(lat, lng)) throw const FormatException('Coordenadas inválidas');
    return {'latitude': lat, 'longitude': lng};
  }

  static bool _valid(double lat, double lng) =>
      lat.isFinite && lng.isFinite && lat.abs() <= 90 && lng.abs() <= 180;
}
