import 'package:flutter/material.dart';

/// Ciclo de facturación corporativa + forma de pago preferida a RAI.
abstract final class CorporativoCicloFacturacion {
  CorporativoCicloFacturacion._();

  static const int diasMin = 1;
  static const int diasMax = 90;
  static const int defaultDias = 15;

  /// Presets comerciales (días).
  static const List<({int dias, String label})> presets = [
    (dias: 1, label: 'Diario'),
    (dias: 7, label: 'Semanal'),
    (dias: 15, label: 'Quincenal'),
    (dias: 30, label: 'Mensual'),
  ];

  /// Métodos con los que la empresa puede pagar a RAI (preferencia).
  static const List<({String id, String label})> formasPago = [
    (id: 'transferencia', label: 'Transferencia'),
    (id: 'deposito', label: 'Depósito'),
    (id: 'cheque', label: 'Cheque'),
    (id: 'efectivo', label: 'Efectivo'),
    (id: 'otro', label: 'Otro'),
  ];

  /// Color distintivo solo para botones de selección de forma de pago.
  static Color colorFormaPago(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'transferencia':
        return const Color(0xFFE67E22); // naranja
      case 'deposito':
        return const Color(0xFF0D9488); // teal
      case 'cheque':
        return const Color(0xFF7C3AED); // morado
      case 'efectivo':
        return const Color(0xFF2563EB); // azul
      case 'otro':
        return const Color(0xFF64748B); // gris
      default:
        return const Color(0xFF94A3B8);
    }
  }

  static Color colorFormaPagoFondo(String? raw) =>
      colorFormaPago(raw).withValues(alpha: 0.18);

  static int normalizarDias(int? dias) {
    final d = dias ?? defaultDias;
    if (d < diasMin) return defaultDias;
    if (d > diasMax) return diasMax;
    return d;
  }

  static bool esPreset(int dias) =>
      presets.any((p) => p.dias == normalizarDias(dias));

  static String etiqueta(int dias) {
    final d = normalizarDias(dias);
    for (final p in presets) {
      if (p.dias == d) return p.label;
    }
    if (d == 1) return 'Diario';
    return 'Cada $d días';
  }

  static DateTime finPeriodoDiasCobrables({
    required DateTime inicio,
    required int cicloDias,
    Set<String> diasPausa = const {},
    List<int> diasSemana = const [1, 2, 3, 4, 5],
  }) {
    final objetivo = normalizarDias(cicloDias);
    var contados = 0;
    var cursor = DateTime(inicio.year, inicio.month, inicio.day);
    final maxScan = objetivo * 4;

    for (var i = 0; i < maxScan; i++) {
      if (_esDiaCobrable(cursor, diasSemana, diasPausa)) {
        contados++;
        if (contados >= objetivo) {
          return DateTime(cursor.year, cursor.month, cursor.day, 23, 59, 59);
        }
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return inicio.add(Duration(days: objetivo));
  }

  static bool _esDiaCobrable(
    DateTime fecha,
    List<int> diasSemana,
    Set<String> diasPausa,
  ) {
    final key = claveFechaCalendario(fecha);
    if (diasPausa.contains(key)) return false;
    final iso = fecha.weekday;
    return diasSemana.contains(iso);
  }

  static String descripcionCicloCobrable(int dias) {
    final d = normalizarDias(dias);
    return '${descripcion(d)} · cuenta lun–vie sin feriados de pausa';
  }

  static String descripcion(int dias) {
    final d = normalizarDias(dias);
    return '${etiqueta(d)} ($d días)';
  }

  static String claveFechaCalendario(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? parseFechaCalendario(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    final p = DateTime.tryParse(s);
    if (p == null) return null;
    return DateTime(p.year, p.month, p.day);
  }

  static String etiquetaFormaPago(String? raw) {
    final id = (raw ?? '').trim().toLowerCase();
    if (id.isEmpty) return 'No definida';
    for (final f in formasPago) {
      if (f.id == id) return f.label;
    }
    return id;
  }

  static bool formaPagoValida(String? raw) {
    final id = (raw ?? '').trim().toLowerCase();
    if (id.isEmpty) return true;
    return formasPago.any((f) => f.id == id);
  }
}
