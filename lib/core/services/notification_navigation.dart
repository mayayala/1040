import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geocercas_app/routes.dart';

class NotificationNavigation {
  static final NotificationNavigation _instance = NotificationNavigation._internal();
  factory NotificationNavigation() => _instance;
  NotificationNavigation._internal();

  BuildContext? _context;
  String? _pendingNavigationType;

  void init(BuildContext context) {
    _context = context;
    // Si hay una navegación pendiente, ejecútala ahora
    if (_pendingNavigationType != null) {
      _handleNavigation(_pendingNavigationType!);
      _pendingNavigationType = null;
    }
  }

  /// Maneja la navegación según el tipo de notificación
  void handleNotificationTap(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    
    if (type == null) return;
    
    if (_context != null && _context!.mounted) {
      _handleNavigation(type);
    } else {
      // Guardar para cuando el contexto esté disponible
      _pendingNavigationType = type;
    }
  }

    void _handleNavigation(String type) {
    if (_context == null || !_context!.mounted) return;
    
    switch (type) {
      case 'link_request':
        _context!.go(AppRoutes.pendingRequests);
        break;
        
      case 'link_accepted':
        _context!.go(AppRoutes.home);
        break;
        
      case 'sos_alert':
      case 'alert_critical':
      case 'alert_preventive':
        _context!.go(AppRoutes.home);
        break;
        
      default:
        _context!.go(AppRoutes.home);
    }
  }
}