'use strict';

const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getFirestore} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentCreated, onDocumentUpdated} = require('firebase-functions/v2/firestore');
const {makePush} = require('./push');

initializeApp();
const db = getFirestore();

exports.lookupObjective = onCall(async ({auth, data}) => {
  if (!auth) throw new HttpsError('unauthenticated', 'Inicia sesión');
  const email = data?.email;
  if (typeof email !== 'string' || email.length > 254 || !email.includes('@')) {
    throw new HttpsError('invalid-argument', 'Correo no válido');
  }
  try {
    const user = await getAuth().getUserByEmail(email.trim().toLowerCase());
    const profile = (await db.doc(`users/${user.uid}`).get()).data();
    if (!user.disabled && profile?.is_deleted !== true && profile?.role_tags?.includes('objective')) {
      return {uid: user.uid};
    }
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
  }
  throw new HttpsError('not-found', 'No hay una cuenta de objetivo para ese correo');
});

exports.getPendingObserver = onCall(async ({auth, data}) => {
  if (!auth) throw new HttpsError('unauthenticated', 'Inicia sesión');
  const id = data?.linkId;
  if (typeof id !== 'string' || !id.startsWith(auth.uid + ':') || id.includes('/')) {
    throw new HttpsError('permission-denied', 'Vínculo no disponible');
  }
  const link = (await db.doc(`monitoring_links/${id}`).get()).data();
  if (link?.objective_id !== auth.uid || link.status !== 'pending') {
    throw new HttpsError('permission-denied', 'Vínculo no disponible');
  }
  const observer = (await db.doc(`users/${link.observer_id}`).get()).data();
  return {displayName: observer?.displayName ?? 'Usuario', email: observer?.email ?? ''};
});

async function notify(uid, type, objectiveId, recordId) {
  const user = (await db.doc(`users/${uid}`).get()).data();
  if (user?.is_deleted === true || typeof user?.fcm_token !== 'string' || !user.fcm_token) return;
  const payload = makePush({token: user.fcm_token, type, objectiveId, recordId});
  // El emulador no ofrece FCM. En el proyecto ficticio se verifica el aviso
  // preparado por el trigger sin enviar nada fuera de los emuladores.
  if (process.env.FUNCTIONS_EMULATOR === 'true' &&
      process.env.GCLOUD_PROJECT === 'demo-geocercas' &&
      process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    await db.doc(`_integration_push/${uid}:${type}:${recordId}`).set({
      recipient: uid,
      data: payload.data,
      title: payload.notification.title,
      body: payload.notification.body,
    });
    return;
  }
  try {
    await getMessaging().send(payload);
  } catch (error) {
    if (!['messaging/registration-token-not-registered',
      'messaging/invalid-registration-token'].includes(error.code)) throw error;
  }
}

async function notifyObservers(objectiveId, type, recordId) {
  const objective = (await db.doc(`users/${objectiveId}`).get()).data();
  if (!objective || objective.is_deleted === true) return;
  const links = await db.collection('monitoring_links')
    .where('objective_id', '==', objectiveId).where('status', '==', 'active').get();
  const observers = new Set(links.docs
    .filter((doc) => doc.id === `${objectiveId}:${doc.data().observer_id}`)
    .map((doc) => doc.data().observer_id));
  await Promise.all([...observers].map((uid) => notify(uid, type, objectiveId, recordId)));
}

exports.notifyEvent = onDocumentCreated('events/{id}', async ({data, params}) => {
  const event = data?.data();
  if (!event) return;
  if (event.event_type === 'sos_resolved') {
    return notify(event.objective_id, 'sos_resolved', event.objective_id, params.id);
  }
  const type = event.event_type === 'sos' ? 'sos_alert' :
    event.severity === 'critical' ? 'alert_critical' :
      event.severity === 'preventive' ? 'alert_preventive' : null;
  if (type) return notifyObservers(event.objective_id, type, params.id);
});

exports.notifyLinkRequest = onDocumentCreated('monitoring_links/{id}', async ({data, params}) => {
  const link = data?.data();
  if (link?.status === 'pending') {
    return notify(link.objective_id, 'link_request', link.objective_id, params.id);
  }
});

exports.notifyLinkAccepted = onDocumentUpdated('monitoring_links/{id}', async ({data, params}) => {
  const link = data?.after.data();
  if (data?.before.data()?.status === 'pending' && link?.status === 'active') {
    return notify(link.observer_id, 'link_accepted', link.objective_id, params.id);
  }
});

exports.notifySecurity = onDocumentCreated('security_notices/{id}', async ({data, params}) => {
  const event = data?.data();
  if (event) return notifyObservers(event.objective_id, 'security_alert', params.id);
});
