import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/legal/terms_data.dart';
// lib/servicios/taxista_operacion_gate.dart
// Solo lectura de flags en usuarios/{uid}: aprobación admin + documentos (sin tocar viajes/mapas).

/// Plazo para volver a pedir documentos tras la última aprobación ([docsVerificadoEn]).
const Duration kTaxistaRenovacionDocumentos = Duration(days: 183);

DateTime? _docsVerificadoEnDateTime(Map<String, dynamic> data) {
  final v = data['docsVerificadoEn'];
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
}

/// Estado de documentos unificado (registro usaba [estadoDocumentos], el resto [docsEstado]).
String taxistaDocsEstadoDesdeUsuario(Map<String, dynamic> data) {
  final a = (data['docsEstado'] ?? data['estadoDocumentos'] ?? 'pendiente')
      .toString()
      .trim()
      .toLowerCase();
  return a.isEmpty ? 'pendiente' : a;
}

/// `true` si ya estaba aprobado pero pasó el plazo de [kTaxistaRenovacionDocumentos] desde
/// [docsVerificadoEn]. Sin fecha de verificación (usuarios viejos) no se exige renovación.
bool taxistaRequiereRenovacionDocumentos(Map<String, dynamic> data) {
  if (taxistaDocsEstadoDesdeUsuario(data) != 'aprobado') return false;
  if (data['documentosCompletos'] != true) return false;
  final verified = _docsVerificadoEnDateTime(data);
  if (verified == null) return false;
  return DateTime.now().isAfter(verified.add(kTaxistaRenovacionDocumentos));
}

/// Pool / entrada a [ViajeDisponible] tras onboarding: documentos aprobados por admin.
/// Tras ~6 meses desde [docsVerificadoEn] debe volver a [DocumentosTaxista] hasta nueva aprobación.
/// No usar [puedeRecibirViajes]: lo baja el admin al bloquear y no siempre se rehace al pagar deuda;
/// eso mandaba al taxista otra vez a [DocumentosTaxista] sin necesidad.
/// El bloqueo operativo por comisión efectivo (tope) sigue en [tienePagoPendiente] + repos / UI.
bool taxistaAprobadoParaOperarPool(Map<String, dynamic> data) {
  if (taxistaDocsEstadoDesdeUsuario(data) != 'aprobado') return false;
  if (data['documentosCompletos'] != true) return false;
  if (taxistaRequiereRenovacionDocumentos(data)) return false;
  return true;
}

bool taxistaContratoFirmado(Map<String, dynamic> data) {
  final bool aceptado = data['contratoTaxistaAceptado'] == true;
  final String version =
      (data['contratoTaxistaVersion'] ?? '').toString().trim();
  return aceptado && version == kTaxistaContractVersion;
}

/// Google Sign-In permitido para taxista (registro completo + aprobación admin).
bool taxistaPuedeIniciarSesionConGoogle(Map<String, dynamic> data) {
  return taxistaAprobadoParaOperarPool(data);
}
