'use strict';

const {readFileSync} = require('node:fs');
const {before, after, beforeEach, test} = require('node:test');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, collection, getDoc, getDocs, query, where, setDoc, updateDoc,
  serverTimestamp, runTransaction, Timestamp} = require('firebase/firestore');

let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
const envelope = JSON.stringify({v: 2, boxes: {objective: 'opaque'}});
const profile = (uid) => ({uid, role_tags: ['objective', 'observer'], is_deleted: false});
const event = () => ({objective_id: 'objective', severity: 'critical',
  event_type: 'sos', encrypted_location: envelope, timestamp: Timestamp.now()});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-geocercas',
    firestore: {rules: readFileSync(require('node:path').join(__dirname, '../../firestore.rules'), 'utf8')},
  });
});
after(async () => env?.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ({firestore}) => {
    const admin = firestore();
    await Promise.all(['objective', 'observer', 'other'].map((uid) =>
      setDoc(doc(admin, 'users', uid), profile(uid))));
  });
});

async function requestLink() {
  const observer = db('observer');
  const ref = doc(observer, 'monitoring_links', 'objective:observer');
  await assertSucceeds(runTransaction(observer, async (tx) => {
    const exists = (await tx.get(ref)).exists();
    if (!exists) tx.set(ref, {objective_id: 'objective', observer_id: 'observer',
      status: 'pending', created_at: serverTimestamp()});
  }));
  return ref;
}

test('sólo el objetivo acepta y el observador pierde acceso al revocar', async () => {
  const ref = await requestLink();
  const owner = db('objective');
  const observer = db('observer');
  const recorded = doc(owner, 'events', 'objective:one');
  await assertSucceeds(setDoc(recorded, event()));
  await assertFails(getDoc(doc(observer, 'users', 'objective')));
  await assertFails(getDoc(doc(observer, 'events', 'objective:one')));
  await assertFails(updateDoc(ref, {status: 'active', accepted_at: serverTimestamp()}));
  const ownerRef = doc(owner, 'monitoring_links', 'objective:observer');
  await assertFails(updateDoc(ownerRef, {status: 'active', accepted_at: serverTimestamp()}));
  const key = Buffer.alloc(32, 3).toString('base64');
  await assertSucceeds(setDoc(doc(owner, 'location_public_keys', 'objective'), {key}));
  await assertSucceeds(setDoc(doc(observer, 'location_public_keys', 'observer'), {key}));
  await assertSucceeds(updateDoc(doc(owner, 'monitoring_links', 'objective:observer'),
    {status: 'active', accepted_at: serverTimestamp()}));
  await assertSucceeds(getDoc(doc(observer, 'events', 'objective:one')));
  await assertSucceeds(getDocs(query(collection(observer, 'events'),
    where('objective_id', '==', 'objective'))));
  await assertFails(getDoc(doc(db('other'), 'events', 'objective:one')));
  await assertFails(getDocs(collection(observer, 'events')));
  await assertSucceeds(updateDoc(ref, {status: 'revoked', revoked_at: serverTimestamp()}));
  await assertFails(getDoc(doc(observer, 'events', 'objective:one')));
});

test('un SOS se escribe una vez y rechaza coordenadas en claro', async () => {
  const owner = db('objective');
  const ref = doc(owner, 'events', 'objective:record');
  await assertSucceeds(runTransaction(owner, async (tx) => {
    if (!(await tx.get(ref)).exists()) tx.set(ref, event());
  }));
  await assertFails(updateDoc(ref, {severity: 'informative'}));
  await assertFails(setDoc(doc(owner, 'events', 'objective:raw'), {...event(), latitude: 1}));
  await assertFails(setDoc(doc(db('observer'), 'events', 'observer:wrong'), event()));
  await assertFails(setDoc(doc(owner, 'events', 'objective:bad'),
    {...event(), encrypted_location: 'plaintext'}));
});

test('sólo el propietario puede publicar su clave y no se sobrescribe', async () => {
  const owner = db('objective');
  const key = Buffer.alloc(32, 3).toString('base64');
  await assertFails(setDoc(doc(db('observer'), 'location_public_keys', 'objective'), {key}));
  await assertSucceeds(setDoc(doc(owner, 'location_public_keys', 'objective'), {key}));
  await assertFails(updateDoc(doc(owner, 'location_public_keys', 'objective'),
    {key: Buffer.alloc(32, 4).toString('base64')}));
});
