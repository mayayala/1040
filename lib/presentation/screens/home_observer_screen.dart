import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geocercas_app/routes.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocercas_app/data/services/link_service.dart';
import 'package:geocercas_app/data/services/auth_service.dart';
import 'package:geocercas_app/presentation/screens/objective_map_screen.dart';
import 'package:geocercas_app/presentation/screens/all_objectives_map_screen.dart';
import 'package:geocercas_app/presentation/screens/alert_history_screen.dart';
import 'package:geocercas_app/presentation/screens/geofence_list_screen.dart';
import 'package:geocercas_app/presentation/screens/edit_profile_screen.dart';
import 'package:geocercas_app/presentation/screens/user_profile_screen.dart';

class HomeObserverScreen extends StatefulWidget {
  const HomeObserverScreen({super.key});

  @override
  State<HomeObserverScreen> createState() => _HomeObserverScreenState();
}

class _HomeObserverScreenState extends State<HomeObserverScreen> {
  final LinkService _linkService = LinkService();
  final AuthService _authService = AuthService();
  
  final Map<String, bool> _liveModeStates = {};
  int _currentIndex = 0; // 0: Objetivos, 1: Mapa, 2: Perfil

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildObjectivesListTab(),      // Tab 0: Lista de objetivos
          const AllObjectivesMapScreen(), // Tab 1: Mapa general
          _buildProfileTab(),             // Tab 2: Perfil
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Objetivos',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Mapa',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
  // TAB 0: LISTA DE OBJETIVOS
  Widget _buildObjectivesListTab() {
    final colorScheme = Theme.of(context).colorScheme;
    final user = _authService.currentUser;
    final uid = user?.uid;

    return CustomScrollView(
      slivers: [
        // ✅ StreamBuilder para reaccionar a cambios de rol en tiempo real
        StreamBuilder<DocumentSnapshot>(
          stream: uid != null
              ? FirebaseFirestore.instance.collection('users').doc(uid).snapshots()
              : const Stream.empty(),
          builder: (context, userSnapshot) {
            // Verificar si tiene rol de objetivo
            bool isAlsoObjective = false;
            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final roles = userSnapshot.data!.data() as Map<String, dynamic>?;
              final roleTags = roles?['role_tags'] as List<dynamic>?;
              isAlsoObjective = roleTags?.contains('objective') ?? false;
            }

            return SliverAppBar(
              floating: true,
              title: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      user?.displayName?.substring(0, 1).toUpperCase() ?? '?',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Hola, ${user?.displayName?.split(' ').first ?? 'Usuario'}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Tus objetivos monitoreados',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              backgroundColor: colorScheme.surface,
              actions: [
                // ✅ Botón aparece/desaparece en tiempo real según rol
                if (isAlsoObjective)
                  IconButton(
                    icon: const Icon(Icons.swap_horiz),
                    tooltip: 'Cambiar a modo Objetivo',
                    onPressed: () {
                      context.go(AppRoutes.homeObjective);
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Agregar objetivo',
                  onPressed: () => _showAddObjectiveDialog(),
                ),
              ],
            );
          },
        ),

        // StreamBuilder de objetivos (sin cambios)
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _linkService.getActiveObjectives(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return SliverFillRemaining(
                child: Center(child: Text('Error: ${snapshot.error}')),
              );
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return SliverFillRemaining(
                child: _buildEmptyState(
                  icon: Icons.person_search,
                  title: 'Sin objetivos vinculados',
                  subtitle: 'Agrega personas para comenzar a monitorearlas.',
                ),
              );
            }

            final objectives = snapshot.data!;
            return SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final obj = objectives[index];
                    return _buildObjectiveCard(context, obj);
                  },
                  childCount: objectives.length,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildObjectiveCard(BuildContext context, Map<String, dynamic> obj) {
    final colorScheme = Theme.of(context).colorScheme;
    final uid = obj['objective_uid'] as String;
    final displayName = obj['displayName'] as String;
    final isLive = (obj['live_mode_active'] as bool?) ?? (_liveModeStates[uid] ?? false);
    final observerUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            
            // Alerta "Casa" por objetivo
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('geofences')
                  .where('objective_id', isEqualTo: uid) 
                  .where('is_active', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();

                //Búsqueda mayúsculas/minúsculas
                final hasCasa = snapshot.data!.docs.any((doc) {
                  final name = (doc.data() as Map<String, dynamic>)['name']
                          ?.toString()
                          .toLowerCase()
                          .trim() ??
                      '';
                  return name == 'casa';
                });

                if (hasCasa) return const SizedBox.shrink();

                // No tiene casa, mostrar la advertencia
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.orange.shade800, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Falta definir Casa',
                              style: TextStyle(
                                color: Colors.orange.shade900,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Requerido para que la IA detecte anomalías correctamente en las rutinas de $displayName.',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 36,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            context.push(
                              AppRoutes.geofenceCreator,
                              extra: {
                                'objectiveId': uid,
                                'objectiveName': displayName,
                                'forceHomeName': true,
                              },
                            );
                          },
                          icon: const Icon(Icons.add_location_alt, size: 16),
                          label: const Text('Crear Casa',
                              style: TextStyle(fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade600,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            // SOS activo 
            StreamBuilder<bool>(
              stream: _linkService.isSOSActive(uid),
              builder: (context, snapshot) {
                final isSOSActive = snapshot.data ?? false;
                if (!isSOSActive) return const SizedBox.shrink();
                
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, 
                              color: Colors.red.shade700, size: 24),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              ' EMERGENCIA ACTIVA',
                              style: TextStyle(
                                color: Colors.red.shade900,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Este objetivo activó el SOS. Ubicación actualizándose cada minuto.',
                        style: TextStyle(fontSize: 11, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _confirmDeactivateSOS(uid, displayName),
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text('Desactivar SOS'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(
                    displayName.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          Container(
                            width: 8, height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.green, shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Activo',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) => _handleObjectiveMenu(context, value, obj),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'geofences',
                      child: Text('Gestionar Geocercas'),
                    ),
                    const PopupMenuItem(
                      value: 'history',
                      child: Text('Historial de Alertas'),
                    ),
                    const PopupMenuItem(
                      value: 'profile',
                      child: Text('Ver Perfil'),
                    ),
                    const PopupMenuItem(
                      value: 'revoke',
                      child: Text('Revocar Vínculo', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Botones Mapa + En vivo
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ObjectiveMapScreen(
                            objectiveUid: uid,
                            objectiveName: displayName,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Ver mapa'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _toggleLiveMode(uid, isLive),
                    icon: Icon(isLive ? Icons.videocam : Icons.videocam_off),
                    label: Text(isLive ? 'En vivo' : 'Activar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: isLive ? Colors.red.shade600 : null,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeactivateSOS(String uid, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green.shade700),
            const SizedBox(width: 8),
            const Expanded(child: Text('¿Desactivar SOS?')),
          ],
        ),
        content: Text(
          'Confirma que la emergencia de "$displayName" fue resuelta. '
          'El objetivo dejará de enviar ubicación cada minuto y volverá al monitoreo normal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _linkService.deactivateSOS(uid);
        if (!context.mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(' SOS de $displayName desactivado')),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // TAB 2: PERFIL
  Widget _buildProfileTab() {
    final user = _authService.currentUser;
    final colorScheme = Theme.of(context).colorScheme;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: const Text('Mi Perfil'),
          backgroundColor: colorScheme.surface,
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(
                    user?.displayName?.substring(0, 1).toUpperCase() ?? '?',
                    style: TextStyle(
                      fontSize: 32,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  user?.displayName ?? 'Usuario',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  user?.email ?? '',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                ),
                const SizedBox(height: 32),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.edit_outlined, color: colorScheme.primary),
                        title: const Text('Editar perfil'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const EditProfileScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.info_outline, color: colorScheme.primary),
                        title: const Text('Acerca del sistema'),
                        subtitle: const Text('Geocercas Inteligentes v1.0'),
                        onTap: () {},
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.shield, color: Colors.green),
                        title: const Text('Privacidad'),
                        subtitle: const Text('Cifrado AES-256-GCM activo'),
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text(
                      'Cerrar sesión',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () async {
                      await _authService.signOut();
                      if (!context.mounted) return;
                      context.go(AppRoutes.login);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }


  void _handleObjectiveMenu(BuildContext context, String action, Map<String, dynamic> obj) {
    final uid = obj['objective_uid'] as String;
    final displayName = obj['displayName'] as String;
    
    switch (action) {
      case 'profile':
  //  Ver perfil Objetivo
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserProfileScreen(
              userUid: uid,
              displayName: displayName,
            ),
          ),
        );
        break;
      case 'geofences':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GeofenceListScreen(
              objectiveId: uid,
              objectiveName: displayName,
            ),
          ),
        );
        break;
      case 'history':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AlertHistoryScreen(objectiveId: uid, objectiveName: displayName),
          ),
        );
        break;
      case 'revoke':
        _confirmRevoke(context, obj);
        break;
    }
  }
  Future<void> _confirmRevoke(BuildContext context, Map<String, dynamic> obj) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Revocar vínculo?'),
        content: Text('Dejarás de monitorear a "${obj['displayName']}".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Revocar'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      try {
        await _linkService.revokeLink(obj['link_id'] as String);
        if (!context.mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(' Vínculo revocado')),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _toggleLiveMode(String uid, bool currentStatus) async {
    final newStatus = !currentStatus;
    
    setState(() => _liveModeStates[uid] = newStatus);
    
    try {
      await _linkService.toggleLiveMode(uid, newStatus);
      if (!context.mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                newStatus ? Icons.videocam : Icons.videocam_off,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  newStatus
                      ? ' Monitoreo en vivo ACTIVADO (actualizaciones cada 1 min)'
                      : '⚪ Monitoreo en vivo desactivado',
                ),
              ),
            ],
          ),
          backgroundColor: newStatus ? Colors.red.shade700 : Colors.grey.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      
      setState(() => _liveModeStates[uid] = currentStatus);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAddObjectiveDialog() {
    final emailController = TextEditingController();
    bool isLoading = false;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (contextInner, setStateInner) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.person_add, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Agregar Objetivo'),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ingresa el correo electrónico del usuario que deseas monitorear. La persona recibirá una solicitud de vínculo.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Correo electrónico',
                  hintText: 'ejemplo@correo.com',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: const OutlineInputBorder(),
                  errorText: errorMessage,
                  suffixIcon: emailController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setStateInner(() {
                              emailController.clear();
                              errorMessage = null;
                            });
                          },
                        )
                      : null,
                ),
                onChanged: (_) => setStateInner(() => errorMessage = null),
              ),
              if (isLoading) ...[
                const SizedBox(height: 16),
                const Center(
                  child: CircularProgressIndicator(),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Enviando solicitud...',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: isLoading
                  ? null
                  : () async {
                      final email = emailController.text.trim();

                      if (email.isEmpty) {
                        setStateInner(() => errorMessage = 'Ingresa un correo electrónico');
                        return;
                      }

                      if (!email.contains('@') || !email.contains('.')) {
                        setStateInner(() => errorMessage = 'Correo electrónico inválido');
                        return;
                      }

                      setStateInner(() {
                        isLoading = true;
                        errorMessage = null;
                      });

                      try {
                        await _linkService.sendLinkRequest(email);

                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Colors.white),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(' Solicitud enviada a $email'),
                                ),
                              ],
                            ),
                            backgroundColor: Colors.green.shade700,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      } catch (e) {
                        final errorMsg = e.toString().replaceAll('Exception: ', '');
                        if (contextInner.mounted) {
                          setStateInner(() {
                            isLoading = false;
                            errorMessage = errorMsg;
                          });
                        }
                      }
                    },
              icon: const Icon(Icons.send),
              label: const Text('Enviar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}