import 'package:flygo_nuevo/legal/terms_data.dart';
// lib/servicios/taxista_operacion_gate.dart
// Solo lectura de flags en usuarios/{uid}: aprobación admin + documentos (sin tocar viajes/mapas).

/// Estado de documentos unificado (registro usaba [estadoDocumentos], el resto [docsEstado]).
String taxistaDocsEstadoDesdeUsuario(Map<String, dynamic> data) {
  final a = (data['docsEstado'] ?? data['estadoDocumentos'] ?? 'pendiente')
      .toString()
      .trim()
      .toLowerCase();
  return a.isEmpty ? 'pendiente' : a;
}

/// Pool / tomar viajes: misma regla que Google para taxista.
bool taxistaAprobadoParaOperarPool(Map<String, dynamic> data) {
  if (taxistaDocsEstadoDesdeUsuario(data) != 'aprobado') return false;
  if (data['documentosCompletos'] != true) return false;
  if (data['puedeRecibirViajes'] != true) return false;
  return true;
}

bool taxistaContratoFirmado(Map<String, dynamic> data) {
  final bool aceptado = data['contratoTaxistaAceptado'] == true;
  final String version = (data['contratoTaxistaVersion'] ?? '').toString().trim();
  return aceptado && version == kTaxistaContractVersion;
}

/// Google Sign-In permitido para taxista (registro completo + aprobación admin).
bool taxistaPuedeIniciarSesionConGoogle(Map<String, dynamic> data) {
  return taxistaAprobadoParaOperarPool(data);
}
