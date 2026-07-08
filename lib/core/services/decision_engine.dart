import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocercas_app/core/models/geofence_event.dart';
import 'package:geocercas_app/core/models/risk_prediction.dart';
import 'package:geocercas_app/core/services/decision_tree_model.dart';
import 'package:geocercas_app/core/services/geofence_adaptive.dart';
import 'package:geocercas_app/core/services/position_history.dart';
import 'package:geocercas_app/core/services/event_queue_service.dart';
import 'package:geocercas_app/core/services/friendly_messages.dart';

class DecisionEngine {
  static final DecisionTreeModel _treeModel = DecisionTreeModel();
  static final PositionHistory _positionHistory = PositionHistory(maxSize: 30);

  static final Map<String, bool> _lastGeofenceStates = {};
  static final Map<String, DateTime> _lastHeartbeats = {};
  static final Map<String, int> _lastMlStates = {};

  static Future<void> initialize() async {
    await _treeModel.loadModel();
  }

  static void updatePositionHistory(
    LatLng position, DateTime timestamp, {
    double speed = 0.0,
    double accuracy = 10.0,
    double altitude = 3640.0,
    double zoneRisk = 0.3,
    bool isNight = false,
    bool isRushHour = false,
    double distanceFromHome = 0.0,
  }) {
    _positionHistory.addPosition(
      position, timestamp,
      speed: speed,
      accuracy: accuracy,
      altitude: altitude,
      zoneRisk: zoneRisk,
      isNight: isNight,
      isRushHour: isRushHour,
      distanceFromHome: distanceFromHome,
    );
  }

  static List<GeofenceEvent> evaluate({
    required String objectiveId,
    required Position position,
    required List<Map<String, dynamic>> activeGeofences,
    required bool isSOSActive,
  }) {
    final events = <GeofenceEvent>[];
    final currentPos = LatLng(position.latitude, position.longitude);
    final now = DateTime.now();

    if (isSOSActive) {
      final event = _createEvent(
        objectiveId: objectiveId,
        geofenceId: 'sos_manual',
        geofenceName: 'SOS Manual',
        severity: EventSeverity.critical,
        eventType: 'sos',
        explanation: ' Regla Hard: Botón SOS activado manualmente.',
        position: position,
      );
      events.add(event);

      EventQueueService().notifyObserversOfAlert(
        objectiveId: objectiveId,
        severity: 'critical',
        geofenceName: 'SOS Manual',
        explanation: event.explanation,
        latitude: position.latitude,
        longitude: position.longitude,
        eventType: 'sos', 
      );

      return events;
    }

    if (position.accuracy > 50.0) {
      final event = _createEvent(
        objectiveId: objectiveId,
        geofenceId: 'signal_loss',
        geofenceName: 'Pérdida de Señal',
        severity: EventSeverity.critical,
        eventType: 'signal_loss',
        explanation: ' Regla Hard: Pérdida de señal GNSS (accuracy > 50m).',
        position: position,
      );
      events.add(event);

      EventQueueService().notifyObserversOfAlert(
        objectiveId: objectiveId,
        severity: 'critical',
        geofenceName: 'Pérdida de Señal',
        explanation: event.explanation,
        latitude: position.latitude,
        longitude: position.longitude,
        eventType: 'signal_loss', 
      );

      return events;
    }

    final features = _positionHistory.buildFeatureVector();
    final mlPrediction = _treeModel.predict(features);
    final decisionPath = _treeModel.getDecisionPath(features);

    for (final geofenceData in activeGeofences) {
      final geofence = AdaptiveGeofence.fromFirestore(geofenceData);
      final geofenceId = geofence.id;
      final wasInside = _lastGeofenceStates[geofenceId] ?? false;

      final evaluation = geofence.evaluate(
        position: currentPos,
        accuracy: position.accuracy,
        speed: position.speed,
        timestamp: now,
        wasInside: wasInside,
      );

      _lastGeofenceStates[geofenceId] = evaluation.isInside;

      if (evaluation.justEntered && (geofence.riskLevel == 'high' || geofence.riskLevel == 'medium')) {
        final event = _createEvent(
          objectiveId: objectiveId,
          geofenceId: geofenceId,
          geofenceName: geofence.name,
          severity: _getEntrySeverity(geofence.riskLevel, mlPrediction),
          eventType: 'entry_${geofence.riskLevel}_risk',
          explanation: _buildEntryExplanation(geofence, evaluation, mlPrediction, decisionPath),
          position: position,
        );
        events.add(event);

        EventQueueService().notifyObserversOfAlert(
          objectiveId: objectiveId,
          severity: event.severity == EventSeverity.critical ? 'critical' : 'preventive',
          geofenceName: geofence.name,
          explanation: event.explanation,
          latitude: position.latitude,
          longitude: position.longitude,
          eventType: 'entry_${geofence.riskLevel}_risk',
        );
      } else if (evaluation.justExited) {
        events.add(_createEvent(
          objectiveId: objectiveId,
          geofenceId: geofenceId,
          geofenceName: geofence.name,
          severity: _getExitSeverity(geofence.riskLevel, mlPrediction),
          eventType: 'exit_${geofence.riskLevel}_risk',
          explanation: _buildExitExplanation(geofence, evaluation, mlPrediction, decisionPath),
          position: position,
        ));
      } else if (evaluation.isInside) {
        final insideEvent = _evaluateInsideGeofence(
          objectiveId: objectiveId,
          position: position,
          geofence: geofence,
          evaluation: evaluation,
          mlPrediction: mlPrediction,
          decisionPath: decisionPath,
        );
        if (insideEvent != null) {
          events.add(insideEvent);

          if (insideEvent.severity == EventSeverity.critical || insideEvent.severity == EventSeverity.preventive) {
            EventQueueService().notifyObserversOfAlert(
              objectiveId: objectiveId,
              severity: insideEvent.severity == EventSeverity.critical ? 'critical' : 'preventive',
              geofenceName: geofence.name,
              explanation: insideEvent.explanation,
              latitude: position.latitude,
              longitude: position.longitude,
              eventType: 'ml_anomaly_no_geofence',
            );
          }
        }
      }
    }

    if (mlPrediction != null && (mlPrediction.isAnomalous || mlPrediction.isCritical)) {
      const globalKey = 'global_ml_state';
      final lastClass = _lastMlStates[globalKey] ?? 0;
      final currentClass = mlPrediction.predictedClass;
      final classChanged = lastClass != currentClass;
      _lastMlStates[globalKey] = currentClass;

      if (classChanged || mlPrediction.isCritical) {
        final event = _createEvent(
          objectiveId: objectiveId,
          geofenceId: 'ml_anomaly_no_geofence',
          geofenceName: 'Alerta ML (sin geocerca)',
          severity: mlPrediction.isCritical ? EventSeverity.critical : EventSeverity.preventive,
          eventType: 'ml_anomaly_no_geofence',
          explanation: _buildMlAlertExplanation(mlPrediction, decisionPath, position),
          position: position,
        );
        events.add(event);

        EventQueueService().notifyObserversOfAlert(
          objectiveId: objectiveId,
          severity: mlPrediction.isCritical ? 'critical' : 'preventive',
          geofenceName: 'Alerta ML',
          explanation: event.explanation,
          latitude: position.latitude,
          longitude: position.longitude,
          eventType: 'ml_anomaly_no_geofence',
        );
      }
    }

    return events;
  }

