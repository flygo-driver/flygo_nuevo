import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import 'package:flygo_nuevo/app_flavor.dart';
import 'package:flygo_nuevo/servicios/push_open_router.dart';

class PushService {
  PushService._();

  static final FirebaseMessaging _fm = FirebaseMessaging.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static bool _openHandlersBound = false;

  /// En Windows, `firebase_messaging` puede venir sin implementación completa
  /// (MissingPluginException en métodos como `getInitialMessage`).
  /// Para administración desde PC, evitamos llamadas a FCM y nos mantenemos en
  /// Firestore/Auth.
  static bool get _messagingSupported {
    if (kIsWeb) return false;
    if (Platform.isWindows) return false;
    return true;
  }

  /// Abre destino al tocar la push (remoto).
  static void registerNotificationOpenHandlers() {
    if (!_messagingSupported || _openHandlersBound) return;
    _openHandlersBound = true;
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      PushOpenRouter.handleOpenedPushData(m.data);
    });
  }

  /// Arranque en frío: notificación que abrió la app.
  static Future<void> consumeInitialNotificationIfAny() async {
    if (!_messagingSupported) return;
    final RemoteMessage? initial = await _fm.getInitialMessage();
    if (initial != null) {
      await PushOpenRouter.handleOpenedPushData(initial.data);
    }
  }

  /// Compat con tu código viejo:
  static Future<void> ensureInitedAndSaved() => initAndRegisterToken();

  /// Llamar al arrancar (si hay sesión) y justo después de iniciar sesión.
  static Future<void> initAndRegisterToken() async {
    if (!_messagingSupported) return;
    if (!kIsWeb) {
      await _requestPermissionsMobile();
      await _fm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: isTaxistaCapableFlavor,
      );
    }

    final u = _auth.currentUser;
    if (u == null) return;

    final token = await _fm.getToken();
    if (token != null && token.isNotEmpty) {
      await _saveToken(u.uid, token);
    }

    _fm.onTokenRefresh.listen((t) async {
      final cu = _auth.currentUser;
      if (cu != null && t.isNotEmpty) {
        await _saveToken(cu.uid, t);
      }
    });
  }

  /// Quita el token actual del usuario (logout).
  static Future<void> removeCurrentToken() async {
    if (!_messagingSupported) return;
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
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }
  }

  static Future<void> _saveToken(String uid, String token) async {
    final ref = _db.collection('push_tokens').doc(uid);
    await ref.set({
      'tokens': FieldValue.arrayUnion([token]),
      'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    try {
      await _db.collection('usuarios').doc(uid).set(
        {
          'pushToken': token,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      debugPrint('[FCM] pushToken guardado en usuarios/$uid (merge)');
    } catch (e) {
      debugPrint('[FCM] usuarios pushToken skip: $e');
    }
  }
}
