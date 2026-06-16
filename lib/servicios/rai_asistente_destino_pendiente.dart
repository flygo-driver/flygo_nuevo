import 'package:flygo_nuevo/servicios/lugares_service.dart';

/// Destino elegido en el asistente RAI para aplicar una sola vez al abrir motor/taxi.
class RaiAsistenteDestinoPendiente {
  RaiAsistenteDestinoPendiente._();

  static DetalleLugar? _destino;

  static void guardar(DetalleLugar det) {
    _destino = det;
  }

  /// Lee y limpia el destino pendiente (evita reaplicar en rebuilds).
  static DetalleLugar? consumir() {
    final v = _destino;
    _destino = null;
    return v;
  }
}
