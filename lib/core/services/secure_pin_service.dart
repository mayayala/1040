import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecurePinService {
  static final SecurePinService _instance = SecurePinService._internal();
  factory SecurePinService() => _instance;
  SecurePinService._internal();

  final _storage = const FlutterSecureStorage();
  static const String _pinKey = 'app_security_pin';
  static const String _biometricEnabledKey = 'app_biometric_enabled';
  static const String _failedAttemptsKey = 'app_failed_pin_attempts';
  static const String _lockedUntilKey = 'app_locked_until';
  
  static const int maxFailedAttempts = 3;

  Future<void> setPin(String pin) async {
    await _storage.write(key: _pinKey, value: pin);
    await resetFailedAttempts();
  }

  Future<String?> getPin() async {
    return await _storage.read(key: _pinKey);
  }

  Future<void> clearPin() async {
    await _storage.delete(key: _pinKey);
    await _storage.delete(key: _biometricEnabledKey);
    await resetFailedAttempts();
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(key: _biometricEnabledKey, value: enabled.toString());
  }

  Future<bool> isBiometricEnabled() async {
    final value = await _storage.read(key: _biometricEnabledKey);
    return value == 'true';
  }

  Future<int> getFailedAttempts() async {
    final value = await _storage.read(key: _failedAttemptsKey);
    return value != null ? int.tryParse(value) ?? 0 : 0;
  }

  Future<void> incrementFailedAttempts() async {
    final current = await getFailedAttempts();
    await _storage.write(key: _failedAttemptsKey, value: (current + 1).toString());
  }

  Future<void> resetFailedAttempts() async {
    await _storage.write(key: _failedAttemptsKey, value: '0');
    await _storage.delete(key: _lockedUntilKey);
  }

  /// Usa .inSeconds <= 0 para evitar discrepancias de milisegundos
  Future<bool> isLocked() async {
    final lockedUntilStr = await _storage.read(key: _lockedUntilKey);
    if (lockedUntilStr == null) return false;
    
    final lockedUntil = DateTime.tryParse(lockedUntilStr);
    if (lockedUntil == null) {
      await resetFailedAttempts();
      return false;
    }
    
    // Si los segundos restantes son 0 o menos, desbloqueamos inmediatamente
    final remainingSeconds = lockedUntil.difference(DateTime.now()).inSeconds;
    if (remainingSeconds <= 0) {
      await resetFailedAttempts();
      return false;
    }
    
    return true;
  }

  Future<void> lockAccount() async {
    // Bloqueo de 1 minuto
    final lockUntil = DateTime.now().add(const Duration(minutes: 1));
    await _storage.write(key: _lockedUntilKey, value: lockUntil.toIso8601String());
  }
  
  Future<int> getRemainingLockTime() async {
    final lockedUntilStr = await _storage.read(key: _lockedUntilKey);
    if (lockedUntilStr == null) return 0;
    
    final lockedUntil = DateTime.tryParse(lockedUntilStr);
    if (lockedUntil == null) return 0;
    
    final remaining = lockedUntil.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }
}