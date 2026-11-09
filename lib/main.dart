import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import 'package:geocercas_app/routes.dart';
import 'package:geocercas_app/data/services/location_service.dart';
import 'package:geocercas_app/core/services/notification_service.dart';
import 'package:geocercas_app/core/services/notification_navigation.dart';
import 'package:geocercas_app/core/services/event_queue_service.dart';
import 'package:geocercas_app/core/services/e2e_encryption_service.dart';
import 'package:geocercas_app/core/services/decision_engine.dart';
import 'package:geocercas_app/core/widgets/app_lock_wrapper.dart';

// Instancia de notificaciones locales
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  if (response.payload != null) {
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      debugPrint('️Notificación en BACKGROUND tocada: type=${data['type']}');
      NotificationNavigation().handleNotificationTap(data);
    } catch (e) {
      debugPrint('Error en background response: $e');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeFirebase();
  
  // Inicializar notificaciones locales antges del NotificationService
  await _initLocalNotifications();
  
  unawaited(NotificationService().init().catchError((Object _) {
    debugPrint('Servicio de notificaciones no disponible al iniciar');
  }));
  await Hive.initFlutter();
  await EventQueueService().init();
  await DecisionEngine.initialize();
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user == null) {
      unawaited(LocationService().stopBackgroundTracking());
    } else {
      unawaited(_resumeSession());
    }
  });

  Connectivity().onConnectivityChanged.listen((result) {
    if (result != ConnectivityResult.none && FirebaseAuth.instance.currentUser != null) {
      unawaited(_resumeSession());
    }
  });

  runApp(const GeocercasApp());
}

// Función de inicialización de notificaciones locales
Future<void> _initLocalNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      if (response.payload != null) {
        try {
          final data = jsonDecode(response.payload!) as Map<String, dynamic>;
          debugPrint('Notificación local tocada: type=${data['type']}');
          NotificationNavigation().handleNotificationTap(data);
        } catch (e) {
          debugPrint('Error al parsear payload de notificación: $e');
        }
      }
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );
  
  debugPrint('Notificaciones locales inicializadas');
}

// Android obtiene la configuración del google-services.json del entorno.
Future<void> _initializeFirebase() async {
  await Firebase.initializeApp();
}

Future<void> _resumeSession() async {
  unawaited(EventQueueService().syncPendingEvents());
  try {
    await E2EEncryptionService().registerDeviceKey();
  } catch (_) {
    debugPrint('La clave del dispositivo aún no pudo registrarse');
  }
}

class GeocercasApp extends StatelessWidget {
  const GeocercasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Geocercas Inteligentes',
      debugShowCheckedModeBanner: false,
      locale: const Locale('es', 'ES'),
      supportedLocales: const [
        Locale('es', 'ES'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      routerConfig: router,
      builder: (context, child) {
        NotificationNavigation().init(context);
        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final user = snapshot.data;
            if (user == null) return child!;
            return AppLockWrapper(child: child!);
          },
        );
      },
    );
  }
}