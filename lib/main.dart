import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import 'package:geocercas_app/routes.dart';
import 'package:geocercas_app/core/services/notification_service.dart';
import 'package:geocercas_app/core/services/notification_navigation.dart';
import 'package:geocercas_app/core/services/event_queue_service.dart';
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
  
  await NotificationService().init();
  await Hive.initFlutter();
  await EventQueueService().init();
  await DecisionEngine.initialize();
  await EventQueueService().cleanInvalidEvents();

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

Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "",  // APP KEY
        appId: "", // APP ID
        messagingSenderId: "", // SENDER ID
        projectId: "", // PROJECT ID
        storageBucket: "", // PROJECT ID appspot.com
      ),
    );
  } catch (e) {
    if (e.toString().contains('duplicate-app')) {
      Firebase.app();
      debugPrint('Firebase ya inicializado');
    } else {
      rethrow;
    }
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