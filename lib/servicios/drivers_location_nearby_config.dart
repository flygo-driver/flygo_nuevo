/// Configuración de consultas `drivers_location` (escala nacional).
abstract final class DriversLocationNearbyConfig {
  DriversLocationNearbyConfig._();

  /// Consultas geohash sin `region` (app conductor antigua).
  /// Desactivar cuando todos los conductores activos publiquen `region`.
  static const bool consultasLegacySinRegion = true;
}
