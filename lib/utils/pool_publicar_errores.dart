import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/pool_gira_abuso.dart';

/// Mensajes claros al publicar giras (sin errores crudos de Firestore/Functions).
abstract final class PoolPublicarErrores {
  PoolPublicarErrores._();

  static String traducir(Object error) {
    if (error is PoolGiraAbusoBloqueo) return error.mensajeUsuario;

    if (error is FirebaseFunctionsException) {
      final msg = (error.message ?? '').trim();
      if (msg.isNotEmpty) return msg;
      return _codigoFunctions(error.code);
    }

    if (error is FirebaseException) {
      final msg = (error.message ?? '').trim();
      if (msg.isNotEmpty && !_pareceTecnico(msg)) return msg;
      return _codigoFirebase(error.code);
    }

    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    if (raw.isEmpty) return 'No se pudo publicar la salida. Intenta de nuevo.';
    if (_pareceTecnico(raw)) {
      return 'No se pudo publicar la salida. Revisa tu conexión e intenta de nuevo.';
    }
    return raw;
  }

  static String traducirSubida(Object error) {
    final s = error.toString().toLowerCase();
    if (s.contains('network') ||
        s.contains('unavailable') ||
        s.contains('connection') ||
        s.contains('socket')) {
      return 'Sin conexión a internet. Conéctate y vuelve a subir la foto.';
    }
    if (s.contains('unauthorized') || s.contains('permission')) {
      return 'No tienes permiso para subir archivos. Cierra sesión y vuelve a entrar.';
    }
    if (s.contains('quota') || s.contains('storage')) {
      return 'No se pudo guardar la imagen en el servidor. Intenta con otra foto.';
    }
    return 'No se pudo subir la imagen. Intenta de nuevo.';
  }

  static bool _pareceTecnico(String s) {
    final l = s.toLowerCase();
    return l.contains('firebase') ||
        l.contains('firestore') ||
        l.contains('cloud_functions') ||
        l.contains('permission-denied') ||
        l.contains('internal') ||
        l.contains('grpc') ||
        l.contains('platformexception');
  }

  static String _codigoFunctions(String code) {
    switch (code) {
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Sin conexión estable. Revisa tu internet e intenta de nuevo.';
      case 'unauthenticated':
        return 'Tu sesión expiró. Cierra la app, inicia sesión y vuelve a publicar.';
      case 'permission-denied':
        return 'No tienes permiso para publicar. Completa tu registro de organizador.';
      case 'failed-precondition':
        return 'Faltan datos o hay un bloqueo en tu cuenta. Revisa el formulario.';
      case 'invalid-argument':
        return 'Hay datos incompletos o incorrectos. Revisa todos los pasos.';
      case 'resource-exhausted':
        return 'Demasiados intentos. Espera un momento e intenta de nuevo.';
      default:
        return 'No se pudo publicar la salida ($code). Intenta de nuevo.';
    }
  }

  static String _codigoFirebase(String code) {
    switch (code) {
      case 'unavailable':
        return 'Sin conexión a internet. Conéctate y vuelve a intentar.';
      case 'permission-denied':
        return 'No tienes permiso para esta acción. Verifica tu sesión.';
      default:
        return 'Error de conexión ($code). Intenta de nuevo.';
    }
  }

  static Future<void> mostrarSinInternet(BuildContext context) {
    return mostrarDialogo(
      context,
      titulo: 'Sin internet',
      mensaje:
          'Necesitas conexión para publicar la gira y subir fotos.\n\n'
          'Activa datos móviles o Wi‑Fi e intenta de nuevo.',
      icono: Icons.wifi_off_rounded,
      color: const Color(0xFFDC6803),
    );
  }

  static Future<void> mostrarFaltaDato(
    BuildContext context, {
    required String mensaje,
    String? paso,
  }) {
    return mostrarDialogo(
      context,
      titulo: 'Falta completar',
      mensaje: paso != null ? '$mensaje\n\nPaso: $paso' : mensaje,
      icono: Icons.edit_note_rounded,
      color: const Color(0xFF0D9488),
    );
  }

  static Future<void> mostrarErrorPublicar(
    BuildContext context,
    Object error,
  ) {
    return mostrarDialogo(
      context,
      titulo: 'No se pudo publicar',
      mensaje: traducir(error),
      icono: Icons.error_outline_rounded,
      color: Colors.red.shade700,
    );
  }

  static Future<void> mostrarDialogo(
    BuildContext context, {
    required String titulo,
    required String mensaje,
    IconData icono = Icons.info_outline_rounded,
    Color color = const Color(0xFF0D9488),
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(icono, color: color, size: 32),
        title: Text(titulo, textAlign: TextAlign.center),
        content: Text(
          mensaje,
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.45),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
            ),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
}
