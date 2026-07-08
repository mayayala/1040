import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:geocercas_app/routes.dart';
import 'package:geocercas_app/data/services/auth_service.dart';
import 'package:geocercas_app/presentation/screens/app_lock_screen.dart';
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  int? _selectedAge;
  String? _selectedGender;
  DateTime? _selectedDateOfBirth;
  
   final Set<String> _selectedRoles = {};
  
  final _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  final List<int> _ageOptions = List.generate(80, (i) => i + 10);
  final List<Map<String, String>> _genderOptions = [
    {'id': 'male', 'label': 'Masculino'},
    {'id': 'female', 'label': 'Femenino'},
    {'id': 'other', 'label': 'Otro'},
    {'id': 'prefer_not_to_say', 'label': 'Prefiero no decirlo'},
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Seleccionar fecha';
    return DateFormat('dd/MM/yyyy', 'es').format(date);
  }

  /// Seleccionar fecha de nacimiento
  Future<void> _selectDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25),
      firstDate: DateTime(now.year - 90),
      lastDate: DateTime(now.year - 10),
    );
    
    if (picked != null) {
      setState(() => _selectedDateOfBirth = picked);
    }
  }

  /// Calcular edad desde fecha de nacimiento
  int? _calculateAge(DateTime birthDate) {
    final today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month || 
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  /// Validar y ejecutar registro
  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'Las contraseñas no coinciden');
      return;
    }
    if (_selectedRoles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos un rol')),
      );
      return;
    }
    if (_selectedDateOfBirth == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona tu fecha de nacimiento')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Calcular edad si no se ingresó manualmente
      final age = _selectedAge ?? _calculateAge(_selectedDateOfBirth!) ?? 18;

      await _authService.registerWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
        displayName: _nameController.text,
        age: age,
        gender: _selectedGender ?? 'prefer_not_to_say',
        dateOfBirth: _selectedDateOfBirth!,
        roleTags: _selectedRoles.toList(),
      );
      await AuthService.markOnboardingCompleted();

      // Registro exitoso: ir directo al Home
      if (!mounted) return;

      // Configurar pin de entrada
      final pinConfigured = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => AppLockScreen(
            isFirstTimeSetup: true,
            onUnlock: () => Navigator.pop(context, true),
          ),
        ),
      );

      if (!mounted) return;

      if (pinConfigured == true || pinConfigured == null) {
        // Determinar a qué home ir según el rol
        final primaryRole = _selectedRoles.first;
        if (primaryRole == 'observer') {
          context.go(AppRoutes.homeObserver);
        } else {
          context.go(AppRoutes.homeObjective);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AuthService.getErrorMessage(e as FirebaseAuthException)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Crear Cuenta'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSectionTitle('Datos Personales'),
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                  validator: (v) => v == null || v.trim().length < 2 ? 'Ingresa tu nombre' : null,
                ),
                const SizedBox(height: 12),
                
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Campo obligatorio';
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v)) return 'Correo inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                  validator: (v) => v == null || v.length < 6 ? 'Mínimo 6 caracteres' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Confirmar contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                  validator: (v) => v != _passwordController.text ? 'No coinciden' : null,
                ),
                
                const SizedBox(height: 24),
                
                _buildSectionTitle('Información Demográfica'),
                const SizedBox(height: 16),
                
                InkWell(
                  onTap: _selectDateOfBirth,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Fecha de nacimiento',
                      prefixIcon: Icon(Icons.cake_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                    child: Text(_formatDate(_selectedDateOfBirth), 
                        style: TextStyle(color: _selectedDateOfBirth == null ? Colors.grey : null)),
                  ),
                ),
                const SizedBox(height: 12),
                
                DropdownButtonFormField<int>(
                  value: _selectedAge,
                  decoration: const InputDecoration(
                    labelText: 'Edad (opcional)',
                    prefixIcon: Icon(Icons.numbers_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                  items: _ageOptions.map((age) => DropdownMenuItem(value: age, child: Text('$age años'))).toList(),
                  onChanged: (v) => setState(() => _selectedAge = v),
                  isExpanded: true,
                ),
                const SizedBox(height: 12),
                
                DropdownButtonFormField<String>(
                  value: _selectedGender,
                  decoration: const InputDecoration(
                    labelText: 'Género',
                    prefixIcon: Icon(Icons.transgender_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                  items: _genderOptions.map((g) => DropdownMenuItem(value: g['id'], child: Text(g['label']!))).toList(),
                  onChanged: (v) => setState(() => _selectedGender = v),
                  isExpanded: true,
                ),
                
                const SizedBox(height: 24),
                
                _buildSectionTitle('¿Cuál es tu rol?'),
                const SizedBox(height: 12),
                Text(
                  'Puedes ser monitoreado, monitorear a otros, o ambos. Esto se puede cambiar después.', 
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ...[
                  _buildRoleCard(
                    id: 'objective',
                    title: 'Objetivo',
                    desc: 'Serás monitoreado por observadores de confianza',
                    icon: Icons.person_outline,
                  ),
                  _buildRoleCard(
                    id: 'observer',
                    title: 'Observador',
                    desc: 'Monitorearás a personas vulnerables',
                    icon: Icons.visibility_outlined,
                  ),
                ],

                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_errorMessage!, 
                            style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                      ],
                    ),
                  ),
                ],
                
                const SizedBox(height: 24),
                
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Crear Cuenta'),
                ),
                
                const SizedBox(height: 16),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('¿Ya tienes cuenta?'),
                    TextButton(
                      onPressed: () => context.go(AppRoutes.login),
                      child: const Text('Inicia sesión'),
                    ),
                  ],
                ),
                
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, 
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold));
  }

  Widget _buildRoleCard({
    required String id,
    required String title,
    required String desc,
    required IconData icon,
  }) {
    final selected = _selectedRoles.contains(id);
    final colorScheme = Theme.of(context).colorScheme;
    
    return GestureDetector(
      onTap: () => setState(() {
        if (selected) {
          _selectedRoles.remove(id);
        } else {
          _selectedRoles.add(id);
        }
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primaryContainer.withOpacity(0.4) : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, 
                      style: TextStyle(fontWeight: FontWeight.w600, 
                          color: selected ? colorScheme.primary : colorScheme.onSurface)),
                  const SizedBox(height: 4),
                  Text(desc, 
                      style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? colorScheme.primary : Colors.grey,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}