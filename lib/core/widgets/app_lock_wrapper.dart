import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocercas_app/presentation/screens/app_lock_screen.dart';

class AppLockWrapper extends StatefulWidget {
  final Widget child;

  const AppLockWrapper({super.key, required this.child});

  @override
  State<AppLockWrapper> createState() => _AppLockWrapperState();
}

class _AppLockWrapperState extends State<AppLockWrapper> with WidgetsBindingObserver {
  bool _isLocked = true;
  bool _isAuthenticated = false;
  
  //  Rastrea si el usuario desbloqueó manualmente
  bool _wasManuallyUnlocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAuthState();
    
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (mounted) {
        setState(() {
          _isAuthenticated = user != null;
          if (user == null) {
            _isLocked = true;
            _wasManuallyUnlocked = false;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkAuthState() async {
    final user = FirebaseAuth.instance.currentUser;
    if (mounted) {
      setState(() {
        _isAuthenticated = user != null;
        _isLocked = user != null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('AppLifecycleState: $state');
    
    if (state == AppLifecycleState.resumed) {
      // Solo bloquear si no fue desbloqueado manualmente
      if (_isAuthenticated && !_wasManuallyUnlocked) {
        setState(() => _isLocked = true);
        debugPrint('App reanudada → Bloqueando de nuevo');
      } else if (_wasManuallyUnlocked) {
        debugPrint('App reanudada pero fue desbloqueada manualmente → Mantener desbloqueada');
      }
    } else if (state == AppLifecycleState.paused || 
               state == AppLifecycleState.inactive) {
      debugPrint('App en segundo plano');
      _wasManuallyUnlocked = false;
    }
  }

  void _onUnlock() {
    setState(() {
      _isLocked = false;
      _wasManuallyUnlocked = true;
    });
    debugPrint('App desbloqueada manualmente');
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return widget.child;
    }

    if (_isLocked) {
      return Navigator(
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            builder: (context) => AppLockScreen(
              onUnlock: _onUnlock,
              isFirstTimeSetup: false,
            ),
          );
        },
      );
    }

    return widget.child;
  }
}