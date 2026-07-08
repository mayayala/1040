import 'package:flutter/services.dart';

class HapticService {
  /// Vibra con patrón personalizado
  static Future<void> vibratePattern(List<int> pattern) async {
    try {
      // Vibración simple secuencial 
      for (int i = 0; i < pattern.length; i += 2) {
        final wait = i < pattern.length ? pattern[i] : 0;
        final duration = (i + 1) < pattern.length ? pattern[i + 1] : 100;
        
        if (wait > 0) {
          await Future.delayed(Duration(milliseconds: wait));
        }
        if (duration > 0) {
          await HapticFeedback.vibrate();
          await Future.delayed(Duration(milliseconds: duration));
        }
      }
    } catch (e) {
      // Vibración no disponible, ignorar
    }
  }

  /// Vibración corta de confirmación
  static Future<void> lightTap() async {
    await HapticFeedback.lightImpact();
  }

  /// Vibración media de alerta
  static Future<void> mediumTap() async {
    await HapticFeedback.mediumImpact();
  }

  /// Vibración fuerte de emergencia
  static Future<void> heavyTap() async {
    await HapticFeedback.heavyImpact();
  }
}