import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geocercas_app/routes.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocercas_app/data/services/link_service.dart';
import 'package:geocercas_app/data/services/auth_service.dart';
import 'package:geocercas_app/core/services/haptic_service.dart';
import 'package:geocercas_app/core/services/decision_engine.dart';
import 'package:geocercas_app/data/services/location_service.dart';
import 'package:geocercas_app/data/services/geofence_service.dart';
import 'package:geocercas_app/core/services/event_queue_service.dart';
import 'package:geocercas_app/presentation/screens/alert_history_screen.dart';
import 'package:geocercas_app/presentation/screens/pending_requests_screen.dart';
import 'package:geocercas_app/presentation/screens/edit_profile_screen.dart';
import 'package:geocercas_app/presentation/screens/objective_own_map_screen.dart';
import 'package:geocercas_app/presentation/screens/user_profile_screen.dart';

class HomeObjectiveScreen extends StatefulWidget {
  const HomeObjectiveScreen({super.key});

  @override
  State<HomeObjectiveScreen> createState() => _HomeObjectiveScreenState();
}

class _HomeObjectiveScreenState extends State<HomeObjectiveScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocationService _locationService = LocationService();
  final EventQueueService _eventQueue = EventQueueService();
  final AuthService _authService = AuthService();

  int _currentIndex = 0; // 0: Inicio, 1: Alertas, 2: Perfil

  // Estado del sistema
  bool _isTracking = false;
  bool _isMlLoaded = false;
  bool _hasLocationPermission = false;
  // Sos
  bool _isSendingSOS = false;
  bool _sosCooldownActive = false;
  int _cooldownSeconds = 0;
  DateTime? _lastSOSTimestamp;
  Timer? _cooldownTimer;
  bool _isSOSActive = false; 
  StreamSubscription? _sosSubscription;
  // Geocercas
  StreamSubscription? _geofencesSubscription;
  List<Map<String, dynamic>> _activeGeofences = [];

  StreamSubscription<Position>? _locationSubscription;
  Position? _lastPosition;
  bool _isLiveModeActive = false;
  
  @override
  void initState() {
    super.initState();
    _initializeSystem();
  }

  Future<void> _initializeSystem() async {
    final permission = await Geolocator.checkPermission();
    setState(() => _hasLocationPermission =
        permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse);

    await DecisionEngine.initialize();
    setState(() => _isMlLoaded = true);

    if (_hasLocationPermission) {
      await _locationService.startBackgroundTracking();
      setState(() => _isTracking = _locationService.isTracking);
    }
    _listenToLocation();
    _listenToGeofences();
    _loadLiveModeState();
    _listenToSOSState();
  }

  void _listenToSOSState() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    _sosSubscription?.cancel();
    _sosSubscription = _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen((userDoc) {
      if (userDoc.exists && mounted) {
        final isSOS = userDoc.data()?['sos_active'] == true;
        setState(() => _isSOSActive = isSOS);
      }
    });
  }

  void _listenToLocation() {
    debugPrint('HomeObjectiveScreen: Iniciando escucha del stream de ubicación...');
    _locationSubscription?.cancel();
    _loadInitialPosition();
    _locationSubscription = _locationService.locationStream.listen(
      (position) {
        debugPrint('HomeObjectiveScreen: Ubicación recibida: ${position.latitude}, ${position.longitude}');
        if (mounted) {
          setState(() => _lastPosition = position);
        }
      },
      onError: (error) {
        debugPrint('HomeObjectiveScreen: Error en stream: $error');
      },
    );
  }

  Future<void> _loadInitialPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 5),
        ),
      );
      debugPrint('Posición inicial obtenida: ${position.latitude}, ${position.longitude}');
      if (mounted) {
        setState(() => _lastPosition = position);
      }
    } catch (e) {
      debugPrint('No se pudo obtener posición inicial: $e');
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null && mounted) {
          debugPrint('Usando última posición conocida: ${lastKnown.latitude}, ${lastKnown.longitude}');
          setState(() => _lastPosition = lastKnown);
        }
      } catch (e2) {
        debugPrint('Tampoco se pudo obtener última posición conocida: $e2');
      }
    }
  }

  void _listenToGeofences() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    _geofencesSubscription?.cancel();
    _geofencesSubscription = GeofenceService()
        .getActiveGeofences(userId)
        .listen((geofences) {
      if (mounted) setState(() => _activeGeofences = geofences);
    });
  }

  Future<void> _loadLiveModeState() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return Future.value();

    _firestore.collection('users').doc(userId).snapshots().listen((userDoc) {
      if (userDoc.exists && mounted) {
        final isLive = userDoc.data()?['live_mode_active'] == true;
        setState(() => _isLiveModeActive = isLive);
      }
    });

    return Future.value();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),           // Tab 0: Inicio
          const ObjectiveOwnMapScreen(), // Tab 1: Mi Mapa
          _buildAlertsTab(),         // Tab 2: Alertas
          _buildProfileTab(),        // Tab 3: Perfil
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Mapa',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alertas',
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

  // TAB 0: INICIO
  Widget _buildHomeTab() {
    final colorScheme = Theme.of(context).colorScheme;
    final user = _auth.currentUser;
    final uid = user?.uid;

    return CustomScrollView(
      slivers: [
        StreamBuilder<DocumentSnapshot>(
          stream: uid != null
              ? _firestore.collection('users').doc(uid).snapshots()
              : const Stream.empty(),
          builder: (context, userSnapshot) {
            bool isAlsoObserver = false;
            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final data = userSnapshot.data!.data() as Map<String, dynamic>?;
              final roleTags = data?['role_tags'] as List<dynamic>?;
              isAlsoObserver = roleTags?.contains('observer') ?? false;
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
                          _isLiveModeActive ? 'Siendo monitoreado' : 'Monitoreo normal',
                          style: TextStyle(
                            fontSize: 11,
                            color: _isLiveModeActive ? Colors.red : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              backgroundColor: colorScheme.surface,
              actions: [
                if (isAlsoObserver)
                  IconButton(
                    icon: const Icon(Icons.swap_horiz),
                    tooltip: 'Cambiar a modo Observador',
                    onPressed: () {
                      context.go(AppRoutes.homeObserver);
                    },
                  ),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: LinkService().getPendingRequests(),
                  builder: (context, snapshot) {
                    final pendingCount = snapshot.data?.length ?? 0;
                    return Stack(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.person_add_alt_1),
                          tooltip: 'Solicitudes pendientes',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PendingRequestsScreen(),
                              ),
                            );
                          },
                        ),
                        if (pendingCount > 0)
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1),
                              ),
                              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                              child: Text(
                                '$pendingCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),

        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              if (_isSOSActive) _buildSOSActiveBanner(),
              if (_isSOSActive) const SizedBox(height: 16),
              _buildSOSButton(),
              const SizedBox(height: 16),
              _buildSystemStatusCard(),
              const SizedBox(height: 16),
              _buildLastLocationCard(),
              const SizedBox(height: 16),
              _buildActiveGeofencesCard(),
              const SizedBox(height: 16),
              _buildObserversCard(),
              const SizedBox(height: 16),
              _buildLiveModeCard(),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildSOSActiveBanner() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade700, Colors.red.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EMERGENCIA ACTIVA',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        'Tus observadores están siendo notificados',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tu ubicación se está enviando cada minuto. Un observador debe confirmar que la emergencia fue resuelta.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  //  BOTÓN SOS
  Widget _buildSOSButton() {

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.red.shade600,
            Colors.red.shade800,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _isSendingSOS || _sosCooldownActive ? null : _confirmAndSendSOS,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.sos, color: Colors.white, size: 48),
                const SizedBox(height: 8),
                const Text(
                  'EMERGENCIA',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isSendingSOS
                      ? 'Enviando...'
                      : _sosCooldownActive
                          ? 'Espera ${_cooldownSeconds}s'
                          : 'Toca para alertar a tus observadores',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
                if (_lastSOSTimestamp != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Último SOS: ${_formatTimeAgo(_lastSOSTimestamp!)}',
                    style: const TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // CARD: ESTADO DEL SISTEMA
  Widget _buildSystemStatusCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.system_update_alt,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Estado del Sistema',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatusRow(
              icon: Icons.location_on,
              label: 'Rastreo GPS',
              isActive: _isTracking,
              activeText: 'Activo',
              inactiveText: 'Inactivo',
            ),
            _buildStatusRow(
              icon: Icons.psychology,
              label: 'Modelo ML',
              isActive: _isMlLoaded,
              activeText: 'Cargado',
              inactiveText: 'No cargado',
            ),
            _buildStatusRow(
              icon: Icons.wifi,
              label: 'Permisos de ubicación',
              isActive: _hasLocationPermission,
              activeText: 'Concedidos',
              inactiveText: 'Denegados',
            ),
            _buildStatusRow(
              icon: Icons.shield,
              label: 'Cifrado E2E',
              isActive: true,
              activeText: 'AES-256',
              inactiveText: 'Inactivo',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow({
    required IconData icon,
    required String label,
    required bool isActive,
    required String activeText,
    required String inactiveText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isActive ? Colors.green.shade600 : Colors.grey,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? Colors.green.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              isActive ? activeText : inactiveText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.green.shade800 : Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ÚLTIMA UBICACIÓN
  Widget _buildLastLocationCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.location_on,
                    color: colorScheme.tertiary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Última Ubicación',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_lastPosition == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Obteniendo ubicación...'),
                  ],
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow('Latitud', _lastPosition!.latitude.toStringAsFixed(6)),
                  _buildInfoRow('Longitud', _lastPosition!.longitude.toStringAsFixed(6)),
                  _buildInfoRow('Precisión', '±${_lastPosition!.accuracy.toStringAsFixed(1)} m'),
                  if (_lastPosition!.speed > 0)
                    _buildInfoRow('Velocidad', '${_lastPosition!.speed.toStringAsFixed(1)} m/s'),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }


  // GEOCERCAS ACTIVAS
  Widget _buildActiveGeofencesCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.place,
                    color: colorScheme.secondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Geocercas Activas',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_activeGeofences.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.secondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_activeGeofences.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey.shade600),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'No tienes geocercas activas. Tus observadores pueden crear geocercas para ti.',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._activeGeofences.map((gf) => _buildGeofenceItem(gf)),
          ],
        ),
      ),
    );
  }

  Widget _buildGeofenceItem(Map<String, dynamic> gf) {
    final name = gf['name'] as String? ?? 'Sin nombre';
    final riskLevel = gf['risk_level'] as String? ?? 'medium';
    final type = gf['type'] as String? ?? 'polygon';

    Color riskColor;
    String riskLabel;
    IconData riskIcon;

    switch (riskLevel) {
      case 'high':
        riskColor = Colors.red;
        riskLabel = 'Alto riesgo';
        riskIcon = Icons.error_outline;
        break;
      case 'medium':
        riskColor = Colors.orange;
        riskLabel = 'Riesgo medio';
        riskIcon = Icons.warning_amber_outlined;
        break;
      default:
        riskColor = Colors.green;
        riskLabel = 'Zona segura';
        riskIcon = Icons.check_circle_outline;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: riskColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: riskColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(riskIcon, color: riskColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                Text(
                  '$riskLabel • ${type == 'circle' ? 'Circular' : 'Poligonal'}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // OBSERVADORES VINCULADOS
  Widget _buildObserversCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.people,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Mis Observadores',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Personas que pueden ver tu ubicación',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: LinkService().getActiveObservers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }

                final observers = snapshot.data ?? [];

                if (observers.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.person_off_outlined, color: Colors.grey.shade600),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'No tienes observadores vinculados actualmente.',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    ...observers.map((obs) => _buildObserverItem(obs)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${observers.length} observador(es) activo(s)',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildObserverItem(Map<String, dynamic> obs) {
    final displayName = obs['displayName'] as String? ?? 'Usuario';
    final email = obs['email'] as String? ?? '';
    final isLive = obs['live_mode_active'] as bool? ?? false;
    final observerUid = obs['observer_uid'] as String;
    final acceptedAt = obs['accepted_at'];

    String linkedSince = 'Recientemente';
    if (acceptedAt is Timestamp) {
      final date = acceptedAt.toDate();
      final diff = DateTime.now().difference(date);
      if (diff.inDays > 30) {
        linkedSince = 'hace ${(diff.inDays / 30).floor()} meses';
      } else if (diff.inDays > 0) {
        linkedSince = 'hace ${diff.inDays} días';
      } else {
        linkedSince = 'hoy';
      }
    }

    return GestureDetector(
      onTap: () {
        // VER PERFIL OBSERVADOR
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserProfileScreen(
              userUid: observerUid,
              displayName: displayName,
              linkedSince: linkedSince,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isLive ? Colors.red.withValues(alpha: 0.05) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLive ? Colors.red.withValues(alpha: 0.2) : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: isLive ? Colors.red.shade100 : Colors.grey.shade200,
              child: Text(
                displayName.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  color: isLive ? Colors.red.shade700 : Colors.grey.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isLive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.videocam, color: Colors.white, size: 10),
                              SizedBox(width: 2),
                              Text(
                                'EN VIVO',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Vinculado $linkedSince',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ],
            ),
            IconButton(
            icon: Icon(Icons.link_off, color: Colors.red.shade400, size: 20),
            tooltip: 'Revocar vínculo',
            onPressed: () => _confirmRevokeObserver(obs),
          ),
          ],
        ),
      ),
    );
  }
  Future<void> _confirmRevokeObserver(Map<String, dynamic> obs) async {
    final displayName = obs['displayName'] as String? ?? 'este observador';
    final linkId = obs['link_id'] as String;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Revocar vínculo?'),
        content: Text('$displayName dejará de ver tu ubicación.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Revocar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await LinkService().revokeLink(linkId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(' $displayName ya no puede verte'),
              backgroundColor: Colors.orange,
            ),
          );
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
      }
    }
  }

  // ESTADO MODO EN VIVO 
  Widget _buildLiveModeCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _isLiveModeActive
                        ? Colors.red.shade100
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.videocam,
                    color: _isLiveModeActive
                        ? Colors.red.shade700
                        : Colors.grey.shade700,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Monitoreo en Vivo',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isLiveModeActive
                        ? Colors.red.shade100
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isLiveModeActive) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        _isLiveModeActive ? 'ACTIVO' : 'INACTIVO',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _isLiveModeActive
                              ? Colors.red.shade900
                              : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _isLiveModeActive
                  ? ' Un observador está viendo tu ubicación en tiempo real. La actualización se realiza cada minuto.'
                  : '⚪ Ningún observador está viendo tu ubicación en vivo. Las actualizaciones son cada 5 minutos (o 2 minutos en zonas de riesgo).',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Solo tus observadores pueden activar o desactivar el monitoreo en vivo.',
                      style: TextStyle(fontSize: 12, color: colorScheme.primary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // TAB 1: ALERTAS
  Widget _buildAlertsTab() {
    return AlertHistoryScreen(
      objectiveId: _auth.currentUser?.uid,
      objectiveName: 'Yo',
    );
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
                      if (mounted) context.go(AppRoutes.login);
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

  //  SOS LOGICA
  Future<void> _confirmAndSendSOS() async {
    final confirmed = await _showSOSConfirmationDialog();
    if (confirmed != true || !mounted) return;

    setState(() => _isSendingSOS = true);
    await HapticService.vibratePattern([0, 100, 50, 100, 50, 200]);

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );

      final objectiveId = _auth.currentUser?.uid;
      if (objectiveId == null) throw Exception('Usuario no autenticado');

      await _eventQueue.sendSOS(
        objectiveId: objectiveId,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        velocity: position.speed,
        message: 'Solicitud de auxilio inmediato.',
      );

      setState(() {
        _lastSOSTimestamp = DateTime.now();
        _isSendingSOS = false;
      });

      _startCooldown();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ' SOS enviado (±${position.accuracy.toStringAsFixed(1)}m)',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error al enviar SOS: $e');
      if (mounted) {
        setState(() => _isSendingSOS = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar SOS: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  Future<bool?> _showSOSConfirmationDialog() async {
    int countdown = 3;
    bool canConfirm = false;
    Timer? timer;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          if (countdown == 3 && timer == null) {
            timer = Timer.periodic(const Duration(seconds: 1), (t) {
              countdown--;
              if (countdown <= 0) {
                t.cancel();
                setState(() => canConfirm = true);
              } else {
                setState(() {});
              }
            });
          }

          return PopScope(
            canPop: false,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.red.shade700, size: 28),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('¿Confirmar SOS?')),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Esta alerta será enviada a TODOS tus observadores con tu ubicación actual.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: canConfirm ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: canConfirm ? Colors.green.shade200 : Colors.orange.shade200,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          canConfirm ? Icons.check_circle : Icons.hourglass_empty,
                          color: canConfirm ? Colors.green.shade700 : Colors.orange.shade700,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          canConfirm ? 'Listo para enviar' : 'Espera $countdown segundos...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: canConfirm ? Colors.green.shade700 : Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    timer?.cancel();
                    Navigator.pop(context, false);
                  },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: canConfirm
                      ? () {
                          timer?.cancel();
                          Navigator.pop(context, true);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    disabledBackgroundColor: Colors.grey.shade300,
                  ),
                  child: const Text('CONFIRMAR SOS', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
        },
      ),
    ).then((result) {
      timer?.cancel();
      return result;
    });
  }

  void _startCooldown() {
    _sosCooldownActive = true;
    _cooldownSeconds = 60;

    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _sosCooldownActive = false;
            _cooldownSeconds = 0;
          });
        }
      } else {
        if (mounted) setState(() => _cooldownSeconds--);
      }
    });
  }

  String _formatTimeAgo(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return 'hace ${diff.inSeconds}s';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    return 'hace ${diff.inDays}d';
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _geofencesSubscription?.cancel();
    _locationSubscription?.cancel();
    _sosSubscription?.cancel(); 
    super.dispose();
  }
}