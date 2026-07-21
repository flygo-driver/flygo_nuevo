import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/servicios/corporativo_ruta_service.dart';
import 'package:flygo_nuevo/utils/corporativo_ciclo_facturacion.dart';
import 'package:flygo_nuevo/servicios/navegacion_externa_launcher.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/corporativo_hora_encargado.dart';
import 'package:flygo_nuevo/utils/hora_am_pm.dart';
import 'package:flygo_nuevo/utils/multiparada_ruta_helper.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';

enum CorporativoAbrirResultado {
  ok,
  otroViajeActivo,
  noEncontrado,
  aunNoEsHora,
  error,
}

/// Evita que [CorporativoAutoAbrirWatcher] reabra una ruta que el chofer ya cerró.
final Map<String, DateTime> _rutasCorpInformativasDismissed = <String, DateTime>{};

/// Liquidación visible para el chofer (neto del viaje + acumulado del período).
class CorporativoChoferPagoResumen {
  const CorporativoChoferPagoResumen({
    required this.empresaId,
    required this.empresaNombre,
    required this.netoEsteViajeRd,
    required this.acumuladoPeriodoRd,
    required this.viajesCompletadosPeriodo,
    this.periodoInicio,
    this.periodoFin,
    this.cicloDias = 15,
    this.viajeYaContabilizado = false,
  });

  final String empresaId;
  final String empresaNombre;
  final double netoEsteViajeRd;
  final double acumuladoPeriodoRd;
  final int viajesCompletadosPeriodo;
  final DateTime? periodoInicio;
  final DateTime? periodoFin;
  final int cicloDias;
  final bool viajeYaContabilizado;

  double get totalTrasEsteViajeRd => viajeYaContabilizado
      ? acumuladoPeriodoRd
      : acumuladoPeriodoRd + netoEsteViajeRd;

  String get etiquetaCiclo =>
      CorporativoCicloFacturacion.descripcion(cicloDias);

  String? get etiquetaFechaPago {
    final fin = periodoFin;
    if (fin == null) return null;
    return 'Pago RAI estimado antes del ${_fmtFechaCorta(fin)}';
  }

  static String _fmtFechaCorta(DateTime d) {
    const dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
    const meses = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    final w = dias[d.weekday - 1];
    return '$w ${d.day} ${meses[d.month - 1]} ${d.year}';
  }
}

/// Viaje corporativo fijo asignado al taxista (no pool).
abstract final class CorporativoTaxistaService {
  CorporativoTaxistaService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Panel único tiempo real (`chofer_operacion/{uid}`) — fuente principal.
  static Stream<Map<String, dynamic>?> streamOperacionChofer(
    String uidTaxista,
  ) {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return Stream.value(null);
    return _db.collection('chofer_operacion').doc(uid).snapshots().map((s) {
      if (!s.exists) return null;
      return s.data();
    });
  }

