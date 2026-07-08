import 'package:latlong2/latlong.dart';
import 'package:geocercas_app/data/services/geofence_service.dart';

/// Geocerca adaptativa con radio dinámico r(t) e histéresis
class AdaptiveGeofence {
  final String id;
  final String name;
  final String riskLevel;
  final String type; // 'circle' o 'polygon'
  final LatLng? center;
  final double baseRadius;
  final List<LatLng> vertices;

  AdaptiveGeofence({
    required this.id,
    required this.name,
    required this.riskLevel,
    required this.type,
    this.center,
    required this.baseRadius,
    this.vertices = const [],
  });

  factory AdaptiveGeofence.fromFirestore(Map<String, dynamic> data) {
    final centerData = data['center'];
    final center = centerData != null
        ? LatLng(centerData.latitude, centerData.longitude)
        : null;

    final verticesData = List<Map<String, dynamic>>.from(data['vertices'] ?? []);
    final vertices = verticesData
        .map((v) => LatLng(
              (v['lat'] as num).toDouble(),
              (v['lng'] as num).toDouble(),
            ))
        .toList();

    return AdaptiveGeofence(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? 'Sin nombre',
      riskLevel: data['risk_level'] as String? ?? 'medium',
      type: data['type'] as String? ?? 'polygon',
      center: center,
      baseRadius: (data['radius'] as num?)?.toDouble() ?? 100.0,
      vertices: vertices,
    );
  }

  ///  Calcula el radio adaptativo r(t) según contexto
  /// Fórmula: r(t) = r_base × f(accuracy) × f(speed) × f(hour) × f(risk)
  double calculateAdaptiveRadius({
    required double accuracy,
    required double speed,
    required DateTime timestamp,
  }) {
    final fAccuracy = _accuracyFactor(accuracy);
    final fSpeed = _speedFactor(speed);
    final fHour = _hourFactor(timestamp);
    final fRisk = _riskFactor();

    return baseRadius * fAccuracy * fSpeed * fHour * fRisk;
  }

  /// Factor por calidad de señal
  /// Mala señal → expande radio para reducir falsos positivos
  double _accuracyFactor(double accuracy) {
    // accuracy en metros; 10m es ideal
    return 1.0 + 0.15 * (accuracy / 10.0);
  }

  /// Factor por velocidad
  /// Alta velocidad → expande radio para evitar activaciones por cruce breve
  double _speedFactor(double speed) {
    // speed en m/s; 2m/s es caminar,
    return 1.0 + 0.05 * speed;
  }

  /// Factor por horario
  /// Noche → reduce radio porque hay más riesgo
  double _hourFactor(DateTime timestamp) {
    final hour = timestamp.hour;
    final isNight = hour >= 22 || hour <= 5;
    return isNight ? 0.85 : 1.0;
  }

  /// Factor por nivel de riesgo
  /// Zona de alto riesgo → reduce radio 
  double _riskFactor() {
    switch (riskLevel) {
      case 'high': return 0.9;   // Más estricto
      case 'medium': return 1.0; // Normal
      case 'low': return 1.1;    // Más permisivo
      default: return 1.0;
    }
  }

  ///  Evalúa pertenencia con HISTÉRESIS
  /// Umbral de entrada: 0.95 × r(t) (más fácil entrar)
  /// Umbral de salida: 1.05 × r(t) (más difícil salir)
  GeofenceEvaluation evaluate({
    required LatLng position,
    required double accuracy,
    required double speed,
    required DateTime timestamp,
    required bool wasInside,
  }) {
    final adaptiveRadius = calculateAdaptiveRadius(
      accuracy: accuracy,
      speed: speed,
      timestamp: timestamp,
    );

    final entryThreshold = adaptiveRadius * 0.95;
    final exitThreshold = adaptiveRadius * 1.05;

    double distance;

    if (type == 'circle' && center != null) {
      distance = GeofenceService.calculateDistance(position, center!);
    } else if (type == 'polygon' && vertices.length >= 3 && center != null) {
      // Para polígonos, usamos distancia al centroide como aproximación
      distance = GeofenceService.calculateDistance(position, center!);
    } else {
      return GeofenceEvaluation(
        isInside: false,
        distance: 999999.0,
        adaptiveRadius: adaptiveRadius,
        justEntered: false,
        justExited: false,
      );
    }

    // Aplicar histéresis
    bool isInside;
    if (wasInside) {
      isInside = distance <= exitThreshold;
    } else {
      isInside = distance <= entryThreshold;
    }

    final justEntered = isInside && !wasInside;
    final justExited = !isInside && wasInside;

    return GeofenceEvaluation(
      isInside: isInside,
      distance: distance,
      adaptiveRadius: adaptiveRadius,
      justEntered: justEntered,
      justExited: justExited,
    );
  }
}

/// Resultado de evaluación de geocerca adaptativa
class GeofenceEvaluation {
  final bool isInside;
  final double distance;
  final double adaptiveRadius;
  final bool justEntered;
  final bool justExited;

  GeofenceEvaluation({
    required this.isInside,
    required this.distance,
    required this.adaptiveRadius,
    required this.justEntered,
    required this.justExited,
  });

  @override
  String toString() {
    return 'GeofenceEvaluation(inside: $isInside, dist: ${distance.toStringAsFixed(1)}m, '
        'r(t): ${adaptiveRadius.toStringAsFixed(1)}m, entered: $justEntered, exited: $justExited)';
  }
}