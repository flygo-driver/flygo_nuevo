import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Métodos de pago que el encargado puede declarar al liquidar con RAI.
abstract final class CorporativoMetodosPago {
  CorporativoMetodosPago._();

  static const transferencia = 'transferencia';
  static const deposito = 'deposito';
  static const cheque = 'cheque';
  static const efectivo = 'efectivo';
  static const otro = 'otro';

  static const List<String> todos = [
    transferencia,
    deposito,
    cheque,
    efectivo,
    otro,
  ];

  static String etiqueta(String raw) {
    return switch (raw.trim().toLowerCase()) {
      transferencia => 'Transferencia bancaria',
      deposito => 'Depósito en ventanilla',
      cheque => 'Cheque',
      efectivo => 'Efectivo',
      otro => 'Otro',
      _ => raw.isEmpty ? '—' : raw,
    };
  }

  static String instruccion(String raw) {
    return switch (raw.trim().toLowerCase()) {
      transferencia =>
        'Transfiere a la cuenta RAI indicada y adjunta el bauche.',
      deposito =>
        'Deposita en ventanilla a la cuenta RAI y adjunta el comprobante.',
      cheque => 'Entrega o deposita el cheque a nombre de RAI y adjunta foto.',
      efectivo => 'Coordina con tu ejecutivo RAI y adjunta el recibo.',
      _ => 'Adjunta el comprobante del pago realizado a RAI.',
    };
  }
}

/// Reportar pago / bauche corporativo (encargado → RAI).
abstract final class CorporativoPagoService {
  CorporativoPagoService._();

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _pagos(String empresaId) =>
      _db
          .collection('empresas_corporativas')
          .doc(empresaId)
          .collection('pagos_reportados');

  static Stream<List<Map<String, dynamic>>> streamPagos(String empresaId) {
    return _pagos(empresaId)
        .orderBy('creadoEn', descending: true)
        .limit(20)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final m = Map<String, dynamic>.from(d.data());
              m['_id'] = d.id;
              return m;
            }).toList());
  }

  static Stream<List<Map<String, dynamic>>> streamPagosPendientes(
    String empresaId,
  ) {
    return streamPagos(empresaId).map(
      (items) => items
          .where(
            (p) =>
                (p['estado'] ?? '').toString().trim().toLowerCase() ==
                'pendiente_validacion',
          )
          .toList(growable: false),
    );
  }

  /// Sube bauche a Storage y reporta el pago vía Cloud Function.
  static Future<String> enviarPagoConBauche({
    required String empresaId,
    required double montoRd,
    required String metodoPago,
    required Uint8List imageBytes,
    String referenciaBancaria = '',
    String nota = '',
    String? liquidacionId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw 'Sesión expirada';
    if (imageBytes.isEmpty) throw 'Elegí la foto del bauche antes de enviar.';
    if (montoRd <= 0) throw 'Indica el monto que pagaste.';

    final path =
        'comprobantes/$uid/corporativo_$empresaId/bauche_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putData(
      imageBytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final url = await ref.getDownloadURL();
    if (url.isEmpty) throw 'No se pudo obtener la URL del bauche.';

    final res = await _fn.httpsCallable('reportarPagoCorporativo').call({
      'empresaId': empresaId.trim(),
      'montoRd': montoRd,
      'metodoPago': metodoPago.trim().toLowerCase(),
      'comprobanteUrl': url,
      if (referenciaBancaria.trim().isNotEmpty)
        'referenciaBancaria': referenciaBancaria.trim(),
      if (nota.trim().isNotEmpty) 'nota': nota.trim(),
      if (liquidacionId != null && liquidacionId.trim().isNotEmpty)
        'liquidacionId': liquidacionId.trim(),
    });

    final data = res.data;
    if (data is Map && data['pagoId'] != null) {
      return data['pagoId'].toString();
    }
    return '';
  }

  static Future<void> adminValidarPago({
    required String empresaId,
    required String pagoId,
    required bool validar,
    String notaAdmin = '',
  }) async {
    await _fn.httpsCallable('adminValidarPagoCorporativo').call({
      'empresaId': empresaId.trim(),
      'pagoId': pagoId.trim(),
      'accion': validar ? 'validar' : 'rechazar',
      if (notaAdmin.trim().isNotEmpty) 'notaAdmin': notaAdmin.trim(),
    });
  }

  static String etiquetaEstado(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'pendiente_validacion' => 'Bauche enviado · pendiente RAI',
      'validado' => 'Validado por RAI',
      'rechazado' => 'Rechazado — revisa con tu ejecutivo',
      _ => raw.isEmpty ? '—' : raw,
    };
  }

  /// Encargado: oculta un viaje del historial (no borra datos de auditoría).
  static Future<Map<String, dynamic>> ocultarViajeHistorial({
    required String empresaId,
    required String viajeId,
  }) async {
    final res = await _fn
        .httpsCallable('encargadoOcultarViajeHistorialCorporativo')
        .call({
      'empresaId': empresaId.trim(),
      'viajeId': viajeId.trim(),
    });
    final data = res.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {'ok': true};
  }

  /// Encargado reporta incidencia (feriado / imprevisto / fraude).
  /// Queda pendiente de validación RAI. Admin puede resolver en el acto.
  static Future<Map<String, dynamic>> anularViaje({
    required String empresaId,
    required String viajeId,
    String motivo = 'imprevisto_operativo',
  }) async {
    final res = await _fn.httpsCallable('encargadoAnularViajeCorporativo').call({
      'empresaId': empresaId.trim(),
      'viajeId': viajeId.trim(),
      'motivo': motivo.trim(),
    });
    final data = res.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {'ok': true};
  }

  /// Admin RAI aprueba o rechaza una incidencia del encargado.
  static Future<void> adminResolverAnulacion({
    required String empresaId,
    required String viajeId,
    required bool aprobar,
    String notaAdmin = '',
  }) async {
    await _fn.httpsCallable('adminResolverAnulacionCorporativo').call({
      'empresaId': empresaId.trim(),
      'viajeId': viajeId.trim(),
      'accion': aprobar ? 'aprobar' : 'rechazar',
      if (notaAdmin.trim().isNotEmpty) 'notaAdmin': notaAdmin.trim(),
    });
  }

  static Stream<List<Map<String, dynamic>>> streamAnulacionesPendientes(
    String empresaId,
  ) {
    return _db
        .collection('empresas_corporativas')
        .doc(empresaId.trim())
        .collection('historial')
        .orderBy('creadoEn', descending: true)
        .limit(80)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) {
                final m = Map<String, dynamic>.from(d.data());
                m['_id'] = d.id;
                m['viajeId'] = d.id;
                return m;
              })
              .where(
                (h) =>
                    (h['estado'] ?? '').toString().trim().toLowerCase() ==
                    'anulacion_pendiente',
              )
              .toList(growable: false),
        );
  }
}
