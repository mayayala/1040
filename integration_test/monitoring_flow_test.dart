import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocercas_app/core/models/geofence_event.dart';
import 'package:geocercas_app/core/services/decision_tree_model.dart';
import 'package:geocercas_app/core/services/e2e_encryption_service.dart';
import 'package:geocercas_app/core/services/event_queue_service.dart';
import 'package:geocercas_app/data/services/geofence_service.dart';
import 'package:geocercas_app/data/services/link_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('LOCAL_FIREBASE_INTEGRATION');
  const host = '10.0.2.2';
  const password = 'Synthetic-test-account-1040';
  const server = GetOptions(source: Source.server);
  const latitude = -16.5;
  const longitude = -68.15;

  testWidgets('vínculo, ubicación cifrada, SOS persistente y revocación',
      (tester) async {
    final app = await Firebase.initializeApp();
    expect(app.options.projectId, 'demo-geocercas',
        reason: 'La prueba sólo puede ejecutarse contra Firebase local ficticio');
    final auth = FirebaseAuth.instance;
    await auth.useAuthEmulator(host, 9099);
    final db = FirebaseFirestore.instance;
    db.useFirestoreEmulator(host, 8080);
    FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
    await Hive.initFlutter();
    final crypto = E2EEncryptionService();
    final links = LinkService();
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final objectiveEmail = 'objective-$nonce@example.test';
    final observerEmail = 'observer-$nonce@example.test';

    Future<String> register(String email, String role) async {
      final user = (await auth.createUserWithEmailAndPassword(
        email: email, password: password,
      )).user!;
      await db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'displayName': role,
        'email': email,
        'role_tags': [role],
        'is_deleted': false,
        'fcm_token': 'fixture-$role',
      });
      await crypto.registerDeviceKey();
      return user.uid;
    }

    Future<void> signIn(String email) async {
      await auth.signOut();
      await auth.signInWithEmailAndPassword(email: email, password: password);
    }

    Future<void> denied(Future<Object?> read) async {
      await expectLater(read, throwsA(isA<FirebaseException>()
          .having((error) => error.code, 'code', 'permission-denied')));
    }

    final objective = await register(objectiveEmail, 'objective');
    await auth.signOut();
    final observer = await register(observerEmail, 'observer');
    final profile = db.collection('users').doc(objective);
    await denied(profile.get(server));
    await links.sendLinkRequest(objectiveEmail);
    await denied(profile.get(server));

    await signIn(objectiveEmail);
    final pending = await links.getPendingRequests().first
        .timeout(const Duration(seconds: 30));
    expect(pending.single['observer_email'], observerEmail);
    final linkId = pending.single['link_id'] as String;
    expect(linkId, '$objective:$observer');
    await links.acceptLinkRequest(linkId);
    await signIn(observerEmail);
    expect((await links.getActiveObjectives().first).single['objective_uid'],
        objective);
    await GeofenceService().createGeofence(
      objectiveId: objective, name: 'Geocerca de prueba', type: 'circle',
      riskLevel: 'high', center: const GeoPoint(latitude, longitude), radius: 100,
    );

    await signIn(objectiveEmail);
    expect((await GeofenceService().getActiveGeofences(objective).first).single['name'],
        'Geocerca de prueba');
    const liveRecord = 'live-ci';
    final encryptedLocation = await crypto.encryptLocation(
      objectiveId: objective, recordId: liveRecord,
      latitude: latitude, longitude: longitude,
    );
    await profile.update({
      'encrypted_last_location': encryptedLocation,
      'last_location_record_id': liveRecord,
    });
    await signIn(observerEmail);
    final live = (await profile.get(server)).data()!;
    expect(await crypto.decryptLocation(
      objectiveId: objective, recordId: live['last_location_record_id'] as String,
      encryptedData: live['encrypted_last_location'] as String,
    ), {'latitude': latitude, 'longitude': longitude});

    await signIn(objectiveEmail);
    var queue = EventQueueService.forIntegrationTest();
    await queue.init();
    await db.disableNetwork();
    try {
      await queue.sendSOS(
        objectiveId: objective, latitude: latitude, longitude: longitude,
      );
      await queue.syncPendingEvents().timeout(const Duration(seconds: 30));
      final beforeRestart = (await queue.getLocalEvents()).single;
      expect(beforeRestart.syncStatus, 'pending');
      final stored = Hive.box<Map>('geofence_events').get(beforeRestart.id)!;
      expect(stored.containsKey('latitude'), isFalse);
      expect(stored.containsKey('longitude'), isFalse);
      expect(stored['local_cipher_version'], 2);
      await queue.closeForIntegrationTest();
      queue = EventQueueService.forIntegrationTest();
      final afterRestart = (await queue.getLocalEvents()).single;
      expect(afterRestart.id, beforeRestart.id);
      expect(afterRestart.latitude, latitude);
      expect(afterRestart.syncStatus, 'pending');
    } finally {
      await db.enableNetwork();
    }
    final reconnect = Stopwatch()..start();
    await queue.syncPendingEvents().timeout(const Duration(seconds: 45));
    final reconnectMs = reconnect.elapsedMilliseconds;
    final sos = (await queue.getLocalEvents()).single;
    expect(sos.syncStatus, 'synced');
    await Future.wait([queue.syncPendingEvents(), queue.syncPendingEvents()]);
    final events = db.collection('events').where('objective_id', isEqualTo: objective);
    expect((await events.get(server)).docs.single.id, sos.id);
    expect((await profile.get(server)).data()!['sos_active'], isTrue);

    await signIn(observerEmail);
    final received = (await events.get(server)).docs.single;
    expect(received.data().containsKey('latitude'), isFalse);
    expect(received.data().containsKey('longitude'), isFalse);
    expect(await crypto.decryptLocation(
      objectiveId: objective, recordId: received.id,
      encryptedData: received.data()['encrypted_location'] as String,
    ), {'latitude': latitude, 'longitude': longitude});

    // El comprobante sólo existe en el proyecto ficticio, sin usar FCM.
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    final noticeUri = Uri(
      scheme: 'http', host: host, port: 8080,
      pathSegments: ['v1', 'projects', 'demo-geocercas', 'databases',
        '(default)', 'documents', '_integration_push', '$observer:sos_alert:${sos.id}'],
    );
    Map<String, dynamic>? notice;
    try {
      final deadline = Stopwatch()..start();
      while (deadline.elapsed < const Duration(seconds: 30)) {
        final request = await http.getUrl(noticeUri);
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
        final response = await request.close();
        final text = await response.transform(utf8.decoder).join();
        if (response.statusCode == 200) {
          notice = jsonDecode(text) as Map<String, dynamic>;
          break;
        }
        expect(response.statusCode, 404, reason: text);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    } finally {
      http.close(force: true);
    }
    expect(notice, isNotNull, reason: 'El trigger no preparó el aviso de SOS');
    final fields = notice!['fields'] as Map;
    expect((fields['recipient'] as Map)['stringValue'], observer);
    final dataFields = ((fields['data'] as Map)['mapValue'] as Map)['fields'] as Map;
    expect((dataFields['type'] as Map)['stringValue'], 'sos_alert');
    expect(dataFields.keys, unorderedEquals(['type', 'objective_id', 'record_id']));

    await signIn(objectiveEmail);
    final times = <int>[];
    for (var i = 0; i < 12; i++) {
      final watch = Stopwatch()..start();
      await queue.enqueueEvent(GeofenceEvent(
        id: '', objectiveId: objective, geofenceId: 'ci',
        geofenceName: 'Medición local', severity: EventSeverity.informative,
        eventType: 'measurement', explanation: 'Datos sintéticos',
        latitude: latitude, longitude: longitude, hdop: 5, velocity: 0,
        timestamp: DateTime.now(),
      ));
      await queue.syncPendingEvents().timeout(const Duration(seconds: 30));
      times.add(watch.elapsedMilliseconds);
    }
    expect((await events.get(server)).size, 13);
    await links.revokeLink(linkId);
    await signIn(observerEmail);
    await denied(profile.get(server));
    await denied(db.collection('events').doc(sos.id).get(server));
    await queue.closeForIntegrationTest();

    final tree = DecisionTreeModel();
    await tree.loadModel();
    final rng = Random(42);
    final features = List.generate(1200, (_) => List.generate(18, (_) => rng.nextDouble()));
    expect(tree.predict(features.first), isNotNull);
    for (final row in features.take(200)) {
      tree.predict(row);
    }
    final watch = Stopwatch()..start();
    for (final row in features) {
      tree.predict(row);
    }
    final elapsedUs = watch.elapsedMicroseconds;
    // ignore: avoid_print
    print('INTEGRATION_EVIDENCE ${jsonEncode({
      'environment': 'android_emulator_debug_firebase_local',
      'sync_after_reconnect_ms': reconnectMs,
      'sync_sample_ms': times,
      'tree_inferences': features.length,
      'tree_total_us': elapsedUs,
      'sos_notification_prepared': true,
      'sos_notifications_received_by_fcm': null,
    })}');
  }, skip: !enabled, timeout: const Timeout(Duration(minutes: 5)));
}
