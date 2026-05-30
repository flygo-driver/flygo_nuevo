/// Lectura consistente del total en RD$ desde documentos Firestore de viaje/bola.
library;

double _parseRd(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  final String s = v.toString().trim().replaceAll(',', '.');
  return double.tryParse(s) ?? 0;
}

/// Prioriza `precio_cents` (cierre CF), luego campos legados de cotización/cierre.
double totalRdDesdeDocViaje(Map<String, dynamic> data) {
  final dynamic pc = data['precio_cents'];
  if (pc is int && pc > 0) return pc / 100.0;
  if (pc is num && pc > 0) return pc.toDouble() / 100.0;

  for (final dynamic key in <dynamic>[
    data['precioFinal'],
    data['precio'],
    data['total'],
    data['montoAcordadoRd'],
  ]) {
    final double v = _parseRd(key);
    if (v > 0.009) return v;
  }
  return 0;
}

bool viajeDocCompletado(Map<String, dynamic> data) {
  if (data['completado'] == true) return true;
  return (data['estado'] ?? '').toString().trim().toLowerCase() ==
      'completado';
}

String etiquetaTipoServicioFactura(Map<String, dynamic> data) {
  final String cat = (data['categoria'] ?? '').toString().trim().toLowerCase();
  if (cat == 'multi') return 'Multiparada';

  final String ts = (data['tipoServicio'] ?? '').toString().trim().toLowerCase();
  switch (ts) {
    case 'motor':
      return 'Motor RAI';
    case 'turismo':
      return 'Turismo';
    case 'bola_ahorro':
      return 'Bola Ahorro';
    case 'normal':
      return 'Normal';
    case 'programado':
      return 'Programado';
    default:
      if (ts.isNotEmpty) {
        return ts[0].toUpperCase() + ts.substring(1);
      }
  }

  final bool esAhora = data['esAhora'] == true;
  final bool esProgramado = data['esProgramado'] == true ||
      (data['programado'] == true) ||
      ts.contains('program');
  if (esProgramado) return 'Programado';
  if (esAhora) return 'Viaje ahora';
  return '';
}