  static GeofenceEvent? _evaluateInsideGeofence({
    required String objectiveId,
    required Position position,
    required AdaptiveGeofence geofence,
    required GeofenceEvaluation evaluation,
    required RiskPrediction? mlPrediction,
    required String decisionPath,
  }) {
    final geofenceId = geofence.id;

    if (mlPrediction != null && (mlPrediction.isAnomalous || mlPrediction.isCritical)) {
      return _createEvent(
        objectiveId: objectiveId,
        geofenceId: geofenceId,
        geofenceName: geofence.name,
        severity: _combineRisks(geofence.riskLevel, mlPrediction),
        eventType: 'anomalous_inside_${geofence.riskLevel}',
        explanation: ' Híbrido: Dentro de zona [${geofence.riskLevel}] + '
            'ML: ${mlPrediction.riskLabel} (${(mlPrediction.confidence * 100).toStringAsFixed(0)}%). '
            'r(t)=${evaluation.adaptiveRadius.toStringAsFixed(1)}m. '
            'Ruta: $decisionPath',
        position: position,
      );
    }

    final lastHeartbeat = _lastHeartbeats[geofenceId];
    final now = DateTime.now();
    final intervalMinutes = geofence.riskLevel == 'high' ? 2 :
                            geofence.riskLevel == 'medium' ? 5 : 10;

    if (lastHeartbeat == null ||
        now.difference(lastHeartbeat).inMinutes >= intervalMinutes) {
      _lastHeartbeats[geofenceId] = now;

      final severity = geofence.riskLevel == 'high' ? EventSeverity.critical :
                       geofence.riskLevel == 'medium' ? EventSeverity.preventive :
                       EventSeverity.informative;

      return _createEvent(
        objectiveId: objectiveId,
        geofenceId: geofenceId,
        geofenceName: geofence.name,
        severity: severity,
        eventType: 'monitoring_${geofence.riskLevel}_zone',
        explanation: ' Monitoreo activo: zona [${geofence.riskLevel}]. '
            'r(t)=${evaluation.adaptiveRadius.toStringAsFixed(1)}m '
            '(base=${geofence.baseRadius.toStringAsFixed(0)}m). '
            'ML: ${mlPrediction?.riskLabel ?? "N/A"}. '
            'Distancia: ${evaluation.distance.toStringAsFixed(1)}m.',
        position: position,
      );
    }

    return null;
  }

