import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/servicios/corporativo_chofer_perfil_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_tarifa_config_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_tarifa_modelos.dart';
import 'package:flygo_nuevo/servicios/navegacion_externa_launcher.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/corporativo_ciclo_facturacion.dart';
import 'package:flygo_nuevo/utils/corporativo_hora_encargado.dart';
import 'package:flygo_nuevo/utils/corporativo_recurrencia_helper.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/hora_am_pm.dart';
import 'package:flygo_nuevo/utils/multiparada_ruta_helper.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

/// CRUD plantillas corporativas, rutas guardadas y lanzamiento multiparada.
abstract final class CorporativoRutaService {
  CorporativoRutaService._();

  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _empresas =>
      _db.collection('empresas_corporativas');

  static CollectionReference<Map<String, dynamic>> _plantillas(String empresaId) =>
      _empresas.doc(empresaId).collection('plantillas_ruta');

  static CollectionReference<Map<String, dynamic>> _historial(String empresaId) =>
      _empresas.doc(empresaId).collection('historial');

  /// Canal de asignación exclusiva al chofer fijo de la ruta.
  static const String canalCorporativoFijo = 'corporativo_fijo';

  static Stream<CorporativoEmpresa?> streamEmpresa(String empresaId) {
    return _empresas.doc(empresaId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return CorporativoEmpresa.fromDoc(snap);
    });
  }

  static Future<String?> empresaIdDelUsuario(String uid) async {
    try {
      final snap = await _db.collection('usuarios').doc(uid).get();
      final id = (snap.data()?['empresaCorporativaId'] ?? '').toString().trim();
      if (id.isNotEmpty) return id;
    } catch (_) {
      // Sin doc o sin permiso: seguimos con query por encargadoUids.
    }

    try {
      final q = await _empresas
          .where('encargadoUids', arrayContains: uid)
          .limit(1)
          .get();
      if (q.docs.isEmpty) return null;
      return q.docs.first.id;
    } catch (_) {
      // Query bloqueada o sin empresa → no habilitado (no tumbar el hub).
      return null;
    }
  }

  /// Encargado habilitado por RAI (vinculado en `encargadoUids` de la empresa).
  static Future<bool> esEncargadoHabilitado(String uid) async {
    try {
      final empresaId = await empresaIdDelUsuario(uid);
      if (empresaId == null) return false;
      final empresa = await cargarEmpresa(empresaId);
      if (empresa == null) return false;
      return empresa.encargadoUids.contains(uid);
    } catch (_) {
      return false;
    }
  }

  static Future<CorporativoEmpresa?> cargarEmpresa(
    String empresaId, {
    bool fromServer = false,
  }) async {
    try {
      final snap = await _empresas.doc(empresaId).get(
            fromServer
                ? const GetOptions(source: Source.server)
                : const GetOptions(),
          );
      if (!snap.exists) return null;
      return CorporativoEmpresa.fromDoc(snap);
    } catch (_) {
      return null;
    }
  }

  static String _generarCodigoAccesoPeriodo() {
    final n = 100000 + math.Random().nextInt(900000);
    return n.toString();
  }

  /// Código único del período de liquidación (mismo todos los días hasta el pago).
  /// Solo lectura en app encargado: escribir `periodoActual` lo hace Admin/Cloud Functions.
  static Future<String> codigoAccesoPeriodoEmpresa(String empresaId) async {
    return leerCodigoAccesoPeriodoEmpresa(empresaId);
  }

  /// Lee el código del período sin escribir en Firestore (evita permission-denied).
  static Future<String> leerCodigoAccesoPeriodoEmpresa(String empresaId) async {
    final id = empresaId.trim();
    if (id.isEmpty) return '';
    try {
      final snap = await _empresas.doc(id).get();
      if (!snap.exists) return '';
      final data = snap.data() ?? {};
      final rawPeriodo = data['periodoActual'];
      final periodo = rawPeriodo is Map
          ? Map<String, dynamic>.from(rawPeriodo)
          : <String, dynamic>{};
      final codigo = (periodo['codigoAcceso'] ?? '')
          .toString()
          .replaceAll(RegExp(r'\D'), '');
      return codigo.length == 6 ? codigo : '';
    } catch (e) {
      debugPrint('[CORP] leer codigo periodo: $e');
      return '';
    }
  }

  /// Si el usuario tiene un vínculo viejo o inválido, lo limpia para permitir un alta nueva.
  static Future<String?> _empresaVinculadaValida(String uidEncargado) async {
    final uid = uidEncargado.trim();
    if (uid.isEmpty) return null;
    final candidato = await empresaIdDelUsuario(uid);
    final empresaId = (candidato ?? '').trim();
    if (empresaId.isEmpty) return null;

    final empresa = await cargarEmpresa(empresaId);
    if (empresa != null && empresa.encargadoUids.contains(uid)) {
      return empresaId;
    }

    await _limpiarVinculoEmpresaUsuario(
      uidEncargado: uid,
      empresaId: empresaId,
    );
    return null;
  }

  static Future<void> _limpiarVinculoEmpresaUsuario({
    required String uidEncargado,
    required String empresaId,
  }) async {
    try {
      final snap = await _db.collection('usuarios').doc(uidEncargado).get();
      if (!snap.exists) return;
      final actual =
          (snap.data()?['empresaCorporativaId'] ?? '').toString().trim();
      if (actual != empresaId.trim()) return;
      await _db.collection('usuarios').doc(uidEncargado).set({
        'empresaCorporativaId': FieldValue.delete(),
        'empresaCorporativaNombre': FieldValue.delete(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[CORP] limpiar vínculo empresa: $e');
    }
  }

  static Future<String> registrarEmpresa({
    required String uidEncargado,
    required String nombreEmpresa,
    String tipoDocumento = 'rnc',
    String documentoLegal = '',
    String telefonoEmpresa = '',
    String emailEmpresa = '',
    String direccion = '',
    int facturacionCicloDias = 15,
  }) async {
    final existente = await _empresaVinculadaValida(uidEncargado);
    if (existente != null && existente.isNotEmpty) {
      return existente;
    }

    final ref = _empresas.doc();
    final ahora = DateTime.now();
    final inicioDia = DateTime(ahora.year, ahora.month, ahora.day);
    final finPeriodo = CorporativoCicloFacturacion.finPeriodoDiasCobrables(
      inicio: inicioDia,
      cicloDias: facturacionCicloDias,
    );
    final codigoAcceso = _generarCodigoAccesoPeriodo();

    Map<String, dynamic> perfilEncargado = {'uid': uidEncargado};
    try {
      final uSnap = await _db.collection('usuarios').doc(uidEncargado).get();
      if (uSnap.exists) {
        final u = uSnap.data() ?? {};
        perfilEncargado = {
          'uid': uidEncargado,
          'nombre': (u['nombre'] ?? u['displayName'] ?? '').toString().trim(),
          'cedula': (u['cedula'] ?? u['ciTaxista'] ?? '').toString().trim(),
          'telefono': (u['telefono'] ?? '').toString().trim(),
          'email': (u['email'] ?? '').toString().trim(),
        };
      }
    } catch (_) {}

    try {
      await ref.set({
        'nombre': nombreEmpresa.trim(),
        'encargadoUids': [uidEncargado],
        if (tipoDocumento.isNotEmpty) 'tipoDocumento': tipoDocumento,
        if (documentoLegal.trim().isNotEmpty) 'documentoLegal': documentoLegal.trim(),
        if (telefonoEmpresa.trim().isNotEmpty) 'telefonoEmpresa': telefonoEmpresa.trim(),
        if (emailEmpresa.trim().isNotEmpty) 'emailEmpresa': emailEmpresa.trim(),
        if (direccion.trim().isNotEmpty) 'direccion': direccion.trim(),
        'encargadosPerfil': {uidEncargado: perfilEncargado},
        'facturacionCicloDias': facturacionCicloDias,
        'activa': true,
        'contratoActivo': false,
        'servicioTipo': 'ruta_fija_contratada',
        'periodoActual': {
          'inicio': Timestamp.fromDate(inicioDia),
          'fin': Timestamp.fromDate(finPeriodo),
          'cicloDiasCobrables': facturacionCicloDias,
          'modoFin': 'dias_cobrables',
          'viajesCount': 0,
          'montoTotalRd': 0,
          'porChofer': <String, dynamic>{},
          'codigoAcceso': codigoAcceso,
        },
        'creadoEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw 'No tienes permiso para crear la empresa. '
            'Probá cerrar sesión, volver a entrar y reintentar.';
      }
      rethrow;
    }

    CorporativoEmpresa? verificada;
    for (var i = 0; i < 5; i++) {
      verificada = await cargarEmpresaEncargado(
        ref.id,
        uidEncargado: uidEncargado,
        recienCreada: true,
      );
      if (verificada != null) break;
      if (i < 4) {
        await Future<void>.delayed(Duration(milliseconds: 300 * (i + 1)));
      }
    }
    if (verificada == null) {
      throw 'La empresa se guardó pero aún no se puede abrir. '
          'Esperá unos segundos y tocá «Reintentar».';
    }

    await _vincularUsuarioEmpresaCorporativa(
      uidEncargado: uidEncargado,
      empresaId: ref.id,
      nombreEmpresa: nombreEmpresa.trim(),
    );
    return ref.id;
  }

  static Future<void> _vincularUsuarioEmpresaCorporativa({
    required String uidEncargado,
    required String empresaId,
    required String nombreEmpresa,
  }) async {
    try {
      await _db.collection('usuarios').doc(uidEncargado).set({
        'empresaCorporativaId': empresaId,
        'empresaCorporativaNombre': nombreEmpresa,
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // El hub también resuelve por encargadoUids; no tumbar el alta.
    }
  }

  /// Tras crear o conocer el id: carga empresa del encargado (con reintento corto).
  static Future<CorporativoEmpresa?> cargarEmpresaEncargado(
    String empresaId, {
    bool fromServer = true,
    String? uidEncargado,
    bool recienCreada = false,
  }) async {
    final id = empresaId.trim();
    if (id.isEmpty) return null;
    final uid = (uidEncargado ?? '').trim();
    for (var i = 0; i < 5; i++) {
      final usarServidor = recienCreada
          ? i >= 2
          : (fromServer && i > 0);
      final emp = await cargarEmpresa(id, fromServer: usarServidor);
      if (emp != null) {
        if (uid.isEmpty || emp.encargadoUids.contains(uid)) return emp;
        return null;
      }
      if (i < 4) {
        await Future<void>.delayed(Duration(milliseconds: 300 * (i + 1)));
      }
    }
    return null;
  }

  /// Encargado: actualiza datos básicos de la empresa (nombre, documento, contacto).
  static Future<void> actualizarDatosEmpresa({
    required String empresaId,
    required String nombreEmpresa,
    String? tipoDocumento,
    String? documentoLegal,
    String? telefonoEmpresa,
    String? emailEmpresa,
    String? direccion,
  }) async {
    final nombre = nombreEmpresa.trim();
    if (nombre.length < 2) {
      throw 'Escribe el nombre de la empresa.';
    }
    final patch = <String, dynamic>{
      'nombre': nombre,
      'actualizadoEn': FieldValue.serverTimestamp(),
    };
    if (tipoDocumento != null && tipoDocumento.trim().isNotEmpty) {
      patch['tipoDocumento'] = tipoDocumento.trim();
    }
    if (documentoLegal != null) {
      patch['documentoLegal'] = documentoLegal.trim();
    }
    if (telefonoEmpresa != null) {
      patch['telefonoEmpresa'] = telefonoEmpresa.trim();
    }
    if (emailEmpresa != null) {
      patch['emailEmpresa'] = emailEmpresa.trim();
    }
    if (direccion != null) {
      patch['direccion'] = direccion.trim();
    }
    await _empresas.doc(empresaId).update(patch);
    try {
      final emp = await _empresas.doc(empresaId).get();
      final uids = List<String>.from(
        (emp.data()?['encargadoUids'] as List?) ?? const [],
      );
      for (final uid in uids) {
        await _db.collection('usuarios').doc(uid).set({
          'empresaCorporativaNombre': nombre,
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  /// Encargado: sube o reemplaza el logo de la empresa (callable + logoUrl).
  static Future<String> subirLogoEmpresa({
    required String empresaId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final id = empresaId.trim();
    if (id.isEmpty) throw 'Empresa inválida.';
    if (bytes.isEmpty) throw 'La imagen está vacía.';
    if (bytes.length > 3 * 1024 * 1024) {
      throw 'El logo debe pesar menos de 3 MB. Elegí una imagen más liviana.';
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw 'Tu sesión expiró. Volvé a entrar e intentá de nuevo.';
    }

    await user.getIdToken(true);
    final mime = contentType.trim().isNotEmpty ? contentType.trim() : 'image/jpeg';
    try {
      final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('encargadoSubirLogoEmpresa')
          .call(<String, dynamic>{
        'empresaId': id,
        'imageBase64': base64Encode(bytes),
        'contentType': mime,
      });
      final data = res.data;
      final url = data is Map ? (data['url'] ?? '').toString().trim() : '';
      if (url.isEmpty) {
        throw 'No se pudo obtener la URL del logo. Intentá de nuevo.';
      }
      return url;
    } on FirebaseFunctionsException catch (e) {
      throw e.message ?? 'No se pudo subir el logo. Intentá de nuevo.';
    }
  }

  /// Encargado: quita el logo de la empresa (solo Firestore).
  static Future<void> quitarLogoEmpresa(String empresaId) async {
    final id = empresaId.trim();
    if (id.isEmpty) throw 'Empresa inválida.';
    await _empresas.doc(id).update({
      'logoUrl': FieldValue.delete(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    });
  }

  /// Encargado: frecuencia de corte + forma preferida de pago a RAI.
  /// No modifica el período abierto; el ciclo aplica al próximo corte.
  static Future<void> actualizarCondicionesPagoRai({
    required String empresaId,
    required int facturacionCicloDias,
    required String formaPagoRai,
  }) async {
    final id = empresaId.trim();
    if (id.isEmpty) throw 'Empresa inválida.';
    final ciclo =
        CorporativoCicloFacturacion.normalizarDias(facturacionCicloDias);
    final forma = formaPagoRai.trim().toLowerCase();
    if (forma.isEmpty || !CorporativoCicloFacturacion.formaPagoValida(forma)) {
      throw 'Elegí una forma de pago válida.';
    }
    // int explícito: evita que reglas/lectura traten el ciclo como decimal.
    await _empresas.doc(id).update({
      'facturacionCicloDias': ciclo,
      'formaPagoRai': forma,
      'actualizadoEn': FieldValue.serverTimestamp(),
    });
  }

  static Stream<List<CorporativoPlantilla>> streamPlantillas(String empresaId) {
    return _plantillas(empresaId)
        .orderBy('actualizadoEn', descending: true)
        .snapshots()
        .map((snap) {
          final out = <CorporativoPlantilla>[];
          for (final d in snap.docs) {
            try {
              out.add(CorporativoPlantilla.fromDoc(d));
            } catch (_) {
              // Un doc mal formado no debe tumbar toda la pantalla ADM.
            }
          }
          return out;
        });
  }

  static Stream<CorporativoPlantilla?> streamPlantilla(
    String empresaId,
    String plantillaId,
  ) {
    return _plantillas(empresaId).doc(plantillaId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return CorporativoPlantilla.fromDoc(snap);
    });
  }

  static Future<CorporativoPlantilla?> cargarPlantilla(
    String empresaId,
    String plantillaId,
  ) async {
    final snap = await _plantillas(empresaId).doc(plantillaId).get();
    if (!snap.exists) return null;
    return CorporativoPlantilla.fromDoc(snap);
  }

  static Stream<List<Map<String, dynamic>>> streamHistorial(String empresaId) {
    return _historial(empresaId)
        .orderBy('creadoEn', descending: true)
        .limit(80)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) {
              final m = Map<String, dynamic>.from(d.data());
              m['_id'] = d.id;
              return m;
            })
            .where((m) => m['archivado'] != true && m['ocultoEncargado'] != true)
            .toList(growable: false));
  }

  /// Rutas ya cobradas / período cerrado (colapsadas en Historial).
  static Stream<List<Map<String, dynamic>>> streamHistorialArchivado(
    String empresaId,
  ) {
    return _historial(empresaId)
        .orderBy('creadoEn', descending: true)
        .limit(80)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) {
              final m = Map<String, dynamic>.from(d.data());
              m['_id'] = d.id;
              return m;
            })
            .where((m) => m['archivado'] == true && m['ocultoEncargado'] != true)
            .toList(growable: false));
  }

  /// Viajes corporativos publicados hoy (desde historial).
  static Stream<List<Map<String, dynamic>>> streamHistorialHoy(String empresaId) {
    return streamHistorial(empresaId).map(filtrarHistorialHoy);
  }

  static DateTime? _fechaHistorial(dynamic ts) {
    if (ts is Timestamp) return ts.toDate().toLocal();
    return null;
  }

  /// Filas de historial cuya recogida cae en el día local actual.
  static List<Map<String, dynamic>> filtrarHistorialHoy(
    List<Map<String, dynamic>> items,
  ) {
    final now = DateTime.now();
    final inicio = DateTime(now.year, now.month, now.day);
    final fin = inicio.add(const Duration(days: 1));
    return items.where((h) {
      final dt = _fechaHistorial(h['fechaRecogida']);
      if (dt == null) return false;
      return !dt.isBefore(inicio) && dt.isBefore(fin);
    }).toList(growable: false);
  }

  /// Último envío de hoy por plantilla (evita duplicar tarjetas en «Rutas de hoy»).
  static Map<String, Map<String, dynamic>> ultimoHistorialPorPlantilla(
    List<Map<String, dynamic>> historialHoy,
  ) {
    final map = <String, Map<String, dynamic>>{};
    for (final h in historialHoy) {
      final pid = (h['plantillaId'] ?? '').toString().trim();
      if (pid.isEmpty) continue;
      final prev = map[pid];
      if (prev == null || _historialEsMasReciente(h, prev)) {
        map[pid] = h;
      }
    }
    return map;
  }

  static bool _historialEsMasReciente(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final ta =
        _fechaHistorial(a['creadoEn']) ?? _fechaHistorial(a['fechaRecogida']);
    final tb =
        _fechaHistorial(b['creadoEn']) ?? _fechaHistorial(b['fechaRecogida']);
    if (ta == null) return false;
    if (tb == null) return true;
    return ta.isAfter(tb);
  }

  /// Envíos de hoy que no están en el panel «Rutas de hoy» (p. ej. rutas puntuales).
  static List<Map<String, dynamic>> historialHoyFueraDePanel(
    List<Map<String, dynamic>> historialHoy,
    Set<String> plantillaIdsEnPanel,
  ) {
    final ultimos = ultimoHistorialPorPlantilla(historialHoy);
    final lista = ultimos.values.where((h) {
      final pid = (h['plantillaId'] ?? '').toString().trim();
      return pid.isEmpty || !plantillaIdsEnPanel.contains(pid);
    }).toList(growable: false);
    lista.sort((a, b) {
      final ta = _fechaHistorial(a['fechaRecogida']);
      final tb = _fechaHistorial(b['fechaRecogida']);
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
    return lista;
  }

  static int contarEnviosHoyPlantilla(
    List<Map<String, dynamic>> historialHoy,
    String plantillaId,
  ) {
    final pid = plantillaId.trim();
    if (pid.isEmpty) return 0;
    return historialHoy
        .where((h) => (h['plantillaId'] ?? '').toString().trim() == pid)
        .length;
  }

  /// ¿La plantilla fija opera hoy según su recurrencia y pausas feriado?
  static bool correHoy(CorporativoPlantilla pl, {DateTime? dia}) {
    if (!pl.activa || !pl.esFijo) return false;
    final d = dia ?? DateTime.now();
    if (!servicioIniciado(pl, dia: d)) return false;
    if (esDiaPausaFeriado(pl, d)) return false;
    return coincidePatronDia(pl, dia: d);
  }

  /// Solo patrón de días (ignora pausa total y feriado).
  static bool coincidePatronDia(CorporativoPlantilla pl, {DateTime? dia}) {
    if (!pl.esFijo) return false;
    final d = dia ?? DateTime.now();
    final ancla = pl.fechaAnclaInterdiaria != null
        ? DateTime.tryParse(pl.fechaAnclaInterdiaria!)
        : null;
    return CorporativoPatronRecurrencia.coincideHoy(
      patron: pl.patronRecurrencia,
      diasSemana: pl.diasSemana,
      fechaAnclaInterdiaria: ancla,
      hoy: d,
    );
  }

  static String claveDia(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// La ruta no publica ni opera antes de esta fecha (yyyy-MM-dd en plantilla).
  static bool servicioIniciado(CorporativoPlantilla pl, {DateTime? dia}) {
    final DateTime? inicio =
        CorporativoCicloFacturacion.parseFechaCalendario(pl.fechaInicioServicio);
    if (inicio == null) return true;
    final DateTime d = dia ?? DateTime.now();
    final DateTime hoy = DateTime(d.year, d.month, d.day);
    return !hoy.isBefore(inicio);
  }

  static String etiquetaInicioServicio(CorporativoPlantilla pl) {
    final DateTime? inicio =
        CorporativoCicloFacturacion.parseFechaCalendario(pl.fechaInicioServicio);
    if (inicio == null) return 'Desde hoy';
    return DateFormat('EEE d MMM yyyy', 'es').format(inicio);
  }

  static bool esDiaPausaFeriado(CorporativoPlantilla pl, DateTime d) =>
      pl.diasPausaFeriado.contains(claveDia(d));

  /// Estado compacto para chips en lista / panel hoy.
  static String estadoChipHoy(CorporativoPlantilla pl) {
    if (!pl.activa) return 'pausada';
    if (esDiaPausaFeriado(pl, DateTime.now())) return 'feriado';
    if (pl.pasajerosActivos.isEmpty) return 'sin_pasajeros';
    if (correHoy(pl)) return 'programa';
    return 'no_hoy';
  }

  /// Resumen legible para el encargado.
  static String resumenEstadoOperativo(CorporativoPlantilla pl) {
    if (!pl.activa) {
      return 'Pausada · no se publica ni se busca el grupo hasta reactivar';
    }
    final hoy = DateTime.now();
    if (!servicioIniciado(pl, dia: hoy)) {
      return 'Inicia el ${etiquetaInicioServicio(pl)} · aún no opera';
    }
    if (esDiaPausaFeriado(pl, hoy)) {
      return 'Hoy feriado · no se busca el grupo';
    }
    if (pl.diasPausaFeriado.isNotEmpty) {
      return '${pl.diasPausaFeriado.length} día(s) feriado marcados';
    }
    if (pl.pasajerosActivos.isEmpty) {
      return 'Sin pasajeros activos · no hay quien buscar';
    }
    if (correHoy(pl)) return 'Opera hoy · se busca el grupo';
    return 'No opera hoy (según horario de la ruta)';
  }

  /// Hora de recogida de hoy si la ruta opera hoy.
  static DateTime? recogidaHoy(CorporativoPlantilla pl) {
    if (!correHoy(pl)) return null;
    return horaRecogidaEnDia(pl, DateTime.now());
  }

  /// Para «Enviar ahora»: si la hora de hoy ya pasó, recogida en ~15 min.
  static DateTime fechaRecogidaParaPublicarAhora(CorporativoPlantilla pl) {
    final ahora = DateTime.now();
    final programada = recogidaHoy(pl) ?? ahora.add(const Duration(hours: 1));
    if (programada.isBefore(ahora.subtract(const Duration(minutes: 5)))) {
      return ahora.add(const Duration(minutes: 15));
    }
    return programada;
  }

  /// Hora programada del día (aunque esté pausada / feriado).
  static DateTime? horaRecogidaEnDia(CorporativoPlantilla pl, DateTime dia) {
    final norm = normalizarHoraHHmm(pl.horaRecogidaGrupo) ?? '07:00';
    final parts = norm.split(':');
    final h = int.tryParse(parts.first) ?? 7;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(dia.year, dia.month, dia.day, h, m);
  }

  /// Rutas del panel «Hoy»: coinciden por patrón (operan, feriado o pausadas).
  static List<CorporativoPlantilla> plantillasPanelHoy(
    List<CorporativoPlantilla> todas,
  ) {
    final hoy = DateTime.now();
    return todas.where((pl) {
      if (!pl.esFijo) return false;
      return coincidePatronDia(pl, dia: hoy);
    }).toList(growable: false);
  }

  /// Días feriado a mostrar en la tarjeta (hoy y futuros; si no hay, los últimos).
  static List<String> proximosFeriados(
    CorporativoPlantilla pl, {
    int max = 8,
  }) {
    if (pl.diasPausaFeriado.isEmpty) return const [];
    final hoy = claveDia(DateTime.now());
    final futuros =
        pl.diasPausaFeriado.where((d) => d.compareTo(hoy) >= 0).toList()
          ..sort();
    if (futuros.isNotEmpty) {
      return futuros.length <= max
          ? futuros
          : futuros.take(max).toList(growable: false);
    }
    final todos = [...pl.diasPausaFeriado]..sort();
    if (todos.length <= max) return todos;
    return todos.sublist(todos.length - max);
  }

  static List<CorporativoPlantilla> plantillasProgramadasHoy(
    List<CorporativoPlantilla> todas,
  ) {
    return todas
        .where((pl) => correHoy(pl) && pl.pasajerosActivos.isNotEmpty)
        .toList(growable: false);
  }

  static Stream<List<Map<String, dynamic>>> streamLiquidaciones(String empresaId) {
    return _empresas
        .doc(empresaId)
        .collection('liquidaciones')
        .orderBy('creadoEn', descending: true)
        .limit(24)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final m = Map<String, dynamic>.from(d.data());
              m['_id'] = d.id;
              return m;
            }).toList());
  }

  static Stream<List<Map<String, dynamic>>> streamLiquidacionesPendientes(
    String empresaId,
  ) {
    return streamLiquidaciones(empresaId).map(
      (items) => items
          .where(
            (lq) =>
                (lq['estado'] ?? '').toString().trim().toLowerCase() ==
                'pendiente_cobro',
          )
          .toList(growable: false),
    );
  }

  static DateTime? _tsToDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static double sumaLiquidacionesPendientes(
    List<Map<String, dynamic>> liquidaciones,
  ) {
    var total = 0.0;
    for (final lq in liquidaciones) {
      if ((lq['estado'] ?? '').toString().trim().toLowerCase() !=
          'pendiente_cobro') {
        continue;
      }
      total += (lq['montoTotalRd'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  static List<Map<String, dynamic>> liquidacionesParaExport(
    List<Map<String, dynamic>> raw,
  ) {
    return raw.map((lq) {
      final m = Map<String, dynamic>.from(lq);
      m['periodoInicio'] = _tsToDate(m['periodoInicio']);
      m['periodoFin'] = _tsToDate(m['periodoFin']);
      return m;
    }).toList(growable: false);
  }

  static List<Map<String, dynamic>> historialParaExport(
    List<Map<String, dynamic>> raw,
  ) {
    return raw.map((h) {
      final m = Map<String, dynamic>.from(h);
      m['fechaRecogida'] = _tsToDate(m['fechaRecogida']);
      return m;
    }).toList(growable: false);
  }

  static Future<void> setPlantillaActiva({
    required String empresaId,
    required String plantillaId,
    required bool activa,
    String causa = '',
    String nota = '',
  }) async {
    await _plantillas(empresaId).doc(plantillaId).set({
      'activa': activa,
      if (causa.isNotEmpty) 'pausaCausa': causa,
      'pausaNota': nota,
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('avisarOperacionCorporativa')
          .call({
            'empresaId': empresaId,
            'plantillaId': plantillaId,
            'tipo': activa ? 'reactivar' : 'pausa_total',
            'nota': nota,
          });
    } catch (_) {
      // Push best-effort; la pausa ya quedó guardada.
    }
  }

  static Future<void> guardarDiasPausaFeriado({
    required String empresaId,
    required String plantillaId,
    required List<String> dias,
    String nota = '',
  }) async {
    final limpios = dias
        .map((e) => e.trim())
        .where((e) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(e))
        .toSet()
        .toList()
      ..sort();
    await _plantillas(empresaId).doc(plantillaId).set({
      'diasPausaFeriado': limpios,
      'pausaCausa': CorporativoPausaCausa.feriado,
      'pausaNota': nota.trim(),
      'activa': true,
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('avisarOperacionCorporativa')
          .call({
            'empresaId': empresaId,
            'plantillaId': plantillaId,
            'tipo': 'feriado',
            'nota': nota.trim(),
          });
    } catch (_) {}
  }

  static Future<void> setPasajeroActivoEnPlantilla({
    required String empresaId,
    required String plantillaId,
    required List<CorporativoPasajero> pasajeros,
    required String pasajeroId,
    required bool activo,
    String nota = '',
  }) async {
    CorporativoPasajero? target;
    for (final p in pasajeros) {
      if (p.id == pasajeroId) {
        target = p;
        break;
      }
    }
    final next = pasajeros
        .map((p) => p.id == pasajeroId ? p.copyWith(activo: activo) : p)
        .toList();
    await _plantillas(empresaId).doc(plantillaId).set({
      'pasajeros': next.map((p) => p.toMap()).toList(),
      'pausaCausa': activo
          ? CorporativoPausaCausa.agregarPasajero
          : CorporativoPausaCausa.quitarPasajero,
      'pausaNota': nota.trim(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    var choferUid = '';
    try {
      final snap = await _plantillas(empresaId).doc(plantillaId).get();
      choferUid = (snap.data()?['choferPreferidoUid'] ?? '').toString().trim();
    } catch (_) {}
    if (plantillaId.isNotEmpty) {
      await _sincronizarPlantillaEnVivoConReintento(
        empresaId: empresaId,
        plantillaId: plantillaId,
        enviarPushHora: false,
        notificarCambioPasajeros: true,
        choferAsignado: choferUid.isNotEmpty,
      );
    }
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('avisarOperacionCorporativa')
          .call({
            'empresaId': empresaId,
            'plantillaId': plantillaId,
            'tipo': activo ? 'agregar_pasajero' : 'quitar_pasajero',
            'pasajeroNombre': target?.nombre ?? 'pasajero',
            'nota': nota.trim(),
          });
    } catch (_) {}
  }

  static String nuevoPasajeroId() =>
      'p_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(9999)}';

  /// Web/Firestore rechaza `null` en campos string anidados (TypeError al guardar).
  static Map<String, dynamic> _sanitizarMapaFirestore(Map<String, dynamic> raw) {
    dynamic limpiar(dynamic value) {
      if (value == null) return null;
      if (value is FieldValue || value is Timestamp) return value;
      if (value is String || value is bool) return value;
      if (value is int || value is double) {
        if (value is double && !value.isFinite) return 0;
        return value;
      }
      if (value is Map) {
        final out = <String, dynamic>{};
        value.forEach((k, v) {
          final limpio = limpiar(v);
          if (limpio != null) out[k.toString()] = limpio;
        });
        return out;
      }
      if (value is List) {
        return value
            .map(limpiar)
            .where((e) => e != null)
            .toList(growable: false);
      }
      return value.toString();
    }

    final limpio = limpiar(raw);
    if (limpio is Map<String, dynamic>) return limpio;
    if (limpio is Map) return Map<String, dynamic>.from(limpio);
    return raw;
  }

  static Future<String?> resolverChoferPorTelefono(String telefono) async {
    final digits = telefono.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return null;
    final q = await _db
        .collection('usuarios')
        .where('telefono', isGreaterThanOrEqualTo: digits)
        .where('telefono', isLessThanOrEqualTo: '$digits\uf8ff')
        .limit(5)
        .get();
    for (final doc in q.docs) {
      final rol = (doc.data()['rol'] ?? '').toString().toLowerCase();
      if (rol == 'taxista' || rol == 'driver') return doc.id;
    }
    return null;
  }

  static ({
    List<Map<String, dynamic>> waypoints,
    String destinoLabel,
    double latDestino,
    double lonDestino,
    double distKm,
    List<Map<String, dynamic>> rutaPuntos,
    String googleMapsRutaUrl,
    String wazeOrigenUrl,
  }) armarRutaCompleta(CorporativoPlantilla plantilla) {
    final activos = plantilla.pasajerosActivos
        .where((p) => MultiparadaRutaHelper.coordsValidas(p.lat, p.lon))
        .toList();
    if (activos.isEmpty) {
      throw 'Agrega al menos un pasajero activo con destino válido.';
    }
    if (!MultiparadaRutaHelper.coordsValidas(
        plantilla.origenLat, plantilla.origenLon)) {
      throw 'Configura el origen (empresa / punto de recogida).';
    }

    final waypointsRaw = <Map<String, dynamic>>[];
    for (int i = 0; i < activos.length - 1; i++) {
      final p = activos[i];
      waypointsRaw.add({
        'lat': p.lat,
        'lon': p.lon,
        'label': _labelPasajero(p),
        'orden': i + 1,
        'pasajeroId': p.id,
        'sector': p.sector,
        if (p.referencia.isNotEmpty) 'referencia': p.referencia,
        if (p.horaDejada.isNotEmpty) 'horaDejada': p.horaDejada,
      });
    }
    final ultimo = activos.last;
    final waypoints = MultiparadaRutaHelper.sanitizarWaypoints(waypointsRaw);
    final destinoLabel = _labelPasajero(ultimo);
    final distKm = _distanciaKmRuta(
      latOrigen: plantilla.origenLat,
      lonOrigen: plantilla.origenLon,
      pasajeros: activos,
      kmMinimoPorTramo:
          CorporativoTarifaConfigService.vigente.kmMinimoPorTramo,
    );
    final rutaPuntos = MultiparadaRutaHelper.construirRutaPuntos(
      latOrigen: plantilla.origenLat,
      lonOrigen: plantilla.origenLon,
      labelOrigen: plantilla.origenLabel,
      latDestino: ultimo.lat,
      lonDestino: ultimo.lon,
      labelDestino: destinoLabel,
      waypoints: waypoints,
    );
  final paradas = waypoints
        .map((w) => (
              lat: (w['lat'] as num).toDouble(),
              lon: (w['lon'] as num).toDouble(),
            ))
        .toList();
    final googleMapsRutaUrl = _urlGoogleMapsRuta(
      origenLat: plantilla.origenLat,
      origenLon: plantilla.origenLon,
      destinoLat: ultimo.lat,
      destinoLon: ultimo.lon,
      paradas: paradas,
    );
    final wazeOrigenUrl =
        'https://waze.com/ul?ll=${plantilla.origenLat.toStringAsFixed(6)},'
        '${plantilla.origenLon.toStringAsFixed(6)}&navigate=yes';

    return (
      waypoints: waypoints,
      destinoLabel: destinoLabel,
      latDestino: ultimo.lat,
      lonDestino: ultimo.lon,
      distKm: distKm,
      rutaPuntos: rutaPuntos,
      googleMapsRutaUrl: googleMapsRutaUrl,
      wazeOrigenUrl: wazeOrigenUrl,
    );
  }

  static String _labelPasajero(CorporativoPasajero p) {
    final ref = p.referencia.trim();
    final base = '${p.nombre} · ${p.destinoLabel}';
    if (ref.isEmpty) return base;
    return '$base (ref: $ref)';
  }

  /// `null` si la plantilla tiene GPS completo y sin paradas duplicadas.
  static String? validarPlantillaGps(CorporativoPlantilla plantilla) {
    if (!MultiparadaRutaHelper.coordsValidas(
        plantilla.origenLat, plantilla.origenLon)) {
      return 'Configura el origen tocando una dirección del buscador.';
    }
    final activos = plantilla.pasajerosActivos;
    if (activos.isEmpty) {
      return 'Agrega al menos un pasajero activo con destino.';
    }
    for (final p in activos) {
      if (!MultiparadaRutaHelper.coordsValidas(p.lat, p.lon)) {
        final nom = p.nombre.trim().isEmpty ? 'Sin nombre' : p.nombre.trim();
        return 'El pasajero «$nom» no tiene GPS del destino. '
            'Edítalo y selecciona el destino tocando una opción del buscador.';
      }
    }
    final paradas = <({double lat, double lon, String label})>[];
    for (int i = 0; i < activos.length - 1; i++) {
      final p = activos[i];
      paradas.add((lat: p.lat, lon: p.lon, label: _labelPasajero(p)));
    }
    final ultimo = activos.last;
    return MultiparadaRutaHelper.validarSecuenciaRuta(
      latOrigen: plantilla.origenLat,
      lonOrigen: plantilla.origenLon,
      labelOrigen: plantilla.origenLabel.trim().isEmpty
          ? 'Origen'
          : plantilla.origenLabel.trim(),
      latDestino: ultimo.lat,
      lonDestino: ultimo.lon,
      labelDestino: _labelPasajero(ultimo),
      paradas: paradas,
      metrosMinimos: MultiparadaRutaHelper.metrosMinEntrePuntosCorporativo,
      mensajeOrigenDestinoCercanos:
          'El destino del pasajero está muy cerca del punto de recogida '
          '(menos de ${MultiparadaRutaHelper.metrosMinEntrePuntosCorporativo.round()} m). '
          'Elegí otra dirección de bajada en el buscador (no la misma que el origen).',
      mensajeOrigenDestinoCoinciden:
          'El destino del pasajero coincide con el origen. '
          'El origen es donde recoge el chofer; cada pasajero necesita '
          'su punto de bajada distinto.',
    );
  }

  static String _urlGoogleMapsRuta({
    required double origenLat,
    required double origenLon,
    required double destinoLat,
    required double destinoLon,
    required List<({double lat, double lon})> paradas,
  }) {
    String fmt(double v) => v.toStringAsFixed(6);
    final o = '${fmt(origenLat)},${fmt(origenLon)}';
    final d = '${fmt(destinoLat)},${fmt(destinoLon)}';
    final wp = paradas.map((p) => '${fmt(p.lat)},${fmt(p.lon)}').join('|');
    return 'https://www.google.com/maps/dir/?api=1'
        '&origin=$o&destination=$d'
        '${wp.isNotEmpty ? '&waypoints=$wp' : ''}'
        '&travelmode=driving';
  }

  static Future<void> abrirRutaEnMaps(CorporativoPlantilla plantilla) async {
    final r = armarRutaCompleta(plantilla);
    final paradas = r.waypoints
        .map((w) => (
              lat: (w['lat'] as num).toDouble(),
              lon: (w['lon'] as num).toDouble(),
            ))
        .toList();
    await NavegacionExternaLauncher.abrirGoogleMapsRutaConParadas(
      origenLat: plantilla.origenLat,
      origenLon: plantilla.origenLon,
      destinoLat: r.latDestino,
      destinoLon: r.lonDestino,
      paradas: paradas,
    );
  }

  static Future<void> abrirRecogidaEnWaze(CorporativoPlantilla plantilla) async {
    if (MultiparadaRutaHelper.coordsValidas(
        plantilla.origenLat, plantilla.origenLon)) {
      await NavegacionExternaLauncher.abrirWazeDestino(
        plantilla.origenLat,
        plantilla.origenLon,
      );
      return;
    }
    final label = plantilla.origenLabel.trim();
    if (label.length >= 3) {
      await NavegacionExternaLauncher.abrirWazeBusqueda(label);
      return;
    }
    throw 'Selecciona el punto de recogida tocando una opción del buscador.';
  }

  static Future<void> asignarChoferPlantillaAdmin({
    required String empresaId,
    required String plantillaId,
    required String telefonoChofer,
  }) async {
    final uid = await resolverChoferPorTelefono(telefonoChofer);
    if (uid == null) {
      throw 'Conductor no encontrado en RAI con ese teléfono.';
    }
    final uSnap = await _db.collection('usuarios').doc(uid).get();
    final u = uSnap.data() ?? {};
    final nombre = (u['nombre'] ?? u['displayName'] ?? '')
        .toString()
        .trim();
    final tel = telefonoChofer.replaceAll(RegExp(r'\D'), '');
    final perfil = CorporativoChoferPerfilService.desdeUsuario(
      u,
      uid: uid,
      asignadoEn: DateTime.now(),
    );
    await _plantillas(empresaId).doc(plantillaId).set({
      'choferPreferidoUid': uid,
      'choferPreferidoTelefono': tel,
      'choferPreferidoNombre':
          nombre.isEmpty ? 'Conductor RAI' : nombre,
      'choferAsignadoPerfil': perfil.toMap(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Firma operativa de pasajeros activos (detecta altas, bajas y cambios de GPS).
  static String firmaPasajerosActivos(List<CorporativoPasajero> pasajeros) {
    final activos = pasajeros.where((p) => p.activo).toList()
      ..sort((a, b) {
        final oa = a.orden > 0 ? a.orden : 999;
        final ob = b.orden > 0 ? b.orden : 999;
        return oa.compareTo(ob);
      });
    return activos
        .map(
          (p) =>
              '${p.id}|${p.orden}|${p.lat.toStringAsFixed(5)},${p.lon.toStringAsFixed(5)}|'
              '${p.nombre.trim()}|${p.destinoLabel.trim()}',
        )
        .join(';');
  }

  static Future<String> guardarPlantilla(
    CorporativoPlantilla plantilla, {
    CorporativoPlantilla? anterior,
  }) async {
    final gpsErr = validarPlantillaGps(plantilla);
    if (gpsErr != null) throw gpsErr;

    var pl = plantilla;
    final ruta = armarRutaCompleta(pl);
    final kmNuevo = ruta.distKm;
    final desgloseNuevo = desgloseTarifaAutomatica(pl);
    // Precio base servicio (sin impuesto transferencia); el backend liquida igual.
    final tarifaNueva = desgloseNuevo.precioBaseServicioRd;
    final prev = anterior;
    // Siempre recalcula al guardar: el botón muestra el monto actual del recorrido.
    final tarifa = tarifaNueva > 0
        ? tarifaNueva
        : (prev?.precioAcordado ?? 0);
    pl = pl.copyWith(
      rutaPuntos: ruta.rutaPuntos,
      googleMapsRutaUrl: ruta.googleMapsRutaUrl,
      wazeOrigenUrl: ruta.wazeOrigenUrl,
      precioAcordado: tarifa,
    );

    // El chofer lo asigna RAI (admin); el encargado solo define la ruta.

    final ref = pl.id.isEmpty
        ? _plantillas(pl.empresaId).doc()
        : _plantillas(pl.empresaId).doc(pl.id);
    final data = pl.toMap();
    // El editor de ruta no toca feriados/pausas: no borrar lo gestionado aparte.
    if (prev != null &&
        plantilla.diasPausaFeriado.isEmpty &&
        prev.diasPausaFeriado.isNotEmpty) {
      data['diasPausaFeriado'] = prev.diasPausaFeriado;
      data['pausaCausa'] = prev.pausaCausa;
      data['pausaNota'] = prev.pausaNota;
    }
    // El chofer lo asigna Admin: si el encargado guarda la ruta sin traer
    // esos campos, no se debe borrar la asignación ya amarrada.
    if (prev != null) {
      final uidNuevo = (plantilla.choferPreferidoUid ?? '').trim();
      final uidPrev = (prev.choferPreferidoUid ?? '').trim();
      if (uidNuevo.isEmpty && uidPrev.isNotEmpty) {
        data['choferPreferidoUid'] = uidPrev;
        if ((prev.choferPreferidoNombre ?? '').trim().isNotEmpty) {
          data['choferPreferidoNombre'] = prev.choferPreferidoNombre;
        }
        if ((prev.choferPreferidoTelefono ?? '').trim().isNotEmpty) {
          data['choferPreferidoTelefono'] = prev.choferPreferidoTelefono;
        }
        if (prev.choferAsignadoPerfil != null &&
            prev.choferAsignadoPerfil!.asignado) {
          data['choferAsignadoPerfil'] = prev.choferAsignadoPerfil!.toMap();
        }
      }
    }
    if (plantilla.id.isEmpty) {
      data['creadoEn'] = FieldValue.serverTimestamp();
      if ((pl.fechaInicioServicio == null || pl.fechaInicioServicio!.isEmpty)) {
        final hoy = DateTime.now();
        data['fechaInicioServicio'] =
            CorporativoCicloFacturacion.claveFechaCalendario(hoy);
      }
      if (pl.patronRecurrencia == CorporativoPatronRecurrencia.interdiaria &&
          (pl.fechaAnclaInterdiaria == null || pl.fechaAnclaInterdiaria!.isEmpty)) {
        final ancla = CorporativoCicloFacturacion.parseFechaCalendario(
              pl.fechaInicioServicio,
            ) ??
            DateTime.now();
        data['fechaAnclaInterdiaria'] =
            CorporativoCicloFacturacion.claveFechaCalendario(ancla);
      }
    }
    data['tarifaDesglose'] = desgloseTarifaAutomatica(pl).toMap();
    data['distanciaKm'] = double.parse(kmNuevo.toStringAsFixed(2));
    final payload = _sanitizarMapaFirestore(data);
    await ref.set(payload, SetOptions(merge: true));

    final plantillaId = ref.id;
    final choferUid = (data['choferPreferidoUid'] ?? '').toString().trim();

    // Tiempo real: plantilla → chofer → viaje de hoy (hora, pasajeros, maps).
    if (plantillaId.isNotEmpty) {
      final horaPrev = prev?.horaRecogidaGrupo.trim() ?? '';
      final horaNow = pl.horaRecogidaGrupo.trim();
      final horaCambio = horaPrev.isNotEmpty && horaPrev != horaNow;
      final horaCambioMaterial = horaCambio &&
          cambioHoraCorporativoMaterial(horaPrev, horaNow);
      var pasajerosCambio = false;
      var agregados = <CorporativoPasajero>[];
      var quitados = <CorporativoPasajero>[];
      if (prev != null) {
        final idsPrev =
            prev.pasajeros.where((p) => p.activo).map((p) => p.id).toSet();
        final idsNow =
            pl.pasajeros.where((p) => p.activo).map((p) => p.id).toSet();
        pasajerosCambio =
            firmaPasajerosActivos(prev.pasajeros) !=
                firmaPasajerosActivos(pl.pasajeros) ||
            idsPrev.length != idsNow.length ||
            !idsPrev.containsAll(idsNow);
        agregados = pl.pasajeros
            .where((p) => p.activo && !idsPrev.contains(p.id))
            .toList();
        quitados = prev.pasajeros
            .where((p) => p.activo && !idsNow.contains(p.id))
            .toList();
      }
      final avisoPasajeroExplicito =
          agregados.isNotEmpty || quitados.isNotEmpty;
      final tarifaCambio = prev != null &&
          (prev.precioAcordado - pl.precioAcordado).abs() > 0.5;
      final rutaCambio = prev != null &&
          (prev.origenLabel.trim() != pl.origenLabel.trim() ||
              prev.googleMapsRutaUrl.trim() != pl.googleMapsRutaUrl.trim() ||
              prev.nombre.trim() != pl.nombre.trim());
      final syncOk = await _sincronizarPlantillaEnVivoConReintento(
        empresaId: pl.empresaId,
        plantillaId: plantillaId,
        // Solo invalida/recrea viaje si el cambio de hora es material (≥5 min).
        // Ajustes chicos parchean el mismo viaje; pasajeros siempre parchean.
        horaAnterior: horaCambioMaterial ? horaPrev : null,
        enviarPushHora: horaCambio,
        notificarCambioPasajeros: pasajerosCambio,
        notificarActualizacionRuta:
            (tarifaCambio || rutaCambio) && !horaCambio && !pasajerosCambio,
        choferAsignado: choferUid.isNotEmpty,
      );
      if (!syncOk && choferUid.isNotEmpty) {
        throw StateError(
          'La ruta se guardó pero no se pudo avisar al chofer en vivo. '
          'Reintentá guardar o pedí al chofer que actualice Mis rutas.',
        );
      }

      if (prev != null && plantilla.id.isNotEmpty && avisoPasajeroExplicito) {
        try {
          final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
              .httpsCallable('avisarOperacionCorporativa');
          for (final p in agregados) {
            await fn.call({
              'empresaId': pl.empresaId,
              'plantillaId': ref.id,
              'tipo': 'agregar_pasajero',
              'pasajeroNombre': p.nombre,
            });
          }
          for (final p in quitados) {
            await fn.call({
              'empresaId': pl.empresaId,
              'plantillaId': ref.id,
              'tipo': 'quitar_pasajero',
              'pasajeroNombre': p.nombre,
            });
          }
        } catch (_) {}
      }
    }

    return ref.id;
  }

  /// Propaga hora/pasajeros al chofer y al viaje de hoy. Reintenta 3 veces.
  /// Devuelve `true` si la sincronización en vivo fue exitosa.
  static Future<bool> _sincronizarPlantillaEnVivoConReintento({
    required String empresaId,
    required String plantillaId,
    String? horaAnterior,
    required bool enviarPushHora,
    bool notificarCambioPasajeros = false,
    bool notificarActualizacionRuta = false,
    required bool choferAsignado,
  }) async {
    const intentos = 3;
    Object? ultimoError;
    for (var i = 0; i < intentos; i++) {
      try {
        await FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('sincronizarPlantillaCorporativaEnVivo')
            .call({
          'empresaId': empresaId,
          'plantillaId': plantillaId,
          if (horaAnterior != null && horaAnterior.isNotEmpty)
            'horaAnterior': horaAnterior,
          'enviarPushHora': enviarPushHora,
          'notificarCambioPasajeros': notificarCambioPasajeros,
          'notificarActualizacionRuta': notificarActualizacionRuta,
        });
        return true;
      } on FirebaseFunctionsException catch (e) {
        ultimoError = e;
        debugPrint('[CORP] sync intento ${i + 1}/$intentos: ${e.code} ${e.message}');
      } catch (e) {
        ultimoError = e;
        debugPrint('[CORP] sync intento ${i + 1}/$intentos: $e');
      }
      if (i < intentos - 1) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    if (choferAsignado) {
      debugPrint(
        '[CORP] sync agotó reintentos con chofer asignado: $ultimoError',
      );
    }
    return false;
  }

  static double _distanciaKmRuta({
    required double latOrigen,
    required double lonOrigen,
    required List<CorporativoPasajero> pasajeros,
    double kmMinimoPorTramo =
        CorporativoTarifaDinamicaModel.kmMinimoPorTramoDefault,
  }) {
    if (pasajeros.isEmpty) return 0;
    if (!MultiparadaRutaHelper.coordsValidas(latOrigen, lonOrigen)) return 0;
    final minTramo = kmMinimoPorTramo.clamp(0.0, 5.0);
    double total = 0;
    double lat = latOrigen;
    double lon = lonOrigen;
    for (final p in pasajeros) {
      if (!MultiparadaRutaHelper.coordsValidas(p.lat, p.lon)) continue;
      final leg = _distanciaKmEntre(lat, lon, p.lat, p.lon);
      total += minTramo > 0 ? math.max(leg, minTramo) : leg;
      lat = p.lat;
      lon = p.lon;
    }
    return total;
  }

  /// Haversine puro (cel / web / desktop) — no depende de plugins nativos.
  static double _distanciaKmEntre(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    try {
      final m = Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
      if (m.isFinite && m >= 0) return m / 1000.0;
    } catch (_) {}
    const r = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180.0;

  /// Tarifa automática con desglose (km carretera, zona, transferencia, ITBIS ref.).
  static CorporativoTarifaDesglose desgloseTarifaAutomatica(
    CorporativoPlantilla plantilla, {
    CorporativoTarifaConfig? config,
  }) {
    final cfg = config ?? CorporativoTarifaConfigService.vigente;
    final kmLineaRecta = distanciaKmRuta(plantilla, config: cfg);
    return CorporativoTarifaDesglose.calcular(
      kmLineaRecta: kmLineaRecta,
      cfg: cfg,
      numParadas: plantilla.pasajerosActivos
          .where((p) => MultiparadaRutaHelper.coordsValidas(p.lat, p.lon))
          .length
          .clamp(1, 99),
    );
  }

  /// Tarifa automática por distancia (origen + paradas). Respeta `config/corporativo`.
  static double calcularTarifaAutomaticaRuta(CorporativoPlantilla plantilla) {
    return desgloseTarifaAutomatica(plantilla).precioViajeRd;
  }

  /// Km del recorrido completo: origen → pasajero1 → … → último (orden de plantilla).
  static double distanciaKmRuta(
    CorporativoPlantilla plantilla, {
    CorporativoTarifaConfig? config,
  }) {
    if (!MultiparadaRutaHelper.coordsValidas(
      plantilla.origenLat,
      plantilla.origenLon,
    )) {
      return 0;
    }
    final activos = plantilla.pasajerosActivos
        .where((p) => MultiparadaRutaHelper.coordsValidas(p.lat, p.lon))
        .toList();
    if (activos.isEmpty) return 0;
    final cfg = config ?? CorporativoTarifaConfigService.vigente;
    return _distanciaKmRuta(
      latOrigen: plantilla.origenLat,
      lonOrigen: plantilla.origenLon,
      pasajeros: activos,
      kmMinimoPorTramo: cfg.kmMinimoPorTramo,
    );
  }

  static double _precioViaje(
    CorporativoPlantilla plantilla,
    double distKm, {
    double tarifaContratadaEmpresa = 0,
  }) {
    return resolverTarifaViaje(
      plantilla: plantilla,
      distKm: distKm,
      tarifaContratadaEmpresa: tarifaContratadaEmpresa,
    );
  }

  /// Tarifa al publicar (monto total factura empresa, con impuesto transferencia):
  /// 1) Tarifa contratada RAI (= precio base) + impuesto →
  /// 2) [precioAcordado] precio base guardado en plantilla + impuesto →
  /// 3) Cálculo automático del recorrido.
  static double resolverTarifaViaje({
    required CorporativoPlantilla plantilla,
    required double distKm,
    double tarifaContratadaEmpresa = 0,
  }) {
    final cfg = CorporativoTarifaConfigService.vigente;
    if (tarifaContratadaEmpresa > 0) {
      return CorporativoFacturaCalculo.desdePrecioBase(
        precioBaseServicio: tarifaContratadaEmpresa,
        cfg: cfg,
      ).montoTotalFacturaRd;
    }
    if (plantilla.precioAcordado > 0) {
      return liquidacionDesdePrecioAcordado(plantilla.precioAcordado)
          .montoTotalFacturaRd;
    }
    return desgloseTarifaAutomatica(plantilla).precioViajeRd;
  }

  /// [precioAcordado] en plantilla = precio base del servicio (sin impuesto).
  static CorporativoLiquidacionMontos liquidacionDesdePrecioAcordado(
    double precioAcordado,
  ) {
    return CorporativoFacturaCalculo.desdePrecioBase(
      precioBaseServicio: precioAcordado,
      cfg: CorporativoTarifaConfigService.vigente,
    );
  }

  /// Monto en vivo mientras el encargado arma la ruta (recorrido completo).
  static double estimarTarifaPlantilla({
    required CorporativoPlantilla plantilla,
  }) {
    if (!puedeCalcularTarifa(plantilla)) return 0;
    try {
      return calcularTarifaAutomaticaRuta(plantilla);
    } catch (_) {
      return 0;
    }
  }

  /// Origen confirmado + ≥1 pasajero activo con destino geolocalizado.
  static bool puedeCalcularTarifa(CorporativoPlantilla plantilla) {
    if (!MultiparadaRutaHelper.coordsValidas(
      plantilla.origenLat,
      plantilla.origenLon,
    )) {
      return false;
    }
    return plantilla.pasajerosActivos.any(
      (p) => MultiparadaRutaHelper.coordsValidas(p.lat, p.lon),
    );
  }

  static Future<bool> esChoferCorporativoHabilitado(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return false;
    final snap = await _db.collection('choferes_corporativos').doc(id).get();
    if (!snap.exists) return false;
    final d = snap.data() ?? {};
    final est = (d['estado'] ?? '').toString().trim().toLowerCase();
    if (est != 'aprobado' && est != 'activo') return false;
    return d['activo'] != false;
  }

  static Future<void> assertChoferCorporativoHabilitado(String uid) async {
    if (!await esChoferCorporativoHabilitado(uid)) {
      throw 'El conductor no está habilitado en el pool corporativo RAI. '
          'Contacta a tu ejecutivo.';
    }
  }

  /// Encargado: da de baja la empresa del servicio corporativo RAI.
  static Future<({int plantillasEliminadas, int viajesCancelados})>
      darDeBajaEmpresa({
    required String empresaId,
    String? motivo,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw 'Sesión expirada';

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('encargadoDarDeBajaEmpresaCorporativa');
      final res = await callable.call(<String, dynamic>{
        'empresaId': empresaId.trim(),
        if (motivo != null && motivo.trim().isNotEmpty) 'motivo': motivo.trim(),
      });
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      return (
        plantillasEliminadas:
            (data['plantillasEliminadas'] as num?)?.toInt() ?? 0,
        viajesCancelados: (data['viajesCancelados'] as num?)?.toInt() ?? 0,
      );
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      throw msg.isNotEmpty
          ? msg
          : 'No se pudo dar de baja la empresa (${e.code}).';
    }
  }

  /// Elimina la ruta completa. Cancela viajes de hoy no iniciados si hace falta.
  static Future<int> eliminarPlantilla({
    required String empresaId,
    required String plantillaId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw 'Sesión expirada';

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('encargadoEliminarRutaCorporativa');
      final res = await callable.call(<String, dynamic>{
        'empresaId': empresaId.trim(),
        'plantillaId': plantillaId.trim(),
      });
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      return (data['viajesCancelados'] as num?)?.toInt() ?? 0;
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      throw msg.isNotEmpty
          ? msg
          : 'No se pudo eliminar la ruta (${e.code}).';
    }
  }

  /// «Enviar ahora»: publica en backend con auto-asignación / respaldo del pool.
  static Future<String> lanzarDesdePlantilla({
    required CorporativoPlantilla plantilla,
    required CorporativoEmpresa empresa,
    required DateTime fechaRecogida,
    String metodoPago = 'transferencia',
    String origenLanzamiento = 'manual',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw 'Sesión expirada';

    if (!empresa.contratoVigente) {
      throw 'El servicio corporativo aún no está activado por RAI. Contacta a tu ejecutivo.';
    }

    if (!empresa.contratoDigitalFirmado) {
      throw 'Debes firmar el Contrato de Servicio Corporativo RAI antes de enviar rutas.';
    }

    if (plantilla.pasajerosActivos.isEmpty) {
      throw 'No hay pasajeros activos en la ruta.';
    }

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('encargadoPublicarRutaCorporativaAhora');
      final res = await callable.call(<String, dynamic>{
        'empresaId': empresa.id,
        'plantillaId': plantilla.id,
        'fechaRecogidaIso': fechaRecogida.toUtc().toIso8601String(),
        'origenLanzamiento': origenLanzamiento,
        'metodoPago': metodoPago,
      });
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      final viajeId = (data['viajeId'] ?? '').toString().trim();
      if (viajeId.isEmpty) {
        throw 'No se pudo publicar la ruta. Intentá de nuevo o contactá a RAI.';
      }
      return viajeId;
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      throw msg.isNotEmpty
          ? msg
          : 'No se pudo publicar la ruta (${e.code}).';
    }
  }

  /// Asigna el viaje exclusivamente al chofer fijo (no pool público).
  static Future<void> asignarChoferFijoAlViaje({
    required String viajeId,
    required String choferUid,
    required bool esAhora,
    String? choferNombre,
  }) async {
    final uid = choferUid.trim();
    if (uid.isEmpty) {
      throw 'Chofer corporativo inválido.';
    }
    await assertChoferCorporativoHabilitado(uid);

    final viajeRef = _db.collection('viajes').doc(viajeId);
    final uRef = _db.collection('usuarios').doc(uid);
    final corpRef = _db.collection('choferes_corporativos').doc(uid);

    var asignadoOk = false;
    await _db.runTransaction((tx) async {
      final vSnap = await tx.get(viajeRef);
      final uSnap = await tx.get(uRef);
      final cSnap = await tx.get(corpRef);
      if (!vSnap.exists) {
        throw 'Viaje no encontrado.';
      }
      if (!uSnap.exists) {
        throw 'Conductor no encontrado en RAI.';
      }
      if (!cSnap.exists) {
        throw 'Conductor no habilitado en pool corporativo.';
      }
      final corp = cSnap.data() ?? {};
      final est = (corp['estado'] ?? '').toString().toLowerCase();
      if ((est != 'aprobado' && est != 'activo') || corp['activo'] == false) {
        throw 'Conductor no habilitado en pool corporativo.';
      }

      final v = vSnap.data() ?? {};
      final u = uSnap.data() ?? {};

      final yaAsignado =
          (v['uidTaxista'] ?? v['taxistaId'] ?? '').toString().trim();
      if (yaAsignado.isNotEmpty && yaAsignado != uid) {
        throw 'El viaje ya tiene otro conductor asignado.';
      }

      final nombre = (choferNombre ?? u['nombre'] ?? u['displayName'] ?? '')
          .toString()
          .trim();
      final telefono = (u['telefono'] ?? '').toString();
      final placa = (u['placa'] ?? '').toString();
      final tipoVeh = (u['tipoVehiculo'] ?? '🚗 NORMAL').toString();
      final viajeActivoId = (u['viajeActivoId'] ?? '').toString().trim();
      final activoViaje = esAhora && viajeActivoId.isEmpty;

      tx.set(viajeRef, {
        'canalAsignacion': canalCorporativoFijo,
        'corporativoChoferAsignadoUid': uid,
        'uidTaxista': uid,
        'taxistaId': uid,
        'nombreTaxista': nombre.isEmpty ? 'Conductor RAI' : nombre,
        'telefono': telefono,
        'placa': placa,
        'tipoVehiculo': tipoVeh,
        'estado': EstadosViaje.aceptado,
        'aceptado': true,
        'rechazado': false,
        'activo': activoViaje,
        'programado': !esAhora,
        'aceptadoEn': FieldValue.serverTimestamp(),
        'reservadoPor': '',
        'reservadoHasta': null,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final patchUser = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      };
      if (activoViaje) {
        patchUser['viajeActivoId'] = viajeId;
      } else if (viajeActivoId != viajeId) {
        patchUser['siguienteViajeId'] = viajeId;
      }
      tx.set(uRef, patchUser, SetOptions(merge: true));
      asignadoOk = true;
    });

    if (!asignadoOk) {
      throw 'No se pudo asignar el viaje al chofer corporativo.';
    }
  }

  static DateTime proximaRecogida(CorporativoPlantilla pl, {DateTime? desde}) {
    final base = desde ?? DateTime.now();
    final norm = normalizarHoraHHmm(pl.horaRecogidaGrupo) ?? '07:00';
    final parts = norm.split(':');
    final h = int.tryParse(parts.first) ?? 7;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    var candidato = DateTime(base.year, base.month, base.day, h, m);
    if (candidato.isBefore(base)) {
      candidato = candidato.add(const Duration(days: 1));
    }
    for (int i = 0; i < 14; i++) {
      final d = candidato.add(Duration(days: i));
      final fechaAncla = pl.fechaAnclaInterdiaria != null
          ? DateTime.tryParse(pl.fechaAnclaInterdiaria!)
          : null;
      if (CorporativoPatronRecurrencia.coincideHoy(
        patron: pl.patronRecurrencia,
        diasSemana: pl.diasSemana,
        fechaAnclaInterdiaria: fechaAncla,
        hoy: d,
      )) {
        return DateTime(d.year, d.month, d.day, h, m);
      }
    }
    return candidato;
  }
}