  static List<Map<String, dynamic>> _rutasDesdeOperacion(
    Map<String, dynamic>? operacion,
  ) {
    if (operacion == null) return const [];
    final raw = operacion['rutasFijas'] ?? operacion['rutasActivasLista'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Rutas fijas desde `chofer_operacion` (fuente principal del panel chofer).
  static List<Map<String, dynamic>> rutasDesdeOperacion(
    Map<String, dynamic>? operacion,
  ) =>
      _rutasDesdeOperacion(operacion);

  /// Viajes publicados hoy en `chofer_operacion`.
  static List<Map<String, dynamic>> viajesHoyDesdeOperacion(
    Map<String, dynamic>? operacion,
  ) {
    if (operacion == null) return const [];
    final raw = operacion['viajesHoy'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Hay datos en el panel servidor del chofer.
  static bool tieneContenidoOperacion(Map<String, dynamic>? operacion) {
    if (operacion == null) return false;
    if (rutasDesdeOperacion(operacion).isNotEmpty) return true;
    if (viajesHoyDesdeOperacion(operacion).isNotEmpty) return true;
    final msg = mensajeGeneralOperacion(operacion);
    return msg.isNotEmpty &&
        !msg.toLowerCase().contains('sin rutas corporativas amarradas');
  }

  /// Prioriza `chofer_operacion`; la hora en vivo viene del stream de plantillas (encargado).
  static List<Map<String, dynamic>> mergeFijasOperacion({
    required List<Map<String, dynamic>> desdeOperacion,
    required List<Map<String, dynamic>> desdeStream,
  }) {
    if (desdeOperacion.isEmpty) return desdeStream;
    if (desdeStream.isEmpty) return desdeOperacion;
    final streamByKey = <String, Map<String, dynamic>>{};
    for (final m in desdeStream) {
      final key = claveRutaCorporativo(
        (m['empresaId'] ?? '').toString(),
        (m['plantillaId'] ?? '').toString(),
      );
      if (key != '_') streamByKey[key] = m;
    }
    final out = <Map<String, dynamic>>[];
    for (final m in desdeOperacion) {
      final key = claveRutaCorporativo(
        (m['empresaId'] ?? '').toString(),
        (m['plantillaId'] ?? '').toString(),
      );
      final vivo = streamByKey.remove(key);
      out.add(
        vivo != null ? overlayEncargadoEnFija(m, vivo) : Map<String, dynamic>.from(m),
      );
    }
    for (final vivo in streamByKey.values) {
      out.add(Map<String, dynamic>.from(vivo));
    }
    return dedupeFijasPorPlantilla(out);
  }

  /// Una sola fila por plantilla (evita duplicados tras cambio de hora del encargado).
  static List<Map<String, dynamic>> dedupeFijasPorPlantilla(
    List<Map<String, dynamic>> fijas,
  ) {
    final byKey = <String, Map<String, dynamic>>{};
    final sinClave = <Map<String, dynamic>>[];

    for (final raw in fijas) {
      final m = Map<String, dynamic>.from(raw);
      final emp = (m['empresaId'] ?? '').toString().trim();
      final pl = (m['plantillaId'] ?? '').toString().trim();
      if (emp.isEmpty || pl.isEmpty) {
        sinClave.add(m);
        continue;
      }
      final key = claveRutaCorporativo(emp, pl);
      final prev = byKey[key];
      byKey[key] =
          prev == null ? m : _preferirFijaCorporativaDuplicada(prev, m);
    }

    final out = [...byKey.values, ...sinClave];
    out.sort((a, b) {
      final ha = horaEncargadoCorporativo(a);
      final hb = horaEncargadoCorporativo(b);
      if (ha.isNotEmpty && hb.isNotEmpty) return ha.compareTo(hb);
      if (ha.isNotEmpty) return -1;
      if (hb.isNotEmpty) return 1;
      return 0;
    });
    return out;
  }

  static int _puntajeFijaCorporativa(Map<String, dynamic> m) {
    var s = 0;
    if (horaEncargadoCorporativo(m).isNotEmpty) s += 8;
    final viajeId =
        (m['viajeHoyId'] ?? m['_viajeHoyId'] ?? '').toString().trim();
    if (viajeId.isNotEmpty) s += 4;
    if (m['listoParaAbrir'] == true) s += 2;
    if (m['_sinteticaDesdeViaje'] == true) s -= 1;
    return s;
  }

  static Map<String, dynamic> _preferirFijaCorporativaDuplicada(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final sa = _puntajeFijaCorporativa(a);
    final sb = _puntajeFijaCorporativa(b);
    final mejor = sa >= sb ? a : b;
    final otro = sa >= sb ? b : a;
    final merged = Map<String, dynamic>.from({...otro, ...mejor});
    final hora = horaEncargadoCorporativo(merged);
    if (hora.isNotEmpty) {
      merged['hora'] = hora;
      merged['corporativoHoraRecogidaGrupo'] = hora;
    }
    return merged;
  }

  /// Clave de día RD `YYYY-MM-DD` para confirmación del chofer.
  static String diaCalendarioRd([DateTime? ref]) {
    final dt = ref ?? DateTime.now();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// El chofer ya confirmó la ruta de hoy en la plantilla.
  static bool choferConfirmoRutaHoy(
    Map<String, dynamic> plantillaData,
    String uidTaxista,
  ) {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return false;
    final key = 'choferConfirmado_${diaCalendarioRd()}';
    return (plantillaData[key] ?? '').toString().trim() == uid;
  }

  /// Política de sustituto requiere confirmación explícita del chofer.
  static bool politicaRequiereConfirmacionChofer(Map<String, dynamic> data) {
    final p = (data['politicaSustituto'] ?? 'auto').toString().toLowerCase();
    return p != 'pausar' && p != 'manual';
  }

  /// Confirma al servidor que el chofer hará la ruta de hoy.
  static Future<void> confirmarRutaCorporativa({
    required String empresaId,
    required String plantillaId,
  }) async {
    final emp = empresaId.trim();
    final pl = plantillaId.trim();
    if (emp.isEmpty || pl.isEmpty) return;
    await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('choferConfirmarRutaCorporativa')
        .call({
      'empresaId': emp,
      'plantillaId': pl,
    });
  }

  /// Stream de plantilla para estado de confirmación en vivo.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> streamPlantillaChofer(
    String empresaId,
    String plantillaId,
  ) {
    final emp = empresaId.trim();
    final pl = plantillaId.trim();
    if (emp.isEmpty || pl.isEmpty) {
      return const Stream.empty();
    }
    return _db
        .collection('empresas_corporativas')
        .doc(emp)
        .collection('plantillas_ruta')
        .doc(pl)
        .snapshots();
  }

  /// Fuerza refresco servidor → chofer_operacion (pull-to-refresh).
  static Future<void> refrescarOperacionChofer(String uidTaxista) async {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return;
    invalidarCacheEmpresaCorporativa();
    await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('taxistaRefrescarOperacionCorporativa')
        .call();
  }

  static String mensajeGeneralOperacion(Map<String, dynamic>? operacion) {
    if (operacion == null) return '';
    return (operacion['mensajeGeneral'] ?? '').toString().trim();
  }

  /// Mapa `viajeId` → listo según `chofer_operacion` (servidor).
  static Map<String, bool> listoOperacionPorViaje(
    Map<String, dynamic>? operacion,
  ) {
    final out = <String, bool>{};
    if (operacion == null) return out;
    for (final raw in [
      operacion['viajesHoy'],
      operacion['rutasFijas'],
      operacion['rutasActivasLista'],
    ]) {
      if (raw is! List) continue;
      for (final item in raw) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        if (m['listoParaAbrir'] != true) continue;
        final id = (m['viajeId'] ?? m['viajeHoyId'] ?? '').toString().trim();
        if (id.isNotEmpty) out[id] = true;
      }
    }
    return out;
  }

  static String _uidChoferEnViajeCorporativo(Map<String, dynamic> data) {
    final tx =
        (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString().trim();
    if (tx.isNotEmpty) return tx;
    return (data['corporativoChoferAsignadoUid'] ??
            data['corporativoChoferPreferidoUid'] ??
            '')
        .toString()
        .trim();
  }

  /// Chofer que opera el viaje publicado (no solo preferido de plantilla).
  static String choferOperativoUidViajeCorporativo(Map<String, dynamic> data) {
    for (final key in [
      'uidTaxista',
      'taxistaId',
      'corporativoChoferAsignadoUid',
    ]) {
      final s = (data[key] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static final Map<String, bool> _empresaCorporativaVigenteCache = {};

  /// Empresa aún existe en `empresas_corporativas` (oculta viajes huérfanos «Bravo», etc.).
  static Future<bool> corporativoEmpresaIdVigente(String empresaId) async {
    final id = empresaId.trim();
    if (id.isEmpty) return false;
    final cached = _empresaCorporativaVigenteCache[id];
    if (cached != null) return cached;
    try {
      final snap = await _db.collection('empresas_corporativas').doc(id).get();
      final ok = snap.exists && snap.data()?['activa'] != false;
      _empresaCorporativaVigenteCache[id] = ok;
      return ok;
    } catch (_) {
      return false;
    }
  }

  static void invalidarCacheEmpresaCorporativa([String? empresaId]) {
    if (empresaId == null || empresaId.trim().isEmpty) {
      _empresaCorporativaVigenteCache.clear();
      _nombreEmpresaPorIdCache.clear();
      return;
    }
    _empresaCorporativaVigenteCache.remove(empresaId.trim());
    _nombreEmpresaPorIdCache.remove(empresaId.trim());
  }

  static final Map<String, String> _nombreEmpresaPorIdCache = {};

  /// Nombre actual desde `empresas_corporativas/{id}` (no el texto viejo del viaje).
  static Future<String> nombreEmpresaCorporativoPorId(String empresaId) async {
    final id = empresaId.trim();
    if (id.isEmpty) return 'Empresa';
    final cached = _nombreEmpresaPorIdCache[id];
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      final snap = await _db.collection('empresas_corporativas').doc(id).get();
      if (!snap.exists) return id;
      final nom = (snap.data()?['nombre'] ?? id).toString().trim();
      final out = nom.isEmpty ? id : nom;
      _nombreEmpresaPorIdCache[id] = out;
      return out;
    } catch (_) {
      return id;
    }
  }

  static String nombreEmpresaCorporativo(Map<String, dynamic> data) {
    final empId = (data['corporativoEmpresaId'] ?? '').toString().trim();
    if (empId.isNotEmpty) {
      final cached = _nombreEmpresaPorIdCache[empId];
      if (cached != null && cached.isNotEmpty) return cached;
    }
    for (final key in ['corporativoEmpresaNombre', 'empresaNombre']) {
      final s = (data[key] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return empId.isNotEmpty ? empId : 'Empresa';
  }

  static Future<void> enriquecerNombresEmpresaEnFijas(
    List<Map<String, dynamic>> fijas,
  ) async {
    for (final m in fijas) {
      final empId = (m['empresaId'] ?? '').toString().trim();
      if (empId.isEmpty) continue;
      m['empresaNombre'] = await nombreEmpresaCorporativoPorId(empId);
    }
  }

  static Future<Map<String, dynamic>> enriquecerViajeCorporativoEmpresa(
    Map<String, dynamic> data,
  ) async {
    final copy = Map<String, dynamic>.from(data);
    final empId = (copy['corporativoEmpresaId'] ?? '').toString().trim();
    if (empId.isNotEmpty) {
      copy['corporativoEmpresaNombre'] =
          await nombreEmpresaCorporativoPorId(empId);
    }
    return copy;
  }

  static Future<bool> viajeCorporativoEmpresaVigente(
    Map<String, dynamic> data,
  ) async {
    if (!esViajeCorporativoDoc(data)) return false;
    final empId = (data['corporativoEmpresaId'] ?? '').toString().trim();
    if (empId.isEmpty) return true;
    return corporativoEmpresaIdVigente(empId);
  }

  static bool esViajeCorporativoAsignado(
    Map<String, dynamic> data,
    String uidTaxista,
  ) {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return false;
    if (!esViajeCorporativoDoc(data)) return false;

    final operativo = choferOperativoUidViajeCorporativo(data);
    if (operativo.isNotEmpty) {
      return operativo == uid;
    }

    // Viaje aún sin chofer operativo en el doc: solo el preferido de plantilla.
    return (data['corporativoChoferPreferidoUid'] ?? '').toString().trim() ==
        uid;
  }

  static bool _viajeCorporativoVisibleParaChofer(
    Map<String, dynamic> data,
    String uidTaxista,
  ) {
    if (!esViajeCorporativoAsignado(data, uidTaxista)) return false;
    if ((data['corporativoSupersedidoPor'] ?? '').toString().trim().isNotEmpty) {
      return false;
    }
    final empId = (data['corporativoEmpresaId'] ?? '').toString().trim();
    if (empId.isNotEmpty) {
      final vigente = _empresaCorporativaVigenteCache[empId];
      if (vigente == false) return false;
    }
    if (data['completado'] == true) return false;
    final estado =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());
    if (estado == EstadosViaje.cancelado ||
        estado == EstadosViaje.rechazado ||
        estado == EstadosViaje.completado ||
        estado == EstadosViaje.canceladoPorTiempo) {
      return false;
    }
    return estadoPermiteVerViajeCorporativo(data);
  }

  static List<DocumentSnapshot<Map<String, dynamic>>>
      _ordenarViajesCorporativos(
    List<DocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final copy = [...docs];
    copy.sort((a, b) {
      final fa = a.data()?['fechaHora'];
      final fb = b.data()?['fechaHora'];
      DateTime? da;
      DateTime? dbDate;
      if (fa is Timestamp) da = fa.toDate();
      if (fb is Timestamp) dbDate = fb.toDate();
      if (da == null && dbDate == null) return 0;
      if (da == null) return 1;
      if (dbDate == null) return -1;
      return da.compareTo(dbDate);
    });
    return copy;
  }

  /// Progreso real: navegación abierta o entregas marcadas (no solo abrir pantalla).
  static bool viajeCorporativoTieneProgresoReal(Map<String, dynamic> data) {
    if (data['corporativoRecogidaAbierta'] == true) return true;
    final abiertas = data['corporativoParadasAbiertas'];
    if (abiertas is List && abiertas.isNotEmpty) return true;
    final hechas = data['corporativoParadasHechas'];
    if (hechas is List && hechas.isNotEmpty) return true;
    return false;
  }

  /// «En curso» solo si hay avance operativo o estados de navegación activa.
  static bool viajeCorporativoEnCursoReal(Map<String, dynamic> data) {
    if (viajeCorporativoTieneProgresoReal(data)) return true;
    final estado =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());
    return estado == EstadosViaje.enCaminoPickup ||
        estado == EstadosViaje.aBordo ||
        estado == EstadosViaje.enOrigenEsperandoCodigo ||
        estado == EstadosViaje.esperandoCodigoEncargado ||
        estado == EstadosViaje.pendienteCodigo;
  }

  static DateTime? _fechaPublicacionViajeCorporativo(Map<String, dynamic> data) {
    for (final key in [
      'corporativoPublicadoEn',
      'publicadoEn',
      'createdAt',
      'fechaHora',
    ]) {
      final raw = data[key];
      if (raw is Timestamp) return raw.toDate();
    }
    return null;
  }

  static bool _viajeCorporativoMasRecienteQue(
    Map<String, dynamic> candidato,
    Map<String, dynamic> actual,
  ) {
    final progC = viajeCorporativoTieneProgresoReal(candidato);
    final progA = viajeCorporativoTieneProgresoReal(actual);
    if (progC && !progA) return true;
    if (progA && !progC) return false;
    final fc = _fechaPublicacionViajeCorporativo(candidato);
    final fa = _fechaPublicacionViajeCorporativo(actual);
    if (fc != null && fa != null) return fc.isAfter(fa);
    if (fc != null) return true;
    return false;
  }

  /// Una sola publicación vigente por plantilla/empresa en el día (evita duplicados).
  static List<DocumentSnapshot<Map<String, dynamic>>> dedupeViajesHoy(
    List<DocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final porPlantilla = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    final sinClave = <DocumentSnapshot<Map<String, dynamic>>>[];

    for (final d in docs) {
      final data = d.data() ?? <String, dynamic>{};
      final empId = (data['corporativoEmpresaId'] ?? '').toString().trim();
      final plId = (data['corporativoPlantillaId'] ?? '').toString().trim();
      if (empId.isEmpty || plId.isEmpty) {
        sinClave.add(d);
        continue;
      }
      final key = '${empId}_$plId';
      final prev = porPlantilla[key];
      if (prev == null ||
          _viajeCorporativoMasRecienteQue(
            data,
            prev.data() ?? <String, dynamic>{},
          )) {
        porPlantilla[key] = d;
      }
    }

    return _ordenarViajesCorporativos([...porPlantilla.values, ...sinClave]);
  }

  /// Viaje corporativo B2B (sin exigir chofer asignado).
  static bool esViajeCorporativoDoc(Map<String, dynamic> data) {
    final canal = (data['canalAsignacion'] ?? '').toString().trim();
    if (canal == CorporativoRutaService.canalCorporativoFijo) return true;
    if (data['corporativo'] == true) return true;
    if ((data['categoria'] ?? '').toString().trim().toLowerCase() ==
        'corporativo') {
      return true;
    }
    if ((data['recaudoDestino'] ?? '').toString().trim() ==
        'empresa_corporativa') {
      return true;
    }
    return false;
  }

  /// Sin tarjeta desplegable ni PIN del período (flujo «Elige tu destino»).
  static bool corpSinPinVerificacionChofer(
    Map<String, dynamic> data, {
    String? uidTaxista,
  }) {
    final uid = (uidTaxista ?? '').trim();
    var esCorp = esViajeCorporativoDoc(data);
    if (!esCorp && uid.isNotEmpty) {
      esCorp = esViajeCorporativoAsignado(data, uid);
    }
    if (!esCorp && pasajerosCount(data) > 0) {
      final empresa =
          (data['corporativoEmpresaNombre'] ?? '').toString().trim();
      esCorp = empresa.isNotEmpty;
    }
    if (!esCorp) return false;
    return esModoInformativo(data);
  }

  /// Corporativo informativo: pantalla destinos, nunca overlay «Mi viaje en curso».
  static bool corpDebeUsarPantallaDestinosChofer(
    Map<String, dynamic> data, {
    String? uidTaxista,
  }) {
    final uid = (uidTaxista ?? '').trim();
    if (uid.isNotEmpty && corpAsignadoUsaPantallaPropia(data, uid)) {
      return corpSinPinVerificacionChofer(data, uidTaxista: uid);
    }
    return corpSinPinVerificacionChofer(data, uidTaxista: uid);
  }

  /// Ruta corporativa solo lectura: lista de pasajeros + Maps/Waze (sin viaje en curso ni PIN).
  static bool esModoInformativo(Map<String, dynamic> data) {
    if (data['corporativoModoInformativo'] == false) return false;
    if (data['corporativoModoInformativo'] == true) return true;
    final ex = data['extras'];
    if (ex is Map) {
      if (ex['corporativoModoInformativo'] == false) return false;
      if (ex['corporativoModoInformativo'] == true) return true;
    }
    // Corporativo sin flag explícito en false → informativo (piloto estable).
    return esViajeCorporativoDoc(data);
  }

  /// Ruta informativa ya cerrada y facturada (no reabrir automáticamente).
  static bool viajeCorporativoInformativoCerradoParaChofer(
    Map<String, dynamic> data,
  ) {
    if (data['completado'] == true) return true;
    final st = EstadosViaje.normalizar((data['estado'] ?? '').toString());
    if (EstadosViaje.esTerminal(st) || EstadosViaje.esCompletado(st)) {
      return true;
    }
    // Paradas hechas ≠ ruta cerrada: falta «Finalizar» y factura.
    return false;
  }

  /// Chofer salió de una ruta cerrada: no auto-abrir de nuevo hoy.
  static void marcarRutaCorpInformativaDismissed(String viajeId) {
    final id = viajeId.trim();
    if (id.isEmpty) return;
    _rutasCorpInformativasDismissed[id] = DateTime.now();
  }

  static bool rutaCorpInformativaDismissedRecientemente(String viajeId) {
    final id = viajeId.trim();
    final t = _rutasCorpInformativasDismissed[id];
    if (t == null) return false;
    if (DateTime.now().difference(t).inHours >= 8) {
      _rutasCorpInformativasDismissed.remove(id);
      return false;
    }
    return true;
  }

  static void limpiarDismissRutaCorpInformativa(String viajeId) {
    _rutasCorpInformativasDismissed.remove(viajeId.trim());
  }

  /// Corporativo asignado abierto: nunca overlay «Mi viaje en curso» del shell taxista.
  static bool corpAsignadoUsaPantallaPropia(
    Map<String, dynamic> data,
    String uidTaxista,
  ) {
    if (!esViajeCorporativoAsignado(data, uidTaxista)) return false;
    if (data['completado'] == true) return false;
    if (viajeCorporativoInformativoCerradoParaChofer(data)) return false;
    final st =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());
    if (EstadosViaje.esTerminal(st) || EstadosViaje.esCompletado(st)) {
      return false;
    }
    return true;
  }

  /// Viaje pool/taxi real en curso (no cuenta ruta corporativa del chofer).
  static Future<bool> taxistaTieneViajeNoCorporativoBloqueante(
    String uidTaxista, {
    String? exceptViajeId,
  }) async {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return false;
    final except = (exceptViajeId ?? '').trim();
    try {
      final uSnap = await _db.collection('usuarios').doc(uid).get();
      final activo =
          (uSnap.data()?['viajeActivoId'] ?? '').toString().trim();
      if (activo.isEmpty) return false;
      if (except.isNotEmpty && activo == except) return false;
      final vSnap = await _db.collection('viajes').doc(activo).get();
      if (!vSnap.exists) return false;
      final d = vSnap.data() ?? <String, dynamic>{};
      if (corpAsignadoUsaPantallaPropia(d, uid)) return false;
      return ViajesRepo.viajeOperativoBloqueanteParaTaxista(d, uid);
    } catch (_) {
      return false;
    }
  }

  /// Encola ruta corporativa mientras hay otro viaje activo (pool/taxi).
  static Future<void> encolarViajeCorporativoInformativo({
    required String uidTaxista,
    required String viajeId,
  }) async {
    final uid = uidTaxista.trim();
    final id = viajeId.trim();
    if (uid.isEmpty || id.isEmpty) return;
    try {
      if (!(await taxistaTieneViajeNoCorporativoBloqueante(uid))) return;
      final uRef = _db.collection('usuarios').doc(uid);
      final uSnap = await uRef.get();
      final sig =
          (uSnap.data()?['siguienteViajeId'] ?? '').toString().trim();
      if (sig == id) return;
      final activo =
          (uSnap.data()?['viajeActivoId'] ?? '').toString().trim();
      if (activo == id) return;
      await uRef.set({
        'siguienteViajeId': id,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Viaje corporativo abierto del chofer (pantalla destinos, sin overlay taxista).
  static Future<String?> idViajeCorporativoOperativoParaChofer(
    String uidTaxista,
  ) async {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return null;
    try {
      final uSnap = await _db.collection('usuarios').doc(uid).get();
      final u = uSnap.data() ?? <String, dynamic>{};
      final candidatos = <String>[];
      for (final raw in [u['viajeActivoId'], u['siguienteViajeId']]) {
        final id = (raw ?? '').toString().trim();
        if (id.isNotEmpty && !candidatos.contains(id)) candidatos.add(id);
      }
      final cola = await idViajeCorporativoPendiente(uid);
      if (cola != null && cola.isNotEmpty && !candidatos.contains(cola)) {
        candidatos.add(cola);
      }
      for (final id in candidatos) {
        final vSnap = await _db.collection('viajes').doc(id).get();
        if (!vSnap.exists) continue;
        final d = vSnap.data() ?? <String, dynamic>{};
        if (!corpAsignadoUsaPantallaPropia(d, uid)) continue;
        if (rutaCorpInformativaDismissedRecientemente(id)) continue;
        return id;
      }
    } catch (_) {}
    return null;
  }

  /// Viaje corporativo informativo activo del chofer (no debe usar overlay «Mi viaje en curso»).
  static Future<String?> idViajeCorporativoInformativoParaChofer(
    String uidTaxista,
  ) async {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return null;
    try {
      final op = await idViajeCorporativoOperativoParaChofer(uid);
      if (op == null || op.isEmpty) return null;
      final vSnap = await _db.collection('viajes').doc(op).get();
      if (!vSnap.exists) return null;
      final d = vSnap.data() ?? <String, dynamic>{};
      if (!esModoInformativo(d)) return null;
      return op;
    } catch (_) {}
    return null;
  }

  /// Resuelve el viaje corporativo a abrir (id explícito, activo o cola del día).
  static Future<String?> resolverViajeCorporativoParaChofer({
    required String uidTaxista,
    String? viajeIdPreferido,
  }) async {
    final uid = uidTaxista.trim();
    final pref = (viajeIdPreferido ?? '').trim();
    if (pref.isNotEmpty) {
      try {
        final snap = await _db.collection('viajes').doc(pref).get();
        if (snap.exists) {
          final d = snap.data() ?? <String, dynamic>{};
          if (esViajeCorporativoAsignado(d, uid) &&
              !viajeCorporativoInformativoCerradoParaChofer(d) &&
              estadoPermiteVerViajeCorporativo(d)) {
            return pref;
          }
        }
      } catch (_) {}
    }
    return idViajeCorporativoPendiente(uid);
  }

  static String textoCopiarPasajero(CorporativoPasajero p) {
    final dest = p.destinoLabel.trim();
    final sec = p.sector.trim();
    final ref = p.referencia.trim();
    final parts = <String>[];
    if (dest.isNotEmpty) parts.add(dest);
    if (sec.isNotEmpty && sec != dest) parts.add(sec);
    if (ref.isNotEmpty) parts.add(ref);
    if (p.lat != 0 && p.lon != 0) {
      parts.add('${p.lat.toStringAsFixed(6)},${p.lon.toStringAsFixed(6)}');
    }
    return parts.isEmpty ? p.nombre : parts.join(' · ');
  }

  static String textoCopiarOrigen(Map<String, dynamic> data) {
    final origen = (data['origen'] ?? '').toString().trim();
    final lat = (data['latCliente'] as num?)?.toDouble() ??
        (data['latOrigen'] as num?)?.toDouble() ??
        0;
    final lon = (data['lonCliente'] as num?)?.toDouble() ??
        (data['lonOrigen'] as num?)?.toDouble() ??
        0;
    if (lat != 0 && lon != 0) {
      return origen.isEmpty
          ? '${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)}'
          : '$origen (${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)})';
    }
    return origen;
  }

  /// Chofer confirmó llegada a la empresa (sin PIN).
  static bool llegadaEmpresaConfirmada(Map<String, dynamic> data) {
    if (data['corporativoLlegadaEmpresaEn'] != null) return true;
    if (data['clienteAbordo'] == true) return true;
    final ex = data['extras'];
    if (ex is Map && ex['clienteAbordo'] == true) return true;
    if (data['pickupConfirmadoEn'] != null) return true;
    return false;
  }

  /// Cantidad de paradas completadas (orden libre o legacy secuencial).
  static int paradaActualIdx(Map<String, dynamic> data, int totalPasajeros) {
    return paradasHechasCount(data, totalPasajeros);
  }

  /// Paradas marcadas (orden libre) por índice de pasajero.
  static Set<int> paradasHechasIndices(
    Map<String, dynamic> data,
    int totalPasajeros,
  ) {
    final raw = data['corporativoParadasHechas'];
    if (raw is List) {
      return raw
          .whereType<num>()
          .map((e) => e.toInt())
          .where((i) => i >= 0 && i < totalPasajeros)
          .toSet();
    }
    var idx = 0;
    final direct = data['corporativoParadaActualIdx'];
    if (direct is num) {
      idx = direct.toInt();
    } else {
      final legs = data['multiparadaLegCompletadas'];
      if (legs is num) idx = legs.toInt();
    }
    idx = idx.clamp(0, totalPasajeros);
    if (idx <= 0) return {};
    return {for (var i = 0; i < idx && i < totalPasajeros; i++) i};
  }

  static bool paradaEstaHecha(
    Map<String, dynamic> data,
    int idx,
    int totalPasajeros,
  ) {
    return paradasHechasIndices(data, totalPasajeros).contains(idx);
  }

  static int paradasHechasCount(Map<String, dynamic> data, int total) {
    return paradasHechasIndices(data, total).length;
  }

  /// Paradas donde el chofer ya abrió Maps/Waze (evita tocar dos veces por error).
  static Set<int> paradasAbiertasIndices(
    Map<String, dynamic> data,
    int totalPasajeros,
  ) {
    final raw = data['corporativoParadasAbiertas'];
    final abiertas = raw is List
        ? raw
            .whereType<num>()
            .map((e) => e.toInt())
            .where((i) => i >= 0 && i < totalPasajeros)
            .toSet()
        : <int>{};
    abiertas.addAll(paradasHechasIndices(data, totalPasajeros));
    return abiertas;
  }

  /// Paradas con Waze/Maps abiertos pero sin ✓ de entrega.
  static int paradasPendientesConfirmarCount(
    Map<String, dynamic> data,
    int totalPasajeros,
  ) {
    if (totalPasajeros <= 0) return 0;
    final hechas = paradasHechasIndices(data, totalPasajeros);
    final abiertas = paradasAbiertasIndices(data, totalPasajeros);
    return abiertas.where((i) => !hechas.contains(i)).length;
  }

  /// Todas las paradas ya navegadas; falta confirmar entregas (✓).
  static bool todasParadasAbiertasPendientesConfirmar(
    Map<String, dynamic> data,
    int totalPasajeros,
  ) {
    if (totalPasajeros <= 0) return false;
    final hechas = paradasHechasIndices(data, totalPasajeros);
    if (hechas.length >= totalPasajeros) return false;
    final abiertas = paradasAbiertasIndices(data, totalPasajeros);
    return abiertas.length >= totalPasajeros;
  }

  /// `chofer_operacion` ya marcó este viaje como cerrado hoy.
  static bool viajeCompletadoEnOperacion(
    Map<String, dynamic>? operacion,
    String viajeId,
  ) {
    final id = viajeId.trim();
    if (id.isEmpty || operacion == null) return false;
    for (final raw in [
      operacion['viajesHoy'],
      operacion['rutasFijas'],
      operacion['rutasActivasLista'],
    ]) {
      if (raw is! List) continue;
      for (final item in raw) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final vid = (m['viajeId'] ?? m['viajeHoyId'] ?? '').toString().trim();
        if (vid != id) continue;
        if (m['completadoHoy'] == true) return true;
        if ((m['estadoOperacion'] ?? '').toString() == 'completado') {
          return true;
        }
      }
    }
    return false;
  }

  static bool recogidaEmpresaAbierta(Map<String, dynamic> data) {
    if (data['corporativoRecogidaAbierta'] == true) return true;
    if (esModoInformativo(data)) return false;
    return llegadaEmpresaConfirmada(data);
  }

  static Future<Map<String, dynamic>> _callableRutaCorpInformativa({
    required String viajeId,
    required String accion,
    int? paradaIdx,
    int? totalPasajeros,
  }) async {
    final id = viajeId.trim();
    if (id.isEmpty) {
      throw StateError('viajeId vacío');
    }
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('taxistaActualizarRutaCorpInformativa');
    final res = await callable.call<Map<String, dynamic>>({
      'viajeId': id,
      'accion': accion,
      if (paradaIdx != null) 'paradaIdx': paradaIdx,
      if (totalPasajeros != null) 'totalPasajeros': totalPasajeros,
    });
    return Map<String, dynamic>.from(res.data ?? const {});
  }

  static Future<void> marcarParadaAbierta({
    required String viajeId,
    required int paradaIdx,
    required int totalPasajeros,
  }) async {
    final id = viajeId.trim();
    if (id.isEmpty || paradaIdx < 0) return;
    await _callableRutaCorpInformativa(
      viajeId: id,
      accion: 'marcar_abierta',
      paradaIdx: paradaIdx,
      totalPasajeros: totalPasajeros,
    );
  }

  static Future<void> marcarRecogidaEmpresaAbierta(String viajeId) async {
    final id = viajeId.trim();
    if (id.isEmpty) return;
    await _callableRutaCorpInformativa(
      viajeId: id,
      accion: 'marcar_recogida_abierta',
    );
  }

  static bool rutaInformativaCompleta(Map<String, dynamic> data, int total) {
    if (total <= 0) {
      return esModoInformativo(data)
          ? data['corporativoRecogidaAbierta'] == true
          : llegadaEmpresaConfirmada(data);
    }
    return paradasHechasCount(data, total) >= total;
  }

  static String uidEncargadoDesdeViaje(Map<String, dynamic> data) {
    return (data['uidCliente'] ?? data['clienteId'] ?? '').toString().trim();
  }

  static String nombreEncargadoDesdeViaje(Map<String, dynamic> data) {
    final n = (data['corporativoClienteNombre'] ??
            data['clienteNombre'] ??
            '')
        .toString()
        .trim();
    return n.isEmpty ? 'Encargado' : n;
  }

  static Future<void> confirmarLlegadaEmpresa(String viajeId) async {
    final id = viajeId.trim();
    if (id.isEmpty) return;
    await _db.collection('viajes').doc(id).set({
      'corporativoLlegadaEmpresaEn': FieldValue.serverTimestamp(),
      'clienteAbordo': true,
      'pickupConfirmadoEn': FieldValue.serverTimestamp(),
      'corporativoParadaActualIdx': 0,
      'estado': EstadosViaje.enCurso,
      'extras.clienteAbordo': true,
      'extras.corporativo': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<bool> marcarParadaHecha({
    required String viajeId,
    required int paradaIdx,
    required int totalPasajeros,
  }) async {
    final id = viajeId.trim();
    if (id.isEmpty) return false;
    final res = await _callableRutaCorpInformativa(
      viajeId: id,
      accion: 'marcar_hecha',
      paradaIdx: paradaIdx,
      totalPasajeros: totalPasajeros,
    );
    return res['completa'] == true;
  }

  /// Metadatos multiparada al cerrar (no marca recogida ni «en curso»).
  static Future<void> prepararRutaInformativaEnCurso({
    required String viajeId,
    required int totalPasajeros,
  }) async {
    final id = viajeId.trim();
    if (id.isEmpty) return;
    await _callableRutaCorpInformativa(
      viajeId: id,
      accion: 'preparar',
      totalPasajeros: totalPasajeros,
    );
  }

  /// Registra todas las entregas antes de cerrar (modo informativo sin PIN).
  static Future<void> marcarTodasParadasHechasInformativa({
    required String viajeId,
    required int totalPasajeros,
  }) async {
    final id = viajeId.trim();
    if (id.isEmpty) return;
    await _callableRutaCorpInformativa(
      viajeId: id,
      accion: 'marcar_todas_hechas',
      totalPasajeros: totalPasajeros,
    );
  }

  /// Cierra la ruta corporativa informativa vía callable (factura + post-viaje).
  /// Requiere todas las entregas marcadas (✓) tras abrir Waze/Maps en cada destino.
  static Future<void> finalizarRutaInformativaChofer({
    required String viajeId,
    required String uidTaxista,
    required int totalPasajeros,
  }) async {
    final id = viajeId.trim();
    if (id.isEmpty) throw StateError('viajeId vacío');

    final snap = await _db.collection('viajes').doc(id).get();
    final data = snap.data();
    if (data == null) {
      throw StateError('Viaje no encontrado.');
    }
    if (!rutaInformativaCompleta(data, totalPasajeros)) {
      final hechas = paradasHechasCount(data, totalPasajeros);
      if (totalPasajeros > 0) {
        throw StateError(
          'Marcá ✓ en cada destino después de navegar '
          '($hechas/$totalPasajeros entregas).',
        );
      }
      throw StateError(
        'Abrí Waze o Maps a la recogida en empresa antes de finalizar.',
      );
    }

    await prepararRutaInformativaEnCurso(
      viajeId: id,
      totalPasajeros: totalPasajeros,
    );
    await ViajesRepo.completarViajePorTaxista(
      id,
      uidTaxista: uidTaxista,
    );
  }

  /// Chofer deja la ruta corporativa informativa (libera chofer, avisa empresa/RAI).
  static Future<void> abandonarRutaInformativaChofer({
    required String viajeId,
    String motivo = '',
  }) async {
    final id = viajeId.trim();
    if (id.isEmpty) throw StateError('viajeId vacío');
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('taxistaAbandonarRutaCorpInformativa');
    final res = await callable.call<Map<String, dynamic>>({
      'viajeId': id,
      'motivo': motivo.trim(),
    });
    final ok = res.data?['ok'] == true;
    if (!ok) {
      throw StateError('No se pudo dejar la ruta. Reintentá en unos segundos.');
    }
  }

  /// WhatsApp oficial de soporte RAI (mismo canal que pantalla Soporte).
  static Future<bool> abrirWhatsAppSoporteRai({
    required String mensaje,
  }) async {
    const numero = '+18293792133';
    final texto = Uri.encodeComponent(mensaje.trim());
    final waScheme =
        Uri.parse('whatsapp://send?phone=$numero&text=$texto');
    if (await canLaunchUrl(waScheme)) {
      return launchUrl(waScheme);
    }
    final waWeb = Uri.parse('https://wa.me/$numero?text=$texto');
    return launchUrl(waWeb, mode: LaunchMode.externalApplication);
  }

  static Future<void> abrirNavegacionParada(CorporativoPasajero p) async {
    if (p.lat != 0 && p.lon != 0) {
      await NavegacionExternaLauncher.abrirGoogleMapsDestino(p.lat, p.lon);
      return;
    }
    final dir = textoCopiarPasajero(p);
    if (dir.trim().isNotEmpty) {
      await NavegacionExternaLauncher.abrirGoogleMapsDireccion(dir);
      return;
    }
    throw StateError('Esta parada no tiene dirección ni GPS');
  }

  static Future<void> abrirWazeParada(CorporativoPasajero p) async {
    if (p.lat != 0 && p.lon != 0) {
      await NavegacionExternaLauncher.abrirWazeDestino(p.lat, p.lon);
      return;
    }
    final dir = textoCopiarPasajero(p);
    if (dir.trim().isNotEmpty) {
      await NavegacionExternaLauncher.abrirGoogleMapsDireccion(dir);
      return;
    }
    throw StateError('Esta parada no tiene dirección ni GPS');
  }

  static Future<void> abrirRutaGlobalDesdeEmpresa(
    Map<String, dynamic> data,
  ) async {
    await abrirMapsDesdeViaje(data);
  }

  static bool estadoPermiteVerViajeCorporativo(Map<String, dynamic> data) {
    final estado =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());
    if (data['completado'] == true) return false;
    return estado == EstadosViaje.aceptado ||
        estado == EstadosViaje.enCaminoPickup ||
        estado == EstadosViaje.aBordo ||
        estado == EstadosViaje.enOrigenEsperandoCodigo ||
        estado == EstadosViaje.esperandoCodigoEncargado ||
        estado == EstadosViaje.pendienteCodigo ||
        estado == EstadosViaje.enCurso ||
        estado == EstadosViaje.pendiente;
  }

  /// Recogida operativa: hora contractual del encargado (nunca `fechaHora` del viaje).
  static DateTime recogidaOperativaCorporativo(Map<String, dynamic> data) {
    final hora = horaEncargadoCorporativo(data);
    if (hora.isNotEmpty) {
      final parsed = _recogidaConHoraHoyLocal(hora);
      if (parsed != null) return parsed;
    }
    final desdeViaje = ViajePoolTaxistaGate.fechaHoraDeViaje(data);
    if (desdeViaje.millisecondsSinceEpoch > 0) return desdeViaje;
    return desdeViaje;
  }

  static DateTime? _recogidaConHoraHoyLocal(String horaStr, [DateTime? ref]) {
    final ahora = ref ?? DateTime.now();
    final norm = normalizarHoraHHmm(horaStr);
    if (norm == null) return null;
    final parts = norm.split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    return DateTime(ahora.year, ahora.month, ahora.day, h, m);
  }

  /// Próxima recogida en empresa (hoy o mañana si ya pasó / ruta cerrada hoy).
  static DateTime? proximaRecogidaDesdeHora(
    String horaStr, {
    bool completadaHoy = false,
  }) {
    final hoy = _recogidaConHoraHoyLocal(horaStr);
    if (hoy == null) return null;
    final now = DateTime.now();
    if (completadaHoy) {
      return hoy.add(const Duration(days: 1));
    }
    if (hoy.isAfter(now)) return hoy;
    if (now.difference(hoy).inHours <= 3) return hoy;
    return DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1))
        .add(Duration(hours: hoy.hour, minutes: hoy.minute));
  }

  /// Mensaje en vivo para ruta fija (misma próxima recogida que el countdown).
  static String mensajeChoferRutaFijaEnVivo({
    required String horaRaw,
    required String estadoOperacion,
    required bool listoParaAbrir,
    required bool viajePublicado,
    required bool recogidaPerdida,
    required bool completadoHoy,
  }) {
    final horaFmt =
        horaRaw.isNotEmpty ? fmtHoraStrAmPm(horaRaw) : 'la hora indicada';
    if (recogidaPerdida) {
      return 'La recogida de las $horaFmt no se realizó hoy. '
          'RAI registró la incidencia.';
    }
    if (completadoHoy) {
      return 'Ruta de hoy cerrada ✓ Mañana se publica el nuevo '
          '~45 min antes de la recogida.';
    }
    if (estadoOperacion == 'en_curso') {
      return 'Ruta en curso. Tocá Abrir ruta para continuar.';
    }
    if (listoParaAbrir || viajePublicado) {
      return 'Listo para abrir · recogida $horaFmt.';
    }

    final proxima = proximaRecogidaDesdeHora(
      horaRaw,
      completadaHoy: completadoHoy,
    );
    if (proxima == null) {
      return 'Ruta amarrada · recogida $horaFmt.';
    }

    const leadMin = 45;
    final ahora = DateTime.now();
    final minParaRecogida = proxima.difference(ahora).inMinutes;
    final hoySlot = _recogidaConHoraHoyLocal(horaRaw, ahora);
    final slotHoyYaPaso = hoySlot != null &&
        hoySlot.isBefore(ahora) &&
        minParaRecogida > 180;

    if (slotHoyYaPaso && !viajePublicado) {
      return 'Ruta amarrada · recogida $horaFmt. '
          'El viaje de hoy aún no está publicado; '
          'mañana se abre unos 45 min antes.';
    }

    final minParaAbrir = minParaRecogida - leadMin;
    if (minParaAbrir > 1) {
      return 'Se abre en ~$minParaAbrir min (recogida $horaFmt).';
    }
    if (minParaRecogida > 0 && minParaRecogida <= leadMin) {
      return 'Pronto se publica el viaje (recogida $horaFmt).';
    }
    return 'Ruta amarrada · recogida $horaFmt. Se publica ~45 min antes.';
  }

  /// Texto de confirmación coherente con la próxima recogida del countdown.
  static String etiquetaConfirmacionRutaFija(String horaRaw) {
    if (horaRaw.trim().isEmpty) {
      return '✓ Confirmaste esta ruta asignada';
    }
    final proxima = proximaRecogidaDesdeHora(horaRaw);
    if (proxima == null) {
      return '✓ Confirmaste esta ruta asignada';
    }
    final ahora = DateTime.now();
    final hoySlot = _recogidaConHoraHoyLocal(horaRaw, ahora);
    final esProximaManana = hoySlot != null &&
        hoySlot.isBefore(ahora) &&
        proxima.difference(ahora).inHours > 3;
    if (esProximaManana) {
      return '✓ Ruta confirmada · próxima recogida ${fmtHoraStrAmPm(horaRaw)}';
    }
    return '✓ Confirmaste que harás esta ruta hoy';
  }

  /// `chofer_operacion` marcó este viaje listo (fuente servidor al publicar).
  static Future<bool> choferOperacionMarcaListo(
    String uidTaxista,
    String viajeId,
  ) async {
    final uid = uidTaxista.trim();
    final vid = viajeId.trim();
    if (uid.isEmpty || vid.isEmpty) return false;
    try {
      final opSnap = await _db.collection('chofer_operacion').doc(uid).get();
      final op = opSnap.data();
      if (op == null) return false;
      for (final raw in [
        op['viajesHoy'],
        op['rutasFijas'],
        op['rutasActivasLista'],
      ]) {
        if (raw is! List) continue;
        for (final item in raw) {
          if (item is! Map) continue;
          final m = Map<String, dynamic>.from(item);
          if (m['listoParaAbrir'] != true) continue;
          final id = (m['viajeId'] ?? m['viajeHoyId'] ?? '').toString().trim();
          if (id == vid) return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Pool corporativo: ventana abierta (~90 min antes) o ruta con avance real.
  static bool viajeCorporativoEnPoolTrabajo(
    Map<String, dynamic> data, {
    bool? listoSegunOperacion,
  }) {
    if (viajeCorporativoEnCursoReal(data)) return true;
    return corporativoListoParaAbrirEnCurso(
      data,
      listoSegunOperacion: listoSegunOperacion,
    );
  }

  /// Ventana de publicación abierta (minutos antes de la recogida configurados en la ruta).
  static bool corporativoListoParaAbrirEnCurso(
    Map<String, dynamic> data, {
    bool? listoSegunOperacion,
  }) {
    if (viajeCorporativoInformativoCerradoParaChofer(data)) return false;
    if (!estadoPermiteVerViajeCorporativo(data)) return false;
    if (listoSegunOperacion == true) return true;

    final uidChofer = _uidChoferEnViajeCorporativo(data);
    final fecha = recogidaOperativaCorporativo(data);
    final ahora = DateTime.now();
    final minParaRecogida = fecha.millisecondsSinceEpoch > 0
        ? fecha.difference(ahora).inMinutes
        : 9999;

    // Chofer ya asignado: priorizar hora de recogida real sobre publishAt viejo
    // (p. ej. encargado movió 9:17 y el doc aún tiene publishAt desfasado).
    if (esViajeCorporativoDoc(data) && uidChofer.isNotEmpty) {
      final minPub = _minutosPublicarAntesCorporativo(data, fecha);
      final ventanaMin = (minPub + 10).clamp(20, 180);
      if (minParaRecogida <= ventanaMin && minParaRecogida >= -90) {
        return true;
      }
      // «Enviar ahora»: viaje publicado hoy con recogida próxima.
      final publicadoHoy = data['publicado'] == true ||
          data['corporativoPublicadoEn'] != null;
      if (publicadoHoy &&
          _esRecogidaMismoDiaLocal(fecha, ahora) &&
          minParaRecogida <= 180 &&
          minParaRecogida >= -120) {
        return true;
      }
      // Mismo día calendario: ventana de publicación o margen tras editar hora.
      if (_esRecogidaMismoDiaLocal(fecha, ahora)) {
        if (ViajePoolTaxistaGate.ventanaPublicacionYAceptacionOk(data)) {
          return true;
        }
        if (minParaRecogida <= minPub + 45) return true;
      }
    }

    if (ViajePoolTaxistaGate.ventanaPublicacionYAceptacionOk(data)) {
      return true;
    }

    return false;
  }

  static int _minutosPublicarAntesCorporativo(
    Map<String, dynamic> data,
    DateTime fechaRecogida,
  ) {
    final raw = data['corporativoMinutosPublicarAntes'];
    if (raw is num && raw > 0) return raw.toInt().clamp(3, 180);

    final pub = fechaPublicacionCorporativo(data);
    if (pub != null && fechaRecogida.isAfter(pub)) {
      return fechaRecogida.difference(pub).inMinutes.clamp(3, 180);
    }
    return 90;
  }

  static bool _esRecogidaMismoDiaLocal(DateTime fecha, DateTime ahora) {
    return fecha.year == ahora.year &&
        fecha.month == ahora.month &&
        fecha.day == ahora.day;
  }

  static DateTime? fechaPublicacionCorporativo(Map<String, dynamic> data) {
    for (final key in ['publishAt', 'acceptAfter', 'startWindowAt']) {
      final raw = data[key];
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is String) {
        final p = DateTime.tryParse(raw);
        if (p != null) return p;
      }
    }
    final fecha = ViajePoolTaxistaGate.fechaHoraDeViaje(data);
    if (fecha.millisecondsSinceEpoch > 0) {
      return ViajePoolTaxistaGate.acceptAfterDeViaje(data, fecha);
    }
    return null;
  }

  static String mensajeCorporativoAunNoEsHora(Map<String, dynamic> data) {
    final fecha = recogidaOperativaCorporativo(data);
    final fh =
        fecha.millisecondsSinceEpoch > 0 ? fmtFechaHoraAmPm(fecha) : 'la hora indicada';
    final ahora = DateTime.now();
    if (fecha.millisecondsSinceEpoch > 0) {
      final minParaRecogida = fecha.difference(ahora).inMinutes;
      final minPub = _minutosPublicarAntesCorporativo(data, fecha);
      final ventanaMin = (minPub + 10).clamp(20, 180);
      if (minParaRecogida > ventanaMin) {
        final falta = minParaRecogida - ventanaMin;
        return 'Tu ruta corporativa se abre en ~$falta min '
            '(recogida $fh; ventana ~$ventanaMin min antes).\n\n'
            'Mientras tanto podés usar Waze y Maps en Mis rutas corporativas.';
      }
    }
    final pub = fechaPublicacionCorporativo(data);
    if (pub != null && ahora.isBefore(pub)) {
      final min = pub.difference(ahora).inMinutes;
      if (min > 0) {
        return 'Tu ruta corporativa se abre en ~$min min '
            '(recogida $fh).\n\n'
            'Mientras tanto podés usar Waze y Maps en Mis rutas corporativas.';
      }
    }
    return 'Aún no es hora de abrir esta ruta (recogida $fh).\n\n'
        'RAI la activa unos minutos antes de la recogida. '
        'Revisá Mis rutas corporativas para Waze, Maps y pasajeros.';
  }

  /// Si se promovió por error antes de la ventana, devuelve el viaje a cola.
  static Future<void> revertirPromocionCorporativaTemprana({
    required String uidTaxista,
    String? viajeId,
  }) async {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return;
    var vid = (viajeId ?? '').trim();
    if (vid.isNotEmpty &&
        await choferOperacionMarcaListo(uid, vid)) {
      return;
    }
    try {
      await _db.runTransaction((tx) async {
        final uRef = _db.collection('usuarios').doc(uid);
        final uSnap = await tx.get(uRef);
        final u = uSnap.data() ?? <String, dynamic>{};
        var vid = (viajeId ?? '').trim();
        if (vid.isEmpty) {
          vid = (u['viajeActivoId'] ?? '').toString().trim();
        }
        if (vid.isEmpty) return;

        final vRef = _db.collection('viajes').doc(vid);
        final vSnap = await tx.get(vRef);
        if (!vSnap.exists) return;
        final v = vSnap.data() ?? <String, dynamic>{};
        if (!esViajeCorporativoAsignado(v, uid)) return;
        if (corporativoListoParaAbrirEnCurso(v)) return;

        final activoId = (u['viajeActivoId'] ?? '').toString().trim();
        if (activoId != vid) return;

        tx.set(uRef, {
          'viajeActivoId': '',
          'siguienteViajeId': vid,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        tx.set(vRef, {
          'activo': false,
          'aceptado': false,
          'estado': EstadosViaje.pendiente,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } catch (_) {}
  }

  /// Mañana (antes de 12) / Tarde (12–17) / Noche (17+).
  static String turnoDeFecha(DateTime? fecha) {
    if (fecha == null) return 'Ruta';
    final h = fecha.hour;
    if (h < 12) return 'Mañana';
    if (h < 17) return 'Tarde';
    return 'Noche';
  }

  /// Hora habitual por `empresaId_plantillaId` (desde asignación fija / merge).
  static Map<String, String> horaFijaPorRuta(
    List<Map<String, dynamic>> fijas,
  ) {
    final out = <String, String>{};
    for (final a in fijas) {
      final emp = (a['empresaId'] ?? '').toString().trim();
      final pl = (a['plantillaId'] ?? '').toString().trim();
      final hora = horaEncargadoCorporativo(a);
      if (emp.isNotEmpty && pl.isNotEmpty && hora.isNotEmpty) {
        out[claveRutaCorporativo(emp, pl)] = hora;
      }
    }
    return out;
  }

  /// Aplica `HH:mm` sobre la fecha del viaje (prioriza asignación en vivo).
  static DateTime? fechaConHoraFija(DateTime? fechaDia, String horaRaw) {
    if (fechaDia == null) return null;
    final parts = horaRaw.trim().split(':');
    if (parts.length < 2) return fechaDia;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return fechaDia;
    return DateTime(fechaDia.year, fechaDia.month, fechaDia.day, h, m);
  }

  static List<dynamic>? _rawPasajerosListDeMap(Map<String, dynamic> data) {
    final lists = <List<dynamic>>[];
    void add(dynamic raw) {
      if (raw is List && raw.isNotEmpty) lists.add(raw);
    }
    add(data['corporativoPasajeros']);
    final ex = data['extras'];
    if (ex is Map) {
      add(ex['corporativoPasajeros']);
      add(ex['pasajeros']);
    }
    add(data['pasajeros']);
    if (lists.isEmpty) return null;
    lists.sort((a, b) => b.length.compareTo(a.length));
    return lists.first;
  }

  static int pasajerosCount(Map<String, dynamic> data) {
    final raw = _rawPasajerosListDeMap(data);
    if (raw == null) return 0;
    var n = 0;
    for (final item in raw) {
      if (item is Map && item['activo'] == false) continue;
      n++;
    }
    return n;
  }

  static String? mapsUrlDe(Map<String, dynamic> data) {
    final ex = data['extras'];
    if (ex is Map) {
      final u = (ex['corporativoGoogleMapsRutaUrl'] ?? '').toString().trim();
      if (u.isNotEmpty) return u;
    }
    final u = (data['corporativoGoogleMapsRutaUrl'] ??
            data['googleMapsRutaUrl'] ??
            '')
        .toString()
        .trim();
    return u.isEmpty ? null : u;
  }

  static String? wazeUrlDe(Map<String, dynamic> data) {
    final ex = data['extras'];
    if (ex is Map) {
      final u = (ex['corporativoWazeOrigenUrl'] ?? '').toString().trim();
      if (u.isNotEmpty) return u;
    }
    final u = (data['corporativoWazeOrigenUrl'] ?? data['wazeOrigenUrl'] ?? '')
        .toString()
        .trim();
    return u.isEmpty ? null : u;
  }

  /// Google Maps URL admite hasta 9 paradas intermedias (+ destino final).
  static const int googleMapsMaxParadasIntermedias = 9;

  static Map<String, dynamic> mapaNavegacionDesdeViaje(Map<String, dynamic> data) {
    final out = Map<String, dynamic>.from(data);
    final ex = data['extras'];
    if (ex is Map) out.addAll(Map<String, dynamic>.from(ex));
    return out;
  }

  static int contarParadasRuta(Map<String, dynamic> data) {
    final coords = _coordsRutaDesdeViaje(data);
    if (coords == null) return 0;
    return coords.paradas.length + 1;
  }

  static Future<void> abrirMapsEmpresa(Map<String, dynamic> data) async {
    final lat = (data['latCliente'] as num?)?.toDouble() ??
        (data['latOrigen'] as num?)?.toDouble();
    final lon = (data['lonCliente'] as num?)?.toDouble() ??
        (data['lonOrigen'] as num?)?.toDouble();
    if (lat != null && lon != null && lat != 0 && lon != 0) {
      await NavegacionExternaLauncher.abrirGoogleMapsDestino(lat, lon);
      return;
    }
    final origen = (data['origen'] ?? '').toString().trim();
    if (origen.isNotEmpty) {
      await NavegacionExternaLauncher.abrirGoogleMapsDireccion(origen);
    }
  }

  static Future<void> abrirMapsDesdeViaje(Map<String, dynamic> data) async {
    final coords = _coordsRutaDesdeViaje(data);
    if (coords != null) {
      await NavegacionExternaLauncher.abrirGoogleMapsRutaConParadas(
        origenLat: coords.origenLat,
        origenLon: coords.origenLon,
        destinoLat: coords.destinoLat,
        destinoLon: coords.destinoLon,
        paradas: coords.paradas,
      );
      return;
    }
    final url = mapsUrlDe(data);
    if (url != null) {
      final ok = await NavegacionExternaLauncher.abrirEnlaceNavegacion(url);
      if (ok) return;
    }
    final lat = (data['latCliente'] as num?)?.toDouble();
    final lon = (data['lonCliente'] as num?)?.toDouble();
    if (lat != null && lon != null && lat != 0 && lon != 0) {
      await NavegacionExternaLauncher.abrirGoogleMapsDestino(lat, lon);
    }
  }

  /// Origen, paradas intermedias y destino final desde doc de viaje corporativo.
  static ({
    double origenLat,
    double origenLon,
    double destinoLat,
    double destinoLon,
    List<({double lat, double lon})> paradas,
  })? _coordsRutaDesdeViaje(Map<String, dynamic> data) {
    final oLat =
        (data['latOrigen'] as num?)?.toDouble() ??
        (data['latCliente'] as num?)?.toDouble();
    final oLon =
        (data['lonOrigen'] as num?)?.toDouble() ??
        (data['lonCliente'] as num?)?.toDouble();
    if (oLat == null || oLon == null || oLat == 0 || oLon == 0) return null;

    final paradas = <({double lat, double lon})>[];
    final wps = data['waypoints'];
    if (wps is List && wps.isNotEmpty) {
      final raw = <Map<String, dynamic>>[];
      for (final item in wps) {
        if (item is Map) raw.add(Map<String, dynamic>.from(item));
      }
      final ordenados = MultiparadaRutaHelper.sanitizarWaypoints(raw);
      for (final m in ordenados) {
        final lat = (m['lat'] as num?)?.toDouble();
        final lon = (m['lon'] as num?)?.toDouble();
        if (lat != null && lon != null && lat != 0 && lon != 0) {
          paradas.add((lat: lat, lon: lon));
        }
      }
      var dLat = (data['latDestino'] as num?)?.toDouble();
      var dLon = (data['lonDestino'] as num?)?.toDouble();
      if (dLat == null || dLon == null || dLat == 0 || dLon == 0) {
        final pas = _pasajerosActivosMaps(data);
        if (pas.isNotEmpty) {
          final ultimo = pas.last;
          dLat = ultimo.lat;
          dLon = ultimo.lon;
        }
      }
      if (dLat == null || dLon == null || dLat == 0 || dLon == 0) return null;
      return (
        origenLat: oLat,
        origenLon: oLon,
        destinoLat: dLat,
        destinoLon: dLon,
        paradas: paradas,
      );
    }

    final pas = _pasajerosActivosMaps(data);
    if (pas.isEmpty) return null;
    for (int i = 0; i < pas.length - 1; i++) {
      paradas.add((lat: pas[i].lat, lon: pas[i].lon));
    }
    final ultimo = pas.last;
    return (
      origenLat: oLat,
      origenLon: oLon,
      destinoLat: ultimo.lat,
      destinoLon: ultimo.lon,
      paradas: paradas,
    );
  }

  static List<({double lat, double lon})> _pasajerosActivosMaps(
    Map<String, dynamic> data,
  ) {
    final raw = _rawPasajerosListDeMap(data);
    if (raw == null) return const [];
    final items = <({double lat, double lon, int orden})>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      if (m['activo'] == false) continue;
      final lat = (m['lat'] as num?)?.toDouble() ?? 0;
      final lon = (m['lon'] as num?)?.toDouble() ?? 0;
      if (lat == 0 || lon == 0) continue;
      final orden = (m['orden'] as num?)?.toInt() ?? 0;
      items.add((lat: lat, lon: lon, orden: orden > 0 ? orden : 999));
    }
    items.sort((a, b) => a.orden.compareTo(b.orden));
    return [for (final p in items) (lat: p.lat, lon: p.lon)];
  }

  static Future<void> abrirWazeDesdeViaje(Map<String, dynamic> data) async {
    final url = wazeUrlDe(data);
    if (url != null) {
      final uri = Uri.tryParse(url);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    final lat = (data['latCliente'] as num?)?.toDouble();
    final lon = (data['lonCliente'] as num?)?.toDouble();
    if (lat != null && lon != null && lat != 0 && lon != 0) {
      await NavegacionExternaLauncher.abrirWazeDestino(lat, lon);
    }
  }

  static List<Map<String, dynamic>> _fijasDesdeChoferDoc(
    DocumentSnapshot<Map<String, dynamic>> s,
  ) {
    if (!s.exists) return const <Map<String, dynamic>>[];
    final data = s.data() ?? <String, dynamic>{};
    final out = <Map<String, dynamic>>[];
    final keys = <String>{};

    void addMap(Map<String, dynamic> m) {
      final emp = (m['empresaId'] ?? '').toString().trim();
      final pl = (m['plantillaId'] ?? '').toString().trim();
      final key = emp.isNotEmpty && pl.isNotEmpty ? '${emp}_$pl' : '';
      if (key.isNotEmpty && keys.contains(key)) return;
      if (key.isNotEmpty) keys.add(key);
      if ((m['_key'] ?? '').toString().isEmpty && key.isNotEmpty) {
        m['_key'] = '${emp}__${pl}'.replaceAll('.', '_');
      }
      out.add(m);
    }

    final lista = data['rutasActivasLista'];
    if (lista is List) {
      for (final item in lista) {
        if (item is! Map) continue;
        addMap(Map<String, dynamic>.from(item));
      }
    }

    void addEntry(String key, dynamic v) {
      if (v is! Map) return;
      final m = Map<String, dynamic>.from(v);
      m['_key'] = key;
      addMap(m);
    }

    final raw = data['asignacionesRutas'];
    if (raw is Map) {
      raw.forEach((k, v) => addEntry(k.toString(), v));
    }

    // Firestore a veces deja claves literales "asignacionesRutas.empresa__plantilla".
    data.forEach((k, v) {
      final key = k.toString();
      if (!key.startsWith('asignacionesRutas.')) return;
      addEntry(key.replaceFirst('asignacionesRutas.', ''), v);
    });

    return out;
  }

  static Map<String, dynamic>? _fijaDesdePlantillaDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    final empresaId = doc.reference.parent.parent?.id ?? '';
    final plantillaId = doc.id;
    if (empresaId.isEmpty || plantillaId.isEmpty) return null;
    final pasajeros = d['pasajeros'];
    var nPas = 0;
    if (pasajeros is List) {
      for (final p in pasajeros) {
        if (p is Map && p['activo'] == false) continue;
        nPas++;
      }
    }
    return {
      '_key': '${empresaId}__${plantillaId}'.replaceAll('.', '_'),
      'empresaId': empresaId,
      'empresaNombre': '', // se resuelve desde empresas_corporativas/{id}
      'plantillaId': plantillaId,
      'plantillaNombre':
          (d['nombre'] ?? d['plantillaNombre'] ?? 'Ruta corporativa')
              .toString(),
      'hora': (d['horaRecogidaGrupo'] ?? d['horaRecogida'] ?? '').toString(),
      'corporativoHoraRecogidaGrupo':
          (d['horaRecogidaGrupo'] ?? d['horaRecogida'] ?? '').toString(),
      'pasajerosActivos': nPas,
      'origenLabel': (d['origenLabel'] ?? '').toString(),
      'viajeHoyId': (d['ultimoViajeId'] ?? '').toString(),
      '_desdePlantillaStream': true,
    };
  }

  static List<Map<String, dynamic>> _unificarFijas(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    final byKey = <String, Map<String, dynamic>>{};
    for (final list in [a, b]) {
      for (final m in list) {
        final emp = (m['empresaId'] ?? '').toString().trim();
        final pl = (m['plantillaId'] ?? '').toString().trim();
        if (emp.isEmpty || pl.isEmpty) continue;
        final key = '${emp}_$pl';
        final prev = byKey[key];
        byKey[key] = prev == null ? Map<String, dynamic>.from(m) : {...prev, ...m};
      }
    }
    return byKey.values.toList();
  }

  static List<Map<String, dynamic>> _overlayPlantillaEnFijas(
    List<Map<String, dynamic>> fijas,
    List<Map<String, dynamic>> plantillas,
  ) {
    if (plantillas.isEmpty) return fijas;
    final byKey = <String, Map<String, dynamic>>{};
    for (final p in plantillas) {
      final key = claveRutaCorporativo(
        (p['empresaId'] ?? '').toString(),
        (p['plantillaId'] ?? '').toString(),
      );
      if (key != '_') byKey[key] = p;
    }
    return fijas.map((f) {
      final key = claveRutaCorporativo(
        (f['empresaId'] ?? '').toString(),
        (f['plantillaId'] ?? '').toString(),
      );
      final pl = byKey[key];
      if (pl == null) return f;
      return overlayEncargadoEnFija(f, pl);
    }).toList();
  }

  static List<Map<String, dynamic>> _fusionarFijasConViajes(
    List<Map<String, dynamic>> fijasDoc,
    List<DocumentSnapshot<Map<String, dynamic>>> viajes,
  ) {
    final out = [...fijasDoc];
    final keys = <String>{
      for (final a in out)
        '${a['empresaId'] ?? ''}_${a['plantillaId'] ?? ''}',
    };
    for (final d in viajes) {
      final data = d.data() ?? <String, dynamic>{};
      final empId = (data['corporativoEmpresaId'] ?? '').toString().trim();
      final plId = (data['corporativoPlantillaId'] ?? '').toString().trim();
      if (empId.isEmpty || plId.isEmpty) continue;
      final key = '${empId}_$plId';
      final fh = data['fechaHora'];
      String horaViaje = '';
      if (fh is Timestamp) {
        final dt = fh.toDate();
        horaViaje =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      final horaContrato = horaEncargadoCorporativo(data);
      final horaMostrar = horaContrato.isNotEmpty ? horaContrato : horaViaje;
      final nPas = pasajerosCount(data);
      final origen = (data['origen'] ?? '').toString();

      final idx = out.indexWhere(
        (a) =>
            '${a['empresaId'] ?? ''}_${a['plantillaId'] ?? ''}' == key,
      );
      if (idx >= 0) {
        final horaEncargadoFija = horaEncargadoCorporativo(out[idx]);
        final horaFinal = horaEncargadoFija.isNotEmpty
            ? horaEncargadoFija
            : (horaContrato.isNotEmpty ? horaContrato : horaViaje);
        if (horaFinal.isNotEmpty) {
          out[idx]['hora'] = horaFinal;
        }
        if (horaContrato.isNotEmpty && horaEncargadoFija.isEmpty) {
          out[idx]['corporativoHoraRecogidaGrupo'] = horaContrato;
        }
        if (nPas > 0) out[idx]['pasajerosActivos'] = nPas;
        if (origen.isNotEmpty) out[idx]['origenLabel'] = origen;
        out[idx]['_viajeHoyId'] = d.id;
        out[idx]['viajeHoyId'] = d.id;
        final empNom = nombreEmpresaCorporativo(data);
        if (empNom.isNotEmpty) out[idx]['empresaNombre'] = empNom;
        continue;
      }
      if (keys.contains(key)) continue;
      keys.add(key);
      out.add({
        '_key': 'viaje_${d.id}',
        'empresaId': empId,
        'empresaNombre':
            (data['corporativoEmpresaNombre'] ?? 'Empresa').toString(),
        'plantillaId': plId,
        'plantillaNombre':
            (data['corporativoPlantillaNombre'] ?? 'Ruta corporativa')
                .toString(),
        'hora': horaMostrar,
        'corporativoHoraRecogidaGrupo':
            horaContrato.isNotEmpty ? horaContrato : horaMostrar,
        'pasajerosActivos': nPas,
        'origenLabel': origen,
        '_sinteticaDesdeViaje': true,
        '_viajeHoyId': d.id,
      });
    }
    return dedupeFijasPorPlantilla(out);
  }

  /// Rutas fijas amarradas al chofer (`chofer_operacion` + respaldos legacy).
  static Stream<List<Map<String, dynamic>>> streamAsignacionesFijas(
    String uidTaxista,
  ) {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return Stream.value(const []);
    return Stream.multi((controller) {
      Map<String, dynamic>? operacion;
      var operacionRecibida = false;
      List<Map<String, dynamic>>? fijasLegacy;
      List<Map<String, dynamic>>? fijasPlantillas;
      List<DocumentSnapshot<Map<String, dynamic>>>? viajes;

      void emit() {
        if (viajes == null) return;
        Future<void> publicar() async {
          List<Map<String, dynamic>> fijas;
          if (operacionRecibida) {
            fijas = _overlayPlantillaEnFijas(
              _rutasDesdeOperacion(operacion),
              fijasPlantillas ?? const [],
            );
            fijas = _fusionarFijasConViajes(fijas, viajes!);
          } else {
            if (fijasLegacy == null || fijasPlantillas == null) return;
            fijas = _fusionarFijasConViajes(
              _unificarFijas(fijasLegacy!, fijasPlantillas!),
              viajes!,
            );
          }
          await enriquecerNombresEmpresaEnFijas(fijas);
          if (!controller.isClosed) {
            controller.add(dedupeFijasPorPlantilla(fijas));
          }
        }
        unawaited(publicar());
      }

      fijasLegacy = const <Map<String, dynamic>>[];
      fijasPlantillas = const <Map<String, dynamic>>[];
      viajes = const <DocumentSnapshot<Map<String, dynamic>>>[];
      final subs = <StreamSubscription<dynamic>>[];
      emit();
      subs.add(
        streamOperacionChofer(uid).listen(
          (op) {
            operacion = op;
            operacionRecibida = true;
            emit();
          },
          onError: (e) {
            debugPrint('[CORP] chofer_operacion stream: $e');
            operacionRecibida = false;
            emit();
          },
        ),
      );
      subs.add(
        _db.collection('choferes_corporativos').doc(uid).snapshots().listen(
          (s) {
            if (!operacionRecibida) {
              fijasLegacy = _fijasDesdeChoferDoc(s);
              emit();
            }
          },
          onError: (e) {
            debugPrint('[CORP] choferes_corporativos stream: $e');
            if (!operacionRecibida) {
              fijasLegacy = const <Map<String, dynamic>>[];
              emit();
            }
          },
        ),
      );
      subs.add(
        _db
            .collectionGroup('plantillas_ruta')
            .where('choferPreferidoUid', isEqualTo: uid)
            .snapshots()
            .listen(
          (snap) {
            final list = <Map<String, dynamic>>[];
            for (final d in snap.docs) {
              if (d.data()['activa'] == false) continue;
              final m = _fijaDesdePlantillaDoc(d);
              if (m != null) list.add(m);
            }
            fijasPlantillas = list;
            emit();
          },
          onError: (e) {
            debugPrint('[CORP] plantillas_ruta chofer stream: $e');
            fijasPlantillas = const <Map<String, dynamic>>[];
            emit();
          },
        ),
      );
      subs.add(
        streamViajesAsignados(uid).listen(
          (docs) {
            viajes = docs;
            emit();
          },
          onError: (e) {
            debugPrint('[CORP] viajes corporativos stream: $e');
            viajes = const [];
            emit();
          },
        ),
      );
      controller.onCancel = () {
        for (final s in subs) {
          s.cancel();
        }
      };
    });
  }

  /// Viajes corporativos asignados al chofer (pendientes / en curso).
  static Stream<List<DocumentSnapshot<Map<String, dynamic>>>>
      streamViajesAsignados(String uidTaxista) {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) {
      return Stream.value(const []);
    }

    return Stream.multi((controller) {
      List<QueryDocumentSnapshot<Map<String, dynamic>>>? byUid =
          const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      List<QueryDocumentSnapshot<Map<String, dynamic>>>? byPref =
          const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      List<QueryDocumentSnapshot<Map<String, dynamic>>>? byAsignado =
          const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      final viajesEspejo =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      final viajeEspejoSubs = <String, StreamSubscription<dynamic>>{};
      DocumentSnapshot<Map<String, dynamic>>? userSnap;
      var emitSeq = 0;

      Future<void> emitMerged() async {
        final seq = ++emitSeq;
        final byId = <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final list in [
          byUid ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
          byPref ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
          byAsignado ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
        ]) {
          for (final d in list) {
            if (_viajeCorporativoVisibleParaChofer(d.data(), uid)) {
              byId[d.id] = d;
            }
          }
        }
        for (final e in viajesEspejo.entries) {
          if (!e.value.exists) continue;
          final data = e.value.data();
          if (data != null &&
              _viajeCorporativoVisibleParaChofer(data, uid)) {
            byId[e.key] = e.value;
          }
        }
        final u = userSnap?.data() ?? <String, dynamic>{};
        for (final raw in [
          u['viajeActivoId'],
          u['siguienteViajeId'],
        ]) {
          final id = (raw ?? '').toString().trim();
          if (id.isEmpty || byId.containsKey(id)) continue;
          try {
            final v = await _db.collection('viajes').doc(id).get();
            if (!v.exists) continue;
            if (_viajeCorporativoVisibleParaChofer(v.data()!, uid)) {
              byId[id] = v;
            }
          } catch (e) {
            debugPrint('[CORP] viaje usuario $id: $e');
          }
        }

        final empresaIds = <String>{};
        for (final d in byId.values) {
          final empId =
              (d.data()?['corporativoEmpresaId'] ?? '').toString().trim();
          if (empId.isNotEmpty) empresaIds.add(empId);
        }
        for (final empId in empresaIds) {
          await corporativoEmpresaIdVigente(empId);
        }
        byId.removeWhere((_, d) {
          final empId =
              (d.data()?['corporativoEmpresaId'] ?? '').toString().trim();
          if (empId.isEmpty) return false;
          return _empresaCorporativaVigenteCache[empId] == false;
        });

        for (final empId in empresaIds) {
          if (_empresaCorporativaVigenteCache[empId] == true) {
            await nombreEmpresaCorporativoPorId(empId);
          }
        }

        if (seq != emitSeq || controller.isClosed) return;
        controller.add(
          dedupeViajesHoy(_ordenarViajesCorporativos(byId.values.toList())),
        );
      }

      void syncViajeEspejoListeners(Set<String> ids) {
        final activos = ids.where((id) => id.isNotEmpty).toSet();
        for (final id in List<String>.from(viajeEspejoSubs.keys)) {
          if (activos.contains(id)) continue;
          viajeEspejoSubs[id]?.cancel();
          viajeEspejoSubs.remove(id);
          viajesEspejo.remove(id);
        }
        for (final id in activos) {
          if (viajeEspejoSubs.containsKey(id)) continue;
          viajeEspejoSubs[id] = _db
              .collection('viajes')
              .doc(id)
              .snapshots()
              .listen(
            (doc) {
              if (!doc.exists) {
                viajesEspejo.remove(id);
              } else {
                viajesEspejo[id] = doc;
              }
              emitMerged();
            },
            onError: (e) {
              debugPrint('[CORP] viaje espejo $id: $e');
            },
          );
        }
      }

      final subs = <StreamSubscription<dynamic>>[];
      emitMerged();
      subs.add(
        streamOperacionChofer(uid).listen(
          (op) {
            final ids = <String>{};
            if (op != null) {
              final viajesOp = op['viajesHoy'];
              if (viajesOp is List) {
                for (final item in viajesOp) {
                  if (item is! Map) continue;
                  final id = (item['viajeId'] ?? '').toString().trim();
                  if (id.isNotEmpty) ids.add(id);
                }
              }
              final rutas = op['rutasFijas'] ?? op['rutasActivasLista'];
              if (rutas is List) {
                for (final item in rutas) {
                  if (item is! Map) continue;
                  final id = (item['viajeHoyId'] ?? '').toString().trim();
                  if (id.isNotEmpty) ids.add(id);
                }
              }
            }
            syncViajeEspejoListeners(ids);
            emitMerged();
          },
          onError: (e) {
            debugPrint('[CORP] chofer_operacion viajes: $e');
          },
        ),
      );
      subs.add(
        _db.collection('choferes_corporativos').doc(uid).snapshots().listen(
          (s) {
            final ids = <String>{};
            final data = s.data() ?? <String, dynamic>{};
            final lista = data['rutasActivasLista'];
            if (lista is List) {
              for (final item in lista) {
                if (item is! Map) continue;
                final id = (item['viajeHoyId'] ?? '').toString().trim();
                if (id.isNotEmpty) ids.add(id);
              }
            }
            final raw = data['asignacionesRutas'];
            if (raw is Map) {
              for (final v in raw.values) {
                if (v is! Map) continue;
                final id = (v['viajeHoyId'] ?? v['_viajeHoyId'] ?? '')
                    .toString()
                    .trim();
                if (id.isNotEmpty) ids.add(id);
              }
            }
            syncViajeEspejoListeners(ids);
            emitMerged();
          },
          onError: (e) {
            debugPrint('[CORP] chofer espejo viajes: $e');
          },
        ),
      );
      subs.add(
        _db
            .collection('viajes')
            .where('uidTaxista', isEqualTo: uid)
            .limit(80)
            .snapshots()
            .listen(
          (snap) {
            byUid = snap.docs
                .where((d) => esViajeCorporativoDoc(d.data()))
                .toList();
            emitMerged();
          },
          onError: (e) {
            debugPrint('[CORP] viajes uidTaxista stream: $e');
            byUid = const [];
            emitMerged();
          },
        ),
      );
      subs.add(
        _db
            .collection('viajes')
            .where('corporativoChoferPreferidoUid', isEqualTo: uid)
            .limit(30)
            .snapshots()
            .listen(
          (snap) {
            byPref = snap.docs
                .where((d) => esViajeCorporativoDoc(d.data()))
                .toList();
            emitMerged();
          },
          onError: (e) {
            debugPrint('[CORP] viajes preferido stream: $e');
            byPref = const [];
            emitMerged();
          },
        ),
      );
      subs.add(
        _db
            .collection('viajes')
            .where('corporativoChoferAsignadoUid', isEqualTo: uid)
            .limit(30)
            .snapshots()
            .listen(
          (snap) {
            byAsignado = snap.docs
                .where((d) => esViajeCorporativoDoc(d.data()))
                .toList();
            emitMerged();
          },
          onError: (e) {
            debugPrint('[CORP] viajes asignado stream: $e');
            byAsignado = const [];
            emitMerged();
          },
        ),
      );
      subs.add(
        _db.collection('usuarios').doc(uid).snapshots().listen(
          (snap) {
            userSnap = snap;
            emitMerged();
          },
          onError: (_) {
            userSnap = null;
          },
        ),
      );
      controller.onCancel = () {
        for (final s in subs) {
          s.cancel();
        }
        for (final s in viajeEspejoSubs.values) {
          s.cancel();
        }
      };
    });
  }

  /// ID del viaje corporativo en `viajeActivoId` o `siguienteViajeId`.
  static Future<String?> idViajeCorporativoPendiente(String uidTaxista) async {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return null;
    final uSnap = await _db.collection('usuarios').doc(uid).get();
    final u = uSnap.data() ?? <String, dynamic>{};

    for (final raw in [
      (u['viajeActivoId'] ?? '').toString().trim(),
      (u['siguienteViajeId'] ?? '').toString().trim(),
    ]) {
      if (raw.isEmpty) continue;
      if (rutaCorpInformativaDismissedRecientemente(raw)) continue;
      final vSnap = await _db.collection('viajes').doc(raw).get();
      if (!vSnap.exists) continue;
      final d = vSnap.data() ?? <String, dynamic>{};
      if (esViajeCorporativoAsignado(d, uid) &&
          !viajeCorporativoInformativoCerradoParaChofer(d) &&
          estadoPermiteVerViajeCorporativo(d)) {
        return raw;
      }
    }

    try {
      final opSnap = await _db.collection('chofer_operacion').doc(uid).get();
      final op = opSnap.data();
      if (op != null) {
        final viajesHoy = op['viajesHoy'];
        if (viajesHoy is List) {
          for (final item in viajesHoy) {
            if (item is! Map) continue;
            final m = Map<String, dynamic>.from(item);
            if (m['completadoHoy'] == true) continue;
            if ((m['estadoOperacion'] ?? '').toString() == 'completado') {
              continue;
            }
            if (m['listoParaAbrir'] != true) continue;
            final id = (m['viajeId'] ?? '').toString().trim();
            if (id.isEmpty) continue;
            if (rutaCorpInformativaDismissedRecientemente(id)) continue;
            final vSnap = await _db.collection('viajes').doc(id).get();
            if (!vSnap.exists) continue;
            final d = vSnap.data() ?? <String, dynamic>{};
            if (esViajeCorporativoAsignado(d, uid) &&
                !viajeCorporativoInformativoCerradoParaChofer(d) &&
                estadoPermiteVerViajeCorporativo(d)) {
              return id;
            }
          }
        }
        final rutas = op['rutasFijas'] ?? op['rutasActivasLista'];
        if (rutas is List) {
          for (final item in rutas) {
            if (item is! Map) continue;
            final m = Map<String, dynamic>.from(item);
            if (m['completadoHoy'] == true) continue;
            if ((m['estadoOperacion'] ?? '').toString() == 'completado') {
              continue;
            }
            if (m['listoParaAbrir'] != true) continue;
            final id = (m['viajeHoyId'] ?? '').toString().trim();
            if (id.isEmpty) continue;
            if (rutaCorpInformativaDismissedRecientemente(id)) continue;
            final vSnap = await _db.collection('viajes').doc(id).get();
            if (!vSnap.exists) continue;
            final d = vSnap.data() ?? <String, dynamic>{};
            if (esViajeCorporativoAsignado(d, uid) &&
                !viajeCorporativoInformativoCerradoParaChofer(d) &&
                estadoPermiteVerViajeCorporativo(d)) {
              return id;
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }

  static CorporativoAbrirResultado _mapResultadoAbrirCorporativo(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'ok':
        return CorporativoAbrirResultado.ok;
      case 'otro_viaje_activo':
        return CorporativoAbrirResultado.otroViajeActivo;
      case 'no_encontrado':
        return CorporativoAbrirResultado.noEncontrado;
      case 'aun_no_es_hora':
        return CorporativoAbrirResultado.aunNoEsHora;
      default:
        return CorporativoAbrirResultado.error;
    }
  }

  /// Promueve el viaje corporativo a activo, o lo deja en cola si hay otro activo.
  static Future<CorporativoAbrirResultado> abrirViajeCorporativoEnCurso({
    required String uidTaxista,
    String? viajeId,
  }) async {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return CorporativoAbrirResultado.error;

    await ViajesRepo.limpiarViajeActivoSiNoOperativo(uid);

    final resolvedId = (viajeId ?? '').trim().isNotEmpty
        ? viajeId!.trim()
        : await idViajeCorporativoPendiente(uid);
    if (resolvedId == null || resolvedId.isEmpty) {
      return CorporativoAbrirResultado.noEncontrado;
    }

    final id = resolvedId;

    final opListo = await choferOperacionMarcaListo(uid, id);

    try {
      final vSnap = await _db.collection('viajes').doc(id).get();
      if (vSnap.exists) {
        final v = vSnap.data() ?? <String, dynamic>{};
        if (esViajeCorporativoAsignado(v, uid) && esModoInformativo(v)) {
          return CorporativoAbrirResultado.ok;
        }
      }
    } catch (_) {}

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('taxistaAbrirViajeCorporativoEnCurso');
      final res = await callable.call<Map<String, dynamic>>({
        'viajeId': id,
      });
      final data = Map<String, dynamic>.from(res.data ?? const {});
      final resultado = _mapResultadoAbrirCorporativo(
        (data['resultado'] ?? '').toString(),
      );
      if (resultado == CorporativoAbrirResultado.ok ||
          resultado == CorporativoAbrirResultado.otroViajeActivo ||
          resultado == CorporativoAbrirResultado.noEncontrado) {
        return resultado;
      }
      if (resultado == CorporativoAbrirResultado.aunNoEsHora && !opListo) {
        return resultado;
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[CORP] taxistaAbrirViajeCorporativoEnCurso ${e.code}: ${e.message}',
      );
      if (e.code == 'not-found' || e.code == 'failed-precondition') {
        return CorporativoAbrirResultado.noEncontrado;
      }
      if (e.code == 'unauthenticated') {
        return CorporativoAbrirResultado.error;
      }
    } catch (e) {
      debugPrint('[CORP] callable abrir corporativo falló: $e');
    }

    try {
      var resultado = CorporativoAbrirResultado.ok;
      await _db.runTransaction((tx) async {
        final vRef = _db.collection('viajes').doc(id);
        final uRef = _db.collection('usuarios').doc(uid);
        final vSnap = await tx.get(vRef);
        final uSnap = await tx.get(uRef);
        if (!vSnap.exists) {
          resultado = CorporativoAbrirResultado.noEncontrado;
          return;
        }

        final v = vSnap.data() ?? <String, dynamic>{};
        if (!esViajeCorporativoAsignado(v, uid)) {
          resultado = CorporativoAbrirResultado.noEncontrado;
          return;
        }
        if (!estadoPermiteVerViajeCorporativo(v)) {
          resultado = CorporativoAbrirResultado.noEncontrado;
          return;
        }
        if (!corporativoListoParaAbrirEnCurso(
              v,
              listoSegunOperacion: opListo,
            )) {
          resultado = CorporativoAbrirResultado.aunNoEsHora;
          return;
        }

        final activoOtro =
            (uSnap.data()?['viajeActivoId'] ?? '').toString().trim();
        if (activoOtro.isNotEmpty && activoOtro != id) {
          final otroSnap = await tx.get(_db.collection('viajes').doc(activoOtro));
          final otroData = otroSnap.data() ?? <String, dynamic>{};
          final otroVigente = otroSnap.exists &&
              ViajesRepo.viajeOperativoBloqueanteParaTaxista(otroData, uid);
          if (otroVigente) {
            tx.set(uRef, {
              'siguienteViajeId': id,
              'updatedAt': FieldValue.serverTimestamp(),
              'actualizadoEn': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            resultado = CorporativoAbrirResultado.otroViajeActivo;
            return;
          }
          tx.set(uRef, {
            'viajeActivoId': '',
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        tx.set(vRef, {
          'activo': true,
          'aceptado': true,
          'estado': EstadosViaje.aceptado,
          'uidTaxista': uid,
          'taxistaId': uid,
          'rechazado': false,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        tx.set(uRef, {
          'viajeActivoId': id,
          'siguienteViajeId': '',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        resultado = CorporativoAbrirResultado.ok;
      });
      return resultado;
    } catch (e) {
      debugPrint('[CORP] transacción abrir corporativo falló: $e');
      return CorporativoAbrirResultado.error;
    }
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    final s = (v ?? '').toString();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static double _toDouble(dynamic v) {
    if (v is num && v.isFinite) return v.toDouble();
    return double.tryParse((v ?? '').toString()) ?? 0;
  }

  static double _netoChoferDesdeViaje(Map<String, dynamic> d) {
    final extras = d['extras'];
    if (extras is Map) {
      final desglose = extras['corporativoTarifaDesglose'];
      if (desglose is Map) {
        final pago = _toDouble(desglose['pagoChoferRd']);
        if (pago > 0) return pago;
      }
    }
    final estimado = _toDouble(d['corporativoPagoChoferEstimadoRd']);
    if (estimado > 0) return estimado;
    final ganancia = _toDouble(d['gananciaTaxista']);
    if (ganancia > 0) return ganancia;
    final gc = _toDouble(d['ganancia_cents']);
    if (gc > 0) return gc / 100.0;
    final total = _toDouble(
      d['precioFinal'] ?? d['precio'] ?? d['total'] ?? 0,
    );
    if (total > 0) {
      return PlataformaEconomia.gananciaTaxistaRdDesdeTotal(total);
    }
    return 0;
  }

  /// Resumen de pago corporativo para mostrar al chofer durante/fin de ruta.
  static CorporativoChoferPagoResumen? resumenPagoChofer({
    required Map<String, dynamic> viaje,
    required String uidTaxista,
    Map<String, dynamic>? operacionChofer,
  }) {
    final empresaId =
        (viaje['corporativoEmpresaId'] ?? '').toString().trim();
    if (empresaId.isEmpty) return null;

    final empresaNombre =
        (viaje['corporativoEmpresaNombre'] ?? 'Empresa').toString().trim();

    Map<String, dynamic>? resumenEmpresa;
    final rawResumen = operacionChofer?['resumenPagoEmpresas'];
    if (rawResumen is Map) {
      final row = rawResumen[empresaId];
      if (row is Map) {
        resumenEmpresa = Map<String, dynamic>.from(row);
      }
    }

    final viajeYaContabilizado = viaje['corporativoContabilizado'] == true ||
        viaje['completado'] == true;

    var acumulado = _toDouble(viaje['corporativoChoferAcumuladoPeriodoRd']);
    var viajesPeriodo =
        (viaje['corporativoChoferViajesPeriodo'] as num?)?.toInt() ?? 0;

    if (resumenEmpresa != null) {
      acumulado = _toDouble(resumenEmpresa['acumuladoRd']);
      viajesPeriodo = (resumenEmpresa['viajesCount'] as num?)?.toInt() ??
          viajesPeriodo;
    }

    if (viajeYaContabilizado && acumulado <= 0) {
      acumulado = _toDouble(viaje['corporativoChoferAcumuladoPeriodoRd']);
    }

    final periodoFin = _ts(
      resumenEmpresa?['periodoFin'] ?? viaje['corporativoPeriodoFin'],
    );
    final periodoInicio = _ts(
      resumenEmpresa?['periodoInicio'] ?? viaje['corporativoPeriodoInicio'],
    );
    final ciclo = CorporativoCicloFacturacion.normalizarDias(
      (resumenEmpresa?['cicloDias'] as num?)?.toInt() ??
          (viaje['corporativoFacturacionCicloDias'] as num?)?.toInt(),
    );

    return CorporativoChoferPagoResumen(
      empresaId: empresaId,
      empresaNombre: empresaNombre,
      netoEsteViajeRd: _netoChoferDesdeViaje(viaje),
      acumuladoPeriodoRd: acumulado,
      viajesCompletadosPeriodo: viajesPeriodo,
      periodoInicio: periodoInicio,
      periodoFin: periodoFin,
      cicloDias: ciclo,
      viajeYaContabilizado: viajeYaContabilizado,
    );
  }
}
