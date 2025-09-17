// lib/servicios/distancia_service.dart
import 'dart:math' as math;

/// Cálculo de distancia y precio estimado.
/// Ajusta las TARIFAS aquí si lo necesitas.
class DistanciaService {
  // ======= TARIFAS =======
  static const double _tarifaBase = 120.0; // RD$
  static const double _tarifaPorKm = 45.0; // RD$ por km
  static const double _minimo = 150.0; // mínimo a cobrar

  /// Distancia Haversine en KM (redondeada a 2 decimales).
  static double calcularDistancia(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371.0; // radio tierra en km
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final km = r * c;
    return double.parse(km.toStringAsFixed(2));
  }

  /// Precio estimado en RD$ (aplica base, por-km y mínimo).
  /// Si idaYVuelta es true, se duplican los km.
  static double calcularPrecio(double distanciaKm, {bool idaYVuelta = false}) {
    final kms = idaYVuelta ? (distanciaKm * 2.0) : distanciaKm;
    double precio = _tarifaBase + (kms * _tarifaPorKm);
    if (precio < _minimo) precio = _minimo;
    return double.parse(precio.toStringAsFixed(2));
  }

  /// Tramo absurdo (protección de lógica). Ajusta umbral si quieres.
  static bool tramoEsImposible(double km) {
    if (km.isNaN || km.isInfinite) return true;
    if (km <= 0) return true;
    // 350 km por tramo como límite razonable para viajes urbanos/interurbanos medianos
    return km > 350;
  }

  static double _deg2rad(double deg) => deg * (math.pi / 180.0);
}