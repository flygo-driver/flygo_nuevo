import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/servicios/navegacion_externa_launcher.dart';
import 'package:flygo_nuevo/utils/multiparada_ruta_helper.dart';

/// Punto único para resolver origen, destino y legs multiparada antes de Waze/Maps.
abstract final class ViajeNavegacionResolver {
  ViajeNavegacionResolver._();

  static Map<String, dynamic> documento(Viaje v) =>
      MultiparadaRutaHelper.viajeDocDesdeModelo(
        waypoints: v.waypoints,
        extras: v.extras,
        latDestino: v.latDestino,
        lonDestino: v.lonDestino,
        destino: v.destino,
        latCliente: v.latCliente,
        lonCliente: v.lonCliente,
      );

  static List<({double lat, double lon, String label, bool esFinal})> legs(
    Viaje v,
  ) =>
      MultiparadaRutaHelper.legsNavegacionMultiparada(
        viajeData: documento(v),
        waypointsModel: v.waypoints,
        latDestinoModelo: v.latDestino,
        lonDestinoModelo: v.lonDestino,
        labelDestino: v.destino,
      );

  static List<({double lat, double lon, String label, bool esFinal})>
      legsDesdeMap(Map<String, dynamic> data) =>
          MultiparadaRutaHelper.legsNavegacionMultiparada(
            viajeData: data,
            waypointsModel: MultiparadaRutaHelper.waypointsDesdeDoc(data),
            latDestinoModelo: _asDouble(data['latDestino']),
            lonDestinoModelo: _asDouble(data['lonDestino']),
            labelDestino: (data['destino'] ?? '').toString(),
          );

  static ({double lat, double lon, String label})? origen(Viaje v) =>
      MultiparadaRutaHelper.origenParaNavegacion(
        viajeData: documento(v),
        latClienteModelo: v.latCliente,
        lonClienteModelo: v.lonCliente,
        labelOrigen: v.origen,
      );

  static ({double lat, double lon, String label})? destino(Viaje v) {
    final dest = MultiparadaRutaHelper.destinoFinalLegParaNavegacion(
      viajeData: documento(v),
      latDestinoModelo: v.latDestino,
      lonDestinoModelo: v.lonDestino,
      labelDestino: v.destino,
    );
    if (dest == null) return null;
    return (lat: dest.lat, lon: dest.lon, label: dest.label);
  }

  static ({double lat, double lon, String label, bool esFinal})? legEnIndice(
    Viaje v,
    int indice,
  ) {
    final List<({double lat, double lon, String label, bool esFinal})> all =
        legs(v);
    if (indice < 0 || indice >= all.length) return null;
    final leg = all[indice];
    if (!coordsValidas(leg.lat, leg.lon)) return null;
    return leg;
  }

  static bool coordsValidas(double lat, double lon) =>
      NavegacionExternaLauncher.coordsValidas(lat, lon);

  static Future<bool> abrirWaze(double lat, double lon) =>
      NavegacionExternaLauncher.abrirWazeDestino(lat, lon);

  static Future<bool> abrirWazeLeg(Viaje v, int indice) async {
    final leg = legEnIndice(v, indice);
    if (leg == null) return false;
    return abrirWaze(leg.lat, leg.lon);
  }

  static Future<bool> abrirWazeDestinoViaje(Viaje v) async {
    final d = destino(v);
    if (d == null) return false;
    return abrirWaze(d.lat, d.lon);
  }

  static Future<bool> abrirWazeOrigen(Viaje v) async {
    final o = origen(v);
    if (o == null) return false;
    return abrirWaze(o.lat, o.lon);
  }

  static double _asDouble(dynamic v) {
    if (v is num && v.isFinite) return v.toDouble();
    final double? d = double.tryParse('$v');
    return d != null && d.isFinite ? d : 0;
  }
}
