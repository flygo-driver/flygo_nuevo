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

import 'package:flygo_nuevo/servicios/bola_pueblo_repo.dart';
import 'package:flygo_nuevo/servicios/pool_repo.dart';
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

  /// Bauche/recibo de transferencia para reserva de asiento en gira por cupos.
  ///
  /// Flujo recomendado en UI: [seleccionarImagenComprobante] → preview →
  /// [enviarComprobantePoolReserva].
  static Future<Uint8List?> seleccionarImagenComprobante(
    BuildContext context,
  ) async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto del bauche'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de galería'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;

    try {
      final XFile? file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
      );
      if (file == null) return null;
      return file.readAsBytes();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo elegir la imagen: $e')),
        );
      }
      return null;
    }
  }

  /// Sube bytes ya elegidos y reporta al backend (sin abrir el picker).
  static Future<ResultadoSubidaComprobante> enviarComprobantePoolReserva({
    required String poolId,
    required String reservaId,
    required Uint8List imageBytes,
  }) async {
    final User? u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      return const ResultadoSubidaComprobante(
        ok: false,
        mensaje: 'Debes iniciar sesión para enviar el bauche.',
      );
    }
    if (poolId.isEmpty || reservaId.isEmpty) {
      return const ResultadoSubidaComprobante(
        ok: false,
        mensaje: 'Reserva inválida.',
      );
    }
    if (imageBytes.isEmpty) {
      return const ResultadoSubidaComprobante(
        ok: false,
        mensaje: 'Elegí una foto del bauche antes de enviar.',
      );
    }

    try {
      final String path =
          'comprobantes/${u.uid}/$reservaId/pool_${poolId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Reference ref = FirebaseStorage.instance.ref(path);
      await ref.putData(
        imageBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final String url = await ref.getDownloadURL();
      if (url.isEmpty) {
        return const ResultadoSubidaComprobante(
          ok: false,
          mensaje: 'No se pudo obtener la URL del comprobante.',
        );
      }

      await PoolRepo.reportarComprobanteReservaSeguro(
        poolId: poolId,
        reservaId: reservaId,
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
        mensaje: 'No se pudo enviar el bauche: $e',
      );
    }
  }

  /// Atajo one-shot (picker + envío). Preferir el flujo en dos pasos en giras.
  static Future<ResultadoSubidaComprobante> subirYReportarPoolReserva({
    required String poolId,
    required String reservaId,
    ImageSource source = ImageSource.camera,
  }) async {
    final User? u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      return const ResultadoSubidaComprobante(
        ok: false,
        mensaje: 'Debes iniciar sesión para subir el comprobante.',
      );
    }
    if (poolId.isEmpty || reservaId.isEmpty) {
      return const ResultadoSubidaComprobante(
        ok: false,
        mensaje: 'Reserva inválida.',
      );
    }

    try {
      final XFile? file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
      );
      if (file == null) {
        return _kResultCancelled;
      }

      final Uint8List bytes = await file.readAsBytes();
      return enviarComprobantePoolReserva(
        poolId: poolId,
        reservaId: reservaId,
        imageBytes: bytes,
      );
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

  static void mostrarFeedbackPoolReserva(
    BuildContext context,
    ResultadoSubidaComprobante r,
  ) {
    if (!context.mounted) return;
    if (r.cancelled) return;
    if (r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Recibo enviado. RAI revisará tu pago y confirmará tu asiento.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }
    mostrarFeedback(context, r);
  }

  /// Igual que [subirYReportar] pero para Bola Ahorro (`bolas_pueblo/{id}`).
  static Future<ResultadoSubidaComprobante> subirYReportarBola({
    required String bolaId,
  }) async {
    final User? u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      return const ResultadoSubidaComprobante(
        ok: false,
        mensaje: 'Debes iniciar sesión para subir el comprobante.',
      );
    }
    if (bolaId.isEmpty) {
      return const ResultadoSubidaComprobante(
        ok: false,
        mensaje: 'Identificador de Bola Ahorro inválido.',
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
          'comprobantes/${u.uid}/bola_$bolaId/transfer_${DateTime.now().millisecondsSinceEpoch}.jpg';
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

      await BolaPuebloRepo.reportarTransferenciaCliente(
        bolaId: bolaId,
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
