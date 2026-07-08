import 'package:flutter/material.dart';
import 'package:geocercas_app/core/services/app_lock_service.dart';
import 'package:geocercas_app/core/services/secure_pin_service.dart';

enum _PinStep { verifyCurrent, enterNew, confirmNew }

class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final AppLockService _lockService = AppLockService();
  final SecurePinService _pinService = SecurePinService();

  _PinStep _currentStep = _PinStep.verifyCurrent;
  String _enteredPin = '';
  String _newPin = '';
  String _errorMessage = '';
  bool _hasExistingPin = true;
  bool _isBiometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkExistingPin();
  }

  Future<void> _checkExistingPin() async {
    final pin = await _pinService.getPin();
    final biometric = await _pinService.isBiometricEnabled();

    if (mounted) {
      setState(() {
        _hasExistingPin = pin != null && pin.isNotEmpty;
        _isBiometricEnabled = biometric;
        if (!_hasExistingPin) {
          _currentStep = _PinStep.enterNew;
        }
      });
    }
  }

  void _onKeyPressed(String key) {
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
        _handlePinComplete();
      }
    }
  }

  Future<void> _handlePinComplete() async {
    switch (_currentStep) {
      case _PinStep.verifyCurrent:
        final isValid = await _lockService.verifyPin(_enteredPin);
        if (isValid) {
          setState(() {
            _currentStep = _PinStep.enterNew;
            _enteredPin = '';
          });
        } else {
          setState(() {
            _errorMessage = 'PIN actual incorrecto';
            _enteredPin = '';
          });
        }
        break;

      case _PinStep.enterNew:
        setState(() {
          _newPin = _enteredPin;
          _currentStep = _PinStep.confirmNew;
          _enteredPin = '';
        });
        break;

      case _PinStep.confirmNew:
        if (_enteredPin == _newPin) {
          await _lockService.setupPin(_newPin);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(' PIN actualizado correctamente'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context, true);
          }
        } else {
          setState(() {
            _errorMessage = 'Los PINs no coinciden';
            _enteredPin = '';
            _currentStep = _PinStep.enterNew;
            _newPin = '';
          });
        }
        break;
    }
  }

  Future<void> _disablePin() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Desactivar bloqueo?'),
        content: const Text('La app se abrirá sin pedir PIN ni biometría.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Desactivar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _pinService.clearPin();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(' Bloqueo desactivado'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context, true);
      }
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      // Verificar que la biometría esté disponible
      final canCheck = await _lockService.canCheckBiometrics();
      
      if (!canCheck) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(' Tu dispositivo no soporta biometría o no tiene huella/rostro registrado'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      final availableBiometrics = await _lockService.getAvailableBiometrics();
      
      if (availableBiometrics.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(' No hay huella o rostro registrado en tu dispositivo. Configúralo en Ajustes del sistema.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Intentar autenticación biométrica
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(' Usa tu huella/rostro para confirmar'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final success = await _lockService.authenticateWithBiometrics();
      
      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(' Autenticación biométrica cancelada o fallida'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    // Activar/desactivar biometría
    await _pinService.setBiometricEnabled(value);
    
    if (mounted) {
      setState(() => _isBiometricEnabled = value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value 
              ? ' Biometría activada. Se usará automáticamente al abrir la app.' 
              : '⚪ Biometría desactivada. Solo se usará el PIN.'),
          backgroundColor: value ? Colors.green : Colors.grey,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  String _getTitle() {
    switch (_currentStep) {
      case _PinStep.verifyCurrent:
        return 'Ingresa tu PIN actual';
      case _PinStep.enterNew:
        return _hasExistingPin ? 'Nuevo PIN de 4 dígitos' : 'Crea tu PIN de 4 dígitos';
      case _PinStep.confirmNew:
        return 'Confirma tu nuevo PIN';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seguridad de la App'),
        backgroundColor: colorScheme.surface,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Icon(
                Icons.security,
                size: 56,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                _getTitle(),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

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
                Text(_errorMessage, style: TextStyle(color: Colors.red.shade700)),
              ],
              const SizedBox(height: 32),

              _buildKeypad(),

              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),

              if (_hasExistingPin && _currentStep == _PinStep.verifyCurrent) ...[
                FutureBuilder<bool>(
                  future: _lockService.canCheckBiometrics(),
                  builder: (context, snapshot) {
                    final canCheck = snapshot.data ?? false;
                    
                    return Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Usar biometría'),
                          subtitle: canCheck 
                              ? const Text('Huella dactilar o Face ID')
                              : const Text(
                                  'No disponible en este dispositivo',
                                  style: TextStyle(color: Colors.orange, fontSize: 12),
                                ),
                          value: _isBiometricEnabled && canCheck,
                          activeThumbColor: colorScheme.primary,
                          onChanged: canCheck ? _toggleBiometric : null,
                        ),
                        if (!canCheck && snapshot.connectionState == ConnectionState.done)
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Para usar biometría, registra tu huella o rostro en los Ajustes de seguridad de tu dispositivo.',
                                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.lock_open, color: Colors.red),
                  title: const Text('Desactivar bloqueo', style: TextStyle(color: Colors.red)),
                  subtitle: const Text('No pedir PIN al abrir la app'),
                  onTap: _disablePin,
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