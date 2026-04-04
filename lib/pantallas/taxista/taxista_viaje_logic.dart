// lib/servicios/taxista_viaje_logic.dart
//
// Nota de producción:
// Adaptador de compatibilidad. Si se habilita desde UI en algún momento,
// validar que los efectos (especialmente pagos/estados) queden alineados
// con el flujo central (`viajes_repo.dart` + pantallas actuales).
import 'package:url_launcher/url_launcher.dart';
import 'package:flygo_nuevo/data/viaje_data.dart';

/// Adaptador fino para pantallas/Widgets viejos:
/// - Reexpone acciones del taxista contra la API centralizada (ViajeData).
/// - Mantiene las mismas firmas públicas para no romper nada.
/// - No escribe campos raros ni anidados; cumple con tus reglas.
/// - La captura/registro de pagos (si aplica) ya no se hace aquí.
class TaxistaViajeLogic {
  /// Marca "cliente a bordo" (aceptado/en_camino_pickup -> a_bordo).
  /// Cumple reglas y valida uid del taxista en transacción.
  static Future<void> marcarClienteAbordo({
    required String viajeId,
    required String uidTaxista,
  }) {
    return ViajeData.marcarClienteAbordoTx(
      viajeId: viajeId,
      uidTaxista: uidTaxista,
    );
  }

  /// Inicia el viaje (a_bordo | aceptado | en_camino_pickup -> en_curso).
  /// Cumple reglas y valida uid del taxista en transacción.
  static Future<void> iniciarViaje({
    required String viajeId,
    required String uidTaxista,
  }) {
    return ViajeData.iniciarViajeTx(viajeId: viajeId, uidTaxista: uidTaxista);
  }

  /// Finaliza el viaje (en_curso -> completado).
  /// Idempotente y calcula 20/80 si faltan partidas.
  /// Nota: no necesita uidTaxista para completar con la lógica actual,
  /// pero dejamos el parámetro para compatibilidad con llamadas existentes.
  static Future<void> finalizarViaje({
    required String viajeId,
    String? uidTaxista, // compatibilidad; no se usa
  }) {
    return ViajeData.completarViaje(viajeId);
  }

  // ===================== Utilidades de navegación =====================

  /// Abre Waze guiando al punto destino.
  static Future<void> abrirWazeDestino(double lat, double lon) async {
    final url = Uri.parse('https://waze.com/ul?ll=$lat,$lon&navigate=yes');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  /// Abre Waze buscando una dirección por texto (por si no hay coordenadas).
  static Future<void> abrirWazeBusqueda(String query) async {
    final q = Uri.encodeComponent(query);
    final url = Uri.parse('https://waze.com/ul?q=$q&navigate=yes');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  /// Abre Google Maps guiando al punto destino.
  static Future<void> abrirGoogleMapsDestino(double lat, double lon) async {
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=driving',
    );
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  /// Abre Google Maps buscando una dirección por texto.
  static Future<void> abrirGoogleMapsDireccion(String direccion) async {
    final q = Uri.encodeComponent(direccion);
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }
}
