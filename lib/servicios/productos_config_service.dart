import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// `config/productos` — visibilidad por producto en cliente (sin redeploy).
///
/// Todo visible por defecto. [modoLanzamientoNucleo] se lee de Firestore pero
/// ya no oculta secciones en la UI (solo telemetría / compat admin legacy).
/// compatibilidad pero ya no oculta secciones en home.
class ProductosConfigService {
  ProductosConfigService._();

  /// Legacy: ya no oculta el menú (se mantiene por compatibilidad remota).
  static bool modoLanzamientoNucleo = false;

  static bool clienteBolaHabilitado = true;
  static bool clienteMultiparadaHabilitado = true;
  static bool clienteMotorHabilitado = true;
  static bool clienteGirasHabilitado = true;
  static bool clienteTurismoHabilitado = true;

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  static bool _started = false;

  /// Incrementa en cada cambio remoto para reconstruir home cliente.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static bool get muestraBola => clienteBolaHabilitado;

  static bool get muestraMultiparada => clienteMultiparadaHabilitado;

  static bool get muestraMotor => clienteMotorHabilitado;

  static bool get muestraGiras => clienteGirasHabilitado;

  static bool get muestraTurismo => clienteTurismoHabilitado;

  static bool get muestraConductoresEnRuta => muestraBola;

  static bool get hayOpcionesExtrasHome =>
      muestraMultiparada ||
      muestraMotor ||
      muestraGiras ||
      muestraTurismo;

  static bool get hayExperienciasSecundarias =>
      muestraGiras || muestraBola || muestraConductoresEnRuta;

  static Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('config')
          .doc('productos')
          .get();
      _apply(snap.data());
    } catch (_) {}
    _sub = FirebaseFirestore.instance
        .collection('config')
        .doc('productos')
        .snapshots()
        .listen((snap) => _apply(snap.data()));
  }

  static void _apply(Map<String, dynamic>? data) {
    if (data == null) return;
    modoLanzamientoNucleo =
        _boolOr(data['modoLanzamientoNucleo'], false);
    clienteBolaHabilitado =
        _boolOr(data['clienteBolaHabilitado'], true);
    clienteMultiparadaHabilitado =
        _boolOr(data['clienteMultiparadaHabilitado'], true);
    clienteMotorHabilitado =
        _boolOr(data['clienteMotorHabilitado'], true);
    clienteGirasHabilitado =
        _boolOr(data['clienteGirasHabilitado'], true);
    clienteTurismoHabilitado =
        _boolOr(data['clienteTurismoHabilitado'], true);
    revision.value++;
  }

  static bool _boolOr(dynamic raw, bool defaultValue) {
    if (raw == null) return defaultValue;
    if (raw is bool) return raw;
    return defaultValue;
  }

  static void disposeService() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
