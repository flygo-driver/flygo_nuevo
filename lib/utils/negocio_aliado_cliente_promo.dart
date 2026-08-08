import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/servicios/negocio_aliado_config.dart';

class NegocioAliadoClientePromoEstado {
  const NegocioAliadoClientePromoEstado({
    required this.codigo,
    required this.nombreNegocio,
    required this.ciudad,
    required this.contador,
    required this.m,
    required this.k,
    required this.venceAt,
  });

  final String codigo;
  final String nombreNegocio;
  final String ciudad;
  final int contador;
  final int m;
  final int k;
  final DateTime? venceAt;

  bool get elegibleGratis => contador >= m && k > 0;
  bool get vigente =>
      venceAt == null || DateTime.now().isBefore(venceAt!);
}

abstract final class NegocioAliadoClientePromo {
  NegocioAliadoClientePromo._();

  /// Solo clientes que se registraron con código QR (`negocioReferidoAt`).
  static bool tienePromoQrRegistrada(Map<String, dynamic>? usuario) {
    if (usuario == null) return false;
    final codigo =
        (usuario['negocioReferidoCodigo'] ?? '').toString().trim();
    if (codigo.isEmpty) return false;
    if (usuario['negocioReferidoAt'] == null) return false;
    return true;
  }

  static NegocioAliadoClientePromoEstado? estadoDesdeUsuario(
    Map<String, dynamic>? usuario,
  ) {
    if (!tienePromoQrRegistrada(usuario)) return null;

    final vence = _leerFecha(usuario!['negocioPromoVenceAt']);
    if (vence != null && DateTime.now().isAfter(vence)) return null;

    final m = _int(usuario['negocioPromoMxKM'], NegocioAliadoConfig.promoViajesM);
    final k = _int(usuario['negocioPromoMxKK'], NegocioAliadoConfig.promoViajesK);
    final contador = _int(usuario['negocioPromoContador'], 0).clamp(0, 9999);

    return NegocioAliadoClientePromoEstado(
      codigo: (usuario['negocioReferidoCodigo'] ?? '').toString().trim(),
      nombreNegocio: (usuario['negocioReferidoNombre'] ?? '').toString().trim(),
      ciudad: (usuario['negocioReferidoCiudad'] ?? '').toString().trim(),
      contador: contador,
      m: m,
      k: k,
      venceAt: vence,
    );
  }

  static DateTime? _leerFecha(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static int _int(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? fallback;
  }
}
