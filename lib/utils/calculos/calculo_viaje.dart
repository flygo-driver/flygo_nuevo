import 'dart:math';

class CalculoViaje {
  // Distancia Haversine entre dos puntos GPS
  static double calcularDistancia(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371.0; // Radio de la Tierra en km
    final dLat = _gradosARadianes(lat2 - lat1);
    final dLon = _gradosARadianes(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_gradosARadianes(lat1)) *
            cos(_gradosARadianes(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c; // en km
  }

  static double _gradosARadianes(double grados) {
    return grados * pi / 180;
  }

  // Calcular precio según distancia
  static double calcularPrecio(double distanciaKm, {bool idaYVuelta = false}) {
    const tarifaBase = 45.0;
    const tarifaReducida = 40.0;
    double precio;

    if (distanciaKm <= 40) {
      precio = distanciaKm * tarifaBase;
    } else {
      final extra = distanciaKm - 40;
      precio = (40 * tarifaBase) + (extra * tarifaReducida);
    }

    if (idaYVuelta) {
      precio += precio * 0.5; // solo 50% del regreso
    }

    return double.parse(precio.toStringAsFixed(2));
  }

  // Calcular comisión de FlyGo (20%) y ganancia del taxista (80%)
  static Map<String, double> calcularComisionYGanancia(double precioTotal) {
    final comision = precioTotal * 0.20;
    final ganancia = precioTotal - comision;

    return {
      'comision': double.parse(comision.toStringAsFixed(2)),
      'gananciaTaxista': double.parse(ganancia.toStringAsFixed(2)),
    };
  }
}
