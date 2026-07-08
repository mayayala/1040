import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocercas_app/core/services/notification_service.dart';

/// Servicio de autenticación: registro, login, logout, recuperación de contraseña y gestión de perfil
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  
  User? get currentUser => _auth.currentUser;

  /// Registra un nuevo usuario y guarda su FCM token
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
    required int age,
    required String gender,
    required DateTime dateOfBirth,
    required List<String> roleTags,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    await credential.user?.updateDisplayName(displayName.trim());

    final fcmToken = await _notificationService.getCurrentToken();

    await _firestore.collection('users').doc(credential.user?.uid).set({
      'uid': credential.user?.uid,
      'email': email.trim().toLowerCase(),
      'displayName': displayName.trim(),
      'age': age,
      'gender': gender,
      'date_of_birth': Timestamp.fromDate(dateOfBirth),
      'role_tags': roleTags,
      'consent_accepted': true,
      'consent_date': FieldValue.serverTimestamp(),
      'onboarding_completed': true,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'is_deleted': false,
      'live_mode_active': false,
      if (fcmToken != null) 'fcm_token': fcmToken,
    }, SetOptions(merge: true));

    _notificationService.refreshAndSaveToken();
    return credential;
  }
  /// Inicia sesión y actualiza el FCM token del usuario
  Future<UserCredential> loginWithEmail({
    required String email,
    required String password,
  }) async {
    // 1. Autenticar con Firebase
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );

    // 2.  Actualizar token FCM después de login exitoso
    _notificationService.refreshAndSaveToken(); 
    return credential;
  }

  /// Cierra sesión del usuario actual
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Envía email de recuperación de contraseña
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
  }

  /// Elimina la cuenta del usuario actual
  Future<void> deleteAccount() async {
    final user = currentUser;
    if (user == null) throw Exception('No hay usuario autenticado');

    // 1. Marcar como eliminado
    await _firestore.collection('users').doc(user.uid).update({
      'is_deleted': true,
      'deleted_at': FieldValue.serverTimestamp(),
      'retention_date': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 30)),
      ),
      'updated_at': FieldValue.serverTimestamp(),
    });

    // 2. Revocar todos los vínculos de monitoreo asociados
    final batch = _firestore.batch();
    final linksSnapshot = await _firestore
        .collection('monitoring_links')
        .where(Filter.or(
          Filter('observer_id', isEqualTo: user.uid),
          Filter('objective_id', isEqualTo: user.uid),
        ))
        .get();

    for (final doc in linksSnapshot.docs) {
      batch.update(doc.reference, {
        'status': 'revoked',
        'revoked_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    // 3. Eliminar cuenta en Firebase Auth (irreversible)
    await user.delete();
  }

  /// Obtiene los datos del perfil del usuario desde Firestore
  Future<DocumentSnapshot<Map<String, dynamic>>> getUserProfile(String uid) async {
    return await _firestore.collection('users').doc(uid).get();
  }

  Future<void> updateUserProfile({
    required String uid,
    String? displayName,
    List<String>? roleTags,
    bool? liveModeActive,
    String? gender,
    DateTime? dateOfBirth,
    int? age,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': FieldValue.serverTimestamp(),
    };
    
    if (displayName != null) updates['displayName'] = displayName.trim();
    if (roleTags != null) updates['role_tags'] = roleTags;
    if (liveModeActive != null) updates['live_mode_active'] = liveModeActive;
    if (gender != null) updates['gender'] = gender;
    if (dateOfBirth != null) updates['date_of_birth'] = Timestamp.fromDate(dateOfBirth);
    if (age != null) updates['age'] = age;

    await _firestore.collection('users').doc(uid).set(updates, SetOptions(merge: true));
  }

    /// Marca onboarding como completado 
  static Future<void> markOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
  }
  static Future<bool> hasCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarding_completed') ?? false;
  }
  static String getErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No existe una cuenta con este correo.';
      case 'wrong-password':
        return 'Contraseña incorrecta.';
      case 'email-already-in-use':
        return 'Este correo ya está registrado.';
      case 'invalid-email':
        return 'El correo electrónico no es válido.';
      case 'weak-password':
        return 'La contraseña es muy débil (mínimo 6 caracteres).';
      case 'operation-not-allowed':
        return 'Operación no permitida. Contacta al soporte.';
      case 'user-disabled':
        return 'Esta cuenta ha sido desactivada.';
      case 'too-many-requests':
        return 'Demasiados intentos. Intenta más tarde.';
      case 'network-request-failed':
        return 'Error de conexión. Verifica tu internet.';
      default:
        return 'Error de autenticación: ${e.message}';
    }
  }
}