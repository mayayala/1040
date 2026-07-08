import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocercas_app/core/services/app_lock_service.dart';
import 'package:geocercas_app/core/services/secure_pin_service.dart';
import 'package:geocercas_app/core/services/notification_service.dart';

class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlock;
  final bool isFirstTimeSetup;

  const AppLockScreen({
    super.key,
    required this.onUnlock,
    this.isFirstTimeSetup = false,
  });

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final AppLockService _lockService = AppLockService();
  final SecurePinService _pinService = SecurePinService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _enteredPin = '';
  bool _isBiometricAvailable = false;
  bool _biometricFailed = false;
  String _errorMessage = '';
  int _failedAttempts = 0;
  bool _isLocked = false;
  int _remainingLockTime = 0;
  bool _isUnlockingWithPassword = false;

  @override
  void initState() {
    super.initState();
    _checkSecurityState();
  }

  Future<void> _checkSecurityState() async {
    final canCheck = await _lockService.canCheckBiometrics();
    final isBiometricEnabled = await _pinService.isBiometricEnabled();
    final failedAttempts = await _pinService.getFailedAttempts();
    final isLocked = await _pinService.isLocked();

    debugPrint('Estado de seguridad:');
    debugPrint('Biometría disponible: $canCheck');
    debugPrint('Biometría habilitada: $isBiometricEnabled');
    debugPrint('Intentos fallidos: $failedAttempts');
    debugPrint('Cuenta bloqueada: $isLocked');

    if (mounted) {
      setState(() {
        _isBiometricAvailable = canCheck && isBiometricEnabled;
        _failedAttempts = failedAttempts;
        _isLocked = isLocked;
      });
      // Inicialmente desbloqueo con biometria
      if (_isBiometricAvailable && !widget.isFirstTimeSetup && !_isLocked) {
        await _tryBiometricAuth();
      }
    }
  }

  Future<void> _tryBiometricAuth() async {
    debugPrint('Intentando autenticación biométrica...');
    final success = await _lockService.authenticateWithBiometrics();
    
    if (success && mounted) {
      debugPrint('Biometría exitosa');
      await _pinService.resetFailedAttempts();
      widget.onUnlock();
    } else if (mounted) {
      debugPrint('Biometría falló, mostrando PIN');
      setState(() {
        _biometricFailed = true;
        _errorMessage = 'Biometría no reconocida. Ingresa tu PIN.';
      });
    }
  }

  void _onKeyPressed(String key) {
    if (_isLocked) return;

    if (key == '⌫') {
      if (_enteredPin.isNotEmpty) {
        setState(() {
          _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
          _errorMessage = '';
        });
      }
    } else if (_enteredPin.length < 4) {
      setState(() {
        _enteredPin += key;
        _errorMessage = '';
      });

      if (_enteredPin.length == 4) {
        _verifyPin();
      }
    }
  }

  Future<void> _verifyPin() async {
    if (widget.isFirstTimeSetup) {
      await _lockService.setupPin(_enteredPin);
      await _pinService.setBiometricEnabled(true);
      widget.onUnlock();
      return;
    }

    final isValid = await _lockService.verifyPin(_enteredPin);
    debugPrint('Verificación PIN: ${isValid ? "CORRECTO" : "INCORRECTO"}');

    if (isValid) {
      await _pinService.resetFailedAttempts();
      widget.onUnlock();
    } else {
      final newAttempts = _failedAttempts + 1;
      await _pinService.incrementFailedAttempts();

      setState(() {
        _failedAttempts = newAttempts;
        _enteredPin = '';
      });

      if (newAttempts >= SecurePinService.maxFailedAttempts) {
        await _pinService.lockAccount();
        await _notifyObserversOfFailedAttempts();

        setState(() {
          _isLocked = true;
          _errorMessage = 'Cuenta bloqueada por seguridad.';
        });

        _startLockTimer();
      } else {
        setState(() {
          _errorMessage = 'PIN incorrecto. Intento $newAttempts de ${SecurePinService.maxFailedAttempts}.';
        });
      }
    }
  }

  Future<void> _notifyObserversOfFailedAttempts() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('No hay usuario autenticado para notificar');
        return;
      }

      debugPrint('Notificando a observadores sobre intentos fallidos...');

      final linksSnapshot = await FirebaseFirestore.instance
          .collection('monitoring_links')
          .where('objective_id', isEqualTo: user.uid)
          .where('status', isEqualTo: 'active')
          .get();

      debugPrint('Encontrados ${linksSnapshot.docs.length} observadores vinculados');

      for (final linkDoc in linksSnapshot.docs) {
        final observerUid = linkDoc.data()['observer_id'] as String;
        final observerDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(observerUid)
            .get();

        final observerToken = observerDoc.data()?['fcm_token'] as String?;

        if (observerToken != null && observerToken.isNotEmpty) {
          await NotificationService.sendPushNotification(
            targetToken: observerToken,
            title: 'Alerta de Seguridad',
            body: 'Se detectaron 3 intentos fallidos de acceso a la cuenta de ${user.displayName ?? "tu objetivo"}. La cuenta fue bloqueada temporalmente.',
            data: {
              'type': 'security_alert',
              'objective_id': user.uid,
              'reason': 'failed_pin_attempts',
            },
          );
          debugPrint('Notificación enviada a observador $observerUid');
        }
      }
    } catch (e) {
      debugPrint('Error al notificar intentos fallidos: $e');
    }
  }

  void _startLockTimer() {
    Future.doWhile(() async {
      if (!mounted || !_isLocked) return false;

      final remaining = await _pinService.getRemainingLockTime();
      if (remaining <= 0) {
        setState(() {
          _isLocked = false;
          _failedAttempts = 0;
          _errorMessage = '';
        });
        return false;
      }

      setState(() => _remainingLockTime = remaining);
      await Future.delayed(const Duration(seconds: 1));
      return true;
    });
  }

  /// Despues de fallar desbloqueo con contraseña de cuenta
  Future<void> _unlockWithPassword() async {
    debugPrint('Iniciando desbloqueo con contraseña...');
    
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('No hay usuario autenticado');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: No hay sesión activa'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final userEmail = user.email;
    if (userEmail == null || userEmail.isEmpty) {
      debugPrint('Usuario no tiene email asociado');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Tu cuenta no tiene email asociado'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    debugPrint('Email del usuario: $userEmail');

    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.lock_reset, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              const Expanded(child: Text('Desbloquear Cuenta')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ingresa la contraseña de tu cuenta:\n$userEmail',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              Form(
                key: formKey,
                child: TextFormField(
                  controller: passwordController,
                  obscureText: true,
                  autofocus: true,
                  enabled: !isLoading,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: Icon(Icons.vpn_key),
                    border: OutlineInputBorder(),
                    helperText: 'Es la misma contraseña que usas para iniciar sesión',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ingresa tu contraseña';
                    }
                    if (value.length < 6) {
                      return 'La contraseña debe tener al menos 6 caracteres';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) async {
                    if (formKey.currentState!.validate() && !isLoading) {
                      setDialogState(() => isLoading = true);
                      await _attemptPasswordUnlock(
                        dialogContext,
                        passwordController.text,
                        userEmail,
                      );
                    }
                  },
                ),
              ),
              if (isLoading) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      
                      setDialogState(() => isLoading = true);
                      await _attemptPasswordUnlock(
                        dialogContext,
                        passwordController.text,
                        userEmail,
                      );
                    },
              child: const Text('Desbloquear'),
            ),
          ],
        ),
      ),
    );

    debugPrint('Resultado del diálogo: $result');

    if (result == true && mounted) {
      widget.onUnlock();
    }
  }

  Future<void> _attemptPasswordUnlock(
    BuildContext dialogContext,
    String password,
    String email,
  ) async {
    try {
      debugPrint('Intentando reautenticación con Firebase...');
      
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('No hay usuario actual');
        if (mounted) Navigator.pop(dialogContext, false);
        return;
      }

      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );

      await user.reauthenticateWithCredential(credential);
      
      debugPrint('Contraseña correcta - Reautenticación exitosa');

      // Resetear intentos fallidos
      await _pinService.resetFailedAttempts();
      
      if (mounted) {
        Navigator.pop(dialogContext, true);
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('Error de Firebase Auth: ${e.code} - ${e.message}');
      
      if (mounted) {
        String errorMessage;
        switch (e.code) {
          case 'wrong-password':
            errorMessage = 'Contraseña incorrecta';
            break;
          case 'user-not-found':
            errorMessage = 'Usuario no encontrado';
            break;
          case 'invalid-credential':
            errorMessage = 'Credenciales inválidas';
            break;
          case 'too-many-requests':
            errorMessage = 'Demasiados intentos. Intenta más tarde.';
            break;
          default:
            errorMessage = 'Error: ${e.message ?? "Error desconocido"}';
        }

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );

        Navigator.pop(dialogContext, false);
      }
    } catch (e) {
      debugPrint('Error inesperado: $e');
      if (mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text('Error inesperado: $e'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(dialogContext, false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isLocked
                    ? Icons.lock_clock
                    : (widget.isFirstTimeSetup ? Icons.security : Icons.lock_outline),
                size: 64,
                color: _isLocked ? Colors.orange : colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                _isLocked
                    ? 'Cuenta Bloqueada'
                    : (widget.isFirstTimeSetup
                        ? 'Crea tu PIN de 4 dígitos'
                        : 'Desbloquear App'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _isLocked
                    ? 'Demasiados intentos fallidos.\nEspera $_remainingLockTime segundos o verifica tu identidad.'
                    : (widget.isFirstTimeSetup
                        ? 'Este PIN protegerá tu app cada vez que la abras.'
                        : (_biometricFailed
                            ? 'Biometría no reconocida. Ingresa tu PIN.'
                            : 'Usa tu huella/rostro o ingresa tu PIN.')),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _isLocked ? Colors.orange : Colors.grey,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              if (!_isLocked)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index < _enteredPin.length
                            ? colorScheme.primary
                            : Colors.grey.shade300,
                      ),
                    );
                  }),
                ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage,
                  style: TextStyle(
                    color: _isLocked ? Colors.orange : Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),

              if (!_isLocked) _buildKeypad(),

              // Botón de desbloqueo con contraseña
              if (_isLocked) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _isUnlockingWithPassword ? null : _unlockWithPassword,
                  icon: _isUnlockingWithPassword
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.vpn_key),
                  label: Text(_isUnlockingWithPassword ? 'Verificando...' : 'Desbloquear con Contraseña'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Ingresa la contraseña de tu cuenta para desbloquear',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
              ],

              // Botón de biometría
              if (_isBiometricAvailable &&
                  !widget.isFirstTimeSetup &&
                  !_isLocked &&
                  _failedAttempts == 0) ...[
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: _tryBiometricAuth,
                  icon: const Icon(Icons.fingerprint, size: 28),
                  label: const Text('Intentar biometría de nuevo'),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                  ),
                ),
              ],

              // Contador de intentos
              if (_failedAttempts > 0 && !_isLocked) ...[
                const SizedBox(height: 16),
                Text(
                  'Intentos fallidos: $_failedAttempts / ${SecurePinService.maxFailedAttempts}',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.5,
      ),
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final key = keys[index];
        if (key.isEmpty) return const SizedBox.shrink();

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _onKeyPressed(key),
            borderRadius: BorderRadius.circular(50),
            child: Center(
              child: key == '⌫'
                  ? const Icon(Icons.backspace_outlined, size: 28)
                  : Text(key, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500)),
            ),
          ),
        );
      },
    );
  }
}