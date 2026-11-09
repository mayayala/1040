import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocercas_app/core/services/location_cipher.dart';

void main() {
  test('dos dispositivos comparten su sobre sin exponer la clave privada', () async {
    final agreement = X25519();
    final objective = await (await agreement.newKeyPair()).extract();
    final observer = await (await agreement.newKeyPair()).extract();
    final other = await (await agreement.newKeyPair()).extract();

    Future<SecretKey> derive(SimpleKeyPairData local, SimpleKeyPairData remote) =>
        LocationCipher.recipientKey(
          local: local, remotePublic: remote.publicKey.bytes,
          objectiveId: 'objective', recipientId: 'observer', recordId: 'event',
        );

    final senderKey = await derive(objective, observer);
    final observerKey = await derive(observer, objective);
    final otherKey = await derive(other, objective);
    final aad = LocationCipher.context('location-v2', ['objective', 'observer', 'event']);
    Future<String> seal() => LocationCipher.seal(
      key: senderKey, latitude: -16.5, longitude: -68.1, aad: aad,
    );
    final first = await seal();
    final second = await seal();
    expect(base64Decode(first).take(12), isNot(equals(base64Decode(second).take(12))));
    expect(await LocationCipher.open(key: observerKey, payload: first, aad: aad),
        {'latitude': -16.5, 'longitude': -68.1});
    await expectLater(LocationCipher.open(key: otherKey, payload: first, aad: aad),
        throwsA(isA<SecretBoxAuthenticationError>()));
    final corrupted = base64Decode(first);
    corrupted[12] ^= 1;
    await expectLater(LocationCipher.open(
      key: observerKey, payload: base64Encode(corrupted), aad: aad,
    ), throwsA(isA<SecretBoxAuthenticationError>()));
    await expectLater(LocationCipher.open(
      key: observerKey, payload: first, aad: LocationCipher.context(
        'location-v2', ['objective', 'observer', 'different-record'],
      ),
    ), throwsA(isA<SecretBoxAuthenticationError>()));
  });
}
