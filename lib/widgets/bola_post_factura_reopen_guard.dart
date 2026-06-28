import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Evita reabrir [FacturaBolaPueblo] para la misma bola/rol tras cerrar el comprobante.
///
/// Memoria (sesión) + SharedPreferences (reinicio) + marca en `bolas_pueblo`.
class BolaPostFacturaReopenGuard {
  BolaPostFacturaReopenGuard._();

  static final Set<String> _keysSesion = <String>{};
  static const String _prefsKey = 'rai_bola_factura_vista_keys';
  static const int _maxKeysPersistidos = 120;

  static String _storageKey(String bolaId, String role) {
    final String id = bolaId.trim();
    final String r = role.trim().toLowerCase();
    if (id.isEmpty || (r != 'taxista' && r != 'cliente')) return '';
    return '$r:$id';
  }

  static bool shouldSuppressListenerPush(String bolaId, {String role = ''}) {
    return shouldSuppress(bolaId, role: role);
  }

  static bool shouldSuppress(
    String bolaId, {
    String role = '',
    Map<String, dynamic>? bolaData,
  }) {
    final String key = _storageKey(bolaId, role);
    if (key.isEmpty) return false;
    if (_keysSesion.contains(key)) return true;
    if (_vistoEnDoc(bolaData, role)) return true;
    return false;
  }

  static bool _vistoEnDoc(Map<String, dynamic>? d, String role) {
    if (d == null) return false;
    final String r = role.trim().toLowerCase();
    if (r == 'taxista') return d['taxistaFacturaBolaVistaEn'] != null;
    if (r == 'cliente') return d['clienteFacturaBolaVistaEn'] != null;
    return d['taxistaFacturaBolaVistaEn'] != null ||
        d['clienteFacturaBolaVistaEn'] != null;
  }

  static void markOpened(String bolaId, {String role = ''}) {
    final String key = _storageKey(bolaId, role);
    if (key.isNotEmpty) _keysSesion.add(key);
  }

  static Future<void> markCompleted({
    required String bolaId,
    required String role,
    String? uid,
  }) async {
    final String key = _storageKey(bolaId, role);
    if (key.isEmpty) return;
    _keysSesion.add(key);

    unawaited(_persistirPrefs(key));
    if (uid != null && uid.trim().isNotEmpty) {
      unawaited(_persistirFirestore(bolaId.trim(), role.trim().toLowerCase(), uid.trim()));
    }
  }

  static Future<void> _persistirPrefs(String key) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> keys = List<String>.from(
        prefs.getStringList(_prefsKey) ?? const <String>[],
      );
      if (!keys.contains(key)) {
        keys.insert(0, key);
        while (keys.length > _maxKeysPersistidos) {
          keys.removeLast();
        }
        await prefs.setStringList(_prefsKey, keys);
      }
    } catch (e) {
      debugPrint('[BolaFacturaGuard] prefs $e');
    }
  }

  static Future<void> _persistirFirestore(
    String bolaId,
    String role,
    String uid,
  ) async {
    try {
      final Map<String, dynamic> patch = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (role == 'taxista') {
        patch['taxistaFacturaBolaVistaEn'] = FieldValue.serverTimestamp();
        patch['taxistaFacturaBolaVistaPorUid'] = uid;
      } else {
        patch['clienteFacturaBolaVistaEn'] = FieldValue.serverTimestamp();
        patch['clienteFacturaBolaVistaPorUid'] = uid;
      }
      await FirebaseFirestore.instance
          .collection('bolas_pueblo')
          .doc(bolaId)
          .set(patch, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[BolaFacturaGuard] firestore $e');
    }
  }

  static Future<void> hydrateFromPrefs() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> keys =
          prefs.getStringList(_prefsKey) ?? const <String>[];
      _keysSesion.addAll(keys.where((s) => s.trim().isNotEmpty));
    } catch (_) {}
  }

  static Future<bool> shouldSuppressAsync(
    String bolaId, {
    required String role,
    Map<String, dynamic>? bolaData,
  }) async {
    if (shouldSuppress(bolaId, role: role, bolaData: bolaData)) return true;
    final String key = _storageKey(bolaId, role);
    if (key.isEmpty) return false;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> keys =
          prefs.getStringList(_prefsKey) ?? const <String>[];
      return keys.contains(key);
    } catch (_) {
      return false;
    }
  }
}
