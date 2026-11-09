'use strict';
const assert = require('node:assert/strict');
const {test} = require('node:test');
const {makePush} = require('../push');

test('el push de SOS sólo contiene los identificadores de navegación', () => {
  const push = makePush({token: 'test', type: 'sos_alert', objectiveId: 'owner',
    recordId: 'owner:record', latitude: -16.5001, longitude: -68.1234});
  assert.deepEqual(push.data, {type: 'sos_alert', objective_id: 'owner', record_id: 'owner:record'});
  assert.doesNotMatch(JSON.stringify(push), /latitude|longitude|-16\.5001|-68\.1234/);
  assert.equal(push.android.notification.visibility, 'private');
});
test('un tipo no definido no genera un mensaje', () => {
  assert.throws(() => makePush({token: 'test', type: 'toString',
    objectiveId: 'owner', recordId: 'record'}), TypeError);
});
