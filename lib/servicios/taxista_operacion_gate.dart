import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/legal/terms_data.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';
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
  // ADM moderno usa documentosCompletos; legacy / desbloqueo usa puedeRecibirViajes.
  final docsOk = data['documentosCompletos'] == true ||
      data['puedeRecibirViajes'] == true;
  if (!docsOk) return false;
  if (taxistaRequiereRenovacionDocumentos(data)) return false;
  return true;
}

/// Tras el registro operativo: debe subir/enviar documentos antes de usar la app.
/// En `en_revision` puede entrar en modo limitado hasta que ADM apruebe.
bool taxistaDebeCompletarDocumentosAhora(Map<String, dynamic> data) {
  if (taxistaAprobadoParaOperarPool(data)) return false;
  if (taxistaRequiereRenovacionDocumentos(data)) return true;
  final e = taxistaDocsEstadoDesdeUsuario(data);
  return e == 'pendiente' || e == 'rechazado';
}

bool taxistaContratoFirmado(Map<String, dynamic> data) {
  final bool aceptado = data['contratoTaxistaAceptado'] == true;
  final String version =
      (data['contratoTaxistaVersion'] ?? '').toString().trim();
  return aceptado && version == kTaxistaContractVersion;
}

String? _campoVehiculoStr(Map<String, dynamic> data, String key) {
  final v = (data[key] ?? '').toString().trim();
  return v.isEmpty ? null : v;
}

/// URL de foto del vehículo (raíz o `docs.fotoVehiculoUrl`).
String? taxistaFotoVehiculoUrlDesdeUsuario(Map<String, dynamic> data) {
  final docs = data['docs'];
  if (docs is Map) {
    final u = (docs['fotoVehiculoUrl'] ?? '').toString().trim();
    if (u.isNotEmpty) return u;
  }
  final root = (data['fotoVehiculoUrl'] ?? '').toString().trim();
  if (root.isNotEmpty) return root;
  return null;
}

int? _anioDesdeUsuario(Map<String, dynamic> data) {
  final raw = data['anio'] ?? data['vehiculoAnio'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '');
}

/// Campos mínimos del carro antes de operar en pool (capa previa a documentos admin).
List<String> taxistaCamposVehiculoFaltantes(Map<String, dynamic> data) {
  final faltan = <String>[];
  if (_campoVehiculoStr(data, 'placa') == null) faltan.add('placa');
  final modelo =
      _campoVehiculoStr(data, 'vehiculoModelo') ?? _campoVehiculoStr(data, 'modelo');
  if (modelo == null) faltan.add('modelo');
  final anio = _anioDesdeUsuario(data);
  if (anio == null || anio < 1990) faltan.add('anio');
  final color =
      _campoVehiculoStr(data, 'vehiculoColor') ?? _campoVehiculoStr(data, 'color');
  if (color == null) faltan.add('color');
  return faltan;
}

bool taxistaVehiculoPerfilCompleto(Map<String, dynamic> data) {
  if (data['vehiculoPerfilCompleto'] == true) return true;
  return taxistaCamposVehiculoFaltantes(data).isEmpty;
}

/// Mapa para merge en Firestore al guardar perfil de vehículo.
Map<String, dynamic> taxistaMergeVehiculoPerfil({
  required String placa,
  required String modelo,
  required int anio,
  required String color,
  String? marca,
  String? fotoVehiculoUrl,
}) {
  final foto = (fotoVehiculoUrl ?? '').trim();
  final merge = <String, dynamic>{
    'placa': placa.trim().toUpperCase(),
    'vehiculoModelo': modelo.trim(),
    'vehiculoColor': color.trim(),
    'modelo': modelo.trim(),
    'color': color.trim(),
    'anio': anio,
    'vehiculoAnio': anio,
    'vehiculoPerfilCompleto': true,
    'actualizadoEn': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
  if (foto.isNotEmpty) {
    merge['fotoVehiculoUrl'] = foto;
    merge['docs'] = {
      'fotoVehiculoUrl': foto,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
  final m = (marca ?? '').trim();
  if (m.isNotEmpty) {
    merge['vehiculoMarca'] = m;
    merge['marca'] = m;
  }
  return merge;
}

/// Google Sign-In permitido para taxista (registro completo + aprobación admin).
bool taxistaPuedeIniciarSesionConGoogle(Map<String, dynamic> data) {
  return taxistaAprobadoParaOperarPool(data);
}

/// Código de rechazo para claim/aceptar viaje pool (`null` = apto).
/// Paridad con [assertTaxistaAptoParaClaimPool] en Cloud Functions.
/// Misma lógica que [TaxistaEntry] / pool: docs + contrato + registro; no [puedeRecibirViajes].
String? taxistaRechazoAceptarViajePool(Map<String, dynamic> data) {
  if (data['bloqueado'] == true) return 'bloqueado-admin';
  if (data['registroTaxistaCompleto'] != true) return 'registro-incompleto';
  if (!taxistaContratoFirmado(data)) return 'contrato-no-firmado';
  if (!taxistaAprobadoParaOperarPool(data)) return 'documentos-no-aprobados';
  return null;
}

/// Mensaje en español para SnackBar / detalle al fallar [ViajesRepo.claimTripWithReason].
String taxistaMensajeClaimFallido(
  String res, {
  String poolModoConductor = TaxistaPoolModoConductor.vehiculo,
}) {
  switch (res) {
    case 'no-existe':
      return 'El viaje ya no existe.';
    case 'estado-no-pendiente':
      return 'El viaje ya no está pendiente.';
    case 'ya-asignado':
      return 'Ese viaje ya fue asignado.';
    case 'acceptAfter-futuro':
      return 'Aún no se libera para aceptar.';
    case 'publish-futuro':
      return 'Aún no se publica en el pool.';
    case 'reservado-otro':
      return 'Reservado por otro taxista.';
    case 'taxista-ocupado':
      return 'Tienes un viaje activo. Finalízalo o cancélalo.';
    case 'bloqueado-pago-semanal':
    case 'bloqueado-comision-efectivo':
      return PagosTaxistaRepo.mensajeRecargaTomarViajes;
    case 'prepago-insuficiente-comision-viaje':
      return PagosTaxistaRepo.mensajePrepagoInsuficienteComisionViajeGenerico;
    case 'bloqueado-admin':
      return 'Tu cuenta está bloqueada por administración. Contacta soporte.';
    case 'registro-incompleto':
      return 'Completa tu registro de taxista antes de aceptar viajes.';
    case 'contrato-no-firmado':
      return 'Debes firmar el contrato de taxista en tu cuenta.';
    case 'documentos-no-aprobados':
      return 'Tus documentos aún no están aprobados por administración.';
    case 'tipo-servicio-no-coincide':
      return poolModoConductor == TaxistaPoolModoConductor.motor
          ? 'Este viaje es de carro/taxi. Tu perfil es de motores.'
          : 'Este viaje es de motores. Tu perfil es vehículo.';
    case 'no-puede-recibir-viajes':
      return 'Tu cuenta no está habilitada para recibir viajes. '
          'Si ya tienes documentos aprobados, contacta administración.';
    default:
      if (res.startsWith('permiso:')) {
        return 'No se pudo aceptar (permisos). Intenta de nuevo o contacta soporte.';
      }
      if (res.startsWith('bloqueado')) {
        return PagosTaxistaRepo.mensajeRecargaTomarViajes;
      }
      return 'No se pudo aceptar el viaje. Intenta de nuevo.';
  }
}
