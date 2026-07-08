import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:geocercas_app/core/services/secure_pin_service.dart';

class AppLockService {
  static final AppLockService _instance = AppLockService._internal();
  factory AppLockService() => _instance;
  AppLockService._internal();

  final LocalAuthentication _localAuth = LocalAuthentication();
  final SecurePinService _pinService = SecurePinService();

  Future<bool> canCheckBiometrics() async {
    try {
      final isAvailable = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return isAvailable && isDeviceSupported;
    } catch (e) {
      print(' Error al verificar biometría: $e');
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      print(' Error al obtener tipos de biometría: $e');
      return [];
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      final canCheck = await canCheckBiometrics();
      if (!canCheck) {
        print(' Biometría no disponible en este dispositivo');
        return false;
      }

      final availableBiometrics = await getAvailableBiometrics();
      print(' Biometría disponible: $availableBiometrics');

      if (availableBiometrics.isEmpty) {
        print(' No hay sensores biométricos registrados');
        return false;
      }

      return await _localAuth.authenticate(
        localizedReason: 'Autentícate para acceder a Geocercas',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (e) {
      print(' Error de plataforma en biometría: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      print(' Error inesperado en biometría: $e');
      return false;
    }
  }

  Future<bool> verifyPin(String enteredPin) async {
    final savedPin = await _pinService.getPin();
    return savedPin == enteredPin;
  }

  Future<void> setupPin(String newPin) async {
    await _pinService.setPin(newPin);
  }
}