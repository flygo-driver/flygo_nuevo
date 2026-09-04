import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';

/// Elección de pago del cliente en el viaje activo, fuera del árbol de widgets.
///
/// El selector se dibuja en varias ramas del sheet (aceptado, a bordo, en curso
/// y mapa) y cada rama construye un `State` distinto: si la elección viviera
/// dentro del widget se perdería al cambiar de rama y la UI volvería al valor
/// remoto antes de que el servidor confirme el cambio.
abstract final class ClienteMetodoPagoViajeUi {
  ClienteMetodoPagoViajeUi._();

  /// Máximo que la elección local puede ir por delante del documento. Si el
  /// servidor no confirma en esta ventana, la UI vuelve a mostrar la verdad.
  static const Duration ventana = Duration(seconds: 45);

  static const Set<String> _categorias = <String>{
    'efectivo',
    'transferencia',
    'tarjeta',
  };

  static String _viajeId = '';
  static String _categoria = '';
  static DateTime _marcadaEn = DateTime.fromMillisecondsSinceEpoch(0);

  /// Reloj inyectable para las pruebas.
  static DateTime Function() ahora = DateTime.now;

  /// Registra la elección del cliente mientras el callable viaja al servidor.
  static void marcar({required String viajeId, required String categoria}) {
    final String id = viajeId.trim();
    final String cat = categoria.trim().toLowerCase();
    if (id.isEmpty || !_categorias.contains(cat)) return;
    _viajeId = id;
    _categoria = cat;
    _marcadaEn = ahora();
  }

  /// Categoría elegida y aún vigente para [viajeId]; vacío si no aplica.
  static String categoriaPara(String viajeId) {
    final String id = viajeId.trim();
    if (id.isEmpty || id != _viajeId || _categoria.isEmpty) return '';
    if (ahora().difference(_marcadaEn) > ventana) {
      limpiar(id);
      return '';
    }
    return _categoria;
  }

  /// Método a mostrar: la elección local manda hasta que el doc la refleje.
  ///
  /// Es idempotente: aplicarla dos veces (pantalla y selector) da lo mismo.
  static String resolver({
    required String viajeId,
    required String metodoRemoto,
  }) {
    final String cat = categoriaPara(viajeId);
    if (cat.isEmpty) return metodoRemoto;
    if (MetodoPagoViaje.asientoCategoria(metodoRemoto) == cat) {
      return metodoRemoto;
    }
    return MetodoPagoViaje.etiquetaDocumento(cat);
  }

  /// Descarta la elección local (el callable falló o el viaje cambió).
  static void limpiar(String viajeId) {
    final String id = viajeId.trim();
    if (id.isNotEmpty && id != _viajeId) return;
    _viajeId = '';
    _categoria = '';
    _marcadaEn = DateTime.fromMillisecondsSinceEpoch(0);
  }

  static void limpiarTodo() {
    _viajeId = '';
    _categoria = '';
    _marcadaEn = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
