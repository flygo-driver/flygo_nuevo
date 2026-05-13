// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/firebase_bootstrap.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_en_curso_cliente.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/notification_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

/// Handler top-level requerido por FCM en segundo plano / terminada.
@pragma('vm:entry-point')
Future<void> fcmFirebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('[FCM] background isolate messageId=${message.messageId}');
  await FirebaseBootstrap.ensureInitialized();
  await NotificationService.I.ensureInited();
  final data = message.data;
  final type = (data['type'] ?? '').toString();
  if (type == 'trip_chat_message' || type == 'trip_call_attempt') {
    if (message.notification != null) {
      print('[FCM] background: payload con notification; el SO muestra bandeja');
      return;
    }
    final title = message.notification?.title ??
        (type == 'trip_chat_message' ? 'Mensaje RAI' : 'Contacto RAI');
    final body = message.notification?.body ??
        (type == 'trip_chat_message'
            ? 'Nuevo mensaje en tu viaje'
            : 'Intento de contacto en tu viaje');
    final payload = jsonEncode(data);
    await NotificationService.I.showTripCommsLocal(
      title: title.isEmpty ? 'RAI' : title,
      body: body.isEmpty ? 'Toca para abrir' : body,
      payload: payload,
    );
  }
}

/// FCM: primer plano, taps y navegación a viaje en curso (cliente / taxista).
class FcmService {
  FcmService._();

  static bool get _supported => !kIsWeb && !Platform.isWindows;

  static bool _foregroundBound = false;

  /// Registra tap en notificaciones locales + [FirebaseMessaging.onMessage].
  static void registerForegroundHandlers() {
    if (!_supported || _foregroundBound) return;
    _foregroundBound = true;
    NotificationService.notificationTapPayloadHandler =
        handleLocalNotificationTap;
    FirebaseMessaging.onMessage.listen((RemoteMessage m) async {
      print('[FCM] onMessage type=${m.data['type']}');
      final type = (m.data['type'] ?? '').toString();
      if (type == 'trip_chat_message' || type == 'trip_call_attempt') {
        final title = m.notification?.title ??
            (type == 'trip_chat_message' ? 'Mensaje RAI' : 'Contacto RAI');
        final body = m.notification?.body ??
            (type == 'trip_chat_message'
                ? (m.data['preview'] ?? 'Nuevo mensaje').toString()
                : 'Intento de llamada o WhatsApp en tu viaje');
        final payload = jsonEncode(m.data);
        await NotificationService.I.showTripCommsLocal(
          title: title,
          body: body,
          payload: payload,
        );
      }
    });
  }

  static void handleLocalNotificationTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    print('[FCM] local notification tap payload len=${payload.length}');
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      unawaited(openTripFromPushData(map));
    } catch (e) {
      print('[FCM] tap parse error: $e');
    }
  }

  /// Abre la pantalla de viaje en curso según participación en [viajeId].
  static Future<void> openTripFromPushData(Map<String, dynamic> data) async {
    final type = (data['type'] ?? '').toString();
    if (type != 'trip_chat_message' && type != 'trip_call_attempt') {
      return;
    }
    final viajeId = (data['viajeId'] ?? '').toString().trim();
    if (viajeId.isEmpty) return;
    print('[CHAT_NOTIFICACION] navigate type=$type viajeId=$viajeId');

    User? u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      u = FirebaseAuth.instance.currentUser;
    }
    if (u == null) return;

    final snap =
        await FirebaseFirestore.instance.collection('viajes').doc(viajeId).get();
    if (!snap.exists) return;
    final vd = snap.data() ?? {};
    final cid = ViajesRepo.uidClienteDesdeDocViaje(vd);
    final tid = (vd['uidTaxista'] ?? vd['taxistaId'] ?? '').toString().trim();
    final bool isCliente = cid == u.uid;
    final bool isTaxista = tid == u.uid;
    if (!isCliente && !isTaxista) {
      print('[CHAT_NOTIFICACION] skip navigate: uid no participa en viaje');
      return;
    }

    final nav = NavigationService.navigatorKey.currentState;
    if (nav == null || !nav.mounted) return;

    if (isCliente) {
      await nav.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const ViajeEnCursoCliente(),
        ),
      );
    } else {
      await nav.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const ViajeEnCursoTaxista(),
        ),
      );
    }
  }

  static Future<void> handleRemoteOpen(RemoteMessage message) async {
    await openTripFromPushData(
      Map<String, dynamic>.from(message.data),
    );
  }
}
