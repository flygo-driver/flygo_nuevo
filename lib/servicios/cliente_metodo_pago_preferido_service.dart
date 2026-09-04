import 'package:shared_preferences/shared_preferences.dart';

import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';

/// Recuerda el último método de pago elegido al solicitar viajes (mapa / buscador).
abstract final class ClienteMetodoPagoPreferidoService {
  ClienteMetodoPagoPreferidoService._();

  static const String _prefsKey = 'cliente_metodo_pago_preferido_v1';

  /// `efectivo` | `transferencia` | `tarjeta`
  static Future<String> cargarCategoria() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String raw = (prefs.getString(_prefsKey) ?? '').trim().toLowerCase();
      if (raw == 'transferencia' || raw == 'tarjeta') return raw;
    } catch (_) {}
    return 'efectivo';
  }

  static Future<void> guardarCategoria(String categoria) async {
    final String cat = categoria.trim().toLowerCase();
    if (cat != 'efectivo' && cat != 'transferencia' && cat != 'tarjeta') {
      return;
    }
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, cat);
    } catch (_) {}
  }

  static String etiquetaDocumentoDesdeCategoria(String categoria) {
    return MetodoPagoViaje.etiquetaDocumento(categoria);
  }
}
