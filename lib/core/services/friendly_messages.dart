/// Genera mensajes amigables para el usuario 
class FriendlyMessages {
  
  /// Mensajes para notificaciones push
  static String getPushTitle(String eventType, String severity) {
    switch (eventType) {
      case 'sos':
        return ' ¡EMERGENCIA!';
      case 'entry_high_risk':
        return ' Zona de riesgo detectada';
      case 'entry_medium_risk':
        return ' Entrada a zona monitoreada';
      case 'exit_high_risk':
        return ' Salió de zona de riesgo';
      case 'exit_medium_risk':
        return ' Salida de zona monitoreada';
      case 'signal_loss':
        return ' Señal de ubicación perdida';
      case 'ml_anomaly_no_geofence':
        return severity == 'critical' ? ' Comportamiento inusual detectado' : ' Actividad inusual';
      default:
        return ' Actualización de ubicación';
    }
  }

  static String getPushBody(String geofenceName, String eventType, String severity) {
    switch (eventType) {
      case 'sos':
        return 'Se activó el botón de emergencia. Revisa la ubicación inmediatamente.';
      case 'entry_high_risk':
        return '$geofenceName ingresó a una zona de alto riesgo. Mantente atento.';
      case 'entry_medium_risk':
        return '$geofenceName entró a una zona que estás monitoreando.';
      case 'exit_high_risk':
        return '$geofenceName salió de la zona de riesgo. Todo en orden.';
      case 'exit_medium_risk':
        return '$geofenceName salió de la zona monitoreada.';
      case 'signal_loss':
        return 'No se puede obtener la ubicación. Puede ser por mala señal o el dispositivo está apagado.';
      case 'ml_anomaly_no_geofence':
        return severity == 'critical' 
            ? 'Se detectó un movimiento inusual que podría indicar una situación de riesgo.'
            : 'Se observó un patrón de movimiento diferente al habitual.';
      default:
        return 'Nueva actualización de $geofenceName.';
    }
  }

  /// Explicaciones para el historial de eventos 
  static String getHistoryExplanation(String eventType, String geofenceName, String riskLevel) {
    switch (eventType) {
      case 'sos':
        return 'El usuario presionó el botón de emergencia solicitando ayuda inmediata.';
      
      case 'entry_high_risk':
        return '$geofenceName ingresó a una zona clasificada como de alto riesgo. El sistema generó una alerta crítica para que los observadores puedan actuar rápidamente.';
      
      case 'entry_medium_risk':
        return '$geofenceName entró a una zona que requiere atención. No es una emergencia inmediata, pero es importante mantener el seguimiento.';
      
      case 'exit_high_risk':
        return '$geofenceName salió de la zona de alto riesgo. La situación se normaliza, pero se recomienda verificar que esté en un lugar seguro.';
      
      case 'exit_medium_risk':
        return '$geofenceName salió de la zona monitoreada. El movimiento continúa siendo rastreado.';
      
      case 'signal_loss':
        return 'El dispositivo perdió la señal de ubicación. Esto puede deberse a: edificios altos, sótanos, zonas rurales o el dispositivo está apagado. Se registró la última posición conocida.';
      
      case 'ml_anomaly_no_geofence':
        return 'El sistema detectó un patrón de movimiento inusual fuera de las zonas configuradas. Esto puede indicar: cambios de ruta inesperados, velocidad anormal o comportamiento diferente al habitual.';
      
      case 'heartbeat_safe_zone':
        return 'Monitoreo rutinario: $geofenceName se encuentra en una zona segura con movimiento normal.';
      
      default:
        return 'Evento registrado en $geofenceName.';
    }
  }

  static String getTechnicalDetails({
    required String eventType,
    required double adaptiveRadius,
    required double baseRadius,
    required String mlPrediction,
    required double mlConfidence,
    required double speed,
  }) {
    return 'Detalles técnicos: Radio adaptativo ${adaptiveRadius.toStringAsFixed(0)}m (base ${baseRadius.toStringAsFixed(0)}m) | ML: $mlPrediction (${(mlConfidence * 100).toStringAsFixed(0)}%) | Velocidad: ${speed.toStringAsFixed(1)} m/s';
  }
}