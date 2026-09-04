// Aísla Bola Ahorro del flujo principal pool / viaje en curso.
// El producto Bola sigue en sus pantallas y tabs; no toca shells ni viajeActivoId
// de viajes normales mientras `activo == true`.

abstract final class BolaAhorroPoolIsolation {
  /// `true` = pool + cliente↔taxista sin listeners/banners/reconciliación Bola.
  static const bool activo = true;

  /// `true` = aviso «en desarrollo» y sin entrada nueva al tablero (retomar sigue).
  static const bool enDesarrollo = true;

  static bool bloquearInterferenciaEnFlujoPool() => activo;
}
