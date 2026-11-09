import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geocercas_app/core/services/decision_tree_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Dart coincide con las ocho rutas evaluadas en Python', () async {
    final model = DecisionTreeModel();
    await model.loadModel();
    final cases = jsonDecode(
      File('test/fixtures/critical_tree_cases.json').readAsStringSync(),
    ) as List;

    for (final sample in cases) {
      final features = (sample['features'] as List)
          .cast<num>()
          .map((x) => x.toDouble())
          .toList();
      final prediction = model.predict(features)!;
      final scores = (sample['scores'] as List).cast<num>();
      expect(prediction.predictedClass, sample['label'],
          reason: sample['path'] as String);
      expect(prediction.probabilities, orderedEquals(scores));
      expect(prediction.confidence, scores[prediction.predictedClass]);
      final path = model.getDecisionPath(features);
      expect(path, contains(prediction.riskLabel));
      expect(model.getDecisionPath(features), path);
    }
    expect(model.predict(List<double>.filled(18, double.nan)), isNull);
  });
}
