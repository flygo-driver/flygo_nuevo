import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/cliente/cliente_verificacion_identidad_page.dart';

/// Verificación periódica del pasajero (selfie) antes de pedir viajes o reservar giras.
///
/// No se exige foto al registrarse; sí al usar el servicio cada [intervaloPorDefecto].
abstract final class ClienteVerificacionIdentidadService {
  ClienteVerificacionIdentidadService._();

  static const Duration intervaloPorDefecto = Duration(days: 30);

  static const String mensajeRequerida =
      'Por seguridad, confirma que eres tú con una selfie para continuar.';

  static DateTime? ultimaVerificacionDesde(Map<String, dynamic> data) {
    final v = data['verificacionIdentidadEn'];
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static Duration intervaloDesdeUsuario(Map<String, dynamic> data) {
    final dias = data['verificacionIdentidadIntervaloDias'];
    if (dias is num && dias >= 1 && dias <= 365) {
      return Duration(days: dias.round());
    }
    return intervaloPorDefecto;
  }

  static DateTime? _fechaRegistroDesde(Map<String, dynamic> data) {
    final v = data['fechaRegistro'] ?? data['createdAt'];
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  /// `true` solo si pasó el intervalo desde la última selfie (o desde el registro si nunca hubo).
  static bool debeVerificarAhora(Map<String, dynamic> data) {
    final rol = (data['rol'] ?? 'cliente').toString().trim().toLowerCase();
    if (rol != 'cliente') return false;

    final intervalo = intervaloDesdeUsuario(data);
    final ultima = ultimaVerificacionDesde(data);
    if (ultima != null) {
      return DateTime.now().difference(ultima) >= intervalo;
    }

    // Sin selfie previa: gracia desde el registro (entra fácil; no en cada viaje).
    final registro = _fechaRegistroDesde(data);
    if (registro == null) return false;
    return DateTime.now().difference(registro) >= intervalo;
  }

  static Future<Map<String, dynamic>> _datosUsuario(String uid) async {
    final snap = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .get();
    return snap.data() ?? <String, dynamic>{};
  }

  static Future<bool> necesitaVerificacionAhora() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final data = await _datosUsuario(uid);
    return debeVerificarAhora(data);
  }

  /// Muestra pantalla de selfie si corresponde. Devuelve `true` si puede continuar.
  static Future<bool> ensureVerificadoOMostrar(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return true;

    final data = await _datosUsuario(uid);
    if (!debeVerificarAhora(data)) return true;
    if (!context.mounted) return false;

    final ok = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => const ClienteVerificacionIdentidadPage(),
      ),
    );
    return ok == true;
  }

  /// Backend en repos: lanza si falta verificación vigente.
  static Future<void> exigirParaPedirViaje() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final data = await _datosUsuario(uid);
    if (!debeVerificarAhora(data)) return;
    throw ClienteVerificacionIdentidadRequeridaException(mensajeRequerida);
  }
}

class ClienteVerificacionIdentidadRequeridaException implements Exception {
  ClienteVerificacionIdentidadRequeridaException(this.message);
  final String message;

  @override
  String toString() => message;
}
