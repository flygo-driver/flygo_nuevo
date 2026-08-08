/// Configuración de consultas `drivers_location` (escala nacional).
abstract final class DriversLocationNearbyConfig {
  DriversLocationNearbyConfig._();

  /// Consultas geohash sin `region` (app conductor antigua).
  /// Desactivar cuando todos los conductores activos publiquen `region`.
  static const bool consultasLegacySinRegion = true;

  /// Frescura máxima para conductores disponibles en el mapa cliente.
  static const Duration maxAgeConductoresDisponibles = Duration(seconds: 90);

  /// Ventana más amplia para el conductor asignado al cliente en curso.
  static const Duration maxAgeConductorAsignado = Duration(minutes: 3);
}
