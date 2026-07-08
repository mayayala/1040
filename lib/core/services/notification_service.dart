import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:googleapis_auth/auth_io.dart' as auth;
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
      debugPrint('Token FCM obtenido: ${_currentToken?.substring(0, 20)}...');
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
    debugPrint('FCM Token obtenido: ${token?.substring(0, 20)}...');
    if (token != null) await _saveFcmToken(token);

    // 4. Escuchar cambios de token
    _messaging.onTokenRefresh.listen(_saveFcmToken);

    // 5. Manejar mensajes en foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FOREGROUND] Mensaje recibido: ${message.notification?.title}');
      debugPrint('Título: ${message.notification?.title}');
      debugPrint('Cuerpo: ${message.notification?.body}');
      debugPrint('Data: ${message.data}');
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
        await _firestore.collection('users').doc(user.uid).set({
          'fcm_token': token,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('FCM Token guardado para ${user.uid}');
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
      'type': message.data['type'],
      'data': message.data,
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

  /// Enviar notificacion
  static Future<void> sendPushNotification({
    required String targetToken,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    const String projectId = 'geocercasmvp';
    const String serviceAccountJson = r'''{

    }''';

    try {
      debugPrint('[API v1] Enviando a: ${targetToken.substring(0, 20)}...');
      
      final credentials = auth.ServiceAccountCredentials.fromJson(
        jsonDecode(serviceAccountJson),
      );
      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
      final client = await auth.clientViaServiceAccount(credentials, scopes);
      
      final message = {
        'message': {
          'token': targetToken,
          'notification': {'title': title, 'body': body},
          'android': {
            'priority': 'high',
            'ttl': '3600s',
            'notification': {
              'channel_id': 'high_importance_channel',
              'sound': 'default',
              'visibility': 'PUBLIC',
            },
          },
          'data': {
            ...(data ?? {}),
            'type': data?['type'] ?? 'generic',
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
        },
      };

      final response = await client.post(
        Uri.parse('https://fcm.googleapis.com/v1/projects/$projectId/messages:send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(message),
      );

      debugPrint('Status: ${response.statusCode}');
      debugPrint('Body crudo: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('Notificación enviada exitosamente (API v1)');
      } else {
        debugPrint('Error API v1 ${response.statusCode}');
        if (response.body.trim().startsWith('{')) {
          debugPrint('Error JSON: ${response.body}');
        } else {
          debugPrint('Respuesta NO es JSON (probablemente HTML o texto):');
          debugPrint(response.body.substring(0, response.body.length.clamp(0, 500)));
        }
      }
      
      client.close();
    } catch (e, stack) {
      debugPrint('Excepción en API v1: $e');
      debugPrint('Stack: $stack');
    }
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[BACKGROUND] Mensaje recibido: ${message.notification?.title}');
}