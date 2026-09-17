/// Parámetros de tarifa dinámica (lluvia, tapón, hora pico).
/// Valores por defecto en código; futuro: `config/tarifas_dinamicas` en Firestore.
abstract final class TarifasDinamicasConfig {
  /// Hora pico RD: mañana 7:30–9:00 y tarde 16:30–19:30.
  static const int picoMananaInicioMin = 7 * 60 + 30;
  static const int picoMananaFinMin = 9 * 60;
  static const int picoTardeInicioMin = 16 * 60 + 30;
  static const int picoTardeFinMin = 19 * 60 + 30;

  // —— RD$/min urbano por severidad de tráfico (carro) ——
  static const double porMinutoFluidoCarro = 2.2;
  static const double porMinutoLeveCarro = 2.9;
  static const double porMinutoModeradoCarro = 3.6;
  static const double porMinutoFuerteCarro = 4.4;

  static const double porMinutoFluidoMotor = 1.2;
  static const double porMinutoLeveMotor = 1.55;
  static const double porMinutoModeradoMotor = 1.95;
  static const double porMinutoFuerteMotor = 2.4;

  /// Por debajo de esto: tráfico fluido, mismo precio que antes (−7%).
  static const double ratioTraficoFluidoMax = 1.10;
  /// A partir de aquí sube RD$/min (tapón leve real, no ruido de Google).
  static const double ratioPorMinutoLeve = 1.15;
  static const double ratioTaponModerado = 1.25;
  static const double ratioTaponFuerte = 1.40;
  /// Para piso mínimo y recargos fuertes.
  static const double ratioTaponMinimo = 1.10;

  static const double descuentoTraficoFluidoPct = 7.0;

  /// Sin Google Directions en trayecto urbano: no subestimar (línea recta).
  static const double factorSinDirectionsUrbano = 1.22;

  // —— Recargo multiplicativo (urbano con minutos de tráfico) ——
  static const double factorLluvia = 1.12;
  static const double factorHoraPico = 1.08;
  static const double factorMaximoUrbano = 1.42;

  // —— Recargo aditivo (sin modo urbano_tiempo: solo km) ——
  static const double pctLluviaAditivo = 15.0;
  static const double pctHoraPicoAditivo = 12.0;
  static const double pctMaximoAditivo = 50.0;

  static double porMinutoDesdeRatio({
    required double ratio,
    required String claveVehiculo,
  }) {
    final k = claveVehiculo.toLowerCase();
    final bool motor = k == 'motor';
    if (!ratio.isFinite || ratio < ratioPorMinutoLeve) {
      return motor ? porMinutoFluidoMotor : porMinutoFluidoCarro;
    }
    if (ratio < ratioTaponModerado) {
      return motor ? porMinutoLeveMotor : porMinutoLeveCarro;
    }
    if (ratio < ratioTaponFuerte) {
      return motor ? porMinutoModeradoMotor : porMinutoModeradoCarro;
    }
    return motor ? porMinutoFuerteMotor : porMinutoFuerteCarro;
  }

  /// Piso urbano cuando llueve, hay tapón fuerte u hora pico.
  static double pisoUrbanoCondicionesAdversas({
    required double km,
    required double minimoLocalRd,
    required bool condicionesAdversas,
  }) {
    if (!condicionesAdversas || !km.isFinite || km <= 0) return minimoLocalRd;
    if (km >= 8 && km <= 20) {
      return minimoLocalRd > 380 ? minimoLocalRd : 380;
    }
    if (km > 20 && km < 40) {
      return minimoLocalRd > 520 ? minimoLocalRd : 520;
    }
    return minimoLocalRd;
  }
}
