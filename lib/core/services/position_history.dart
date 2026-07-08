import 'package:latlong2/latlong.dart';

class PositionHistory {
  final int maxSize;
  final List<_PositionSample> _buffer = [];

  PositionHistory({this.maxSize = 30});

  /// Agrega una posición con todos los datos
  void addPosition(
    LatLng position,
    DateTime timestamp, {
    double speed = 0.0,
    double accuracy = 10.0,
    double altitude = 3640.0,
    double zoneRisk = 0.3,
    bool isNight = false,
    bool isRushHour = false,
    double distanceFromHome = 0.0,
  }) {
    final hour = timestamp.hour;
    final hourSin = _sin(2 * 3.14159265359 * hour / 24);
    final hourCos = _cos(2 * 3.14159265359 * hour / 24);

    _buffer.add(_PositionSample(
      position: position,
      timestamp: timestamp,
      speed: speed,
      accuracy: accuracy,
      altitude: altitude,
      zoneRisk: zoneRisk,
      isNight: isNight,
      isRushHour: isRushHour,
      distanceFromHome: distanceFromHome,
      hourSin: hourSin,
      hourCos: hourCos,
    ));

    if (_buffer.length > maxSize) {
      _buffer.removeAt(0);
    }
  }

  ///  Construye el vector de 18 features agregadas
  List<double> buildFeatureVector() {
    if (_buffer.length < 5) {
      return List.filled(18, 0.0);
    }

    // 1. Velocidad
    final speeds = _buffer.map((s) => s.speed).toList();
    final meanSpeed = _mean(speeds);
    final maxSpeed = speeds.reduce((a, b) => a > b ? a : b);
    final stdSpeed = _std(speeds);

    // 2. Distancia total recorrida en la ventana
    double totalDistance = 0.0;
    for (int i = 1; i < _buffer.length; i++) {
      totalDistance += _haversineDistance(_buffer[i - 1].position, _buffer[i].position);
    }

    // 3. Cambios de dirección
    final dirChanges = <double>[];
    for (int i = 2; i < _buffer.length; i++) {
      final p0 = _buffer[i - 2].position;
      final p1 = _buffer[i - 1].position;
      final p2 = _buffer[i].position;

      final v1Lat = p1.latitude - p0.latitude;
      final v1Lng = p1.longitude - p0.longitude;
      final v2Lat = p2.latitude - p1.latitude;
      final v2Lng = p2.longitude - p1.longitude;

      final mag1 = _sqrt(v1Lat * v1Lat + v1Lng * v1Lng);
      final mag2 = _sqrt(v2Lat * v2Lat + v2Lng * v2Lng);

      if (mag1 > 1e-10 && mag2 > 1e-10) {
        final dot = v1Lat * v2Lat + v1Lng * v2Lng;
        final cosAngle = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
        dirChanges.add(_acos(cosAngle) / 3.14159265359);
      }
    }
    final meanDirChange = dirChanges.isEmpty ? 0.0 : _mean(dirChanges);
    final maxDirChange = dirChanges.isEmpty ? 0.0 : dirChanges.reduce((a, b) => a > b ? a : b);

    // 4. Ratio de estacionariedad (velocidad < 0.5 m/s)
    final stationaryCount = _buffer.where((s) => s.speed < 0.5).length;
    final stationaryRatio = stationaryCount / _buffer.length;

    // 5. Distancia al hogar
    final distancesFromHome = _buffer.map((s) => s.distanceFromHome).toList();
    final maxDistFromHome = distancesFromHome.reduce((a, b) => a > b ? a : b);
    final meanDistFromHome = _mean(distancesFromHome);

    // 6. Riesgo de zona
    final risks = _buffer.map((s) => s.zoneRisk).toList();
    final meanZoneRisk = _mean(risks);
    final maxZoneRisk = risks.reduce((a, b) => a > b ? a : b);

    // 7. Calidad GPS
    final accuracies = _buffer.map((s) => s.accuracy).toList();
    final gpsAccMean = _mean(accuracies);
    final gpsAccStd = _std(accuracies);

    // 8. Contexto temporal
    final hourSins = _buffer.map((s) => s.hourSin).toList();
    final hourCoss = _buffer.map((s) => s.hourCos).toList();
    final meanHourSin = _mean(hourSins);
    final meanHourCos = _mean(hourCoss);

    final nightCount = _buffer.where((s) => s.isNight).length;
    final nightRatio = nightCount / _buffer.length;

    final rushHourCount = _buffer.where((s) => s.isRushHour).length;
    final rushHourRatio = rushHourCount / _buffer.length;

    // 9. Altitud
    final altitudes = _buffer.map((s) => s.altitude).toList();
    final meanAltitude = _mean(altitudes);

    //  Vector de 18 features
    return [
      meanSpeed,          // [0]  mean_speed
      maxSpeed,           // [1]  max_speed
      stdSpeed,           // [2]  std_speed
      totalDistance,      // [3]  total_distance
      meanDirChange,      // [4]  mean_direction_change
      maxDirChange,       // [5]  max_direction_change
      stationaryRatio,    // [6]  stationary_ratio
      maxDistFromHome,    // [7]  max_distance_from_home
      meanDistFromHome,   // [8]  mean_distance_from_home
      meanZoneRisk,       // [9]  mean_zone_risk
      maxZoneRisk,        // [10] max_zone_risk
      gpsAccMean,         // [11] gps_accuracy_mean
      gpsAccStd,          // [12] gps_accuracy_std
      meanHourSin,        // [13] mean_hour_sin
      meanHourCos,        // [14] mean_hour_cos
      nightRatio,         // [15] night_ratio
      rushHourRatio,      // [16] rush_hour_ratio
      meanAltitude,       // [17] mean_altitude
    ];
  }


