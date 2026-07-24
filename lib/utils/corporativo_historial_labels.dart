import 'package:flutter/material.dart';

/// Etiquetas en español para estados de historial corporativo.
abstract final class CorporativoHistorialLabels {
  CorporativoHistorialLabels._();

  static String etiqueta(String estadoRaw) {
    final e = estadoRaw.trim().toLowerCase();
    return switch (e) {
      'completado' => 'Completado · cobrado',
      'lanzado' => 'Enviado al chofer',
      'publicado_auto' => 'Publicado · pendiente código',
      'fallo_publicacion' => 'Falló publicación',
      'fallo_asignacion' => 'Chofer no asignado',
      'no_ejecutado' => 'No ejecutado · no cobra',
      'anulacion_pendiente' => 'Incidencia · espera RAI',
      'cancelado' => 'Cancelado · no cobra',
      'en_curso' => 'En curso',
      'aceptado' => 'Aceptado',
      '' => 'Pendiente',
      _ => estadoRaw,
    };
  }

  /// Tipo de incidencia reportada por el encargado.
  static String etiquetaIncidencia(String motivoRaw) {
    return switch (motivoRaw.trim().toLowerCase()) {
      'feriado_no_laborable' => 'Feriado / no laborable',
      'imprevisto_operativo' => 'Imprevisto operativo',
      'fraude_chofer_sin_ruta' => 'Chofer marcó sin hacer la ruta',
      'no_laboro_feriado_o_fraude' => 'No laboró / fraude',
      'no_laboro_feriado' => 'No laboró / feriado',
      '' => '',
      _ => motivoRaw,
    };
  }

  static Color colorEstado(String estadoRaw, {required Color success, required Color accent, required Color warning, required Color error}) {
    final e = estadoRaw.trim().toLowerCase();
    if (e == 'completado') return success;
    if (e == 'anulacion_pendiente') return warning;
    if (e == 'no_ejecutado' || e == 'cancelado') return warning;
    if (e == 'fallo_publicacion' || e == 'fallo_asignacion') {
      return error;
    }
    if (e == 'lanzado' || e == 'publicado_auto' || e == 'aceptado' || e == 'en_curso') {
      return accent;
    }
    return warning;
  }
}
