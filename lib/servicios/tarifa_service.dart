// lib/servicios/tarifa_service.dart

import 'distancia_service.dart';

class TarifaService {

  /// ✅ SOLO para viajes NORMALES y MOTOR
  /// ✅ TURISMO se maneja aparte
  static double calcularPrecioPorTipo({
    required double distanciaKm,
    required String tipoVehiculo,
  }) {

    // 🔥 1) Base (tu lógica actual)
    final double base = DistanciaService.calcularPrecio(distanciaKm);

    final String t = tipoVehiculo.toLowerCase().trim();

    // ============================================
    // 🏝️ TURISMO (NO TOCAR)
    // ============================================
    if (t.contains('turismo')) {
      return double.parse(base.toStringAsFixed(2));
    }

    // ============================================
    // 🏍️ MOTOR (TU LÓGICA ORIGINAL)
    // ============================================
    if (t.contains('motor') || t.contains('moto') || t.contains('motocic')) {
      final precioMotor = _ajustarParaMotorSiAplica(base, t);
      return double.parse(precioMotor.toStringAsFixed(2));
    }

    // ============================================
    // 🚗 NUEVO: TIPOS DE VEHÍCULO
    // ============================================

    double multiplicador = 1.0;

    if (t.contains('carro')) {
      multiplicador = 1.0;
    } else if (t.contains('jeepeta')) {
      multiplicador = 1.25;
    } else if (t.contains('minivan')) {
      multiplicador = 1.4;
    } else if (t.contains('bus')) {
      multiplicador = 1.7;
    }

    final double precioFinal = base * multiplicador;

    return double.parse(precioFinal.toStringAsFixed(2));
  }

  // ============================================
  // 🔥 FUNCIÓN QUE TE FALTABA
  // ============================================
  static double _ajustarParaMotorSiAplica(double precioBase, String tipoVehiculo) {

    const double factorMotor = 0.75;
    const double minimoMotor = 120.0;

    double precioMotor = precioBase * factorMotor;

    if (precioMotor < minimoMotor) {
      precioMotor = minimoMotor;
    }

    return precioMotor;
  }
}