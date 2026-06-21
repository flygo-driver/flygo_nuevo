import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Publica en Firestore la config de lanzamiento soportable (merge).
/// Solo admin puede escribir `config/*` — se invoca al entrar al panel ADM.
class LaunchConfigBootstrap {
  LaunchConfigBootstrap._();

  static const int _version = 2;
  static bool _running = false;
  static bool _done = false;

  static const Map<String, dynamic> financePatch = {
    'pagosConTarjetaAzulHabilitados': false,
    'poolRecaudoCentralHabilitado': true,
    'poolRecaudoSoloNuevasGiras': true,
    'poolLiquidacionAlFinalizar': true,
    'poolRecaudoAutoVerificarConciliacion': true,
    'transferenciaRecaudoEnCuentaRai': true,
    'transferenciaExigeVerificadoParaFinalizar': false,
    'conciliacionAutomaticaHabilitada': true,
  };

  static const Map<String, dynamic> productosPatch = {
    'modoLanzamientoNucleo': false,
    'clienteBolaHabilitado': true,
    'clienteMultiparadaHabilitado': true,
    'clienteMotorHabilitado': true,
    'clienteGirasHabilitado': true,
    'clienteTurismoHabilitado': true,
    'launchConfigVersion': _version,
  };

  /// Idempotente: merge en Firestore; no pisa flags distintos salvo los del patch.
  static Future<void> ensureProduccionSoportable() async {
    if (_done || _running) return;
    _running = true;
    try {
      final db = FirebaseFirestore.instance;
      final productosRef = db.collection('config').doc('productos');
      final snap = await productosRef.get();
      final currentVer =
          ((snap.data()?['launchConfigVersion'] ?? 0) as num).toInt();
      if (currentVer >= _version) {
        _done = true;
        return;
      }

      final ts = FieldValue.serverTimestamp();
      await productosRef.set(
        {...productosPatch, 'updatedAt': ts},
        SetOptions(merge: true),
      );
      await db.collection('config').doc('finance').set(
            {...financePatch, 'updatedAt': ts},
            SetOptions(merge: true),
          );
      _done = true;
      debugPrint('[LaunchConfigBootstrap] OK config/productos + config/finance v$_version');
    } catch (e, st) {
      debugPrint('[LaunchConfigBootstrap] error: $e\n$st');
    } finally {
      _running = false;
    }
  }
}
