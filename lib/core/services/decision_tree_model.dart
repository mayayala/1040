import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:geocercas_app/core/models/risk_prediction.dart';

class DecisionTreeModel {
  static final DecisionTreeModel _instance = DecisionTreeModel._internal();
  factory DecisionTreeModel() => _instance;
  DecisionTreeModel._internal();

  bool _isLoaded = false;

  List<double> _mean = [];
  List<double> _scale = [];

  double _thresholdAnomalous = 0.5;
  double _thresholdCritical = 0.5;

  static const List<String> _featureNames = [
    'mean_speed',              // [0]
    'max_speed',               // [1]
    'std_speed',               // [2]
    'total_distance',          // [3]
    'mean_direction_change',   // [4]
    'max_direction_change',    // [5]
    'stationary_ratio',        // [6]
    'max_distance_from_home',  // [7]
    'mean_distance_from_home', // [8]
    'mean_zone_risk',          // [9]
    'max_zone_risk',           // [10]
    'gps_accuracy_mean',       // [11]
    'gps_accuracy_std',        // [12]
    'mean_hour_sin',           // [13]
    'mean_hour_cos',           // [14]
    'night_ratio',             // [15]
    'rush_hour_ratio',         // [16]
    'mean_altitude',           // [17]
  ];

  Future<void> loadModel() async {
    try {
      // Cargar parámetros
      final scalerJson = await rootBundle.loadString('assets/ml/tree_scaler_params.json');
      final scalerData = jsonDecode(scalerJson);
      _mean = List<double>.from(scalerData['mean']);
      _scale = List<double>.from(scalerData['scale']);

      // Cargar umbrales optimizados
      final thresholdJson = await rootBundle.loadString('assets/ml/threshold_params.json');
      final thresholdData = jsonDecode(thresholdJson);
      _thresholdAnomalous = (thresholdData['threshold_anomalous'] as num).toDouble();
      _thresholdCritical = (thresholdData['threshold_critical'] as num).toDouble();

      _isLoaded = true;
      print(' Árbol cargado: ${_mean.length} features, umbrales A=$_thresholdAnomalous C=$_thresholdCritical');
    } catch (e) {
      print(' Error al cargar árbol: $e');
      _isLoaded = false;
    }
  }

  /// Prediccion usando el árbol entrenado
  RiskPrediction? predict(List<double> features) {
    if (!_isLoaded || features.length != 18) {
      print(' Error: Se esperaban 18 features, se recibieron ${features.length}');
      return null;
    }

    final normalized = _normalize(features);
    final classProbs = _traverseTree(normalized, 0);

    int predictedClass;
    if (classProbs[2] >= _thresholdCritical) {
      predictedClass = 2; // Crítico
    } else if (classProbs[1] >= _thresholdAnomalous) {
      predictedClass = 1; // Anómalo
    } else {
      predictedClass = 0; // Normal
    }

    final confidence = classProbs[predictedClass];

    return RiskPrediction(
      probabilities: classProbs,
      predictedClass: predictedClass,
      confidence: confidence,
    );
  }

  List<double> _normalize(List<double> features) {
    if (_mean.isEmpty || _scale.isEmpty) return features;
    return List.generate(features.length, (i) {
      return (features[i] - _mean[i]) / (_scale[i] + 1e-10);
    });
  }

  List<double> _traverseTree(List<double> x, int depth) {
    if (x[2] < 0.0457) { // std_speed
      if (x[4] < 1.1950) { // mean_direction_change
        return [0.9765, 0.0227, 0.0008];
      } else {
        return [0.1704, 0.7785, 0.0511];
      }
    } else {
      if (x[2] < 1.6244) { // std_speed
        if (x[2] < 1.1977) { // std_speed
          return [0.0702, 0.8497, 0.0801];
        } else {
          return [0.0000, 0.6090, 0.3910];
        }
      } else {
        return [0.0000, 0.0946, 0.9054];
      }
    }
  }

  String getDecisionPath(List<double> features) {
    if (!_isLoaded) return 'Modelo no cargado';

    final normalized = _normalize(features);
    final path = <String>[];
    path.add('${_featureNames[2]}=${features[2].toStringAsFixed(3)} m/s');

    if (normalized[2] < 0.0457) {
      path.add('→ ${_featureNames[2]} ESTABLE (σ < 0.0457)');
      path.add('${_featureNames[4]}=${features[4].toStringAsFixed(3)}');

      if (normalized[4] < 1.1950) {
        path.add('→ ${_featureNames[4]} ESTABLE');
        path.add('→ Clasificación: NORMAL (97.6%)');
        path.add('Patrón: Movimiento predecible y constante');
      } else {
        path.add('→ ${_featureNames[4]} ERRÁTICA');
        path.add('→ Clasificación: ANÓMALO (77.8%)');
        path.add('Patrón: Cambios bruscos de dirección sin velocidad');
      }
    } else {
      path.add('→ ${_featureNames[2]} VARIABLE (σ ≥ 0.0457)');

      if (normalized[2] < 1.6244) {
        path.add('→ Variabilidad MODERADA');

        if (normalized[2] < 1.1977) {
          path.add('→ Clasificación: ANÓMALO (84.9%)');
          path.add('Patrón: Velocidad fluctuante moderada');
        } else {
          path.add('→ Variabilidad ALTA');
          path.add('→ Clasificación: ANÓMALO/CRÍTICO (60.9%/39.1%)');
          path.add('Patrón: Comportamiento errático intenso');
        }
      } else {
        path.add('→ Variabilidad EXTREMA (σ ≥ 1.6244)');
        path.add('→ Clasificación: CRÍTICO (90.5%)');
        path.add('Patrón: Movimiento caótico, posible emergencia');
      }
    }

    return path.join(' | ');
  }

  void dispose() {
    _isLoaded = false;
  }
}