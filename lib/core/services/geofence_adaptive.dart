import 'dart:math' as math;
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
    if (!baseRadius.isFinite || baseRadius <= 0) return 0.0;
    final fAccuracy = _accuracyFactor(accuracy);
    final fSpeed = _speedFactor(speed);
    final fHour = _hourFactor(timestamp);
    final fRisk = _riskFactor();

    return (baseRadius * fAccuracy * fSpeed * fHour * fRisk)
        .clamp(baseRadius * 0.75, baseRadius * 1.5).toDouble();
  }

  /// Factor por calidad de señal
  /// Mala señal → expande radio para reducir falsos positivos
  double _accuracyFactor(double accuracy) {
    // accuracy en metros; 10m es ideal
    return 1.0 + 0.15 * (accuracy.isFinite ? math.max(0.0, accuracy) : 0.0) / 10.0;
  }

  /// Factor por velocidad
  /// Alta velocidad → expande radio para evitar activaciones por cruce breve
  double _speedFactor(double speed) {
    // speed en m/s; 2m/s es caminar,
    return 1.0 + 0.05 * (speed.isFinite ? math.max(0.0, speed) : 0.0);
  }

  /// Factor por horario
  /// Factor nocturno de la política adaptativa
  double _hourFactor(DateTime timestamp) {
    final hour = timestamp.hour;
    final isNight = hour >= 22 || hour <= 5;
    return isNight ? 1.2 : 1.0;
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
  /// Umbral de entrada: 0.95 × r(t) (exige cruzar hacia el interior)
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
    bool isInside;
    final threshold = wasInside ? exitThreshold : entryThreshold;

    if (adaptiveRadius > 0 && type == 'circle' && center != null) {
      distance = GeofenceService.calculateDistance(position, center!);
      isInside = distance <= threshold;
    } else if (adaptiveRadius > 0 && type == 'polygon' && vertices.length >= 3) {
      final signedDistance = _signedDistanceToBoundary(position);
      distance = signedDistance.abs();
      // El radio equivalente determina el margen; el límite sigue siendo
      // el contorno del polígono, incluso cuando no es convexo.
      isInside = signedDistance <= threshold - baseRadius;
    } else {
      return GeofenceEvaluation(
        isInside: false,
        distance: 999999.0,
        adaptiveRadius: adaptiveRadius,
        justEntered: false,
        justExited: false,
      );
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
  // Proyección local en metros para perímetros urbanos.
  double _signedDistanceToBoundary(LatLng point) {
    const metresPerDegree = 6371000 * math.pi / 180;
    final lonScale = metresPerDegree * math.cos(point.latitude * math.pi / 180);
    var nearest = double.infinity;
    for (var i = 0; i < vertices.length; i++) {
      final a = vertices[i];
      final b = vertices[(i + 1) % vertices.length];
      final ax = (a.longitude - point.longitude) * lonScale;
      final ay = (a.latitude - point.latitude) * metresPerDegree;
      final dx = (b.longitude - a.longitude) * lonScale;
      final dy = (b.latitude - a.latitude) * metresPerDegree;
      final length2 = dx * dx + dy * dy;
      final t = length2 == 0 ? 0.0 :
          (-(ax * dx + ay * dy) / length2).clamp(0.0, 1.0).toDouble();
      final x = ax + t * dx;
      final y = ay + t * dy;
      nearest = math.min(nearest, math.sqrt(x * x + y * y));
    }
    return GeofenceService.isPointInPolygon(point, vertices) ? -nearest : nearest;
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