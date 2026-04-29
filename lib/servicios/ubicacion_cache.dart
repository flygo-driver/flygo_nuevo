// lib/servicios/ubicacion_cache.dart
import 'package:geolocator/geolocator.dart';

/// Servicio simple para almacenar en memoria la última ubicación conocida
/// y evitar esperar al GPS cada vez que se abre la pantalla.
class UbicacionCache {
  static Position? _ultimaUbicacion;
  static DateTime? _ultimaActualizacion;

  /// Devuelve la última ubicación almacenada (puede ser null)
  static Position? get ultimaUbicacion => _ultimaUbicacion;

  /// Devuelve la fecha/hora de la última actualización
  static DateTime? get ultimaActualizacion => _ultimaActualizacion;

  /// Guarda una nueva ubicación en la caché
  static void guardar(Position pos) {
    _ultimaUbicacion = pos;
    _ultimaActualizacion = DateTime.now();
  }

  /// Indica si la caché tiene una ubicación reciente (menos de 30 segundos por defecto)
  static bool esReciente({Duration maxAge = const Duration(seconds: 30)}) {
    if (_ultimaActualizacion == null) return false;
    return DateTime.now().difference(_ultimaActualizacion!) < maxAge;
  }

  /// Limpia la caché manualmente
  static void limpiar() {
    _ultimaUbicacion = null;
    _ultimaActualizacion = null;
  }
}
