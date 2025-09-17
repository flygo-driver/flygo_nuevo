// lib/servicios/push_service.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart'; // ✅ init en BG
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PushService {
  PushService._();

  static final FirebaseMessaging _fm = FirebaseMessaging.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Compatibilidad con tu código viejo: puedes seguir llamando a este.
  static Future<void> ensureInitedAndSaved() => initAndRegisterToken();

  /// Llamar al arrancar (si hay sesión) y justo después de iniciar sesión.
  static Future<void> initAndRegisterToken() async {
    // Permisos y presentación en foreground (Android/iOS)
    if (!kIsWeb) {
      await _requestPermissionsMobile();
      await _fm.setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true,
      );
    }

    final u = _auth.currentUser;
    if (u == null) return;

    // Token actual
    final token = await _fm.getToken();
    if (token != null && token.isNotEmpty) {
      await _saveToken(u.uid, token);
    }

    // Refresh de token
    _fm.onTokenRefresh.listen((t) async {
      final cu = _auth.currentUser;
      if (cu != null && t.isNotEmpty) {
        await _saveToken(cu.uid, t);
      }
    });
  }

  /// Quita el token actual del usuario (llámalo en logout).
  static Future<void> removeCurrentToken() async {
    final u = _auth.currentUser;
    if (u == null) return;
    final t = await _fm.getToken();
    if (t == null || t.isEmpty) return;

    final ref = _db.collection('push_tokens').doc(u.uid);
    await ref.set({
      'tokens': FieldValue.arrayRemove([t]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> _requestPermissionsMobile() async {
    final settings = await _fm.requestPermission(
      alert: true, badge: true, sound: true,
      announcement: false, carPlay: false, criticalAlert: false, provisional: false,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      // Si el usuario niega, simplemente no guardamos token.
      return;
    }
  }

  /// Guarda tokens en /push_tokens/{uid} (array multi-dispositivo).
  static Future<void> _saveToken(String uid, String token) async {
    final ref = _db.collection('push_tokens').doc(uid);
    await ref.set({
      'tokens': FieldValue.arrayUnion([token]),
      'platform': kIsWeb ? 'web' : Platform.operatingSystem, // 'android' | 'ios' | 'web'
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

/// Handler de mensajes en background (regístralo en main.dart)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try { await Firebase.initializeApp(); } catch (_) {}
  // Aquí puedes hacer logging o prefetch si lo necesitas.
}
