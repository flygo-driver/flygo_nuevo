// lib/utils/mensajes.dart
import 'package:flutter/material.dart';

class MensajeUtils {
  static void mostrar(BuildContext context, String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  static void mostrarError(BuildContext context, String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), backgroundColor: Colors.red),
    );
  }

  static void mostrarExito(BuildContext context, String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.green),
    );
  }

  static String traducirErrorCancelacion(Object error) {
    final s = error.toString();
    if (s.contains('permission-denied')) {
      return 'No se pudo cancelar: solo puedes cancelar durante los primeros 10 minutos y antes de que el viaje esté en curso.';
    }
    if (s.contains('not-found')) {
      return 'Este viaje ya no existe (posiblemente fue cancelado o completado).';
    }
    if (s.contains('failed-precondition')) {
      return 'No se pudo cancelar por una condición del servidor. Intenta de nuevo.';
    }
    if (s.contains('unavailable')) {
      return 'Servicio no disponible momentáneamente. Revisa tu conexión e inténtalo de nuevo.';
    }
    if (s.contains('deadline-exceeded') || s.contains('network-request-failed')) {
      return 'Conexión lenta o inestable. Vuelve a intentar la cancelación.';
    }
    return 'No se pudo cancelar por un error inesperado.';
  }
}
