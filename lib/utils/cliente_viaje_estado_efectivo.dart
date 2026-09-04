import 'package:flygo_nuevo/utils/calculos/estados.dart';

/// Estado que debe ver el cliente (fuente única, testeable, sin UI).
class ClienteViajeEstadoEfectivo {
  ClienteViajeEstadoEfectivo._();

  static bool codigoVerificadoEnDoc(Map<String, dynamic> viajeData) =>
      viajeData['codigoVerificado'] == true;

  static bool clienteAbordoEnDoc(Map<String, dynamic> viajeData) {
    if (viajeData['clienteAbordo'] == true) return true;
    final dynamic ex = viajeData['extras'];
    return ex is Map && ex['clienteAbordo'] == true;
  }

  /// Misma regla que [ViajeEnCursoCliente]: servidor + flags de abordo/PIN.
  static String resolver(Map<String, dynamic> viajeData) {
    final bool completado = viajeData['completado'] == true;
    final bool aceptado = viajeData['aceptado'] == true;
    final String estadoRaw = (viajeData['estado'] ?? '').toString();

    final String base = EstadosViaje.normalizar(
      estadoRaw.isNotEmpty
          ? estadoRaw
          : (completado
              ? EstadosViaje.completado
              : (aceptado
                  ? EstadosViaje.aceptado
                  : EstadosViaje.pendiente)),
    );

    if (completado || EstadosViaje.esCompletado(base)) {
      return EstadosViaje.completado;
    }
    if (EstadosViaje.esTerminal(base)) return base;

    if (codigoVerificadoEnDoc(viajeData)) {
      if (EstadosViaje.esEnCurso(base)) return base;
      return EstadosViaje.enCurso;
    }

    if (clienteAbordoEnDoc(viajeData) &&
        (EstadosViaje.esAceptado(base) ||
            EstadosViaje.esEnCaminoPickup(base) ||
            EstadosViaje.esEnCurso(base))) {
      return EstadosViaje.aBordo;
    }
    return base;
  }
}
