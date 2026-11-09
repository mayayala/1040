import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:geocercas_app/core/services/notification_navigation.dart';
import 'package:geocercas_app/main.dart' show flutterLocalNotificationsPlugin;

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  String? _currentToken;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
   Future<String?> getCurrentToken() async {
    if (_currentToken != null) return _currentToken;
    try {
      _currentToken = await _messaging.getToken();

      return _currentToken;
    } catch (e) {
      debugPrint('Error al obtener token FCM: $e');
      return null;
    }
  }

  Future<void> refreshAndSaveToken() async {
    try {
      _currentToken = await _messaging.getToken();
      if (_currentToken != null) {
        await _saveFcmToken(_currentToken!);
        debugPrint('Token FCM refrescado y guardado');
      }
    } catch (e) {
      debugPrint('Error al refrescar token: $e');
    }
  }

  Future<void> init() async {
    debugPrint('Inicializando NotificationService...');

    // 1. Solicitar permisos
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('Permisos de notificación: ${settings.authorizationStatus}');

    // 2. Crear canal de notificación usando la INSTANCIA GLOBAL
    await _setupLocalNotifications();

    // 3. Obtener y guardar token
    String? token = await _messaging.getToken();

    if (token != null) await _saveFcmToken(token);

    // 4. Escuchar cambios de token
    _messaging.onTokenRefresh.listen(_saveFcmToken);

    // 5. Manejar mensajes en foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FOREGROUND] Mensaje recibido: ${message.notification?.title}');
      debugPrint('Título: ${message.notification?.title}');
      debugPrint('Cuerpo: ${message.notification?.body}');

      debugPrint('Channel ID: ${message.notification?.android?.channelId}');
      _showLocalNotification(message);
    });

    // 6. Manejar cuando se toca una notificación (background/killed)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('️ Notificación tocada: type=${message.data['type']}');
      NotificationNavigation().handleNotificationTap(message.data);
    });

    // 7. Manejar notificación al iniciar la app desde killed state
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('App iniciada desde notificación: type=${initialMessage.data['type']}');
      Future.delayed(const Duration(milliseconds: 500), () {
        NotificationNavigation().handleNotificationTap(initialMessage.data);
      });
    }

    debugPrint('NotificationService inicializado');
  }

  Future<void> _setupLocalNotifications() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'Notificaciones importantes de geocercas',
      importance: Importance.high,
      playSound: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    
    debugPrint('Canal de notificación creado/verificado');
  }

  Future<void> _saveFcmToken(String token) async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _firestore.collection('users').doc(user.uid).update({
          'fcm_token': token,
          'updated_at': FieldValue.serverTimestamp(),
        });

      } catch (e) {
        debugPrint('Error al guardar token: $e');
      }
    }
  }

  /// Muestra notificación local
  Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      channelDescription: 'Notificaciones importantes de geocercas',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    final payload = jsonEncode({
      ...message.data,
    });

    await flutterLocalNotificationsPlugin.show(
      message.hashCode,
      message.notification?.title ?? 'Geocercas',
      message.notification?.body ?? 'Nueva notificación',
      platformChannelSpecifics,
      payload: payload,
    );
    debugPrint('Notificación local mostrada en foreground');
  }

}
