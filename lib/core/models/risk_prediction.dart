class RiskPrediction {
  final List<double> probabilities;
  final int predictedClass; 
  final double confidence; 

  RiskPrediction({
    required this.probabilities,
    required this.predictedClass,
    required this.confidence,
  });

  String get riskLabel {
    switch (predictedClass) {
      case 0: return 'Normal';
      case 1: return 'Anómalo';
      case 2: return 'Crítico';
      default: return 'Desconocido';
    }
  }

  bool get isCritical => predictedClass == 2;
  bool get isAnomalous => predictedClass == 1;
  bool get isNormal => predictedClass == 0;
}