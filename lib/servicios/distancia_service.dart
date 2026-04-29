import 'dart:math' as math;

class DistanciaService {
  static const double _tarifaBase = 120.0; // RD$
  static const double _tarifaPorKm = 45.0; // RD$ por km
  static const double _minimo = 150.0;

  // 👇 NUEVO: para que otros servicios (TarifaService) puedan ver el mínimo global
  static double get minimoGlobal => _minimo;

  static double calcularDistancia(
      double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371.0;
    final double dLat = _deg2rad(lat2 - lat1);
    final double dLon = _deg2rad(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final double km = r * c;
    return double.parse(km.toStringAsFixed(2));
  }

  static double calcularPrecio(double distanciaKm, {bool idaVuelta = false}) {
    final double kms = idaVuelta ? (distanciaKm * 2.0) : distanciaKm;
    double precio = _tarifaBase + (kms * _tarifaPorKm);
    if (precio < _minimo) precio = _minimo;
    return double.parse(precio.toStringAsFixed(2));
  }

  static bool tramoEsImposible(double km) {
    if (km.isNaN || km.isInfinite) return true;
    if (km <= 0) return true;
    return km > 350;
  }

  static double _deg2rad(double deg) => deg * (math.pi / 180.0);
}
