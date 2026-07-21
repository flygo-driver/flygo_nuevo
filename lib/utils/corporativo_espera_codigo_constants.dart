/// Tiempo de gracia corporativo en origen antes de cancelar por falta de PIN.
///
/// El reloj arranca en el **máximo** entre llegada del chofer y hora de recogida
/// programada (si el encargado puso 8:00 y los empleados suben ~8:15, no penaliza
/// al chofer que llegó temprano).
class CorporativoEsperaCodigoConstants {
  CorporativoEsperaCodigoConstants._();

  static const int timeoutMinutos = 20;
  static const Duration timeout = Duration(minutes: timeoutMinutos);

  static DateTime? inicioEsperaCodigo({
    DateTime? tiempoLlegadaOrigen,
    DateTime? fechaHoraRecogida,
  }) {
    DateTime? inicio = tiempoLlegadaOrigen;
    if (fechaHoraRecogida != null) {
      if (inicio == null || fechaHoraRecogida.isAfter(inicio)) {
        inicio = fechaHoraRecogida;
      }
    }
    return inicio;
  }

  static DateTime? limiteEsperaCodigo({
    DateTime? tiempoLlegadaOrigen,
    DateTime? fechaHoraRecogida,
  }) {
    final inicio = inicioEsperaCodigo(
      tiempoLlegadaOrigen: tiempoLlegadaOrigen,
      fechaHoraRecogida: fechaHoraRecogida,
    );
    if (inicio == null) return null;
    return inicio.add(timeout);
  }
}
