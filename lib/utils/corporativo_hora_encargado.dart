import 'package:flygo_nuevo/utils/hora_am_pm.dart';

/// Minutos de diferencia para tratar un cambio de hora como operación nueva
/// (cancelar viaje del día y crear otro). Debe coincidir con el servidor.
const int corporativoCambioHoraMaterialMin = 5;

/// Clave estable `empresaId_plantillaId` para mapas en vivo.
String claveRutaCorporativo(String empresaId, String plantillaId) =>
    '${empresaId.trim()}_${plantillaId.trim()}';

/// Hora contractual del encargado — única fuente de verdad para el chofer.
///
/// Orden: plantilla en vivo (stream) > campos corporativos del viaje/asignación.
String horaEncargadoCorporativo(
  Map<String, dynamic> data, {
  String? horaPlantillaViva,
}) {
  final viva = normalizarHoraHHmm(horaPlantillaViva) ??
      (horaPlantillaViva ?? '').trim();
  if (viva.isNotEmpty) return viva;

  for (final key in [
    'corporativoHoraRecogidaGrupo',
    'horaRecogidaGrupo',
    'horaRecogida',
    'hora',
  ]) {
    final norm = normalizarHoraHHmm((data[key] ?? '').toString());
    if (norm != null && norm.isNotEmpty) return norm;
  }
  return '';
}

/// Aplica la hora del encargado sobre un mapa de viaje (countdown / UI).
Map<String, dynamic> viajeConHoraEncargado(
  Map<String, dynamic> viaje, {
  String? horaEncargado,
}) {
  final hora = horaEncargado ?? horaEncargadoCorporativo(viaje);
  if (hora.isEmpty) return viaje;
  return {
    ...viaje,
    'corporativoHoraRecogidaGrupo': hora,
  };
}

/// Campos operativos de plantilla que el encargado controla y el chofer debe ver en vivo.
Map<String, dynamic> overlayEncargadoEnFija(
  Map<String, dynamic> fija,
  Map<String, dynamic> plantillaViva,
) {
  final merged = Map<String, dynamic>.from(fija);
  final hora = horaEncargadoCorporativo(plantillaViva);
  if (hora.isNotEmpty) {
    merged['hora'] = hora;
    merged['corporativoHoraRecogidaGrupo'] = hora;
  }
  final nom = (plantillaViva['plantillaNombre'] ?? '').toString().trim();
  if (nom.isNotEmpty) merged['plantillaNombre'] = nom;
  final nPas = plantillaViva['pasajerosActivos'];
  if (nPas is int && nPas > 0) merged['pasajerosActivos'] = nPas;
  final origen = (plantillaViva['origenLabel'] ?? '').toString().trim();
  if (origen.isNotEmpty) merged['origenLabel'] = origen;
  return merged;
}

/// Diferencia en minutos entre dos HH:mm (0–720; cruza medianoche).
int minutosEntreHorasContrato(String a, String b) {
  final pa = normalizarHoraHHmm(a);
  final pb = normalizarHoraHHmm(b);
  if (pa == null || pb == null) return 0;
  final partsA = pa.split(':');
  final partsB = pb.split(':');
  final ma = int.parse(partsA[0]) * 60 + int.parse(partsA[1]);
  final mb = int.parse(partsB[0]) * 60 + int.parse(partsB[1]);
  var d = (mb - ma).abs();
  if (d > 12 * 60) d = 24 * 60 - d;
  return d;
}

/// Cambio de hora que exige viaje nuevo (no solo parche). Ajustes ≤4 min parchean.
bool cambioHoraCorporativoMaterial(String horaAnterior, String horaNueva) {
  final prev = normalizarHoraHHmm(horaAnterior) ?? horaAnterior.trim();
  final next = normalizarHoraHHmm(horaNueva) ?? horaNueva.trim();
  if (prev.isEmpty || next.isEmpty || prev == next) return false;
  return minutosEntreHorasContrato(prev, next) >= corporativoCambioHoraMaterialMin;
}
