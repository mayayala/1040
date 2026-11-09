import 'package:flutter_test/flutter_test.dart';
import 'package:geocercas_app/core/services/geofence_adaptive.dart';
import 'package:latlong2/latlong.dart';

void main() {
  final circle = AdaptiveGeofence(
    id: 'circle', name: 'Círculo', riskLevel: 'medium',
    type: 'circle', center: const LatLng(0, 0), baseRadius: 100,
  );
  final noon = DateTime(2026, 1, 1, 12);

  test('el ajuste responde a señal, velocidad y horario con límite superior', () {
    expect(circle.calculateAdaptiveRadius(accuracy: 10, speed: 2,
        timestamp: noon), closeTo(126.5, 1e-8));
    expect(circle.calculateAdaptiveRadius(accuracy: 10, speed: 2,
        timestamp: DateTime(2026, 1, 1, 23)), closeTo(150, 1e-8));
    expect(circle.calculateAdaptiveRadius(accuracy: 100, speed: 40,
        timestamp: noon), 150);
    final high = AdaptiveGeofence(id: 'high', name: 'Alto', riskLevel: 'high',
        type: 'circle', center: const LatLng(0, 0), baseRadius: 100);
    expect(high.calculateAdaptiveRadius(accuracy: 10, speed: 2,
        timestamp: DateTime(2026, 1, 1, 23)), closeTo(136.62, 1e-8));
  });

  test('la banda de histéresis conserva el estado anterior', () {
    final point = const LatLng(0, .0009);
    GeofenceEvaluation evaluate(bool previous) => circle.evaluate(
      position: point, accuracy: 0, speed: 0, timestamp: noon, wasInside: previous,
    );
    expect(evaluate(false).isInside, isFalse);
    expect(evaluate(true).isInside, isTrue);
    expect(evaluate(true).justExited, isFalse);
  });

  test('un polígono alargado sigue su contorno, no un círculo equivalente', () {
    final polygon = AdaptiveGeofence(
      id: 'p', name: 'Polígono', riskLevel: 'medium', type: 'polygon',
      baseRadius: 50, center: const LatLng(0, 0),
      vertices: const [LatLng(-.0001, -.002), LatLng(.0001, -.002),
        LatLng(.0001, .002), LatLng(-.0001, .002)],
    );
    GeofenceEvaluation evaluate(LatLng point) => polygon.evaluate(
      position: point, accuracy: 0, speed: 0, timestamp: noon, wasInside: false,
    );
    expect(evaluate(const LatLng(0, .0015)).justEntered, isTrue);
    expect(evaluate(const LatLng(.0003, 0)).isInside, isFalse);
  });
}
