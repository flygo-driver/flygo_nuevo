import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../modelo/recargo_condiciones_cotizacion.dart';
import 'directions_service.dart';

/// Recargos urbanos por condiciones al cotizar (precio fijado, no sube en viaje).
abstract final class RecargoCondicionesService {
  RecargoCondicionesService._();

  static const Duration _offsetRd = Duration(hours: -4);

  /// Mañana 7:00–8:59 y tarde 17:00–19:59 (Gran Santo Domingo).
  static const int _picoMananaInicioMin = 7 * 60;
  static const int _picoMananaFinMin = 9 * 60;
  static const int _picoTardeInicioMin = 17 * 60;
  static const int _picoTardeFinMin = 20 * 60;

  static const double pctHoraPicoDefault = 10.0;
  static const double pctLluviaDefault = 8.0;

  /// Recargo tapón progresivo según ratio Google (duration_in_traffic / duration).
  static const double pctMaximoTotal = 35.0;

  /// Ratio mínimo para considerar tapón (10% más lento que libre).
  static const double ratioTaponMinimo = 1.10;

  /// % tapón según severidad del tráfico en vivo (Google Directions).
  static double pctTaponDesdeRatio(double ratio) {
    if (!ratio.isFinite || ratio < ratioTaponMinimo) return 0;
    if (ratio < 1.22) return 8; // leve
    if (ratio < 1.38) return 14; // moderado
    if (ratio < 1.55) return 20; // fuerte (ej. 27 de Febrero)
    if (ratio < 1.75) return 26; // muy fuerte
    return 30; // extremo
  }

  static bool hayTapon({
    required int durationSeconds,
    int? durationInTrafficSeconds,
  }) {
    if (durationSeconds <= 0 || durationInTrafficSeconds == null) return false;
    if (durationInTrafficSeconds <= durationSeconds) return false;
    return durationInTrafficSeconds / durationSeconds >= ratioTaponMinimo;
  }

  static DateTime ahoraRepublicaDominicana() =>
      DateTime.now().toUtc().add(_offsetRd);

  static bool esHoraPico(DateTime momentoLocalRd) {
    final mins = momentoLocalRd.hour * 60 + momentoLocalRd.minute;
    final enManana =
        mins >= _picoMananaInicioMin && mins < _picoMananaFinMin;
    final enTarde =
        mins >= _picoTardeInicioMin && mins < _picoTardeFinMin;
    return enManana || enTarde;
  }

  static bool esCodigoLluvia(int? code) {
    if (code == null) return false;
    if (code >= 51 && code <= 67) return true;
    if (code >= 80 && code <= 82) return true;
    if (code >= 95 && code <= 99) return true;
    return false;
  }

  static double ratioTrafico({
    required int durationSeconds,
    int? durationInTrafficSeconds,
  }) {
    if (durationSeconds <= 0 || durationInTrafficSeconds == null) return 1.0;
    return durationInTrafficSeconds / durationSeconds;
  }

