/// Anti-abuso: muchas cancelaciones de giras por cupos antes de iniciar.
class PoolGiraAbusoBloqueo implements Exception {
  PoolGiraAbusoBloqueo({
    required this.creadas,
    required this.canceladas,
    required this.ratioMax,
    this.diasHastaReinicio,
  });

  final int creadas;
  final int canceladas;
  final double ratioMax;
  final int? diasHastaReinicio;

  /// Mensaje fijo mostrado al taxista (SnackBar / diálogo).
  String get mensajeUsuario {
    final int pct = creadas > 0
        ? ((canceladas / creadas) * 100).round()
        : 0;
    final int maxPct = (ratioMax * 100).round();
    final String ventana = diasHastaReinicio != null && diasHastaReinicio! > 0
        ? ' El contador se reinicia solo en $diasHastaReinicio día(s).'
        : '';
    return 'Has cancelado muchas salidas por cupos sin confirmar comisión '
        '($canceladas de $creadas en esta ventana, $pct% — máximo $maxPct%). '
        'Contacta a soporte RAI: un administrador debe regularizar tu cuenta '
        'para que puedas publicar otra salida.$ventana';
  }

  @override
  String toString() => mensajeUsuario;
}
