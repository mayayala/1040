import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocercas_app/data/services/auth_service.dart';
import 'package:geocercas_app/presentation/screens/change_pin_screen.dart';
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  
  DateTime? _dateOfBirth;
  String _gender = 'prefer_not_to_say';
  bool _isLoading = true;
  bool _isSaving = false;
  List<String> _selectedRoles = [];

  final List<Map<String, String>> _genderOptions = [
    {'value': 'male', 'label': 'Masculino'},
    {'value': 'female', 'label': 'Femenino'},
    {'value': 'other', 'label': 'Otro'},
    {'value': 'prefer_not_to_say', 'label': 'Prefiero no decir'},
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final profile = await AuthService().getUserProfile(user.uid);
      if (profile.exists && mounted) {
        final data = profile.data()!;
        
        setState(() {
          _nameController.text = data['displayName'] ?? '';
          _ageController.text = (data['age'] ?? '').toString();
          _gender = data['gender'] ?? 'prefer_not_to_say';
          final roles = data['role_tags'] as List<dynamic>?;
          if (roles != null && roles.isNotEmpty) {
            _selectedRoles = roles.map((e) => e.toString()).toList();
          } else {
            _selectedRoles = ['objective'];
          }
          
          final dob = data['date_of_birth'];
          if (dob is Timestamp) {
            _dateOfBirth = dob.toDate();
          }
          
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar perfil: $e')),
        );
      }
    }
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final initialDate = _dateOfBirth ?? DateTime(now.year - 18, now.month, now.day);
    
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: 'Selecciona tu fecha de nacimiento',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
      locale: const Locale('es', 'ES'),
    );

    if (picked != null && mounted) {
      setState(() {
        _dateOfBirth = picked;
        final age = now.year - picked.year;
        _ageController.text = age.toString();
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Usuario no autenticado');

      await AuthService().updateUserProfile(
        uid: user.uid,
        displayName: _nameController.text.trim(),
        gender: _gender,
        dateOfBirth: _dateOfBirth,
        age: int.tryParse(_ageController.text),
        roleTags: _selectedRoles,
      );

      if (_nameController.text.trim().isNotEmpty) {
        await user.updateDisplayName(_nameController.text.trim());
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text(' Perfil actualizado correctamente')),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Perfil'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveProfile,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'GUARDAR',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: colorScheme.primaryContainer,
                            child: Text(
                              _nameController.text.isNotEmpty
                                  ? _nameController.text.substring(0, 1).toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(
                                Icons.edit,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Nombre completo',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: const OutlineInputBorder(),
                        hintText: 'Ej: Juan Pérez',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Ingresa tu nombre';
                        }
                        if (value.trim().length < 3) {
                          return 'El nombre debe tener al menos 3 caracteres';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      initialValue: FirebaseAuth.instance.currentUser?.email ?? '',
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                        helperText: 'El correo no se puede modificar',
                      ),
                      enabled: false,
                    ),
                    const SizedBox(height: 16),

                    InkWell(
                      onTap: _pickDateOfBirth,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Fecha de nacimiento',
                          prefixIcon: const Icon(Icons.cake_outlined),
                          border: const OutlineInputBorder(),
                          suffixIcon: const Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          _dateOfBirth != null
                              ? '${_dateOfBirth!.day}/${_dateOfBirth!.month}/${_dateOfBirth!.year}'
                              : 'Toca para seleccionar',
                          style: TextStyle(
                            color: _dateOfBirth != null 
                                ? Colors.black87 
                                : Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _ageController,
                      decoration: const InputDecoration(
                        labelText: 'Edad',
                        prefixIcon: Icon(Icons.numbers),
                        border: OutlineInputBorder(),
                        helperText: 'Se calcula automáticamente desde la fecha de nacimiento',
                      ),
                      keyboardType: TextInputType.number,
                      readOnly: true,
                    ),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      value: _gender,
                      decoration: const InputDecoration(
                        labelText: 'Género',
                        prefixIcon: Icon(Icons.wc_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: _genderOptions.map((option) {
                        return DropdownMenuItem(
                          value: option['value'],
                          child: Text(option['label']!),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _gender = value);
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    // Roles
                    const Text(
                      'Mis Roles',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      title: const Text('Soy Objetivo (mi ubicación es monitoreada)'),
                      value: _selectedRoles.contains('objective'),
                      activeColor: Theme.of(context).colorScheme.primary,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            if (!_selectedRoles.contains('objective')) _selectedRoles.add('objective');
                          } else {
                            _selectedRoles.remove('objective');
                          }
                          // Rol por defecto
                          if (_selectedRoles.isEmpty) _selectedRoles.add('objective');
                        });
                      },
                    ),
                    CheckboxListTile(
                      title: const Text('Soy Observador (monitoreo a otros)'),
                      value: _selectedRoles.contains('observer'),
                      activeColor: Theme.of(context).colorScheme.primary,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            if (!_selectedRoles.contains('observer')) _selectedRoles.add('observer');
                          } else {
                            _selectedRoles.remove('observer');
                          }
                          if (_selectedRoles.isEmpty) _selectedRoles.add('objective');
                        });
                      },
                    ),
                                        const SizedBox(height: 16),

                    const Text(
                      'Seguridad',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.fingerprint,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: const Text('PIN y Biometría'),
                        subtitle: const Text('Configurar bloqueo de la app'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final changed = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ChangePinScreen(),
                            ),
                          );
                          if (changed == true && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Configuración de seguridad actualizada'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _saveProfile,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: Text(
                        _isSaving ? 'Guardando...' : 'Guardar cambios',
                        style: const TextStyle(fontSize: 16),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}