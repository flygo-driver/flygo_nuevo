// lib/utils/negocio_aliado_viaje_doc.dart
//
// Campos de viaje referido por QR negocio aliado (lectura taxista/cliente).

import 'package:flygo_nuevo/servicios/negocio_aliado_config.dart';

abstract final class NegocioAliadoViajeDoc {
  NegocioAliadoViajeDoc._();

  static String codigo(Map<String, dynamic>? data) {
    return (data?['negocioAliadoCodigo'] ?? '').toString().trim().toUpperCase();
  }

  static bool esReferidoQr(Map<String, dynamic>? data) => codigo(data).isNotEmpty;

  static bool esViajeGratisPromo(Map<String, dynamic>? data) {
    return data?['negocioAliadoPromoGratis'] == true;
  }

  static bool esLocalEnPueblo(Map<String, dynamic>? data) {
    return data?['negocioAliadoViajeLocalPueblo'] == true;
  }

  static String ciudadPueblo(Map<String, dynamic>? data) {
    return (data?['negocioAliadoCiudadPueblo'] ?? '').toString().trim();
  }

  static String nombreNegocio(Map<String, dynamic>? data) {
    return (data?['negocioAliadoNombre'] ?? '').toString().trim();
  }

  static int contadorAlCrear(Map<String, dynamic>? data) {
    final dynamic raw = data?['negocioAliadoPromoContadorAlCrear'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw') ?? 0;
  }

  static double precioNominalRd(Map<String, dynamic>? data) {
    final dynamic cents = data?['precioNominalCents'];
    if (cents is int && cents > 0) return cents / 100.0;
    if (cents is num && cents > 0) return cents.toDouble() / 100.0;
    final dynamic p = data?['precio'];
    if (p is num && p.isFinite) return p.toDouble();
    return 0;
  }

  static bool eraElegibleGratisAlCrear(Map<String, dynamic>? data) {
    if (!esReferidoQr(data)) return false;
    final int m = NegocioAliadoConfig.promoViajesM;
    return contadorAlCrear(data) >= m;
  }

  /// Tenía 5+ viajes pero origen/destino fuera del pueblo → cobrar completo.
  static bool esInterPuebloConPromoPendiente(Map<String, dynamic>? data) {
    return eraElegibleGratisAlCrear(data) &&
        !esViajeGratisPromo(data) &&
        esReferidoQr(data);
  }
}
