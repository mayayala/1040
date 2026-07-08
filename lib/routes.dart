import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geocercas_app/presentation/screens/onboarding_screen.dart';
import 'package:geocercas_app/presentation/screens/login_screen.dart';
import 'package:geocercas_app/presentation/screens/register_screen.dart';
import 'package:geocercas_app/presentation/screens/home_objective_screen.dart';
import 'package:geocercas_app/presentation/screens/home_observer_screen.dart';
import 'package:geocercas_app/data/services/auth_service.dart';
import 'package:geocercas_app/presentation/screens/pending_requests_screen.dart';
import 'package:geocercas_app/presentation/screens/auth_choice_screen.dart';
import 'package:geocercas_app/presentation/screens/geofence_creator_screen.dart'; 

class AppRoutes {
  static const String onboarding = '/onboarding';
  static const String authChoice = '/auth-choice';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String homeObjective = '/home/objective';
  static const String homeObserver = '/home/observer';
  static const String pendingRequests = '/pending-requests';
  static const String geofenceCreator = '/geofence_creator'; 
}

final GoRouter router = GoRouter(
  initialLocation: AppRoutes.onboarding,
  routes: [
    GoRoute(path: AppRoutes.onboarding, builder: (_, __) => const OnboardingScreen()),
    GoRoute(path: AppRoutes.authChoice, builder: (_, __) => const AuthChoiceScreen()),
    GoRoute(path: AppRoutes.login, builder: (_, __) => const LoginScreen()),
    GoRoute(path: AppRoutes.register, builder: (_, __) => const RegisterScreen()),
    GoRoute(path: AppRoutes.home, builder: (_, __) => const HomeScreen()),
    GoRoute(path: AppRoutes.homeObjective, builder: (_, __) => const HomeObjectiveScreen()),
    GoRoute(path: AppRoutes.homeObserver, builder: (_, __) => const HomeObserverScreen()),
    GoRoute(path: AppRoutes.pendingRequests, builder: (_, __) => const PendingRequestsScreen()),
    
    GoRoute(
      path: AppRoutes.geofenceCreator,
      builder: (context, state) {
        final args = state.extra as Map<String, dynamic>? ?? {};
        return GeofenceCreatorScreen(
          objectiveId: args['objectiveId'] ?? '',
          objectiveName: args['objectiveName'] ?? '',
          forceHomeName: args['forceHomeName'] ?? false, 
        );
      },
    ),
  ],
  
  redirect: (context, state) async {
    final isLoggedIn = AuthService().currentUser != null;
    final currentPath = state.matchedLocation;
    
    final publicRoutes = [
      AppRoutes.onboarding,
      AppRoutes.authChoice,
      AppRoutes.login,
      AppRoutes.register,
    ];
    
    if (!isLoggedIn) {
      if (currentPath == AppRoutes.onboarding) {
        final prefs = await SharedPreferences.getInstance();
        final hasSeen = prefs.getBool('onboarding_completed') ?? false;
        return hasSeen ? AppRoutes.authChoice : null;
      }
      
      if (!publicRoutes.contains(currentPath)) {
        return AppRoutes.login;
      }
      
      return null;
    }
    
    if (publicRoutes.contains(currentPath)) {
      return AppRoutes.home;
    }
    
    return null;
  },
);

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(AppRoutes.login);
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      await AuthService().signOut();
                      if (context.mounted) context.go(AppRoutes.login);
                    },
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go(AppRoutes.register);
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final roleTags = List<String>.from(data['role_tags'] ?? []);
        final consentAccepted = data['consent_accepted'] == true;
        
        if (roleTags.isEmpty || !consentAccepted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go(AppRoutes.register);
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final hasObserver = roleTags.contains('observer');
        final hasObjective = roleTags.contains('objective');

        if (hasObserver) {
          return const HomeObserverScreen();
        } else if (hasObjective) {
          return const HomeObjectiveScreen();
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go(AppRoutes.register);
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}