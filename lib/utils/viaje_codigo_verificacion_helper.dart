import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';

/// Reglas únicas del PIN de abordaje para **todos** los productos RAI:
/// normal, motor, turismo, **programado**, multiparada y bola (tras acuerdo → viaje en curso).
///
/// **Programado:** el PIN se genera al crear la reserva (mismo campo `codigoVerificacion`).
/// No se muestra al cliente hasta que un taxista acepte; entonces entra a viaje en curso
/// con la misma UI que un viaje «ahora».
abstract final class ViajeCodigoVerificacionHelper {
  static final RegExp _soloDigitos = RegExp(r'\D');

  static String soloDigitos(String? raw) =>
      (raw ?? '').replaceAll(_soloDigitos, '');

  static bool pinValido(String? raw) => soloDigitos(raw).length == 6;

  /// Lee un PIN ya persistido (no inventa uno nuevo).
  static String? pinExistenteEnMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final String key in <String>[
      'codigoVerificacion',
      'codigo_verificacion',
      'boardingPin',
      'codigoVerificacionBola',
    ]) {
      final String pin = soloDigitos((data[key] ?? '').toString());
      if (pin.length == 6) return pin;
    }
    return null;
  }

  /// Resuelve el PIN para mostrar al cliente o validar en taxista (misma fuente).
  static String pinDesdeViajeDoc({
    required Map<String, dynamic> viajeData,
    String? codigoDesdeModelo,
    Map<String, dynamic>? bolaData,
  }) {
    final String desdeModelo = soloDigitos(codigoDesdeModelo);
    if (desdeModelo.length == 6) return desdeModelo;

    final String? desdeViaje = pinExistenteEnMap(viajeData);
    if (desdeViaje != null) return desdeViaje;

    if (bolaData != null) {
      final String desdeBola =
          soloDigitos((bolaData['codigoVerificacionBola'] ?? '').toString());
      if (desdeBola.length == 6) return desdeBola;
    }

    return '';
  }

  static String uidTaxistaAsignado({
    required Map<String, dynamic> viajeData,
    String? uidTaxistaModelo,
  }) {
    final String desdeModelo = (uidTaxistaModelo ?? '').trim();
    if (desdeModelo.isNotEmpty) return desdeModelo;
    return (viajeData['uidTaxista'] ?? viajeData['taxistaId'] ?? '')
        .toString()
        .trim();
  }

  static bool clienteAbordoEnDoc(
    Map<String, dynamic> viajeData, {
    bool clienteAbordoExtras = false,
  }) {
    if (viajeData['clienteAbordo'] == true) return true;
    if (clienteAbordoExtras) return true;
    final dynamic ex = viajeData['extras'];
    if (ex is Map && ex['clienteAbordo'] == true) return true;
    return false;
  }

  /// Mismo criterio para normal · motor · turismo · programado · multiparada · bola operativa.
  static bool clienteDebeMostrarPin({
    required Map<String, dynamic> viajeData,
    required String estadoNorm,
    required bool codigoVerificado,
    String? uidTaxistaModelo,
    bool clienteAbordoExtras = false,
    Map<String, dynamic>? bolaData,
  }) {
    if (codigoVerificado) return false;

    if (uidTaxistaAsignado(
          viajeData: viajeData,
          uidTaxistaModelo: uidTaxistaModelo,
        ).isEmpty) {
      return false;
    }

    final String estN = EstadosViaje.normalizar(estadoNorm);
    if (EstadosViaje.esTerminal(estN) ||
        EstadosViaje.esCodigoCorpTerminal(estN)) {
      return false;
    }

    if (!ViajePoolTaxistaGate.clientePinBolaPermitidoEnViajeEnCurso(
      viajeData: viajeData,
      bolaData: bolaData,
    )) {
      return false;
    }

    if (clienteAbordoEnDoc(
      viajeData,
      clienteAbordoExtras: clienteAbordoExtras,
    )) {
      return true;
    }

    return EstadosViaje.esAbordo(estN);
  }

  /// Taxista: pide PIN hasta verificar (misma ventana que el cliente ve el código).
  static bool taxistaDebePedirPin({
    required Map<String, dynamic> viajeData,
    required String estadoNorm,
    required bool codigoVerificado,
  }) {
    if (codigoVerificado) return false;
    final String estN = EstadosViaje.normalizar(estadoNorm);
    if (EstadosViaje.esTerminal(estN)) return false;
    if (uidTaxistaAsignado(viajeData: viajeData).isEmpty) return false;
    return EstadosViaje.esAbordo(estN) ||
        EstadosViaje.esEnCurso(estN) ||
        EstadosViaje.esEsperandoCodigoCorporativo(estN);
  }

  static bool necesitaGenerarPin(String pinResuelto) => !pinValido(pinResuelto);

  /// Genera PIN de 6 dígitos (misma convención que backend y [ViajesRepo]).
  static String generarPinSeisDigitos() {
    return (100000 + (DateTime.now().microsecondsSinceEpoch % 900000))
        .toString();
  }

  /// Reserva con fecha futura (`programado: true`, `esAhora: false`).
  static bool esViajeProgramado(Map<String, dynamic> viajeData) {
    return viajeData['programado'] == true && viajeData['esAhora'] != true;
  }
}
