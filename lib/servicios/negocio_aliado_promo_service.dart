// lib/servicios/negocio_aliado_promo_service.dart
//
// Promo negocio aliado: 5 viajes pagados + 6.º gratis (tope RD$600).

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/servicios/negocio_aliado_config.dart';
import 'package:flygo_nuevo/servicios/negocio_aliado_geo.dart';
import 'package:flygo_nuevo/utils/negocio_aliado_cliente_promo.dart';

class NegocioAliadoPromoEval {
  const NegocioAliadoPromoEval({
    required this.activa,
    required this.codigo,
    required this.nombre,
    required this.contador,
    required this.m,
    required this.k,
    required this.esViajeGratis,
    required this.viajeLocalEnPueblo,
    required this.ciudadNegocio,
    required this.precioNominalRd,
    required this.precioClienteRd,
    required this.descuentoRd,
  });

  final bool activa;
  final String codigo;
  final String nombre;
  final int contador;
  final int m;
  final int k;
  final bool esViajeGratis;
  /// Si cumple 6.º viaje pero origen/destino no están en el pueblo del negocio.
  final bool viajeLocalEnPueblo;
  final String ciudadNegocio;
  final double precioNominalRd;
  final double precioClienteRd;
  final double descuentoRd;

  int get precioNominalCents => (precioNominalRd * 100).round();
  int get precioClienteCents => (precioClienteRd * 100).round();

  Map<String, dynamic> toTripPayload() {
    return <String, dynamic>{
      'negocioAliadoCodigo': codigo,
      if (nombre.isNotEmpty) 'negocioAliadoNombre': nombre,
      'negocioAliadoPromoGratis': esViajeGratis,
      'negocioAliadoViajeLocalPueblo': viajeLocalEnPueblo,
      'negocioAliadoDescuentoRd': double.parse(descuentoRd.toStringAsFixed(2)),
      if (ciudadNegocio.isNotEmpty) 'negocioAliadoCiudadPueblo': ciudadNegocio,
      'precioNominalCents': precioNominalCents,
      'negocioAliadoPromoContadorAlCrear': contador,
      'comisionPorcentaje': NegocioAliadoConfig.pctComisionTaxistaReferido,
      'negocioAliadoExigeComision15': true,
      'negocioAliadoPctComisionNegocio':
          NegocioAliadoConfig.pctComisionNegocio,
    };
  }
}

abstract final class NegocioAliadoPromoService {
  NegocioAliadoPromoService._();

  static NegocioAliadoPromoEval? evaluar({
    required Map<String, dynamic>? usuario,
    required double precioNominalRd,
    String origen = '',
    String destino = '',
    String origenGeoExtra = '',
    String destinoGeoExtra = '',
  }) {
    if (usuario == null || precioNominalRd <= 0 || !precioNominalRd.isFinite) {
      return null;
    }
    if (!NegocioAliadoClientePromo.tienePromoQrRegistrada(usuario)) {
      return null;
    }

    final vence = _leerFecha(usuario['negocioPromoVenceAt']);
    if (vence != null && DateTime.now().isAfter(vence)) return null;

    final m = _int(usuario['negocioPromoMxKM'], NegocioAliadoConfig.promoViajesM);
    final k = _int(usuario['negocioPromoMxKK'], NegocioAliadoConfig.promoViajesK);
    final contador = _int(usuario['negocioPromoContador'], 0).clamp(0, 9999);
    final codigo =
        (usuario['negocioReferidoCodigo'] ?? '').toString().trim().toUpperCase();
    final nombre = (usuario['negocioReferidoNombre'] ?? '').toString().trim();
    final ciudadNegocio =
        (usuario['negocioReferidoCiudad'] ?? '').toString().trim();

    final elegibleGratis = contador >= m && k > 0;
    final localEnPueblo = NegocioAliadoGeo.viajeEsLocalEnPuebloNegocio(
      ciudadNegocio: ciudadNegocio,
      origen: origen,
      destino: destino,
      origenGeoExtra: origenGeoExtra,
      destinoGeoExtra: destinoGeoExtra,
    );
    final esGratis = elegibleGratis && localEnPueblo;
    final descuento = esGratis
        ? precioNominalRd.clamp(0.0, NegocioAliadoConfig.topeViajeGratisRd)
        : 0.0;
    final precioCliente =
        double.parse((precioNominalRd - descuento).clamp(0.0, precioNominalRd).toStringAsFixed(2));

    return NegocioAliadoPromoEval(
      activa: true,
      codigo: codigo,
      nombre: nombre,
      contador: contador,
      m: m,
      k: k,
      esViajeGratis: esGratis,
      viajeLocalEnPueblo: localEnPueblo,
      ciudadNegocio: ciudadNegocio,
      precioNominalRd: precioNominalRd,
      precioClienteRd: precioCliente,
      descuentoRd: descuento,
    );
  }

  static Future<NegocioAliadoPromoEval?> evaluarConUbicacion({
    required Map<String, dynamic>? usuario,
    required double precioNominalRd,
    String origen = '',
    String destino = '',
    double? latOrigen,
    double? lonOrigen,
    double? latDestino,
    double? lonDestino,
  }) async {
    var origenGeoExtra = '';
    var destinoGeoExtra = '';
    if (latOrigen != null &&
        lonOrigen != null &&
        latOrigen.isFinite &&
        lonOrigen.isFinite) {
      origenGeoExtra =
          await NegocioAliadoGeo.geoTextoDesdeCoordenadas(latOrigen, lonOrigen);
    }
    if (latDestino != null &&
        lonDestino != null &&
        latDestino.isFinite &&
        lonDestino.isFinite) {
      destinoGeoExtra = await NegocioAliadoGeo.geoTextoDesdeCoordenadas(
        latDestino,
        lonDestino,
      );
    }
    return evaluar(
      usuario: usuario,
      precioNominalRd: precioNominalRd,
      origen: origen,
      destino: destino,
      origenGeoExtra: origenGeoExtra,
      destinoGeoExtra: destinoGeoExtra,
    );
  }

  /// Aplica promo al precio del viaje y devuelve payload para Firestore.
  static ({double precioCliente, Map<String, dynamic> campos})? aplicarAlCrearViaje({
    required Map<String, dynamic>? usuario,
    required double precioNominalRd,
    String origen = '',
    String destino = '',
    String origenGeoExtra = '',
    String destinoGeoExtra = '',
  }) {
    final eval = evaluar(
      usuario: usuario,
      precioNominalRd: precioNominalRd,
      origen: origen,
      destino: destino,
      origenGeoExtra: origenGeoExtra,
      destinoGeoExtra: destinoGeoExtra,
    );
    if (eval == null || !eval.activa) return null;
    return (
      precioCliente: eval.precioClienteRd,
      campos: eval.toTripPayload(),
    );
  }

  static Future<({double precioCliente, Map<String, dynamic> campos})?>
      aplicarAlCrearViajeConUbicacion({
    required Map<String, dynamic>? usuario,
    required double precioNominalRd,
    String origen = '',
    String destino = '',
    double? latOrigen,
    double? lonOrigen,
    double? latDestino,
    double? lonDestino,
  }) async {
    final eval = await evaluarConUbicacion(
      usuario: usuario,
      precioNominalRd: precioNominalRd,
      origen: origen,
      destino: destino,
      latOrigen: latOrigen,
      lonOrigen: lonOrigen,
      latDestino: latDestino,
      lonDestino: lonDestino,
    );
    if (eval == null || !eval.activa) return null;
    return (
      precioCliente: eval.precioClienteRd,
      campos: eval.toTripPayload(),
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
