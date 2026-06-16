import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Evita reabrir [PostViajeClienteFlow] para el mismo viaje tras cerrar el flujo.
///
/// Memoria (sesión) + SharedPreferences (reinicio shell / nueva instancia del listener)
/// + campo opcional en `viajes` (`clientePostViajeVistoEn`).
class ClientePostViajeReopenGuard {
  ClientePostViajeReopenGuard._();

  static final Set<String> _idsSesion = <String>{};
  static const String _prefsKey = 'rai_cliente_post_viaje_visto_ids';
  static const int _maxIdsPersistidos = 80;

  static bool shouldSuppressListenerPush(String viajeId) {
    return shouldSuppress(viajeId);
  }

  /// true si el viaje ya cerró post-viaje (RAM, prefs o doc).
  static bool shouldSuppress(
    String viajeId, {
    Map<String, dynamic>? viajeData,
  }) {
    final String id = viajeId.trim();
    if (id.isEmpty) return false;
    if (_idsSesion.contains(id)) return true;
    if (_vistoEnDoc(viajeData)) return true;
    return false;
  }

  static bool _vistoEnDoc(Map<String, dynamic>? d) {
    if (d == null) return false;
    return d['clientePostViajeVistoEn'] != null;
  }

  /// Al abrir el flow (evita doble push concurrente).
  static void markOpened(String viajeId) {
    final String id = viajeId.trim();
    if (id.isNotEmpty) _idsSesion.add(id);
  }

  /// Al terminar el flow (inicio, back, cierre): no volver a ofrecer.
  static Future<void> markCompleted({
    required String viajeId,
    String? uidCliente,
  }) async {
    final String id = viajeId.trim();
    if (id.isEmpty) return;
    _idsSesion.add(id);

    unawaited(_persistirPrefs(id));
    if (uidCliente != null && uidCliente.trim().isNotEmpty) {
      unawaited(_persistirFirestore(id, uidCliente.trim()));
    }
  }

  static Future<void> _persistirPrefs(String viajeId) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> ids = List<String>.from(
        prefs.getStringList(_prefsKey) ?? const <String>[],
      );
      if (!ids.contains(viajeId)) {
        ids.insert(0, viajeId);
        while (ids.length > _maxIdsPersistidos) {
          ids.removeLast();
        }
        await prefs.setStringList(_prefsKey, ids);
      }
    } catch (e) {
      debugPrint('[PostViajeGuard] prefs $e');
    }
  }

  static Future<void> _persistirFirestore(
    String viajeId,
    String uidCliente,
  ) async {
    try {
      await FirebaseFirestore.instance.collection('viajes').doc(viajeId).set(
        <String, dynamic>{
          'clientePostViajeVistoEn': FieldValue.serverTimestamp(),
          'clientePostViajeVistoPorUid': uidCliente,
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[PostViajeGuard] firestore $e');
    }
  }

  /// Carga prefs al arrancar el listener (async).
  static Future<void> hydrateFromPrefs() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> ids =
          prefs.getStringList(_prefsKey) ?? const <String>[];
      _idsSesion.addAll(ids.where((s) => s.trim().isNotEmpty));
    } catch (_) {}
  }

  /// Listener: si el doc ya tiene marca o está en prefs.
  static Future<bool> shouldSuppressAsync(
    String viajeId, {
    Map<String, dynamic>? viajeData,
  }) async {
    if (shouldSuppress(viajeId, viajeData: viajeData)) return true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> ids =
          prefs.getStringList(_prefsKey) ?? const <String>[];
      return ids.contains(viajeId.trim());
    } catch (_) {
      return false;
    }
  }
}
