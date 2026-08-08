// lib/servicios/rai_modo_sesion_service.dart
//
// Modo de sesión para taxistas que usan la app como pasajero sin cambiar `rol`
// en Firestore (mismo correo / mismo uid).

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flygo_nuevo/servicios/roles_service.dart';

enum RaiModoSesion { conductor, pasajero }

/// Persistencia local del modo activo (conductor vs pasajero) para cuentas taxista.
abstract final class RaiModoSesionService {
  RaiModoSesionService._();

  static const String _prefValorPasajero = 'pasajero';

  static RaiModoSesion _modo = RaiModoSesion.conductor;
  static String? _uidCargado;

  /// Notifica shells / router cuando cambia el modo.
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  static RaiModoSesion get modo => _modo;

  static bool get enModoPasajero => _modo == RaiModoSesion.pasajero;

  static bool get enModoConductor => _modo == RaiModoSesion.conductor;

  static String _prefKey(String uid) => 'rai_modo_sesion_${uid.trim()}';

  static Future<void> initParaUsuario(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return;
    if (_uidCargado == u && tick.value > 0) return;

    _uidCargado = u;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey(u));
      _modo = raw == _prefValorPasajero
          ? RaiModoSesion.pasajero
          : RaiModoSesion.conductor;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RAI_MODO_SESION] init error: $e');
      }
      _modo = RaiModoSesion.conductor;
    }
    tick.value++;
  }

  static Future<void> activarModoPasajero(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return;
    _uidCargado = u;
    _modo = RaiModoSesion.pasajero;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey(u), _prefValorPasajero);
    } catch (_) {}
    tick.value++;
  }

  static Future<void> activarModoConductor(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return;
    _uidCargado = u;
    _modo = RaiModoSesion.conductor;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey(u));
    } catch (_) {}
    tick.value++;
  }

  static void limpiarAlCerrarSesion() {
    _uidCargado = null;
    _modo = RaiModoSesion.conductor;
    tick.value++;
  }

  /// Taxista en modo pasajero o cliente nativo pueden pedir viajes.
  static Future<bool> cuentaPuedePedirViaje(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return false;
    final rol = (await RolesService.getRol(u))?.toLowerCase().trim();
    if (rol == Roles.cliente) return true;
    if (rol == Roles.taxista && enModoPasajero) return true;
    return false;
  }

  /// Router: taxista con sesión pasajero abre shell cliente.
  static bool taxistaDebeUsarShellPasajero(String rolFirestore) {
    final r = rolFirestore.trim().toLowerCase();
    return r == Roles.taxista && enModoPasajero;
  }
}