  static EventSeverity _combineRisks(String observerRisk, RiskPrediction? ml) {
    if (ml == null) {
      switch (observerRisk) {
        case 'high':
          return EventSeverity.critical;
        case 'medium':
          return EventSeverity.preventive;
        default:
          return EventSeverity.informative;
      }
    }
    if (ml.isCritical) {
      return EventSeverity.critical;
    }
    if (ml.isAnomalous && observerRisk == 'high') {
      return EventSeverity.critical;
    }
    if (ml.isAnomalous) {
      return EventSeverity.preventive;
    }
    switch (observerRisk) {
      case 'high':
        return EventSeverity.critical;
      case 'medium':
        return EventSeverity.preventive;
      default:
        return EventSeverity.informative;
    }
  }

  static EventSeverity _getEntrySeverity(String risk, RiskPrediction? ml) {
    return _combineRisks(risk, ml);
  }

  static EventSeverity _getExitSeverity(String risk, RiskPrediction? ml) {
    if (ml?.isNormal == true && risk != 'high') {
      return EventSeverity.informative;
    }
    return _combineRisks(risk, ml);
  }

  static String _buildEntryExplanation(
    AdaptiveGeofence geofence,
    GeofenceEvaluation eval,
    RiskPrediction? mlPrediction,
    String decisionPath,
  ) {
    final friendlyMsg = FriendlyMessages.getHistoryExplanation(
      'entry_${geofence.riskLevel}_risk',
      geofence.name,
      geofence.riskLevel,
    );

    final technicalDetails = mlPrediction != null
        ? '\n\n Análisis técnico: ${FriendlyMessages.getTechnicalDetails(
            eventType: 'entry',
            adaptiveRadius: eval.adaptiveRadius,
            baseRadius: geofence.baseRadius,
            mlPrediction: mlPrediction.riskLabel,
            mlConfidence: mlPrediction.confidence,
            speed: 0.0, 
          )}'
        : '';

    return '$friendlyMsg$technicalDetails';
  }

  static String _buildExitExplanation(
    AdaptiveGeofence geofence,
    GeofenceEvaluation eval,
    RiskPrediction? mlPrediction,
    String decisionPath,
  ) {
    final friendlyMsg = FriendlyMessages.getHistoryExplanation(
      'exit_${geofence.riskLevel}_risk',
      geofence.name,
      geofence.riskLevel,
    );

    final technicalDetails = mlPrediction != null
        ? '\n\n Análisis técnico: ${FriendlyMessages.getTechnicalDetails(
            eventType: 'exit',
            adaptiveRadius: eval.adaptiveRadius,
            baseRadius: geofence.baseRadius,
            mlPrediction: mlPrediction.riskLabel,
            mlConfidence: mlPrediction.confidence,
            speed: 0.0,
          )}'
        : '';

    return '$friendlyMsg$technicalDetails';
  }

  static String _buildMlAlertExplanation(
    RiskPrediction ml,
    String decisionPath,
    Position position,
  ) {
    final friendlyMsg = ml.isCritical
        ? ' El sistema detectó un movimiento inusual que podría indicar una situación de riesgo. Se recomienda contactar al usuario inmediatamente.'
        : ' Se observó un patrón de movimiento diferente al habitual. No es una emergencia, pero es recomendable verificar el estado del usuario.';

    final technicalDetails = '\n\n Análisis técnico: Confianza del modelo ${(ml.confidence * 100).toStringAsFixed(1)}% | Velocidad: ${position.speed.toStringAsFixed(1)} m/s';

    return '$friendlyMsg$technicalDetails';
  }

  static GeofenceEvent _createEvent({
    required String objectiveId,
    required String geofenceId,
    required String geofenceName,
    required EventSeverity severity,
    required String eventType,
    required String explanation,
    required Position position,
  }) {
    return GeofenceEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      objectiveId: objectiveId,
      geofenceId: geofenceId,
      geofenceName: geofenceName,
      severity: severity,
      eventType: eventType,
      explanation: explanation,
      latitude: position.latitude,
      longitude: position.longitude,
      hdop: position.accuracy,
      velocity: position.speed,
      timestamp: DateTime.now(),
    );
  }
}