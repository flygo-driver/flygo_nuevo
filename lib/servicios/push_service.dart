import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/cliente/viaje_en_curso_cliente.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';

class PushService {
  PushService._();

  static final FirebaseMessaging _fm = FirebaseMessaging.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static bool _openHandlersBound = false;

  /// Abre [ViajeEnCursoCliente] al tocar la push de viaje programado en pool.
  static void registerNotificationOpenHandlers() {
    if (kIsWeb || _openHandlersBound) return;
    _openHandlersBound = true;
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedRemoteMessage);
  }

  /// Arranque en frío: notificación que abrió la app.
  static Future<void> consumeInitialNotificationIfAny() async {
    if (kIsWeb) return;
    final RemoteMessage? initial = await _fm.getInitialMessage();
    if (initial != null) {
      await _handleOpenedRemoteMessage(initial);
    }
  }

  static Future<void> _handleOpenedRemoteMessage(RemoteMessage message) async {
    final data = message.data;
    final String type = (data['type'] ?? '').toString();
    if (type != 'scheduled_trip_pool_open') return;

    final String viajeId = (data['viajeId'] ?? '').toString().trim();
    if (viajeId.isEmpty) return;

    User? u = _auth.currentUser;
    if (u == null) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      u = _auth.currentUser;
    }
    if (u == null) return;

    final snap = await _db.collection('viajes').doc(viajeId).get();
    if (!snap.exists) return;
    final vd = snap.data()!;
    final String cid =
        (vd['uidCliente'] ?? vd['clienteId'] ?? '').toString().trim();
    if (cid != u.uid) return;

    await _db.collection('usuarios').doc(u.uid).set(
      {
        'viajeActivoId': viajeId,
        'siguienteViajeId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    final nav = NavigationService.navigatorKey.currentState;
    if (nav == null || !nav.mounted) return;

    nav.push(
      MaterialPageRoute<void>(
        fullscreenDialog: false,
        builder: (_) => const ViajeEnCursoCliente(),
      ),
    );
  }

  /// Compat con tu código viejo:
  static Future<void> ensureInitedAndSaved() => initAndRegisterToken();

  /// Llamar al arrancar (si hay sesión) y justo después de iniciar sesión.
  static Future<void> initAndRegisterToken() async {
    // Permisos/presentación (Android/iOS)
    if (!kIsWeb) {
      await _requestPermissionsMobile();
      await _fm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
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

  /// Quita el token actual del usuario (logout).
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
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return; // si niega, no guardamos token
    }
  }

  /// Guarda tokens en /push_tokens/{uid}
  static Future<void> _saveToken(String uid, String token) async {
    final ref = _db.collection('push_tokens').doc(uid);
    await ref.set({
      'tokens': FieldValue.arrayUnion([token]),
      'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
