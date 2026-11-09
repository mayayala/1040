import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocercas_app/core/services/decision_tree_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('las cinco hojas conservan clasificación y ruta reproducibles', () async {
    final model = DecisionTreeModel();
    await model.loadModel();
    final scaler = jsonDecode(await rootBundle.loadString('assets/ml/tree_scaler_params.json'));
    final means = (scaler['mean'] as List).cast<num>().map((x) => x.toDouble()).toList();
    final scales = (scaler['scale'] as List).cast<num>().map((x) => x.toDouble()).toList();

    for (final (stdSpeed, direction, label, expectedScore) in [
      (0.0, 0.0, 0, .9765), (0.0, 1.3, 1, .7785),
      (1.0, 0.0, 1, .8497), (1.4, 0.0, 1, .609),
      (2.0, 0.0, 2, .9054),
    ]) {
      final features = [...means];
      features[2] += stdSpeed * scales[2];
      features[4] += direction * scales[4];
      final prediction = model.predict(features)!;
      expect(prediction.predictedClass, label);
      expect(prediction.confidence, expectedScore);
      final path = model.getDecisionPath(features);
      expect(path, contains(prediction.riskLabel));
      expect(model.getDecisionPath(features), path);
    }
    expect(model.predict(List<double>.filled(18, double.nan)), isNull);
  });
}
