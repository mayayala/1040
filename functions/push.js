'use strict';

const labels = {
  sos_alert: 'Alerta SOS',
  alert_critical: 'Alerta crítica',
  alert_preventive: 'Alerta preventiva',
  sos_resolved: 'Alerta SOS desactivada',
  link_request: 'Nueva solicitud de vínculo',
  link_accepted: 'Solicitud de vínculo aceptada',
  security_alert: 'Alerta de seguridad',
};

function makePush({token, type, objectiveId, recordId}) {
  if (!Object.hasOwn(labels, type) || !token || !objectiveId || !recordId) {
    throw new TypeError('Tipo o identificador de notificación inválido');
  }
  return {
    token,
    notification: {title: labels[type], body: 'Abre la aplicación para consultar los detalles.'},
    data: {type, objective_id: objectiveId, record_id: recordId},
    android: {
      priority: 'high',
      ttl: 3600 * 1000,
      notification: {channelId: 'high_importance_channel', visibility: 'private', tag: recordId},
    },
  };
}

module.exports = {makePush};