  /// Consulta clima actual (Open-Meteo, sin API key).
  static Future<({bool lluvia, double precipitacionMm})> detectarLluvia({
    required double lat,
    required double lon,
  }) async {
    if (!lat.isFinite || !lon.isFinite) {
      return (lluvia: false, precipitacionMm: 0.0);
    }
    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', <String, String>{
        'latitude': lat.toStringAsFixed(5),
        'longitude': lon.toStringAsFixed(5),
        'current': 'precipitation,rain,weather_code',
        'timezone': 'America/Santo_Domingo',
      });
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) {
        return (lluvia: false, precipitacionMm: 0.0);
      }
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final current = data['current'];
      if (current is! Map) return (lluvia: false, precipitacionMm: 0.0);
      final precip = (current['precipitation'] as num?)?.toDouble() ?? 0.0;
      final rain = (current['rain'] as num?)?.toDouble() ?? 0.0;
      final code = (current['weather_code'] as num?)?.toInt();
      final lluvia =
          precip > 0.05 || rain > 0.05 || esCodigoLluvia(code);
      return (lluvia: lluvia, precipitacionMm: precip > rain ? precip : rain);
    } catch (e) {
      if (kDebugMode) debugPrint('RecargoCondiciones lluvia: $e');
      return (lluvia: false, precipitacionMm: 0.0);
    }
  }

  static Future<RecargoCondicionesCotizacion> resolver({
    required double latOrigen,
    required double lonOrigen,
    DirectionsResult? directions,
    DateTime? momentoHoraPico,
    DateTime? momentoClima,
    bool incluirRecargoTapon = true,
    /// false en tarifa urbana por minutos (el tapón ya está en el tiempo).
    bool incluirRecargoHoraPico = true,
  }) async {
    final DateTime picoRd =
        (momentoHoraPico ?? ahoraRepublicaDominicana()).toUtc().add(_offsetRd);
    final bool horaPico = esHoraPico(picoRd);

    final clima = await detectarLluvia(lat: latOrigen, lon: lonOrigen);

    final int dur = directions?.seconds ?? 0;
    final int? durTraf = directions?.secondsInTraffic;
    final bool tapon = hayTapon(
      durationSeconds: dur,
      durationInTrafficSeconds: durTraf,
    );
    final double? ratio =
        dur > 0 ? ratioTrafico(durationSeconds: dur, durationInTrafficSeconds: durTraf) : null;
    final double pctTaponCalc = incluirRecargoTapon && ratio != null
        ? pctTaponDesdeRatio(ratio)
        : 0;
    final int? minLibres = dur > 0 ? (dur / 60).ceil() : null;
    final int? minTraf =
        durTraf != null && durTraf > 0 ? (durTraf / 60).ceil() : minLibres;

    return RecargoCondicionesCotizacion(
      horaPico: horaPico,
      lluvia: clima.lluvia,
      tapon: pctTaponCalc > 0,
      pctHoraPico:
          horaPico && incluirRecargoHoraPico ? pctHoraPicoDefault : 0,
      pctLluvia: clima.lluvia ? pctLluviaDefault : 0,
      pctTapon: pctTaponCalc,
      pctTotal: 0,
      recargoRd: 0,
      precioAntesRecargoRd: 0,
      precioDespuesRecargoRd: 0,
      ratioTrafico: ratio,
      precipitacionMm: clima.precipitacionMm,
      cotizadoEn: momentoClima ?? DateTime.now(),
      minutosSinTrafico: minLibres,
      minutosConTrafico: minTraf,
    );
  }

  static double pctTotalDesdeFlags({
    double pctHoraPico = 0,
    double pctLluvia = 0,
    required double pctTapon,
  }) {
    final pct = pctHoraPico + pctLluvia + pctTapon;
    return pct.clamp(0, pctMaximoTotal);
  }

  static RecargoCondicionesCotizacion aplicar({
    required RecargoCondicionesCotizacion base,
    required double precioRd,
  }) {
    if (!precioRd.isFinite || precioRd <= 0) return base;

    final pct = pctTotalDesdeFlags(
      pctHoraPico: base.pctHoraPico,
      pctLluvia: base.pctLluvia,
      pctTapon: base.pctTapon,
    );
    if (pct <= 0) {
      return RecargoCondicionesCotizacion(
        horaPico: base.horaPico,
        lluvia: base.lluvia,
        tapon: base.tapon,
        pctHoraPico: base.pctHoraPico,
        pctLluvia: base.pctLluvia,
        pctTapon: base.pctTapon,
        pctTotal: 0,
        recargoRd: 0,
        precioAntesRecargoRd: precioRd,
        precioDespuesRecargoRd: precioRd,
        ratioTrafico: base.ratioTrafico,
        precipitacionMm: base.precipitacionMm,
        cotizadoEn: base.cotizadoEn,
      );
    }

    final recargo = precioRd * (pct / 100.0);
    final despues = precioRd + recargo;

    return RecargoCondicionesCotizacion(
      horaPico: base.horaPico,
      lluvia: base.lluvia,
      tapon: base.tapon,
      pctHoraPico: base.pctHoraPico,
      pctLluvia: base.pctLluvia,
      pctTapon: base.pctTapon,
      pctTotal: pct,
      recargoRd: double.parse(recargo.toStringAsFixed(2)),
      precioAntesRecargoRd: double.parse(precioRd.toStringAsFixed(2)),
      precioDespuesRecargoRd: double.parse(despues.toStringAsFixed(2)),
      ratioTrafico: base.ratioTrafico,
      precipitacionMm: base.precipitacionMm,
      cotizadoEn: base.cotizadoEn,
    );
  }
}
