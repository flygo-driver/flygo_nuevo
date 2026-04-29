/// Ventanas de publicación / aceptación para viajes en `viajes` (pool de conductores).
///
/// **Debe coincidir** con `functions/src/trip_publish_windows.ts`. Si cambias valores,
/// actualiza ambos archivos en el mismo commit.

class TripPublishWindows {
  TripPublishWindows._();

  /// Minutos antes de la recogida en que el viaje entra al pool (visible y aceptable).
  /// Estilo apps tipo Uber/Lyft: ventana corta (~45 min), no horas antes.
  /// Si cambias esto, actualiza `functions/src/trip_publish_windows.ts`.
  static const int poolLeadMinutesProgramado = 45;

  /// Cuándo el cliente puede marcar “listo” / arrancar ventana operativa (GPS, recordatorios).
  /// Mantener ≤ o igual a [poolLeadMinutesProgramado] para no adelantar UX respecto al pool.
  static const int readyMinutesBeforePickup = 45;
  static const int ahoraThresholdMinutes = 15;

  static DateTime poolOpensAtForScheduledPickup(DateTime pickup, DateTime now) {
    final DateTime t = pickup.subtract(
      const Duration(minutes: poolLeadMinutesProgramado),
    );
    return t.isBefore(now) ? now : t;
  }

  /// Misma política que servidor: un solo instante para publicar y permitir claim.
  static DateTime acceptAfterForScheduledPickup(DateTime pickup, DateTime now) {
    return poolOpensAtForScheduledPickup(pickup, now);
  }

  static DateTime startWindowAtForScheduledPickup(
      DateTime pickup, DateTime now) {
    final DateTime t = pickup.subtract(
      const Duration(minutes: readyMinutesBeforePickup),
    );
    return t.isBefore(now) ? now : t;
  }

  static bool esAhoraPorFechaPickup(DateTime pickup, DateTime now) {
    return pickup
        .isBefore(now.add(const Duration(minutes: ahoraThresholdMinutes)));
  }

  /// Tab **Programar** con recogida “pronto” (dentro del mismo margen que el pool):
  /// mismo destino que tab **Ahora** → [ViajeEnCursoCliente] al confirmar.
  /// Usa [poolLeadMinutesProgramado] para no desfasarse de cuándo el viaje ya puede salir al pool.
  static bool esProgramadoRecogidaCasiInmediata(
      DateTime pickupUtc, DateTime nowUtc) {
    return !pickupUtc.isAfter(
      nowUtc.add(
        const Duration(minutes: poolLeadMinutesProgramado),
      ),
    );
  }
}
