import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/cliente/cliente_verificacion_identidad_page.dart';
import 'package:flygo_nuevo/servicios/flygo_storage.dart';

/// Estado visible de la confirmación periódica (selfie) del pasajero.
enum ClienteVerificacionIdentidadEstado {
  noAplica,
  sinSelfie,
  vigente,
  porRevisar,
  vencida,
  rechazada,
}

/// Verificación periódica del pasajero (selfie) antes de pedir viajes o reservar giras.
///
/// No se exige foto al registrarse; sí al usar el servicio cada [intervaloPorDefecto].
abstract final class ClienteVerificacionIdentidadService {
  ClienteVerificacionIdentidadService._();

  static const Duration intervaloPorDefecto = Duration(days: 30);

  static const String mensajeRequerida =
      'Por seguridad, confirma que eres tú con una selfie para continuar.';

  static const String campoRevision = 'verificacionIdentidadRevision';
  static const String campoMotivoRechazo = 'verificacionIdentidadRechazoMotivo';

  static const String revisionPendiente = 'pendiente';
  static const String revisionAprobada = 'aprobada';
  static const String revisionRechazada = 'rechazada';

  /// Estado de revisión del ADM. Las selfies viejas no traen el campo y cuentan
  /// como pendientes: así el admin ve el rezago en vez de darlas por buenas.
  static String revisionDesde(Map<String, dynamic> data) {
    final v = (data[campoRevision] ?? '').toString().trim().toLowerCase();
    if (v == revisionAprobada || v == revisionRechazada) return v;
    return revisionPendiente;
  }

  static String? motivoRechazoDesde(Map<String, dynamic> data) {
    if (revisionDesde(data) != revisionRechazada) return null;
    final m = (data[campoMotivoRechazo] ?? '').toString().trim();
    return m.isEmpty ? null : m;
  }

  /// Etiqueta corta para ADM y conductores (no implica KYC biométrico).
  static String etiquetaEstado(ClienteVerificacionIdentidadEstado estado) {
    switch (estado) {
      case ClienteVerificacionIdentidadEstado.noAplica:
        return 'N/A';
      case ClienteVerificacionIdentidadEstado.sinSelfie:
        return 'Sin confirmación';
      case ClienteVerificacionIdentidadEstado.vigente:
        return 'Selfie al día';
      case ClienteVerificacionIdentidadEstado.porRevisar:
        return 'Por revisar';
      case ClienteVerificacionIdentidadEstado.vencida:
        return 'Selfie vencida';
      case ClienteVerificacionIdentidadEstado.rechazada:
        return 'Selfie rechazada';
    }
  }

  static Color colorEstado(
    ClienteVerificacionIdentidadEstado estado, {
    bool isDark = true,
  }) {
    switch (estado) {
      case ClienteVerificacionIdentidadEstado.noAplica:
        return isDark ? Colors.white38 : const Color(0xFF98A2B3);
      case ClienteVerificacionIdentidadEstado.sinSelfie:
        return isDark ? Colors.orangeAccent : const Color(0xFFB54708);
      case ClienteVerificacionIdentidadEstado.vigente:
        return isDark ? Colors.greenAccent : const Color(0xFF027A48);
      case ClienteVerificacionIdentidadEstado.porRevisar:
        return isDark ? Colors.lightBlueAccent : const Color(0xFF175CD3);
      case ClienteVerificacionIdentidadEstado.vencida:
        return isDark ? Colors.redAccent : const Color(0xFFB42318);
      case ClienteVerificacionIdentidadEstado.rechazada:
        return isDark ? Colors.red : const Color(0xFF912018);
    }
  }

  static bool esCuentaPasajeroParaSelfie(Map<String, dynamic> data) {
    final String rol =
        (data['rol'] ?? 'cliente').toString().trim().toLowerCase();
    if (rol == 'cliente' || rol == 'user' || rol.isEmpty) return true;
    if (data['registroClienteCompleto'] == true) return true;
    if ((data['verificacionIdentidadUrl'] ?? '').toString().trim().isNotEmpty) {
      return true;
    }
    if (data['verificacionIdentidadEn'] != null) return true;
    return false;
  }

  static ClienteVerificacionIdentidadEstado estadoDesde(
    Map<String, dynamic> data,
  ) {
    if (!esCuentaPasajeroParaSelfie(data)) {
      return ClienteVerificacionIdentidadEstado.noAplica;
    }

    final ultima = ultimaVerificacionDesde(data);
    if (ultima == null) {
      final registro = _fechaRegistroDesde(data);
      if (registro == null) {
        return ClienteVerificacionIdentidadEstado.sinSelfie;
      }
      if (DateTime.now().difference(registro) >= intervaloDesdeUsuario(data)) {
        return ClienteVerificacionIdentidadEstado.vencida;
      }
      return ClienteVerificacionIdentidadEstado.sinSelfie;
    }

    if (revisionDesde(data) == revisionRechazada) {
      return ClienteVerificacionIdentidadEstado.rechazada;
    }
    if (_vencidaPorFecha(data)) {
      return ClienteVerificacionIdentidadEstado.vencida;
    }
    if (revisionDesde(data) == revisionPendiente) {
      return ClienteVerificacionIdentidadEstado.porRevisar;
    }
    return ClienteVerificacionIdentidadEstado.vigente;
  }

