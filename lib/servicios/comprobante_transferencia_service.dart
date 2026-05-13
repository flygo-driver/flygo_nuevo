// lib/servicios/comprobante_transferencia_service.dart
//
// Servicio reusable para que el cliente suba el comprobante de
// transferencia bancaria de un viaje y lo reporte al backend.
//
// Encapsula lo que antes vivía solo en
// `viaje_en_curso_cliente.dart::_subirComprobanteTransferencia` +
// `_reportarTransferencia`, para poder invocarlo también desde
// `factura_viaje.dart` (Problema #3 del flujo de facturación).
//
// IMPORTANTE: NO duplica la lógica de Cloud Function. Sigue llamando a
// `ViajesRepo.marcarTransferenciaReportadaCliente`, que internamente invoca
// `reportarTransferenciaClienteSeguro`. Tampoco modifica reglas de Firestore
// ni cambia el contrato de Storage (`comprobantes/{uid}/{viajeId}/...`).

import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flygo_nuevo/servicios/viajes_repo.dart';

class ComprobanteTransferenciaService {
  ComprobanteTransferenciaService._();

  /// Resultado simple para que el caller pueda decidir UI sin try/catch.
  /// `ok == false` y `cancelled == true` cuando el usuario sale del picker
  /// sin elegir imagen (no es un error a mostrar).
  static const ResultadoSubidaComprobante _kResultCancelled =
      ResultadoSubidaComprobante(ok: false, cancelled: true);

  /// Abre el picker de galería, sube la imagen a Firebase Storage en la
  /// ruta `comprobantes/{uid}/{viajeId}/transfer_<timestamp>.jpg` y reporta
  /// el comprobante al backend vía `marcarTransferenciaReportadaCliente`.
  ///
  /// - Devuelve `_ResultadoSubida` con `ok=true` cuando todo terminó bien.
  /// - Si el usuario cancela el picker, devuelve `_kResultCancelled` (ok=false,
  ///   cancelled=true) y el caller puede ignorarlo silenciosamente.
  /// - Si hay error técnico, devuelve `ok=false` con `mensaje` para mostrar.
  ///
  /// Esta función NO muestra SnackBars por sí misma para que cada pantalla
  /// (viaje en curso, factura, etc.) decida cómo notificar al usuario.
  static Future<ResultadoSubidaComprobante> subirYReportar({
    required String viajeId,
  }) async {
    final User? u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      return const ResultadoSubidaComprobante(
        ok: false,
        mensaje: 'Debes iniciar sesión para subir el comprobante.',
      );
    }
    if (viajeId.isEmpty) {
      return const ResultadoSubidaComprobante(
        ok: false,
        mensaje: 'Identificador de viaje inválido.',
      );
    }

    try {
      final XFile? file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (file == null) {
        return _kResultCancelled;
      }

      final Uint8List bytes = await file.readAsBytes();
      final String path =
          'comprobantes/${u.uid}/$viajeId/transfer_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Reference ref = FirebaseStorage.instance.ref(path);
      await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final String url = await ref.getDownloadURL();
      if (url.isEmpty) {
        return const ResultadoSubidaComprobante(
          ok: false,
          mensaje: 'No se pudo obtener la URL del comprobante.',
        );
      }

      await ViajesRepo.marcarTransferenciaReportadaCliente(
        viajeId: viajeId,
        comprobanteUrl: url,
      );

      return ResultadoSubidaComprobante(ok: true, comprobanteUrl: url);
    } on FirebaseException catch (e) {
      return ResultadoSubidaComprobante(
        ok: false,
        mensaje: 'Error (${e.code}): ${e.message ?? 'No se pudo subir.'}',
      );
    } catch (e) {
      return ResultadoSubidaComprobante(
        ok: false,
        mensaje: 'No se pudo subir el comprobante: $e',
      );
    }
  }

  /// Helper opcional que muestra SnackBars estándar sobre el resultado.
  /// Útil para callers que solo quieren la UX por defecto. No bloquea el
  /// flujo si el `BuildContext` ya no está montado.
  static void mostrarFeedback(
    BuildContext context,
    ResultadoSubidaComprobante r,
  ) {
    if (!context.mounted) return;
    if (r.cancelled) return;
    if (r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Comprobante enviado. Pendiente de validación por el taxista o admin.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }
    final String msg = (r.mensaje ?? 'No se pudo subir el comprobante.');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
      ),
    );
  }
}

/// Resultado simple e inmutable de [ComprobanteTransferenciaService.subirYReportar].
class ResultadoSubidaComprobante {
  const ResultadoSubidaComprobante({
    required this.ok,
    this.cancelled = false,
    this.mensaje,
    this.comprobanteUrl,
  });

  final bool ok;
  final bool cancelled;
  final String? mensaje;
  final String? comprobanteUrl;
}
