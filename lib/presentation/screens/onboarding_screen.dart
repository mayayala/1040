import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:geocercas_app/routes.dart';
import 'package:geocercas_app/core/constants/app_strings.dart';
import 'package:geocercas_app/data/services/auth_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _consentAccepted = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) _showLocationServiceDialog();
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Ubicación requerida'),
        content: const Text(
          'Esta aplicación necesita acceso a tu ubicación para funcionar. '
          'Por favor, activa el servicio de ubicación en tu dispositivo.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openLocationSettings();
              _checkPermissions();
            },
            child: const Text('Activar'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final requested = await Geolocator.requestPermission();
      if (requested == LocationPermission.deniedForever) {
        _showPermissionDeniedDialog();
      }
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permiso denegado'),
        content: const Text(
          'El permiso de ubicación fue denegado permanentemente. '
          'Puedes habilitarlo manualmente en: '
          'Ajustes → Aplicaciones → Geocercas → Permisos.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Aceptar')),
        ],
      ),
    );
  }

  Future<void> _onAcceptConsent() async {
    if (!_consentAccepted) return;
    setState(() => _isLoading = true);
    try {
      await _requestLocationPermission();
      await AuthService.markOnboardingCompleted();
      if (mounted) {
        context.go(AppRoutes.authChoice);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.shield_moon_rounded, size: 80, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 32),
              Text(AppStrings.onboardingTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Text(AppStrings.onboardingDescription,
                  style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
              const SizedBox(height: 32),
              _buildPermissionItem(icon: Icons.location_on_outlined, title: 'Ubicación en segundo plano', description: 'Para monitorear geocercas incluso con la app cerrada.'),
              const SizedBox(height: 12),
              _buildPermissionItem(icon: Icons.notifications_outlined, title: 'Notificaciones push', description: 'Para recibir alertas críticas en tiempo real.'),
              const SizedBox(height: 12),
              _buildPermissionItem(icon: Icons.lock_outline, title: 'Cifrado de extremo a extremo', description: 'Tus datos sensibles nunca se almacenan en texto claro.'),
              const Spacer(),
              CheckboxListTile(
                value: _consentAccepted,
                onChanged: (value) => setState(() => _consentAccepted = value ?? false),
                title: const Text('He leído y acepto los términos y política de privacidad'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _consentAccepted && !_isLoading ? _onAcceptConsent : null,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Continuar'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionItem({required IconData icon, required String title, required String description}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}