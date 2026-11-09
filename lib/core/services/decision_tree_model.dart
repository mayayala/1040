import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:geocercas_app/core/models/risk_prediction.dart';

class DecisionTreeModel {
  static final DecisionTreeModel _instance = DecisionTreeModel._internal();
  factory DecisionTreeModel() => _instance;
  DecisionTreeModel._internal();

  _TreeNode? _root;
  late List<double> _mean;
  late List<double> _scale;
  late List<String> _names;
  late double _anomalous;
  late double _critical;

  Future<void> loadModel() async {
    _root = null;
    try {
      final scaler = jsonDecode(
        await rootBundle.loadString('assets/ml/tree_scaler_params.json'),
      ) as Map<String, dynamic>;
      final thresholds = jsonDecode(
        await rootBundle.loadString('assets/ml/threshold_params.json'),
      ) as Map<String, dynamic>;
      final root = _TreeNode.parse(jsonDecode(
        await rootBundle.loadString('assets/ml/decision_tree.json'),
      ) as Map<String, dynamic>, 0);
      _mean = (scaler['mean'] as List).map((x) => (x as num).toDouble()).toList();
      _scale = (scaler['scale'] as List).map((x) => (x as num).toDouble()).toList();
      _names = List<String>.from(scaler['feature_names'] as List);
      _anomalous = (thresholds['threshold_anomalous'] as num).toDouble();
      _critical = (thresholds['threshold_critical'] as num).toDouble();
      if (_mean.length != 18 || _scale.length != 18 || _names.length != 18 ||
          _mean.any((x) => !x.isFinite) ||
          _scale.any((x) => !x.isFinite || x <= 0) ||
          [_anomalous, _critical].any((x) => !x.isFinite || x < 0 || x > 1)) {
        throw const FormatException('Parámetros del árbol inválidos');
      }
      _root = root;
    } catch (_) {
      // Las reglas explícitas del motor siguen disponibles.
      _root = null;
    }
  }

  RiskPrediction? predict(List<double> features) => _evaluate(features);

  String getDecisionPath(List<double> features) {
    final path = <String>[];
    final prediction = _evaluate(features, path: path);
    if (prediction == null) return 'Modelo o datos no disponibles';
    path.add('Clase: ${prediction.riskLabel} '
        '(${(100 * prediction.confidence).toStringAsFixed(1)} %)');
    return path.join(' | ');
  }

  RiskPrediction? _evaluate(List<double> features, {List<String>? path}) {
    final root = _root;
    if (root == null || features.length != 18 ||
        features.any((x) => !x.isFinite)) {
      return null;
    }
    var node = root;
    while (node.scores == null) {
      final index = node.feature!;
      final value = (features[index] - _mean[index]) / (_scale[index] + 1e-10);
      final threshold = node.threshold!;
      final left = value < threshold;
      path?.add('${_names[index]} normalizado: ${value.toStringAsFixed(4)} '
          '${left ? "<" : "≥"} $threshold');
      node = left ? node.left! : node.right!;
    }
    final scores = node.scores!;
    final label = scores[2] >= _critical ? 2 : (scores[1] >= _anomalous ? 1 : 0);
    return RiskPrediction(
      probabilities: scores,
      predictedClass: label,
      confidence: scores[label],
    );
  }

  void dispose() => _root = null;
}

class _TreeNode {
  final List<double>? scores;
  final int? feature;
  final double? threshold;
  final _TreeNode? left;
  final _TreeNode? right;

  const _TreeNode({this.scores, this.feature, this.threshold, this.left, this.right});

  factory _TreeNode.parse(Map<String, dynamic> data, int depth) {
    if (depth > 3) throw const FormatException('Profundidad inválida');
    if (data.containsKey('scores')) {
      final scores = (data['scores'] as List).map((x) => (x as num).toDouble());
      final values = List<double>.unmodifiable(scores);
      if (values.length != 3 ||
          values.any((x) => !x.isFinite || x < 0 || x > 1) ||
          (values.reduce((a, b) => a + b) - 1).abs() > 0.001) {
        throw const FormatException('Hoja inválida');
      }
      return _TreeNode(scores: values);
    }
    final feature = data['feature'] as int;
    final threshold = (data['threshold'] as num).toDouble();
    if (feature < 0 || feature >= 18 || !threshold.isFinite) {
      throw const FormatException('Nodo inválido');
    }
    return _TreeNode(
      feature: feature, threshold: threshold,
      left: _TreeNode.parse(data['left'] as Map<String, dynamic>, depth + 1),
      right: _TreeNode.parse(data['right'] as Map<String, dynamic>, depth + 1),
    );
  }
}