  static String? urlSelfieDesde(Map<String, dynamic> data) {
    final url = (data['verificacionIdentidadUrl'] ?? '').toString().trim();
    return url.isEmpty ? null : url;
  }

  /// Carga bytes de selfie si quedó en respaldo Firestore (`rai-doc://`).
  static Future<Uint8List?> bytesSelfieDesdeUrl({
    required String uid,
    required String? url,
  }) async {
    if (url == null || url.isEmpty) return null;
    if (!RaiDocUrl.isFirestoreDoc(url)) return null;
    final String tipo = RaiDocUrl.tipoFromUrl(url);
    return FlygoStorage.cargarDocImagen(uid: uid, tipo: tipo);
  }

  static String detalleEstadoParaAdmin(Map<String, dynamic> data) {
    final estado = estadoDesde(data);
    final intervalo = intervaloDesdeUsuario(data);
    final ultima = ultimaVerificacionDesde(data);
    final dias = intervalo.inDays;

    switch (estado) {
      case ClienteVerificacionIdentidadEstado.noAplica:
        return 'No aplica (no es cliente).';
      case ClienteVerificacionIdentidadEstado.sinSelfie:
        return 'Aún no ha enviado selfie de confirmación (intervalo $dias días).';
      case ClienteVerificacionIdentidadEstado.vigente:
        if (ultima == null) return 'Confirmación vigente.';
        return 'Última selfie: ${_fmtFecha(ultima)} · aprobada · vigente por $dias días.';
      case ClienteVerificacionIdentidadEstado.porRevisar:
        if (ultima == null) return 'Selfie enviada, falta revisarla.';
        return 'Selfie del ${_fmtFecha(ultima)} · falta revisarla.';
      case ClienteVerificacionIdentidadEstado.rechazada:
        final motivo = motivoRechazoDesde(data);
        if (motivo == null) return 'Selfie rechazada; debe enviar otra.';
        return 'Selfie rechazada: $motivo';
      case ClienteVerificacionIdentidadEstado.vencida:
        if (ultima == null) {
          return 'Debe confirmar identidad (pasó el plazo desde el registro).';
        }
        return 'Última selfie: ${_fmtFecha(ultima)} · vencida (cada $dias días).';
    }
  }

  static String _fmtFecha(DateTime dt) {
    final d = dt.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year} $hh:$min';
  }

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

  static bool _vencidaPorFecha(Map<String, dynamic> data) {
    final intervalo = intervaloDesdeUsuario(data);
    final ultima = ultimaVerificacionDesde(data);
    if (ultima != null) {
      return DateTime.now().difference(ultima) >= intervalo;
    }

    // Sin selfie previa: gracia desde el registro; sin fecha → exigir (cuentas legacy).
    final registro = _fechaRegistroDesde(data);
    if (registro == null) return true;
    return DateTime.now().difference(registro) >= intervalo;
  }

  /// `true` si venció el intervalo o si el ADM rechazó la última selfie.
  ///
  /// Una selfie pendiente de revisar NO frena al pasajero: si esperáramos al
  /// ADM, nadie podría viajar de madrugada.
  static bool debeVerificarAhora(Map<String, dynamic> data) {
    if (!esCuentaPasajeroParaSelfie(data)) return false;
    if (revisionDesde(data) == revisionRechazada) return true;
    return _vencidaPorFecha(data);
  }

  /// ADM aprueba la selfie: queda vigente hasta que venza el intervalo.
  static Future<void> aprobarSelfie({
    required String uid,
    required String adminUid,
  }) async {
    await FirebaseFirestore.instance.collection('usuarios').doc(uid).set(
      <String, dynamic>{
        campoRevision: revisionAprobada,
        campoMotivoRechazo: '',
        'verificacionIdentidadRevisadaEn': FieldValue.serverTimestamp(),
        'verificacionIdentidadRevisadaPor': adminUid,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// ADM rechaza: al pasajero se le vuelve a pedir la selfie con el motivo.
  static Future<void> rechazarSelfie({
    required String uid,
    required String adminUid,
    required String motivo,
  }) async {
    await FirebaseFirestore.instance.collection('usuarios').doc(uid).set(
      <String, dynamic>{
        campoRevision: revisionRechazada,
        campoMotivoRechazo: motivo.trim(),
        'verificacionIdentidadRevisadaEn': FieldValue.serverTimestamp(),
        'verificacionIdentidadRevisadaPor': adminUid,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
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

    Map<String, dynamic> data;
    try {
      data = await _datosUsuario(uid);
    } catch (_) {
      rethrow;
    }
    if (!debeVerificarAhora(data)) return true;
    if (!context.mounted) return false;

    final ok = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => const ClienteVerificacionIdentidadPage(),
      ),
    );
    if (ok != true) return false;
    try {
      data = await _datosUsuario(uid);
    } catch (_) {
      return true;
    }
    return !debeVerificarAhora(data);
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