  double _mean(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double _std(List<double> values) {
    if (values.length < 2) return 0.0;
    final m = _mean(values);
    final variance = values.map((v) => (v - m) * (v - m)).reduce((a, b) => a + b) / values.length;
    return _sqrt(variance);
  }

  double _sqrt(double x) {
    if (x <= 0) return 0.0;
    double r = x;
    for (int i = 0; i < 5; i++) {
      r = (r + x / r) / 2;
    }
    return r;
  }

  double _sin(double x) {
    // Aproximación de Taylor
    return x - (x * x * x) / 6 + (x * x * x * x * x) / 120;
  }

  double _cos(double x) {
    return 1 - (x * x) / 2 + (x * x * x * x) / 24;
  }

  double _acos(double x) {
    if (x <= -1) return 3.14159265359;
    if (x >= 1) return 0.0;
    final asin = x + (x * x * x) / 6 + (3 * x * x * x * x * x) / 40;
    return 1.57079632679 - asin;
  }

  ///  Distancia Haversine entre dos puntos 
  double _haversineDistance(LatLng p1, LatLng p2) {
    const R = 6371000.0; // Radio terrestre 
    final dLat = _toRad(p2.latitude - p1.latitude);
    final dLng = _toRad(p2.longitude - p1.longitude);
    final a = _sin(dLat / 2) * _sin(dLat / 2) +
        _cos(_toRad(p1.latitude)) * _cos(_toRad(p2.latitude)) *
            _sin(dLng / 2) * _sin(dLng / 2);
    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    return R * c;
  }

  double _toRad(double deg) => deg * 0.01745329251;

  double _atan2(double y, double x) {
    if (x > 0) return _atan(y / x);
    if (x < 0 && y >= 0) return _atan(y / x) + 3.14159265359;
    if (x < 0 && y < 0) return _atan(y / x) - 3.14159265359;
    if (x == 0 && y > 0) return 1.57079632679;
    if (x == 0 && y < 0) return -1.57079632679;
    return 0.0;
  }

  double _atan(double x) {
    return x - (x * x * x) / 3 + (x * x * x * x * x) / 5;
  }

  void clear() {
    _buffer.clear();
  }
}

/// Muestra la posición 
class _PositionSample {
  final LatLng position;
  final DateTime timestamp;
  final double speed;
  final double accuracy;
  final double altitude;
  final double zoneRisk;
  final bool isNight;
  final bool isRushHour;
  final double distanceFromHome;
  final double hourSin;
  final double hourCos;

  _PositionSample({
    required this.position,
    required this.timestamp,
    required this.speed,
    required this.accuracy,
    required this.altitude,
    required this.zoneRisk,
    required this.isNight,
    required this.isRushHour,
    required this.distanceFromHome,
    required this.hourSin,
    required this.hourCos,
  });
}