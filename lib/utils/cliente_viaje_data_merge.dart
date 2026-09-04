import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/cliente_viaje_estado_efectivo.dart';
import 'package:flygo_nuevo/utils/viaje_codigo_verificacion_helper.dart';

/// Fusiona el doc local del stream con un pulso de servidor cuando el servidor
/// está más adelante en el flujo (producción: miles de usuarios, redes inestables).
class ClienteViajeDataMerge {
  ClienteViajeDataMerge._();

  static bool _clienteAbordoEnMap(Map<String, dynamic> doc) {
    if (doc['clienteAbordo'] == true) return true;
    final dynamic ex = doc['extras'];
    return ex is Map && ex['clienteAbordo'] == true;
  }

  static int rankEstadoEfectivo(Map<String, dynamic> doc) =>
      rankEstado(ClienteViajeEstadoEfectivo.resolver(doc));

  static int rankEstado(String estado) {
    final String e = EstadosViaje.normalizar(estado);
    if (EstadosViaje.esCompletado(e) || EstadosViaje.esTerminal(e)) return 100;
    if (EstadosViaje.esEnCurso(e)) return 50;
    if (EstadosViaje.esAbordo(e)) return 40;
    if (EstadosViaje.esEnCaminoPickup(e)) return 30;
    if (EstadosViaje.esAceptado(e)) return 20;
    if (e == EstadosViaje.pendientePago) return 11;
    if (EstadosViaje.esPendiente(e)) return 10;
    return 0;
  }

  static bool serverEstaAdelante(
    Map<String, dynamic> stream,
    Map<String, dynamic> server,
  ) {
    final String estStream =
        EstadosViaje.normalizar((stream['estado'] ?? '').toString());
    final String estServer =
        EstadosViaje.normalizar((server['estado'] ?? '').toString());

    if (rankEstado(estServer) > rankEstado(estStream)) return true;
    if (rankEstadoEfectivo(server) > rankEstadoEfectivo(stream)) return true;

    if (server['codigoVerificado'] == true &&
        stream['codigoVerificado'] != true) {
      return true;
    }
    if (_clienteAbordoEnMap(server) && !_clienteAbordoEnMap(stream)) {
      return true;
    }
    if (server['completado'] == true && stream['completado'] != true) {
      return true;
    }

    final String pinStream = ViajeCodigoVerificacionHelper.pinDesdeViajeDoc(
      viajeData: stream,
    );
    final String pinServer = ViajeCodigoVerificacionHelper.pinDesdeViajeDoc(
      viajeData: server,
    );
    if (ViajeCodigoVerificacionHelper.pinValido(pinServer) &&
        !ViajeCodigoVerificacionHelper.pinValido(pinStream)) {
      return true;
    }

    final String tidStream =
        (stream['uidTaxista'] ?? stream['taxistaId'] ?? '').toString().trim();
    final String tidServer =
        (server['uidTaxista'] ?? server['taxistaId'] ?? '').toString().trim();
    if (tidStream.isEmpty && tidServer.isNotEmpty) return true;

    return false;
  }

  static Map<String, dynamic> merge(
    Map<String, dynamic> stream,
    Map<String, dynamic>? server,
  ) {
    if (server == null || server.isEmpty) return stream;
    if (!serverEstaAdelante(stream, server)) return stream;

    final Map<String, dynamic> out = Map<String, dynamic>.from(stream);
    for (final String key in <String>[
      'estado',
      'aceptado',
      'activo',
      'completado',
      'codigoVerificado',
      'codigoVerificadoEn',
      'codigoVerificacion',
      'clienteAbordo',
      'clienteAbordoEn',
      'pickupConfirmadoEn',
      'inicioViaje',
      'viajeIniciadoEn',
      'inicioEnRutaEn',
      'uidTaxista',
      'taxistaId',
      'nombreTaxista',
      'telefono',
      'placa',
      'finalizadoEn',
      'updatedAt',
      'actualizadoEn',
    ]) {
      if (server.containsKey(key) && server[key] != null) {
        out[key] = server[key];
      }
    }
    final dynamic exServer = server['extras'];
    if (exServer is Map) {
      final dynamic exStream = out['extras'];
      if (exStream is Map) {
        out['extras'] = <String, dynamic>{...exStream, ...exServer};
      } else {
        out['extras'] = Map<String, dynamic>.from(exServer);
      }
    }
    return out;
  }
}
