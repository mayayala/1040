'use strict';

const assert = require('node:assert/strict');
const {test} = require('node:test');
const {setTimeout: wait} = require('node:timers/promises');
const {initializeApp, deleteApp} = require('firebase/app');
const {getAuth, connectAuthEmulator, createUserWithEmailAndPassword} = require('firebase/auth');
const {getFirestore, connectFirestoreEmulator, doc, setDoc, getDocFromServer,
  updateDoc, runTransaction, serverTimestamp, Timestamp, terminate} = require('firebase/firestore');
const {getFunctions, connectFunctionsEmulator, httpsCallable} = require('firebase/functions');
const {initializeApp: initAdmin, deleteApp: deleteAdmin} = require('firebase-admin/app');
const {getFirestore: adminFirestore} = require('firebase-admin/firestore');

const projectId = 'demo-geocercas';
const password = 'Synthetic-emulator-test-account';
const expectDenied = (promise) => assert.rejects(promise,
  (error) => error.code === 'permission-denied' || error.code === 'functions/permission-denied');

test('Authentication, Functions, Firestore y preparación de aviso SOS', {timeout: 90000}, async (t) => {
  if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error('Ejecute la prueba con Firebase Emulator Suite.');
  }
  const admin = initAdmin({projectId});
  t.after(() => deleteAdmin(admin));
  const backend = adminFirestore(admin);
  const nonce = Date.now();
  async function account(role) {
    const email = `${role}-${nonce}@example.test`;
    const app = initializeApp({projectId, apiKey: 'local-fake-key', appId: 'demo'}, role);
    const auth = getAuth(app);
    connectAuthEmulator(auth, 'http://127.0.0.1:9099', {disableWarnings: true});
    const db = getFirestore(app);
    connectFirestoreEmulator(db, '127.0.0.1', 8080);
    const functions = getFunctions(app);
    connectFunctionsEmulator(functions, '127.0.0.1', 5001);
    t.after(async () => { await terminate(db); await deleteApp(app); });
    const {user} = await createUserWithEmailAndPassword(auth, email, password);
    await setDoc(doc(db, 'users', user.uid), {
      uid: user.uid, email, displayName: role, role_tags: [role], is_deleted: false, fcm_token: 'test-token',
    });
    await setDoc(doc(db, 'location_public_keys', user.uid), {key: Buffer.alloc(32, 3).toString('base64')});
    return {db, functions, uid: user.uid, email};
  }
  const owner = await account('objective');
  const observer = await account('observer');
  const id = `${owner.uid}:${observer.uid}`;
  const obsProfile = doc(observer.db, 'users', owner.uid);
  await expectDenied(getDocFromServer(obsProfile));
  const lookup = await httpsCallable(observer.functions, 'lookupObjective')({email: owner.email});
  assert.equal(lookup.data.uid, owner.uid);
  await setDoc(doc(observer.db, 'monitoring_links', id), {
    objective_id: owner.uid, observer_id: observer.uid, status: 'pending', created_at: serverTimestamp(),
  });
  await expectDenied(getDocFromServer(obsProfile));
  await expectDenied(httpsCallable(observer.functions, 'getPendingObserver')({linkId: id}));
  const contact = await httpsCallable(owner.functions, 'getPendingObserver')({linkId: id});
  assert.equal(contact.data.email, observer.email);
  await updateDoc(doc(owner.db, 'monitoring_links', id), {
    status: 'active', accepted_at: serverTimestamp(),
  });
  assert.ok((await getDocFromServer(obsProfile)).exists());

  const recordId = `${owner.uid}:sos-emulator`;
  const record = doc(owner.db, 'events', recordId);
  const encrypted = JSON.stringify({v: 2, boxes: {[observer.uid]: 'test-envelope'}});
  async function sync() {
    await runTransaction(owner.db, async (tx) => {
      if (!(await tx.get(record)).exists()) {
        tx.set(record, {objective_id: owner.uid, event_type: 'sos', severity: 'critical',
          timestamp: Timestamp.now(), encrypted_location: encrypted});
      }
    });
  }
  await sync();
  await sync();
  const remote = doc(observer.db, 'events', recordId);
  assert.equal((await getDocFromServer(remote)).data().encrypted_location, encrypted);
  const audit = backend.doc(`_integration_push/${observer.uid}:sos_alert:${recordId}`);
  const deadline = Date.now() + 30000;
  let notice;
  while (!notice && Date.now() < deadline) {
    notice = (await audit.get()).data();
    if (!notice) await wait(250);
  }
  assert.ok(notice, 'Functions no preparó el aviso');
  assert.equal(notice.recipient, observer.uid);
  assert.deepEqual(notice.data, {type: 'sos_alert', objective_id: owner.uid, record_id: recordId});
  await updateDoc(doc(owner.db, 'monitoring_links', id), {
    status: 'revoked', revoked_at: serverTimestamp(),
  });
  await expectDenied(getDocFromServer(remote));
  await expectDenied(getDocFromServer(obsProfile));
});
