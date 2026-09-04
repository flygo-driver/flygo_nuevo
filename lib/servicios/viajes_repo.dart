// lib/servicios/viajes_repo.dart
// ignore_for_file: avoid_print -- [VIAJE_ACTIVO] / [FINALIZAR] trazas producción
import 'dart:async';
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/servicios/cliente_verificacion_identidad_service.dart';
import 'package:flygo_nuevo/servicios/cliente_cuenta_real_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/servicios/asignacion_turismo_repo.dart';
import 'package:flygo_nuevo/servicios/bola_pueblo_firestore_sync.dart';
import 'package:flygo_nuevo/servicios/error_reporting.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/cuenta_rol_perfil_guard.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/utils/pago_tarjeta_cliente_gate.dart';
import 'package:flygo_nuevo/utils/trip_publish_windows.dart';
import 'package:flygo_nuevo/servicios/analytics_rai.dart';
import 'package:flygo_nuevo/utils/ux_log.dart';
import 'package:flygo_nuevo/utils/viaje_codigo_verificacion_helper.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';
import 'package:flygo_nuevo/utils/bola_ahorro_pool_isolation.dart';
import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/servicios/comision_viaje_pct_service.dart';
import 'package:flygo_nuevo/servicios/taxista_operacion_gate.dart';
import 'package:flygo_nuevo/app_flavor.dart';
import 'package:flygo_nuevo/utils/multiparada_ruta_helper.dart';
import 'package:flygo_nuevo/servicios/app_flavor_rol_guard.dart';
import 'package:flygo_nuevo/servicios/notification_service.dart';
import 'package:flygo_nuevo/servicios/negocios_aliados_repo.dart';
import 'package:flygo_nuevo/servicios/negocio_aliado_config.dart';
import 'package:flygo_nuevo/servicios/negocio_aliado_promo_service.dart';
import 'package:flygo_nuevo/servicios/pool_timbre_session_guard.dart';
import 'package:flygo_nuevo/modelo/tarifas_tramos_config.dart';
import 'package:flygo_nuevo/servicios/tarifa_service_unificado.dart';

/// Diagnóstico solo en debug: en release no expone UIDs ni estado interno por logcat.
void _viajesRepoDebugLog(String message) {
  if (kDebugMode) debugPrint(message);
}

  /// Mensaje cuando el cliente intenta crear un segundo viaje (doble toque / reintento).
const String kMsgClienteYaTieneViajeActivo =
    'Ya tienes un viaje activo. Abre tu viaje en curso o espera a que termine antes de pedir otro.';

/// Firestore rechazó guardar el viaje (cuenta, reglas o sesión).
const String kMsgCrearViajeSinPermisoCliente =
    'No se pudo guardar el viaje. Revisá tu conexión, cerrá la app conductor si usás la misma cuenta e intentá otra vez.';

/// Callable no desplegado / sin Blaze: el viaje no se guardó en el servidor.
const String kMsgCrearViajeServidorNoDisponible =
    'El servidor no está disponible para confirmar viajes. Activá facturación (Blaze) y desplegá Functions, o intentá más tarde.';

/// Resultado de [ViajesRepo.promoverColaTrasFinalizarTaxista] (callable `promoverSiguienteViaje`).
class PromoverColaTaxistaOutcome {
  const PromoverColaTaxistaOutcome({
    required this.promotedViajeId,
    required this.code,
    this.message,
  });

  final String? promotedViajeId;
  final String code;
  final String? message;

  bool get hadPromotion =>
      promotedViajeId != null && promotedViajeId!.isNotEmpty;
}

/// Resultado de [ViajesRepo.completarViajePorTaxista].
enum CompletarViajeTaxistaOutcome {
  completedNow,
  alreadyCompleted,
}

class ViajesRepo {
  /// Alias hacia [TripPublishWindows.poolLeadMinutesProgramado] (compat. UI / logs).
  static int get poolLeadMinutesProgramado =>
      TripPublishWindows.poolLeadMinutesProgramado;

  static const bool _diagTripFlow =
      bool.fromEnvironment('TRIP_FLOW_DIAG', defaultValue: false);
  static void _diag(String msg) {
    if (_diagTripFlow) dev.log('[TRIP_FLOW][repo] $msg');
  }

  /// `pickup` y `now` deben ser comparables (misma referencia UTC recomendada).
  static DateTime poolOpensAtForScheduledPickup(DateTime pickup, DateTime now) {
    return TripPublishWindows.poolOpensAtForScheduledPickup(pickup, now);
  }

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('viajes');

  /// Devuelve un PIN de 6 dígitos; si el documento ya tiene uno válido, lo conserva.
  static String codigoVerificacionSeisDigitosDesdeDoc(Map<String, dynamic> d) {
    final String? existente = ViajeCodigoVerificacionHelper.pinExistenteEnMap(d);
    if (existente != null) return existente;
    return ViajeCodigoVerificacionHelper.generarPinSeisDigitos();
  }

  static String? _pinExistenteEnMap(Map<String, dynamic>? data) =>
      ViajeCodigoVerificacionHelper.pinExistenteEnMap(data);

  static Future<String?> _escribirPinEnViajeSiAutorizado({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> d,
    required String uid,
  }) async {
    final String uidCliente =
        (d['uidCliente'] ?? d['clienteId'] ?? '').toString().trim();
    final String tid =
        (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString().trim();
    // Solo el pasajero dueño puede sembrar su PIN si falta (las reglas ya no dejan
    // al chofer tocar `codigoVerificacion*`), y siempre con `codigoVerificado: false`.
    final bool esCliente = uidCliente.isNotEmpty && uidCliente == uid;
    if (!esCliente || tid.isEmpty) return null;

    final String? ya = _pinExistenteEnMap(d);
    if (ya != null) return ya;

    final String pinNuevo = codigoVerificacionSeisDigitosDesdeDoc(d);
    await ref.set(
      <String, dynamic>{
        'codigoVerificacion': pinNuevo,
        'codigoVerificado': false,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return pinNuevo;
  }

  /// Si el viaje no tiene PIN de 6 dígitos, lo crea en Firestore (cliente o taxista).
  static Future<String?> ensureCodigoVerificacionViaje(String viajeId) async {
    final String id = viajeId.trim();
    if (id.isEmpty) return null;

    final DocumentReference<Map<String, dynamic>> ref = _col.doc(id);
    final String? uid = FirebaseAuth.instance.currentUser?.uid;

    Future<String?> leerPin() async {
      try {
        final DocumentSnapshot<Map<String, dynamic>> cacheSnap =
            await ref.get(const GetOptions(source: Source.cache));
        if (cacheSnap.exists) {
          final String? desdeCache = _pinExistenteEnMap(cacheSnap.data());
          if (desdeCache != null) return desdeCache;
        }
      } catch (_) {}
      try {
        final Map<String, dynamic>? autoritativo =
            await fetchViajeDocClienteAutoritativo(id);
        if (autoritativo != null) {
          final String? desdeAuth = _pinExistenteEnMap(autoritativo);
          if (desdeAuth != null) return desdeAuth;
        }
      } catch (_) {}
      return null;
    }

    final String? inicial = await leerPin();
    if (inicial != null) return inicial;

    const int maxIntentos = 3;
    for (int intento = 0; intento < maxIntentos; intento++) {
      try {
        final HttpsCallable callable = FirebaseFunctions.instanceFor(
          region: 'us-central1',
        ).httpsCallable('ensureViajeCodigoVerificacion');
        final HttpsCallableResult<dynamic> r =
            await callable.call(<String, dynamic>{'viajeId': id});
        final Object? raw = r.data;
        if (raw is Map) {
          final String pin = ViajeCodigoVerificacionHelper.soloDigitos(
            (raw['pin'] ?? '').toString(),
          );
          if (pin.length == 6) return pin;
        }
      } catch (e) {
        _viajesRepoDebugLog(
          '⚠️ ensureViajeCodigoVerificacion CF (intento ${intento + 1}): $e',
        );
      }

      final String? trasCf = await leerPin();
      if (trasCf != null) return trasCf;

      if (intento < maxIntentos - 1) {
        await Future<void>.delayed(Duration(milliseconds: 400 * (intento + 1)));
      }
    }

    if (uid == null || uid.isEmpty) return null;
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await ref.get();
      if (!snap.exists) return null;
      return await _escribirPinEnViajeSiAutorizado(
        ref: ref,
        d: snap.data() ?? <String, dynamic>{},
        uid: uid,
      );
    } catch (e) {
      _viajesRepoDebugLog('⚠️ ensureCodigoVerificacion local: $e');
      return await leerPin();
    }
  }

  /// Lectura autoritativa del viaje para el cliente: Firestore servidor y, si
  /// las reglas bloquean la lectura (`permission-denied`), Cloud Function.
  static Future<Map<String, dynamic>?> fetchViajeDocClienteAutoritativo(
    String viajeId, {
    Map<String, dynamic>? base,
  }) async {
    final String id = viajeId.trim();
    if (id.isEmpty) return base;

    try {
      final DocumentReference<Map<String, dynamic>> ref = _col.doc(id);

      try {
        final DocumentSnapshot<Map<String, dynamic>> snap =
            await ref.get(const GetOptions(source: Source.server));
        if (snap.exists) {
          final Map<String, dynamic>? d = snap.data();
          if (d != null && d.isNotEmpty) return d;
        }
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') {
          _viajesRepoDebugLog('⚠️ fetchViajeDocClienteAutoritativo: $e');
        }
      } catch (e) {
        final String s = e.toString().toLowerCase();
        if (!s.contains('permission-denied')) {
          _viajesRepoDebugLog('⚠️ fetchViajeDocClienteAutoritativo: $e');
        }
      }

      Map<String, dynamic>? merged = await _fetchViajeClienteDesdeCallable(
        id,
        callableName: 'syncViajeEstadoCliente',
        base: base,
      );
      if (merged != null && merged.isNotEmpty) return merged;

      merged = await _fetchViajeClienteDesdeCallable(
        id,
        callableName: 'ensureViajeCodigoVerificacion',
        base: base ?? merged,
      );
      return merged;
    } catch (e) {
      _viajesRepoDebugLog('⚠️ fetchViajeDocClienteAutoritativo: $e');
      return base;
    }
  }

  static Future<Map<String, dynamic>?> _fetchViajeClienteDesdeCallable(
    String viajeId, {
    required String callableName,
    Map<String, dynamic>? base,
  }) async {
    try {
      final HttpsCallableResult<dynamic> r = await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable(callableName).call(
        <String, dynamic>{'viajeId': viajeId},
      );
      final Object? raw = r.data;
      if (raw is! Map) return base;
      final Map<String, dynamic> merged =
          Map<String, dynamic>.from(base ?? <String, dynamic>{});
      final String pin = ViajeCodigoVerificacionHelper.soloDigitos(
        (raw['pin'] ?? '').toString(),
      );
      if (pin.length == 6) merged['codigoVerificacion'] = pin;
      final String est = (raw['estado'] ?? '').toString().trim();
      if (est.isNotEmpty) merged['estado'] = est;
      if (raw['clienteAbordo'] == true) merged['clienteAbordo'] = true;
      if (raw['codigoVerificado'] == true) {
        merged['codigoVerificado'] = true;
      } else if (raw['codigoVerificado'] == false) {
        merged['codigoVerificado'] = false;
      }
      return merged.isEmpty ? base : merged;
    } catch (e) {
      _viajesRepoDebugLog('⚠️ $callableName: $e');
      return base;
    }
  }

  /// Viaje borrado en consola o ilegible por reglas: Firestore cliente suele devolver
  /// `permission-denied` (no `exists=false`). El callable autoritativo confirma ausencia.
  static Future<bool> viajeDocAusenteOInaccesibleParaCliente(
    String viajeId,
  ) async {
    final String id = viajeId.trim();
    if (id.isEmpty) return true;

    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await _col.doc(id).get(const GetOptions(source: Source.server));
      if (!snap.exists) return true;
      return false;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') {
        print('[VIAJE_ACTIVO] viajeDocAusenteOInaccesible get: $e');
        return false;
      }
    } catch (e) {
      final String s = e.toString().toLowerCase();
      if (!s.contains('permission-denied')) {
        print('[VIAJE_ACTIVO] viajeDocAusenteOInaccesible get: $e');
        return false;
      }
    }

    try {
      final HttpsCallableResult<dynamic> r =
          await FirebaseFunctions.instanceFor(region: 'us-central1')
              .httpsCallable('syncViajeEstadoCliente')
              .call(<String, dynamic>{'viajeId': id})
              .timeout(const Duration(seconds: 8));
      final Object? raw = r.data;
      if (raw is Map && raw['ok'] == true) {
        return false;
      }
      print(
        '[VIAJE_ACTIVO] viajeDocAusenteOInaccesible callable sin ok ($id)',
      );
      return true;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') {
        print(
          '[VIAJE_ACTIVO] viajeDocAusenteOInaccesible callable → ausente ($id, ${e.code})',
        );
        return true;
      }
      print('[VIAJE_ACTIVO] viajeDocAusenteOInaccesible callable: $e');
      return false;
    } on TimeoutException {
      print(
        '[VIAJE_ACTIVO] viajeDocAusenteOInaccesible callable timeout ($id)',
      );
      return false;
    } catch (e) {
      print('[VIAJE_ACTIVO] viajeDocAusenteOInaccesible callable: $e');
      return false;
    }
  }

  /// Filtra matches de query/caché que ya no existen en servidor (viaje borrado en consola).
  static Future<bool> viajeQueryMatchEsFantasmaParaCliente(
    String viajeId,
  ) async {
    final String id = viajeId.trim();
    if (id.isEmpty) return true;
    return viajeDocAusenteOInaccesibleParaCliente(id);
  }

  /// Si `config/encadenamiento_viajes.maxMetrosPickupDesdeDestinoActivo` > 0, al reservar siguiente
  /// viaje se exige que el pickup del candidato esté a esa distancia del **destino** del viaje activo.
  /// Si el doc no existe o el valor es ≤ 0: sin cambio (comportamiento anterior).
  static Future<int?> _maxMetrosEncadenamientoDesdeConfig() async {
    try {
      final s =
          await _db.collection('config').doc('encadenamiento_viajes').get();
      if (!s.exists) return null;
      final raw = s.data()?['maxMetrosPickupDesdeDestinoActivo'];
      if (raw == null) return null;
      final n = raw is num ? raw.round() : int.tryParse(raw.toString());
      if (n == null || n <= 0) return null;
      return n;
    } catch (_) {
      return null;
    }
  }

  static (double, double)? _coordsPickupClienteViaje(Map<String, dynamic>? m) {
    if (m == null) return null;
    double nn(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? double.nan;
    }

    final la = nn(m['latCliente']);
    final lo = nn(m['lonCliente']);
    if (!la.isFinite || !lo.isFinite) return null;
    if (la.abs() < 1e-6 && lo.abs() < 1e-6) return null;
    return (la, lo);
  }

  static (double, double)? _coordsDestinoViaje(Map<String, dynamic>? m) {
    if (m == null) return null;
    double nn(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? double.nan;
    }

    final la = nn(m['latDestino']);
    final lo = nn(m['lonDestino']);
    if (!la.isFinite || !lo.isFinite) return null;
    if (la.abs() < 1e-6 && lo.abs() < 1e-6) return null;
    return (la, lo);
  }

  static int _multiparadaLegCompletadasDesdeDoc(Map<String, dynamic> m) {
    final dynamic v = m['multiparadaLegCompletadas'];
    if (v is num) return v.toInt().clamp(0, 999);
    return 0;
  }

  static bool _multiparadaRutaCompletaDesdeDoc(Map<String, dynamic> m) {
    if (m['multiparadaCompleta'] == true) return true;
    final dynamic wpsRaw = m['waypoints'];
    if (wpsRaw is! List || wpsRaw.isEmpty) return true;
    final int total = m['multiparadaLegsTotal'] is num
        ? (m['multiparadaLegsTotal'] as num).toInt().clamp(1, 999)
        : wpsRaw.length + 1;
    return _multiparadaLegCompletadasDesdeDoc(m) >= total;
  }

  /// Parada actual (multiparada) o destino final — misma referencia que la UI de encadenar.
  static (double, double)? _coordsReferenciaEncadenamientoViajeActivo(
    Map<String, dynamic>? m,
  ) {
    if (m == null) return null;
    final dynamic wpsRaw = m['waypoints'];
    if (wpsRaw is List &&
        wpsRaw.isNotEmpty &&
        !_multiparadaRutaCompletaDesdeDoc(m)) {
      final List<Map<String, dynamic>> wps =
          MultiparadaRutaHelper.sanitizarWaypoints(
        wpsRaw
            .map((dynamic w) => Map<String, dynamic>.from(w as Map))
            .toList(growable: false),
      );
      final int hechas = _multiparadaLegCompletadasDesdeDoc(m);
      if (wps.isNotEmpty && hechas < wps.length) {
        final double? la = (wps[hechas]['lat'] as num?)?.toDouble();
        final double? lo = (wps[hechas]['lon'] as num?)?.toDouble();
        if (la != null &&
            lo != null &&
            MultiparadaRutaHelper.coordsValidas(la, lo)) {
          return (la, lo);
        }
      }
    }
    return _coordsDestinoViaje(m);
  }

  /// UID del cliente en el documento del viaje.
  /// Importante: `(uidCliente ?? clienteId)` falla si `uidCliente` es `''` (no null): no cae a `clienteId`.
  static String uidClienteDesdeDocViaje(Map<String, dynamic> d) {
    final String u = (d['uidCliente'] ?? '').toString().trim();
    if (u.isNotEmpty) return u;
    final String c = (d['clienteId'] ?? '').toString().trim();
    if (c.isNotEmpty) return c;
    return (d['uid'] ?? '').toString().trim();
  }

  /// Garantiza `usuarios/{uid}` con rol pasajero antes de crear en `viajes`
  /// (evita permission-denied si el doc no existía o `rol` venía vacío).
  static Future<void> _ensurePerfilClienteOperativo(String uidCliente) async {
    final String authUid =
        (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (authUid.isEmpty || authUid != uidCliente.trim()) return;

    final ref = _db.collection('usuarios').doc(uidCliente);
    final snap = await ref.get();
    final String email =
        (FirebaseAuth.instance.currentUser?.email ?? '').trim();

    if (!snap.exists) {
      await ref.set(<String, dynamic>{
        'uid': uidCliente,
        'email': email,
        'rol': 'cliente',
        'registroClienteCompleto': false,
        'fechaRegistro': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
      return;
    }

    final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};
    final String rol = AppFlavorRolGuard.rolCanonicoDesdeMaps(usuario: data);
    if (rol == 'admin') {
      throw StateError(
        'Esta cuenta es de administrador. Usá la app de pasajero con otro correo.',
      );
    }
    if ((data['rol'] ?? '').toString().trim().isEmpty) {
      if (!CuentaRolPerfilGuard.cuentaPareceTaxista(data)) {
        await ref.set(<String, dynamic>{
          'rol': 'cliente',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
  }

  static dynamic _sanitizePersistValue(dynamic value, {int depth = 0}) {
    if (depth > 14) return null;
    if (value == null) return null;
    if (value is FieldValue) return value;
    if (value is Timestamp) return value;
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is num) {
      if (!value.isFinite) return null;
      return value;
    }
    if (value is String || value is bool) return value;
    if (value is List) {
      final out = <dynamic>[];
      for (final item in value) {
        final v = _sanitizePersistValue(item, depth: depth + 1);
        if (v != null) out.add(v);
      }
      return out;
    }
    if (value is Map) {
      final out = <String, dynamic>{};
      for (final e in value.entries) {
        final k = e.key.toString().trim();
        if (k.isEmpty) continue;
        final v = _sanitizePersistValue(e.value, depth: depth + 1);
        if (v != null) out[k] = v;
      }
      return out;
    }
    return value.toString();
  }

  static Map<String, dynamic> _stripTripCamposNoPermitidosEnCreateCliente(
    Map<String, dynamic> data,
  ) {
    const forbidden = <String>{
      'referenciaRecaudo',
      'recaudoDestino',
      'qrRecaudoPayload',
      'qrRecaudoTipo',
      'qrRecaudoVersion',
      'qrRecaudoGeneradoEn',
      'qrRecaudoEstado',
      'pagoAzulId',
      'payment',
      'pagoRegistrado',
      'liquidado',
      'pagoDetalle',
      'settlement',
      'comision_cents',
      'ganancia_cents',
      'comision',
      'comisionFlygo',
      'gananciaTaxista',
      'comisionCalculada',
      'comisionCalculadaEn',
      'confirmacionTransferencia',
    };
    final out = Map<String, dynamic>.from(data);
    for (final k in forbidden) {
      out.remove(k);
    }
    return out;
  }

  static Future<void> _limpiarSiguienteViajeIdUsuario(String uid) async {
    await _db.collection('usuarios').doc(uid).set(
      <String, dynamic>{
        'siguienteViajeId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> _limpiarEnlacesViajeUsuarioParaPedirCliente(
    String uid,
  ) async {
    await _db.collection('usuarios').doc(uid).set(
      <String, dynamic>{
        'viajeActivoId': '',
        'siguienteViajeId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<bool> _usuarioViajeActivoIdEs(
    DocumentReference<Map<String, dynamic>> userRef,
    String viajeId,
  ) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await userRef.get();
      final String vid =
          (snap.data()?['viajeActivoId'] ?? '').toString().trim();
      return vid == viajeId.trim();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _vincularUsuarioTrasCrearViajeCliente({
    required DocumentReference<Map<String, dynamic>> userRef,
    required String uidCliente,
    required String nuevoViajeId,
    required bool nuevoEsAhora,
    Map<String, dynamic>? viajeActivoDocPre,
  }) async {
    final DocumentSnapshot<Map<String, dynamic>> userSnap = await userRef.get();
    final Map<String, dynamic> userData = userSnap.data() ?? <String, dynamic>{};
    final Map<String, String> userPatch =
        ViajePoolTaxistaGate.patchUsuarioTrasCrearViajeCliente(
      uidCliente: uidCliente,
      nuevoViajeId: nuevoViajeId,
      nuevoEsAhora: nuevoEsAhora,
      userData: userData,
      viajeActivoDoc: viajeActivoDocPre,
    );
    final Map<String, dynamic> patch = <String, dynamic>{
      'viajeActivoId': userPatch['viajeActivoId'],
      'siguienteViajeId': userPatch['siguienteViajeId'],
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    };
    try {
      await userRef.set(patch, SetOptions(merge: true));
      if (await _usuarioViajeActivoIdEs(userRef, nuevoViajeId)) {
        return true;
      }
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied' && e.code != 'permission_denied') {
        rethrow;
      }
      _viajesRepoDebugLog(
        '⚠️ vincular usuario falló; intentando solo viajeActivoId ($nuevoViajeId)',
      );
    }
    try {
      await userRef.set(
        <String, dynamic>{
          'viajeActivoId': nuevoViajeId,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (await _usuarioViajeActivoIdEs(userRef, nuevoViajeId)) {
        return true;
      }
    } catch (_) {
      _viajesRepoDebugLog(
        '⚠️ viaje $nuevoViajeId creado sin enlazar usuarios/$uidCliente',
      );
    }
    return false;
  }

  static Map<String, dynamic> _sanitizeTripMap(Map<String, dynamic> data) {
    final raw = _sanitizePersistValue(data);
    if (raw is! Map) return Map<String, dynamic>.from(data);
    return Map<String, dynamic>.from(raw);
  }

  static bool _callableCrearViajeReintentarLocal(FirebaseFunctionsException e) {
    final code = e.code.toLowerCase().trim();
    return code == 'not-found' ||
        code == 'unimplemented' ||
        code == 'unavailable' ||
        code == 'deadline-exceeded' ||
        code == 'internal' ||
        code == 'aborted' ||
        code == 'resource-exhausted';
  }

  static dynamic _encodeTripFieldForCallable(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toUtc().toIso8601String();
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is FieldValue) return null;
    if (value is num && !value.isFinite) return null;
    if (value is List) {
      return value.map(_encodeTripFieldForCallable).toList();
    }
    if (value is Map) {
      final out = <String, dynamic>{};
      for (final e in value.entries) {
        out[e.key.toString()] = _encodeTripFieldForCallable(e.value);
      }
      return out;
    }
    return value;
  }

  static Future<void> _prepararSesionClienteAntesCrearViaje(String uidCliente) async {
    final String uid = uidCliente.trim();
    if (uid.isEmpty) return;
    try {
      final DocumentSnapshot<Map<String, dynamic>> uSnap =
          await _db.collection('usuarios').doc(uid).get();
      final Map<String, dynamic> userData = uSnap.data() ?? <String, dynamic>{};
      final String vid =
          (userData['viajeActivoId'] ?? '').toString().trim();
      if (vid.isNotEmpty) {
        try {
          final DocumentSnapshot<Map<String, dynamic>> vSnap =
              await _col.doc(vid).get();
          if (!vSnap.exists) {
            await _limpiarEnlacesViajeUsuarioParaPedirCliente(uid);
            return;
          }
          final Map<String, dynamic> d = vSnap.data() ?? <String, dynamic>{};
          final String st =
              EstadosViaje.normalizar((d['estado'] ?? '').toString());
          final bool terminal =
              d['completado'] == true || EstadosViaje.esTerminal(st);
          final bool esViajeComoCliente = uidClienteDesdeDocViaje(d) == uid;
          if (terminal || !esViajeComoCliente) {
            await _limpiarEnlacesViajeUsuarioParaPedirCliente(uid);
          }
        } on FirebaseException catch (e) {
          if (e.code == 'permission-denied' || e.code == 'permission_denied') {
            await _limpiarEnlacesViajeUsuarioParaPedirCliente(uid);
          } else {
            rethrow;
          }
        }
      }

      final String sid =
          (userData['siguienteViajeId'] ?? '').toString().trim();
      if (sid.isEmpty) return;
      try {
        final DocumentSnapshot<Map<String, dynamic>> sSnap =
            await _col.doc(sid).get();
        if (!sSnap.exists) {
          await _limpiarSiguienteViajeIdUsuario(uid);
          return;
        }
        final Map<String, dynamic> sd = sSnap.data() ?? <String, dynamic>{};
        final String st =
            EstadosViaje.normalizar((sd['estado'] ?? '').toString());
        if (sd['completado'] == true || EstadosViaje.esTerminal(st)) {
          await _limpiarSiguienteViajeIdUsuario(uid);
        }
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied' || e.code == 'permission_denied') {
          await _limpiarSiguienteViajeIdUsuario(uid);
        }
      }
    } catch (_) {
      /* best-effort: no bloquear crear viaje */
    }
  }

  static Future<void> _runViajePendienteTransaction({
    required DocumentReference<Map<String, dynamic>> doc,
    required Map<String, dynamic> data,
    required String uidCliente,
    required DocumentReference<Map<String, dynamic>> userRef,
    required bool nuevoEsAhora,
    bool vincularUsuarioCliente = true,
  }) async {
    Map<String, dynamic>? viajeActivoDocPre;

    if (vincularUsuarioCliente) {
      final DocumentSnapshot<Map<String, dynamic>> userSnap =
          await userRef.get();
      final Map<String, dynamic> userDataPre =
          userSnap.data() ?? <String, dynamic>{};
      final String vid =
          (userDataPre['viajeActivoId'] ?? '').toString().trim();
      if (vid.isNotEmpty) {
        try {
          final DocumentSnapshot<Map<String, dynamic>> vSnap =
              await _col.doc(vid).get();
          if (vSnap.exists) {
            viajeActivoDocPre = vSnap.data();
            if (ViajePoolTaxistaGate.clienteViajeExistenteBloqueaNuevoPedido(
              viajeActivoDocPre!,
              uidCliente,
              nuevoEsAhora: nuevoEsAhora,
            )) {
              throw StateError(kMsgClienteYaTieneViajeActivo);
            }
          }
        } on FirebaseException catch (e) {
          if (e.code == 'permission-denied' || e.code == 'permission_denied') {
            await _limpiarViajeActivoIdTaxista(uidCliente);
            viajeActivoDocPre = null;
          } else {
            rethrow;
          }
        }
      }
    }

    final Map<String, dynamic>? viajeActivoDocTx = viajeActivoDocPre;

    final Map<String, dynamic> tripPersist =
        _stripTripCamposNoPermitidosEnCreateCliente(data);

    await doc.set(tripPersist);

    if (vincularUsuarioCliente) {
      await _vincularUsuarioTrasCrearViajeCliente(
        userRef: userRef,
        uidCliente: uidCliente,
        nuevoViajeId: doc.id,
        nuevoEsAhora: nuevoEsAhora,
        viajeActivoDocPre: viajeActivoDocTx,
      );
    }
  }

  static Future<void> _persistViajeSoloDocumentoViaje({
    required DocumentReference<Map<String, dynamic>> doc,
    required Map<String, dynamic> tripData,
  }) async {
    await doc.set(_stripTripCamposNoPermitidosEnCreateCliente(tripData));
  }

  static Future<void> _persistViajePendienteCliente({
    required DocumentReference<Map<String, dynamic>> doc,
    required Map<String, dynamic> tripData,
    required String uidCliente,
    required DocumentReference<Map<String, dynamic>> userRef,
    required bool nuevoEsAhora,
    required bool vincularUsuarioCliente,
    required bool usarCallableCliente,
  }) async {
    bool docOk = false;
    bool vinculoOk = !vincularUsuarioCliente;

    try {
      await _runViajePendienteTransaction(
        doc: doc,
        data: tripData,
        uidCliente: uidCliente,
        userRef: userRef,
        nuevoEsAhora: nuevoEsAhora,
        vincularUsuarioCliente: vincularUsuarioCliente,
      );
      docOk = true;
      if (vincularUsuarioCliente) {
        vinculoOk = await _usuarioViajeActivoIdEs(userRef, doc.id);
      }
    } on StateError {
      rethrow;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied' && e.code != 'permission_denied') {
        rethrow;
      }
      _viajesRepoDebugLog(
        '⚠️ crearViaje completo permission-denied; intentando solo documento viaje',
      );
      try {
        await _persistViajeSoloDocumentoViaje(doc: doc, tripData: tripData);
        docOk = true;
        _viajesRepoDebugLog(
          '✅ viaje ${doc.id} creado (fallback solo doc)',
        );
      } on FirebaseException catch (e2) {
        if (e2.code != 'permission-denied' && e2.code != 'permission_denied') {
          rethrow;
        }
      }
      if (!docOk && !usarCallableCliente) {
        throw StateError(kMsgCrearViajeSinPermisoCliente);
      }
      if (!docOk) {
        _viajesRepoDebugLog(
          '⚠️ crearViaje local permission-denied; intentando crearViajePendienteCliente CF',
        );
      }
    }

    if (docOk && vincularUsuarioCliente && !vinculoOk) {
      vinculoOk = await _vincularUsuarioTrasCrearViajeCliente(
        userRef: userRef,
        uidCliente: uidCliente,
        nuevoViajeId: doc.id,
        nuevoEsAhora: nuevoEsAhora,
      );
    }

    if (docOk && (!vincularUsuarioCliente || vinculoOk)) {
      return;
    }

    if (!usarCallableCliente) {
      throw StateError(kMsgCrearViajeSinPermisoCliente);
    }

    if (docOk && vincularUsuarioCliente && !vinculoOk) {
      _viajesRepoDebugLog(
        '⚠️ vinculo viajeActivoId falló; intentando crearViajePendienteCliente CF',
      );
    } else {
      _viajesRepoDebugLog(
        '⚠️ crearViaje local permission-denied; intentando crearViajePendienteCliente CF',
      );
    }

    try {
      await _persistViajePendienteClienteCallable(
        viajeId: doc.id,
        data: tripData,
      );
    } on FirebaseFunctionsException catch (e) {
      if (_callableCrearViajeReintentarLocal(e)) {
        throw StateError(kMsgCrearViajeServidorNoDisponible);
      }
      if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
        throw StateError(kMsgCrearViajeSinPermisoCliente);
      }
      rethrow;
    }
  }

  static Future<void> _persistViajePendienteClienteCallable({
    required String viajeId,
    required Map<String, dynamic> data,
  }) async {
    final trip = <String, dynamic>{};
    for (final e in data.entries) {
      if (e.value is FieldValue) continue;
      trip[e.key] = _encodeTripFieldForCallable(e.value);
    }
    trip['id'] = viajeId;

    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('crearViajePendienteCliente');
    try {
      await callable.call(<String, dynamic>{
        'viajeId': viajeId,
        'trip': trip,
      });
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      if (e.code == 'failed-precondition' && msg.contains('viaje activo')) {
        throw StateError(kMsgClienteYaTieneViajeActivo);
      }
      rethrow;
    }
  }

  /// Tarifa equivalente del mismo trayecto para cada tipo de vehículo.
  ///
  /// Nunca puede tumbar la creación del viaje: si la cotización alternativa
  /// falla, el viaje sale sin mapa y el precio pedido queda tal cual.
  static Future<Map<String, int>> _preciosPorTipoVehiculoCents({
    required double? distanciaKm,
    required String tipoVehiculoPedido,
    required int precioAcordadoCents,
    required bool idaYVuelta,
    Map<String, dynamic>? extras,
  }) async {
    if (distanciaKm == null || !distanciaKm.isFinite || distanciaKm <= 0) {
      return const <String, int>{};
    }
    try {
      final dynamic peajeRaw = extras?['peajeRd'] ?? extras?['peaje'];
      final double peaje =
          peajeRaw is num && peajeRaw.isFinite && peajeRaw > 0
              ? peajeRaw.toDouble()
              : 0.0;
      return await TarifaServiceUnificado().cotizarNormalPorTipoVehiculoCents(
        distanciaKm: distanciaKm,
        tipoVehiculoPedido: tipoVehiculoPedido,
        precioAcordadoCents: precioAcordadoCents,
        idaVuelta: idaYVuelta,
        peaje: peaje,
        forzarTarifaUrbanaLocal: extras?['forzarTarifaUrbanaLocal'] == true,
      );
    } catch (e) {
      _viajesRepoDebugLog('preciosPorTipoVehiculo falló: $e');
      return const <String, int>{};
    }
  }

  // ==============================================================
  //                           CREATE
  // ==============================================================
  static Future<String> crearViajePendiente({
    required String uidCliente,
    required String origen,
    required String destino,
    required double latOrigen,
    required double lonOrigen,
    required double latDestino,
    required double lonDestino,
    required DateTime fechaHora,
    required double precio,
    required String metodoPago,
    required String tipoVehiculo,
    required bool idaYVuelta,
    String? categoria,
    List<Map<String, dynamic>>? waypoints,
    Map<String, dynamic>? extras,
    double? distanciaKm,
    String? tipoServicio,
    String? subtipoTurismo,
    String? catalogoTurismoId,
    String? canalAsignacion,
    DateTime? publishAt,
    DateTime? acceptAfter,
    /// Tab Programar con recogida pronto: alinear `esAhora`/`programado` con pool ya abierto.
    bool? forzarEsAhora,
    /// Turismo: publicar en pool turístico (no auto-asignar chofer).
    bool turismoPublicarEnPool = true,

    /// Si se publica también en `bolas_pueblo`, enlaza el viaje espejo del pool para negociación en Bola.
    String? bolaPuebloId,

    /// % comisión RAI (0–100) alineado con [PlataformaEconomia] para espejo Bola / cierre efectivo.
    double? comisionPorcentajeViaje,

    /// Corporativo / servicios internos: no hijackear viajeActivoId del encargado.
    bool vincularUsuarioCliente = true,
  }) async {
    ClienteCuentaRealPolicy.exigirParaPedirViaje();
    await ClienteVerificacionIdentidadService.exigirParaPedirViaje();

    double _round6Coord(num v) => double.parse(v.toStringAsFixed(6));

    bool _coordsInvalidas(double lat, double lon) =>
        !(lat.isFinite && lon.isFinite) ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180 ||
        (lat.abs() < 1e-6 && lon.abs() < 1e-6);

    latOrigen = _round6Coord(latOrigen);
    lonOrigen = _round6Coord(lonOrigen);
    latDestino = _round6Coord(latDestino);
    lonDestino = _round6Coord(lonDestino);

    if (_coordsInvalidas(latOrigen, lonOrigen) ||
        _coordsInvalidas(latDestino, lonDestino)) {
      throw ArgumentError('Coordenadas inválidas');
    }
    if (!precio.isFinite || precio < 0) {
      throw ArgumentError('Precio inválido');
    }

    final clienteSnap = await _db.collection('usuarios').doc(uidCliente).get();
    final usuarioData = Map<String, dynamic>.from(clienteSnap.data() ?? {});
    final codigoRef =
        (usuarioData['negocioReferidoCodigo'] ?? '').toString().trim();
    if (codigoRef.isNotEmpty &&
        (usuarioData['negocioReferidoCiudad'] ?? '').toString().trim().isEmpty) {
      final neg = await NegociosAliadosRepo.obtenerPorCodigo(codigoRef);
      if (neg != null && neg.ciudad.trim().isNotEmpty) {
        usuarioData['negocioReferidoCiudad'] = neg.ciudad.trim();
      }
    }
    final promoAplicada =
        await NegocioAliadoPromoService.aplicarAlCrearViajeConUbicacion(
      usuario: usuarioData,
      precioNominalRd: precio,
      origen: origen,
      destino: destino,
      latOrigen: latOrigen,
      lonOrigen: lonOrigen,
      latDestino: latDestino,
      lonDestino: lonDestino,
    );
    var precioEfectivo = precio;
    if (promoAplicada != null) {
      precioEfectivo = promoAplicada.precioCliente;
    }
    if (!precioEfectivo.isFinite || precioEfectivo < 0) {
      throw ArgumentError('Precio inválido');
    }
    if (precioEfectivo == 0 && promoAplicada == null) {
      throw ArgumentError('Precio inválido');
    }

    final int precioCents = (precioEfectivo * 100).round();
    await ComisionViajePctService.refresh();
    final pctComision = promoAplicada != null
        ? NegocioAliadoConfig.pctComisionTaxistaReferido
        : ((comisionPorcentajeViaje != null &&
                comisionPorcentajeViaje.isFinite &&
                comisionPorcentajeViaje > 0 &&
                comisionPorcentajeViaje <= 100)
            ? comisionPorcentajeViaje
            : PlataformaEconomia.comisionViajePorcentaje);
    if (!pctComision.isFinite || pctComision < 0 || pctComision > 100) {
      throw ArgumentError('Comisión inválida');
    }

    final DateTime now = DateTime.now();
    final bool esAhora = forzarEsAhora ??
        TripPublishWindows.esAhoraPorFechaPickup(fechaHora, now);

    // Viajes AHORA: pool y aceptación inmediatos.
    // Programados: pool desde `poolLeadMinutesProgramado` antes de la recogida (TripPublishWindows).
    final DateTime publishAtDT = publishAt ??
        (esAhora ? now : poolOpensAtForScheduledPickup(fechaHora, now));
    final DateTime acceptAfterDT = acceptAfter ??
        (esAhora
            ? now
            : TripPublishWindows.acceptAfterForScheduledPickup(fechaHora, now));
    final DateTime startWindowDT = esAhora
        ? now
        : TripPublishWindows.startWindowAtForScheduledPickup(fechaHora, now);

    List<Map<String, dynamic>>? _sanitize(List<Map<String, dynamic>>? wps) {
      if (wps == null) return null;
      final out = MultiparadaRutaHelper.sanitizarWaypoints(wps);
      return out.isEmpty ? null : out;
    }

    final doc = _col.doc();

    if (isPasajeroCapableFlavor) {
      PoolTimbreSessionGuard.activarSesionPasajero();
      await NotificationService.I.prepararViajeClienteSinTimbre(doc.id);
    }

    final String codigoVerificacion =
        (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();

    final String tipoSrvFinal =
        (tipoServicio ?? '').trim().isEmpty ? 'normal' : tipoServicio!.trim();

    late final String canalFinal;
    String tipoVehiculoFormateado = tipoVehiculo;
    if (tipoSrvFinal == 'motor') {
      tipoVehiculoFormateado = '🛵 MOTOR 🛵';
    } else if (tipoSrvFinal == 'turismo') {
      tipoVehiculoFormateado = '🏝️ TURISMO 🏝️';
    } else if (tipoSrvFinal == 'normal') {
      tipoVehiculoFormateado = '🚗 NORMAL';
    } else if (tipoSrvFinal == 'bola_ahorro') {
      tipoVehiculoFormateado = '💚 AHORRA';
    }

    late final String estadoInicial;
    if (tipoSrvFinal == 'turismo') {
      if (esAhora) {
        // Mismo criterio que pool normal: visible de inmediato para choferes turismo.
        canalFinal = AsignacionTurismoRepo.canalTurismoPool;
        estadoInicial = EstadosViaje.pendiente;
      } else {
        canalFinal = 'admin';
        estadoInicial = 'pendiente_admin';
      }
    } else {
      canalFinal = (canalAsignacion ?? '').trim().isEmpty
          ? 'pool'
          : canalAsignacion!.trim();
      // Tarjeta + AZUL activo: `pendiente_pago`. Si AZUL aún no está en prod,
      // guardamos Tarjeta como preferencia pero el viaje entra al pool normal.
      estadoInicial = MetodoPagoViaje.esTarjeta(metodoPago) &&
              PagoTarjetaClienteGate.cobroHabilitado
          ? EstadosViaje.pendientePago
          : EstadosViaje.pendiente;
    }

    final data = <String, dynamic>{
      'id': doc.id,
      'clienteId': uidCliente,
      'uidCliente': uidCliente,
      'uidTaxista': '',
      'taxistaId': '',
      'nombreTaxista': '',
      'telefono': '',
      'placa': '',
      'tipoVehiculo': tipoVehiculoFormateado,
      'tipoVehiculoOriginal': tipoVehiculo,
      'marca': '',
      'modelo': '',
      'color': '',
      'origen': origen,
      'destino': destino,
      'latCliente': latOrigen,
      'lonCliente': lonOrigen,
      'latOrigen': latOrigen,
      'lonOrigen': lonOrigen,
      'latDestino': latDestino,
      'lonDestino': lonDestino,
      'origenGeoPoint': GeoPoint(latOrigen, lonOrigen),
      'destinoGeoPoint': GeoPoint(latDestino, lonDestino),
      'sentido': idaYVuelta ? 'ida_y_vuelta' : 'solo_ida',
      'idaYVuelta': idaYVuelta,
      // El cliente paga el recargo del regreso, así que el viaje no se puede
      // cerrar en el destino de ida: o lo devuelven, o se le quita el recargo.
      if (idaYVuelta && tipoSrvFinal != 'turismo') ...<String, dynamic>{
        'regresoPendiente': true,
        'regresoEnCurso': false,
        'precioSoloIdaCents': (precioCents / 1.8).round(),
      },
      'fechaHora': Timestamp.fromDate(fechaHora),
      'acceptAfter': Timestamp.fromDate(acceptAfterDT),
      'publishAt': Timestamp.fromDate(publishAtDT),
      'startWindowAt': Timestamp.fromDate(startWindowDT),
      'programado': !esAhora,
      'esAhora': esAhora,
      if (!esAhora) 'poolOpeningPushSent': false,
      'metodoPago': metodoPago,
      'transferenciaConfirmada': false,
      'estadoPago': 'pendiente',
      'pagoATaxistaPendiente': false,
      'estado': estadoInicial,
      'aceptado': false,
      'rechazado': false,
      'completado': false,
      'codigoVerificacion': codigoVerificacion,
      'codigoVerificado': false,
      'activo': esAhora,
      'ignoradosPor': <String>[],
      'reservadoPor': '',
      'reservadoHasta': null,
      'precio': precioCents / 100.0,
      'precio_cents': precioCents,
      'comisionPorcentaje': pctComision,
      'latTaxista': 0.0,
      'lonTaxista': 0.0,
      'driverLat': 0.0,
      'driverLon': 0.0,
      'tipoServicio': tipoSrvFinal,
      if (subtipoTurismo != null && subtipoTurismo.isNotEmpty)
        'subtipoTurismo': subtipoTurismo,
      if (catalogoTurismoId != null && catalogoTurismoId.isNotEmpty)
        'catalogoTurismoId': catalogoTurismoId,
      'canalAsignacion': canalFinal,
      if (categoria != null && categoria.isNotEmpty) 'categoria': categoria,
      if (distanciaKm != null && distanciaKm.isFinite && distanciaKm > 0)
        'distanciaKm': distanciaKm,
      'creadoEn': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    };

    // El claim pisa `tipoVehiculo`/`tipoVehiculoOriginal` con los del chofer, así
    // que lo pedido se guarda aparte junto con la tarifa equivalente de cada
    // tipo: si acepta un vehículo más barato, el backend le cobra ese al cliente.
    if (tipoSrvFinal == 'normal') {
      final String tipoPedido =
          TarifasTramosConfig.normalizarClaveVehiculo(tipoVehiculo);
      if (tipoPedido.isNotEmpty) {
        data['tipoVehiculoSolicitado'] = tipoPedido;
        final Map<String, int> porTipo = await _preciosPorTipoVehiculoCents(
          distanciaKm: distanciaKm,
          tipoVehiculoPedido: tipoPedido,
          precioAcordadoCents: precioCents,
          idaYVuelta: idaYVuelta,
          extras: extras,
        );
        if (porTipo.length > 1) {
          data['preciosPorTipoVehiculoCents'] = porTipo;
        }
      }
    }

    final wps = _sanitize(waypoints);
    if (wps != null) {
      data['waypoints'] = wps;
      (extras ??= <String, dynamic>{})['paradas_count'] = wps.length;
      // Plan multiparada fijado al crear (navegación lee waypoints + destino).
      final bool destOk = !_coordsInvalidas(latDestino, lonDestino);
      final int legsTotal = wps.length + (destOk ? 1 : 0);
      if (legsTotal > 0) {
        data['multiparadaLegsTotal'] = legsTotal;
        data['multiparadaLegCompletadas'] = 0;
        data['multiparadaParadasVisitadas'] = <Map<String, dynamic>>[];
        data['multiparadaParadasAbiertas'] = <int>[];
        data['multiparadaRecogidaAbierta'] = false;
        data['multiparadaCompleta'] = false;
      }
    }
    final dynamic rutaExistente = data['rutaPuntos'];
    final bool sinRutaPuntos = rutaExistente is! List || rutaExistente.isEmpty;
    if (sinRutaPuntos) {
      data['rutaPuntos'] = MultiparadaRutaHelper.construirRutaPuntos(
        latOrigen: latOrigen,
        lonOrigen: lonOrigen,
        labelOrigen: origen,
        latDestino: latDestino,
        lonDestino: lonDestino,
        labelDestino: destino,
        waypoints: wps ?? const <Map<String, dynamic>>[],
      );
    }
    if (extras != null && extras.isNotEmpty) {
      final cleanExtras = _sanitizeTripMap(extras);
      if (cleanExtras.isNotEmpty) data['extras'] = cleanExtras;
      // Multiparada: plan en raíz del viaje (taxista/cliente no dependen solo de extras).
      final dynamic rutaPuntos = cleanExtras['rutaPuntos'];
      if (rutaPuntos is List && rutaPuntos.isNotEmpty) {
        data['rutaPuntos'] = rutaPuntos;
      }
      final dynamic segmentosMulti = cleanExtras['segmentos'];
      if (segmentosMulti is List && segmentosMulti.isNotEmpty) {
        data['segmentos'] = segmentosMulti;
      }
    }
    if (data['extras'] is Map &&
        (data['extras'] as Map)['precioBloqueado'] == true) {
      data['precioBloqueado'] = true;
      final cond = (data['extras'] as Map)['cotizacionCondiciones'];
      if (cond is Map) {
        data['cotizacionCondiciones'] = Map<String, dynamic>.from(cond);
      }
    } else if (extras?['precioBloqueado'] == true) {
      data['precioBloqueado'] = true;
      final cond = extras?['cotizacionCondiciones'];
      if (cond is Map) {
        data['cotizacionCondiciones'] = Map<String, dynamic>.from(cond);
      }
    }
    if (promoAplicada != null) {
      data.addAll(promoAplicada.campos);
    }

    final String? bolaTrim = bolaPuebloId?.trim();
    if (bolaTrim != null && bolaTrim.isNotEmpty) {
      data['bolaPuebloId'] = bolaTrim;
      data['bolaNegociacionAbierta'] = true;
    }

    await _ensurePerfilClienteOperativo(uidCliente);
    await _prepararSesionClienteAntesCrearViaje(uidCliente);
    await FirebaseAuth.instance.currentUser?.getIdToken(true);

    final userRef = _db.collection('usuarios').doc(uidCliente);
    final String authUid =
        (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final bool usarCallableCliente = vincularUsuarioCliente &&
        isPasajeroCapableFlavor &&
        authUid == uidCliente.trim();

    final Map<String, dynamic> tripData = _sanitizeTripMap(data);

    try {
      await _persistViajePendienteCliente(
        doc: doc,
        tripData: tripData,
        uidCliente: uidCliente,
        userRef: userRef,
        nuevoEsAhora: esAhora,
        vincularUsuarioCliente: vincularUsuarioCliente,
        usarCallableCliente: usarCallableCliente,
      );
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition' &&
          (e.message ?? '').toLowerCase().contains('viaje activo')) {
        throw StateError(kMsgClienteYaTieneViajeActivo);
      }
      if (_callableCrearViajeReintentarLocal(e)) {
        throw StateError(kMsgCrearViajeServidorNoDisponible);
      }
      if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
        throw StateError(kMsgCrearViajeSinPermisoCliente);
      }
      rethrow;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw StateError(kMsgCrearViajeSinPermisoCliente);
      }
      rethrow;
    }

    if (isPasajeroCapableFlavor) {
      await NotificationService.I.marcarViajePropioSinTimbre(doc.id);
    }

    _viajesRepoDebugLog(
      '✅ crearViajePendiente OK viajeId=${doc.id} esAhora=$esAhora',
    );

    if (tipoSrvFinal == 'turismo' &&
        turismoPublicarEnPool &&
        canalFinal != AsignacionTurismoRepo.canalTurismoPool) {
      try {
        await AsignacionTurismoRepo.publicarViajeEnPoolTurismo(
          viajeId: doc.id,
          omitirVentanaPublicacion: esAhora == true,
        );
      } catch (e, st) {
        await ErrorReporting.reportError(
          e,
          stack: st,
          context: 'crearViajePendiente(turismo pool)',
        );
      }
    }

    unawaited(AnalyticsRai.logTripRequested());
    return doc.id;
  }

  /// Después de `claimTripWithReason` en un viaje del pool turístico, alinea `choferes_turismo` como en asignación ADM.
  static Future<void> sincronizarChoferTurismoTrasAceptarDesdePool({
    required String uidChofer,
    required String viajeId,
  }) async {
    await _db.collection('choferes_turismo').doc(uidChofer).set(
      {
        'disponible': false,
        'viajeActualId': viajeId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> ensureTaxistaLibre(String uidTaxista) async {
    _viajesRepoDebugLog('🟡 ensureTaxistaLibre - uid: $uidTaxista');
    try {
      final userDoc = await _db.collection('usuarios').doc(uidTaxista).get();
      final String viajeActivoId =
          (userDoc.data()?['viajeActivoId'] ?? '').toString().trim();
      _viajesRepoDebugLog('📄 ensureTaxistaLibre - viajeActivoId: $viajeActivoId');

      if (viajeActivoId.isEmpty) {
        _viajesRepoDebugLog('✅ ensureTaxistaLibre - OK (sin viajeActivoId)');
        return;
      }

      DocumentSnapshot<Map<String, dynamic>> tripDoc;
      try {
        tripDoc = await _col.doc(viajeActivoId).get();
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied' || e.code == 'permission_denied') {
          // No borrar viajeActivoId: suele ser transitorio (auth/cambio de app).
          _viajesRepoDebugLog(
            '⚠️ ensureTaxistaLibre - sin lectura viaje (conservar viajeActivoId): $e',
          );
          return;
        }
        rethrow;
      }
      if (!tripDoc.exists) {
        await _limpiarViajeActivoIdTaxista(uidTaxista);
        _viajesRepoDebugLog('✅ ensureTaxistaLibre - limpiado (viaje inexistente)');
        return;
      }

      final d = tripDoc.data() ?? <String, dynamic>{};
      final assignedUid =
          (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString().trim();
      if (assignedUid != uidTaxista) {
        await _limpiarViajeActivoIdTaxista(uidTaxista);
        _viajesRepoDebugLog('✅ ensureTaxistaLibre - limpiado (viaje de otro taxista)');
        return;
      }

      if (!viajeOperativoBloqueanteParaTaxista(d, uidTaxista)) {
        await _limpiarViajeActivoIdTaxista(uidTaxista);
        _viajesRepoDebugLog(
          '✅ ensureTaxistaLibre - limpiado (sin viaje bloqueante operativo)',
        );
        return;
      }

      _viajesRepoDebugLog('✅ ensureTaxistaLibre - OK (viaje activo vigente)');
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'permission_denied') {
        _viajesRepoDebugLog(
          '⚠️ ensureTaxistaLibre permission-denied (no bloquea claim): $e',
        );
        return;
      }
      _viajesRepoDebugLog('❌ ensureTaxistaLibre error: $e');
      rethrow;
    } catch (e) {
      _viajesRepoDebugLog('❌ ensureTaxistaLibre error: $e');
      rethrow;
    }
  }

  static Future<void> _limpiarViajeActivoIdTaxista(String uidTaxista) async {
    await _db.collection('usuarios').doc(uidTaxista).set({
      'viajeActivoId': '',
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static bool _usuarioEsClienteEnDocViaje(
    Map<String, dynamic> data,
    String uid,
  ) {
    final String u = uid.trim();
    if (u.isEmpty) return false;
    return (data['uidCliente'] ?? '').toString().trim() == u ||
        (data['clienteId'] ?? '').toString().trim() == u;
  }

  static bool viajeOperativoBloqueanteParaCliente(
    Map<String, dynamic> data,
    String uidCliente,
  ) {
    final String uid = uidCliente.trim();
    if (uid.isEmpty) return false;
    if (!_usuarioEsClienteEnDocViaje(data, uid)) return false;
    if (data['completado'] == true) return false;
    final String estado =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());
    if (EstadosViaje.esTerminal(estado)) return false;
    if (EstadosViaje.esPendiente(estado) ||
        estado == EstadosViaje.pendientePago) {
      return true;
    }
    return estado == EstadosViaje.aceptado ||
        estado == EstadosViaje.enCaminoPickup ||
        estado == EstadosViaje.aBordo ||
        estado == EstadosViaje.enCurso;
  }

  /// Solo borra `viajeActivoId` si apunta a [viajeId] y ese doc ya no existe.
  /// Seguro para cliente y taxista (no usa reglas de chofer).
  static Future<void> limpiarViajeActivoIdSiViajeInexistente({
    required String uid,
    required String viajeId,
  }) async {
    final String u = uid.trim();
    final String vid = viajeId.trim();
    if (u.isEmpty || vid.isEmpty) return;
    try {
      final uSnap = await _db.collection('usuarios').doc(u).get();
      final String activo =
          (uSnap.data()?['viajeActivoId'] ?? '').toString().trim();
      if (activo != vid) return;
      final vSnap =
          await _col.doc(vid).get(const GetOptions(source: Source.server));
      if (vSnap.exists) return;
      await _limpiarViajeActivoIdTaxista(u);
      _viajesRepoDebugLog(
        '✅ limpiarViajeActivoIdSiViajeInexistente uid=$u vid=$vid',
      );
    } catch (_) {}
  }

  /// Cliente: limpia `viajeActivoId` huérfano sin confundir con uid del taxista.
  static Future<void> ensureClienteViajeActivoCoherente(String uidCliente) async {
    final String uid = uidCliente.trim();
    if (uid.isEmpty) return;
    try {
      final uSnap = await _db.collection('usuarios').doc(uid).get();
      final String vid =
          (uSnap.data()?['viajeActivoId'] ?? '').toString().trim();
      if (vid.isEmpty) return;

      final vSnap = await _col.doc(vid).get();
      if (!vSnap.exists) {
        await _limpiarViajeActivoIdTaxista(uid);
        return;
      }
      final Map<String, dynamic> d = vSnap.data() ?? <String, dynamic>{};
      if (!_usuarioEsClienteEnDocViaje(d, uid)) {
        await _limpiarViajeActivoIdTaxista(uid);
        return;
      }
      if (!viajeOperativoBloqueanteParaCliente(d, uid)) {
        await _limpiarViajeActivoIdTaxista(uid);
      }
    } catch (_) {}
  }

  static Future<void> limpiarViajeActivoClienteSiNoOperativo(
    String uidCliente,
  ) async {
    await ensureClienteViajeActivoCoherente(uidCliente);
  }

  static Future<void> ensureSiguienteCoherente(String uidTaxista) async {
    _viajesRepoDebugLog('🟡 ensureSiguienteCoherente - uid: $uidTaxista');
    final uRef = _db.collection('usuarios').doc(uidTaxista);
    try {
      final u = await uRef.get();
      final m = u.data() ?? {};
      final String nextId = (m['siguienteViajeId'] ?? '').toString();
      _viajesRepoDebugLog('📄 ensureSiguienteCoherente - siguienteViajeId: $nextId');
      if (nextId.isEmpty) {
        _viajesRepoDebugLog('✅ ensureSiguienteCoherente - OK (sin siguiente)');
        return;
      }

      final vRef = _col.doc(nextId);
      final v = await vRef.get();
      if (!v.exists) {
        await uRef.set({'siguienteViajeId': ''}, SetOptions(merge: true));
        _viajesRepoDebugLog('✅ ensureSiguienteCoherente - limpiado (viaje no existe)');
        return;
      }
      final d = v.data()!;
      final String estado = (d['estado'] ?? '').toString();
      final String uidAsig = (d['uidTaxista'] ?? '').toString();
      final String reservadoPor = (d['reservadoPor'] ?? '').toString();
      final Timestamp? reservadoHasta = d['reservadoHasta'];
      final bool reservaVencida = reservadoHasta != null &&
          reservadoHasta.compareTo(Timestamp.now()) <= 0;

      final ok = (estado == EstadosViaje.pendiente ||
              estado == EstadosViaje.pendientePago ||
              estado == 'pendiente_admin') &&
          uidAsig.isEmpty &&
          reservadoPor == uidTaxista &&
          !reservaVencida;
      _viajesRepoDebugLog(
          '📄 ensureSiguienteCoherente - estado=$estado uidAsig=$uidAsig reservadoPor=$reservadoPor ok=$ok');

      if (!ok) {
        try {
          await _db.runTransaction((tx) async {
            tx.update(vRef, {
              'reservadoPor': '',
              'reservadoHasta': null,
              'updatedAt': FieldValue.serverTimestamp(),
              'actualizadoEn': FieldValue.serverTimestamp()
            });
            tx.set(
                uRef,
                {
                  'siguienteViajeId': '',
                  'updatedAt': FieldValue.serverTimestamp(),
                  'actualizadoEn': FieldValue.serverTimestamp()
                },
                SetOptions(merge: true));
          });
        } on FirebaseException catch (e) {
          if (e.code != 'permission-denied' && e.code != 'permission_denied') {
            rethrow;
          }
          _viajesRepoDebugLog(
            '⚠️ ensureSiguienteCoherente: limpieza reserva omitida (rules)',
          );
          try {
            await uRef.set(
              {
                'siguienteViajeId': '',
                'updatedAt': FieldValue.serverTimestamp(),
                'actualizadoEn': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          } catch (_) {}
        }
        try {
          await uRef.collection('cola_viajes').doc(nextId).set(
            {
              'estado': 'invalidado',
              'motivo': 'reserva_invalida',
              'invalidadoEn': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        } catch (_) {
          // Cola solo servidor; no bloquear aceptar viaje del pool.
        }
      }
      _viajesRepoDebugLog('✅ ensureSiguienteCoherente - OK');
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'permission_denied') {
        _viajesRepoDebugLog(
          '⚠️ ensureSiguienteCoherente permission-denied (no bloquea claim): $e',
        );
        return;
      }
      _viajesRepoDebugLog('❌ ensureSiguienteCoherente error: $e');
      rethrow;
    } catch (e) {
      _viajesRepoDebugLog('❌ ensureSiguienteCoherente error: $e');
      rethrow;
    }
  }

  static Future<void> _ensureChatForTrip(String viajeId) async {
    final v = await _col.doc(viajeId).get();
    if (!v.exists) return;
    final d = v.data()!;
    final String uidCli = ViajesRepo.uidClienteDesdeDocViaje(d);
    final String uidTx = (d['uidTaxista'] ??
            d['taxistaId'] ??
            d['corporativoChoferAsignadoUid'] ??
            d['corporativoChoferPreferidoUid'] ??
            '')
        .toString();
    if (uidCli.isEmpty && uidTx.isEmpty) return;

    final String uidActual =
        (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final Set<String> participantes = <String>{
      if (uidCli.isNotEmpty) uidCli,
      if (uidTx.isNotEmpty) uidTx,
      if (uidActual.isNotEmpty) uidActual,
    };

    if (participantes.length < 2) {
      final empId = (d['corporativoEmpresaId'] ?? '').toString().trim();
      if (empId.isNotEmpty) {
        try {
          final empSnap =
              await _db.collection('empresas_corporativas').doc(empId).get();
          final raw = empSnap.data()?['encargadoUids'];
          if (raw is List) {
            for (final item in raw) {
              final uid = item.toString().trim();
              if (uid.isNotEmpty) participantes.add(uid);
            }
          }
        } catch (_) {}
      }
    }
    if (participantes.length < 2) return;

    final cRef = _db.collection('chats').doc(viajeId);
    final c = await cRef.get();
    if (!c.exists) {
      await cRef.set({
        'participantes': participantes.toList(),
        'viajeId': viajeId,
        'lastMessage': '',
        'lastAt': FieldValue.serverTimestamp(),
        'creadoAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final raw = c.data()?['participantes'];
    final existentes = raw is List
        ? raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toSet()
        : <String>{};
    final merged = <String>{...existentes, ...participantes};
    if (merged.length == existentes.length) return;

    await cRef.set(
      {
        'participantes': merged.toList(),
        'viajeId': viajeId,
        'lastAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Asegura `chats/{viajeId}` (participantes cliente/taxista). Usado por la pantalla de chat en viaje.
  static Future<void> ensureChatDocForViaje(String viajeId) =>
      _ensureChatForTrip(viajeId.trim());

  static Future<bool> claimTrip({
    required String viajeId,
    required String uidTaxista,
    required String nombreTaxista,
    String telefono = '',
    String placa = '',
    String tipoVehiculo = '',
  }) async {
    final ref = _col.doc(viajeId);
    final uRef = _db.collection('usuarios').doc(uidTaxista);

    final bool ok = await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');
      final data = snap.data()!;

      final String estado = (data['estado'] ?? '').toString();
      final bool yaAsignado =
          ((data['uidTaxista'] ?? '') as String).isNotEmpty ||
              ((data['taxistaId'] ?? '') as String).isNotEmpty;
      final bool estadoPermitido = (estado == EstadosViaje.pendiente ||
          estado == EstadosViaje.pendientePago ||
          estado == 'pendiente_admin');
      if (!estadoPermitido || yaAsignado) return false;

      final String reservadoPor = (data['reservadoPor'] ?? '').toString();
      final Timestamp? reservadoHasta = data['reservadoHasta'];
      final bool reservaVigente = reservadoPor.isNotEmpty &&
          (reservadoHasta == null ||
              reservadoHasta.compareTo(Timestamp.now()) > 0);
      if (reservaVigente && reservadoPor != uidTaxista) return false;

      final tsAcceptAfter = data['acceptAfter'];
      if (tsAcceptAfter is Timestamp) {
        final DateTime acceptAfter = tsAcceptAfter.toDate();
        if (DateTime.now().isBefore(acceptAfter)) return false;
      }

      final uSnap = await tx.get(uRef);
      final uData = uSnap.data() ?? <String, dynamic>{};
      final rechazoClaim = taxistaRechazoAceptarViajePool(uData);
      if (rechazoClaim != null) return false;
      final bSnap =
          await tx.get(_db.collection('billeteras_taxista').doc(uidTaxista));
      if (!PagosTaxistaRepo.taxistaSinBloqueoPrepagoOperativo(
          uData, bSnap.data())) {
        return false;
      }
      final prepagoRechazo =
          PagosTaxistaRepo.codigoRechazoPrepagoInsuficienteComisionViaje(
        billeData: bSnap.data(),
        viajeData: data,
      );
      if (prepagoRechazo != null) return false;
      final String viajeActivoId =
          (uData['viajeActivoId'] ?? '').toString().trim();
      if (viajeActivoId.isNotEmpty && viajeActivoId != viajeId) {
        final activoSnap = await tx.get(_col.doc(viajeActivoId));
        if (activoSnap.exists) {
          final ad = activoSnap.data() ?? <String, dynamic>{};
          if (viajeOperativoBloqueanteParaTaxista(ad, uidTaxista)) {
            return false;
          }
        }
        tx.set(
          uRef,
          {
            'viajeActivoId': '',
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      final String _tel =
          (telefono.isNotEmpty ? telefono : (uData['telefono'] ?? ''))
              .toString();
      final String _plac =
          (placa.isNotEmpty ? placa : (uData['placa'] ?? '')).toString();
      final String _tipo = (tipoVehiculo.isNotEmpty
              ? tipoVehiculo
              : (uData['tipoVehiculo'] ?? ''))
          .toString();
      final String _marca =
          (uData['marca'] ?? uData['vehiculoMarca'] ?? '').toString();
      final String _modelo =
          (uData['modelo'] ?? uData['vehiculoModelo'] ?? '').toString();
      final String _color =
          (uData['color'] ?? uData['vehiculoColor'] ?? '').toString();

      final String tipoServicio = data['tipoServicio'] ?? 'normal';
      String tipoVehiculoFormateado = _tipo;
      if (tipoServicio == 'motor') {
        tipoVehiculoFormateado = '🛵 MOTOR 🛵';
      } else if (tipoServicio == 'turismo') {
        tipoVehiculoFormateado = '🏝️ TURISMO 🏝️';
      } else if (tipoServicio == 'normal') {
        tipoVehiculoFormateado = '🚗 NORMAL';
      } else if (tipoServicio == 'bola_ahorro') {
        tipoVehiculoFormateado = '💚 AHORRA';
      }

      final String bolaPidClaim =
          (data['bolaPuebloId'] ?? data['bolaId'] ?? '').toString().trim();
      final bool cierraNegBola =
          bolaPidClaim.isNotEmpty || tipoServicio == 'bola_ahorro';

      final patch = <String, dynamic>{
        'uidTaxista': uidTaxista,
        'taxistaId': uidTaxista,
        'nombreTaxista': nombreTaxista,
        'telefono': _tel,
        'placa': _plac,
        'tipoVehiculo': tipoVehiculoFormateado,
        'tipoVehiculoOriginal': _tipo,
        'marca': _marca,
        'modelo': _modelo,
        'color': _color,
        'latTaxista': 0.0,
        'lonTaxista': 0.0,
        'driverLat': 0.0,
        'driverLon': 0.0,
        'estado': EstadosViaje.aceptado,
        'aceptado': true,
        'rechazado': false,
        'activo': true,
        'aceptadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
        'ignoradosPor': FieldValue.delete(),
        'reservadoPor': '',
        'reservadoHasta': null,
      };
      if (cierraNegBola) {
        patch['bolaNegociacionAbierta'] = false;
      }

      tx.update(ref, patch);

      tx.set(
          uRef,
          {
            'viajeActivoId': viajeId,
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));

      return true;
    });

    if (ok) {
      await _limpiarOtrosActivosDelTaxista(uidTaxista, exceptoId: viajeId);
      await _limpiarSiguienteSiEsElClaimed(
        uidTaxista: uidTaxista,
        viajeIdClaimed: viajeId,
      );
      await _ensureChatForTrip(viajeId);
      unawaited(BolaPuebloFirestoreSync.postClaimViajeEspejo(viajeId));
    }
    return ok;
  }

  /// No borra una ruta corporativa (u otra) encolada en `siguienteViajeId`.
  static Future<void> limpiarSiguienteSiEsElClaimed({
    required String uidTaxista,
    required String viajeIdClaimed,
  }) =>
      _limpiarSiguienteSiEsElClaimed(
        uidTaxista: uidTaxista,
        viajeIdClaimed: viajeIdClaimed,
      );

  static Future<void> _limpiarSiguienteSiEsElClaimed({
    required String uidTaxista,
    required String viajeIdClaimed,
  }) async {
    final uRef = _db.collection('usuarios').doc(uidTaxista);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(uRef);
      final sig =
          (snap.data()?['siguienteViajeId'] ?? '').toString().trim();
      if (sig.isNotEmpty && sig != viajeIdClaimed) {
        return;
      }
      tx.set(
        uRef,
        {
          'siguienteViajeId': '',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  /// Snapshot bancario del taxista en el viaje (paridad con `aceptarViajeSeguro` CF).
  static Map<String, String> _snapshotPerfilTaxistaBanco(
    Map<String, dynamic> uData,
  ) {
    return {
      'bancoTaxista': (uData['banco'] ?? '').toString().trim(),
      'numeroCuentaTaxista': (uData['numeroCuenta'] ?? '').toString().trim(),
      'tipoCuentaTaxista': (uData['tipoCuenta'] ?? '').toString().trim(),
      'titularCuentaTaxista':
          (uData['titularCuenta'] ?? uData['titular'] ?? '').toString().trim(),
      'ciTaxista': (uData['ciTaxista'] ?? uData['cedula'] ?? uData['cedulaTaxista'] ?? '')
          .toString()
          .trim(),
    };
  }

  /// Si el callable falla por red/rol/servidor, seguir con transacción Firestore local.
  static bool _claimCallablePermiteFallbackLocal(String? cfResult) {
    if (cfResult == null || cfResult.isEmpty) return true;
    if (cfResult == 'callable-no-disponible') return true;
    if (cfResult.startsWith('permiso:')) return true;
    return false;
  }

  static Future<void> _asegurarViajeActivoIdLegibleAntesClaim(
    String uidTaxista,
  ) async {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return;
    try {
      final uSnap = await _db.collection('usuarios').doc(uid).get();
      final vid = (uSnap.data()?['viajeActivoId'] ?? '').toString().trim();
      if (vid.isEmpty) return;
      try {
        await _col.doc(vid).get(const GetOptions(source: Source.server));
      } on FirebaseException catch (e) {
        final c = e.code.toLowerCase();
        if (c == 'permission-denied' || c == 'permission_denied') {
          await _limpiarViajeActivoIdTaxista(uid);
          _viajesRepoDebugLog(
            '✅ viajeActivoId ilegible limpiado antes de claim ($vid)',
          );
        }
      }
    } catch (e) {
      _viajesRepoDebugLog('⚠️ _asegurarViajeActivoIdLegibleAntesClaim: $e');
    }
  }

  static Future<String?> _resolverViajeActivoAntesClaim({
    required String uidTaxista,
    required String viajeId,
  }) async {
    final uSnap = await _db.collection('usuarios').doc(uidTaxista).get();
    final viajeActivoId =
        (uSnap.data()?['viajeActivoId'] ?? '').toString().trim();
    if (viajeActivoId.isEmpty || viajeActivoId == viajeId) {
      return null;
    }
    try {
      final activoSnap = await _col
          .doc(viajeActivoId)
          .get(const GetOptions(source: Source.server));
      if (!activoSnap.exists) {
        await _limpiarViajeActivoIdTaxista(uidTaxista);
        return null;
      }
      final ad = activoSnap.data() ?? <String, dynamic>{};
      if (viajeOperativoBloqueanteParaTaxista(ad, uidTaxista)) {
        return 'taxista-ocupado';
      }
      await _limpiarViajeActivoIdTaxista(uidTaxista);
      return null;
    } on FirebaseException catch (e) {
      final c = e.code.toLowerCase();
      if (c == 'permission-denied' || c == 'permission_denied') {
        await _limpiarViajeActivoIdTaxista(uidTaxista);
        _viajesRepoDebugLog(
          '✅ viajeActivoId sin lectura limpiado antes de claim ($viajeActivoId)',
        );
        return null;
      }
      rethrow;
    }
  }

  static Future<String?> _claimViajePorCallable({
    required String viajeId,
    required String uidTaxista,
    required String nombreTaxista,
    String telefono = '',
    String placa = '',
    String tipoVehiculo = '',
  }) async {
    for (var intento = 0; intento < 2; intento++) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          _viajesRepoDebugLog('❌ aceptarViajeSeguro: sin currentUser');
          return 'sesion-expirada';
        }
        if (user.uid.trim() != uidTaxista.trim()) {
          _viajesRepoDebugLog(
            '❌ aceptarViajeSeguro: uid auth=${user.uid} != taxista=$uidTaxista',
          );
          return 'sesion-expirada';
        }
        await user.getIdToken(intento > 0);
        final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('aceptarViajeSeguro');
        final idemKey =
            'accept_${viajeId}_${uidTaxista}_${DateTime.now().millisecondsSinceEpoch}';
        final resp = await callable.call(<String, dynamic>{
          'viajeId': viajeId,
          'nombreTaxista': nombreTaxista,
          'telefono': telefono,
          'placa': placa,
          'tipoVehiculo': tipoVehiculo,
          'idempotencyKey': idemKey,
        });
        final data = (resp.data is Map)
            ? Map<String, dynamic>.from(resp.data as Map)
            : <String, dynamic>{};
        if (data['ok'] == true) {
          _viajesRepoDebugLog('✅ aceptarViajeSeguro fallback OK');
          unawaited(AnalyticsRai.logTripAccepted());
          try {
            await _limpiarOtrosActivosDelTaxista(uidTaxista, exceptoId: viajeId);
            await _limpiarSiguienteSiEsElClaimed(
              uidTaxista: uidTaxista,
              viajeIdClaimed: viajeId,
            );
            await _ensureChatForTrip(viajeId);
          } catch (e) {
            _viajesRepoDebugLog(
                '⚠️ post-claim cleanup (no bloquea ok): $e');
          }
          unawaited(BolaPuebloFirestoreSync.postClaimViajeEspejo(viajeId));
          return 'ok';
        }
      } on FirebaseFunctionsException catch (e) {
        _viajesRepoDebugLog('❌ aceptarViajeSeguro: ${e.code} ${e.message}');
        if (e.code == 'unauthenticated' && intento == 0) {
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
          continue;
        }
        if (e.code == 'failed-precondition') {
          final m = (e.message ?? '').trim();
          if (m.isNotEmpty) return m;
        }
        if (e.code == 'permission-denied') {
          return 'permiso:${e.code}';
        }
        if (e.code == 'unauthenticated') {
          return 'sesion-expirada';
        }
        if (e.code == 'not-found' || e.code == 'unimplemented') {
          return 'callable-no-disponible';
        }
        if (e.code == 'unavailable' ||
            e.code == 'deadline-exceeded' ||
            e.code == 'internal' ||
            e.code == 'aborted' ||
            e.code == 'resource-exhausted') {
          return null;
        }
      } catch (cfErr) {
        _viajesRepoDebugLog('❌ aceptarViajeSeguro fallback error: $cfErr');
      }
      break;
    }
    return null;
  }

  static Future<bool> _viajeAsignadoATaxistaEnServidor({
    required String viajeId,
    required String uidTaxista,
  }) async {
    try {
      final snap = await _col
          .doc(viajeId)
          .get(const GetOptions(source: Source.server));
      if (!snap.exists) return false;
      final d = snap.data() ?? <String, dynamic>{};
      final uid =
          (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString().trim();
      return uid.isNotEmpty && uid == uidTaxista.trim();
    } catch (e) {
      _viajesRepoDebugLog('⚠️ _viajeAsignadoATaxistaEnServidor: $e');
      return false;
    }
  }

  static Future<void> _claimPostProcesoExitoso({
    required String viajeId,
    required String uidTaxista,
  }) async {
    try {
      await _limpiarOtrosActivosDelTaxista(uidTaxista, exceptoId: viajeId);
      await _limpiarSiguienteSiEsElClaimed(
        uidTaxista: uidTaxista,
        viajeIdClaimed: viajeId,
      );
      await _ensureChatForTrip(viajeId);
      _viajesRepoDebugLog('✅ Post-proceso completado');
    } catch (e) {
      _viajesRepoDebugLog('⚠️ post-claim cleanup (no bloquea ok): $e');
    }
    try {
      final DocumentSnapshot<Map<String, dynamic>> vSnap =
          await _col.doc(viajeId).get();
      final Map<String, dynamic> d = vSnap.data() ?? <String, dynamic>{};
      if (AsignacionTurismoRepo.esDocumentoViajeTurismo(d)) {
        await sincronizarChoferTurismoTrasAceptarDesdePool(
          uidChofer: uidTaxista,
          viajeId: viajeId,
        );
        final String uidCli =
            (d['uidCliente'] ?? d['clienteId'] ?? '').toString().trim();
        if (uidCli.isNotEmpty) {
          await _db.collection('usuarios').doc(uidCli).set(
            <String, dynamic>{
              'viajeActivoId': viajeId,
              'updatedAt': FieldValue.serverTimestamp(),
              'actualizadoEn': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }
    } catch (e) {
      _viajesRepoDebugLog('⚠️ post-claim turismo pool sync: $e');
    }
    unawaited(AnalyticsRai.logTripAccepted());
    unawaited(BolaPuebloFirestoreSync.postClaimViajeEspejo(viajeId));
    unawaited(ensureCodigoVerificacionViaje(viajeId));
  }

  static Future<String?> _claimViajeIntentarCallableConRetry({
    required String viajeId,
    required String uidTaxista,
    required String nombreTaxista,
    String telefono = '',
    String placa = '',
    String tipoVehiculo = '',
  }) async {
    var cf = await _claimViajePorCallable(
      viajeId: viajeId,
      uidTaxista: uidTaxista,
      nombreTaxista: nombreTaxista,
      telefono: telefono,
      placa: placa,
      tipoVehiculo: tipoVehiculo,
    );
    if (cf == 'ok') return 'ok';
    if (cf == 'taxista-ocupado') {
      await limpiarViajeActivoSiNoOperativo(uidTaxista);
      cf = await _claimViajePorCallable(
        viajeId: viajeId,
        uidTaxista: uidTaxista,
        nombreTaxista: nombreTaxista,
        telefono: telefono,
        placa: placa,
        tipoVehiculo: tipoVehiculo,
      );
    }
    return cf;
  }

  static Future<String> _claimResolverTrasFalloPermiso({
    required String viajeId,
    required String uidTaxista,
    required String nombreTaxista,
    String telefono = '',
    String placa = '',
    String tipoVehiculo = '',
    String? cfResult,
    required String codigoPermiso,
  }) async {
    if (cfResult == 'ok') return 'ok';
    if (await _viajeAsignadoATaxistaEnServidor(
      viajeId: viajeId,
      uidTaxista: uidTaxista,
    )) {
      await _claimPostProcesoExitoso(
        viajeId: viajeId,
        uidTaxista: uidTaxista,
      );
      return 'ok';
    }
    if (cfResult != null &&
        cfResult.isNotEmpty &&
        !_claimCallablePermiteFallbackLocal(cfResult)) {
      return cfResult;
    }
    return 'permiso:$codigoPermiso';
  }

  static Future<String> claimTripWithReason({
    required String viajeId,
    required String uidTaxista,
    required String nombreTaxista,
    String telefono = '',
    String placa = '',
    String tipoVehiculo = '',
  }) async {
    _viajesRepoDebugLog(
        '🟡 INICIO claimTripWithReason - viajeId: $viajeId, taxista: $uidTaxista');

    await limpiarViajeActivoSiNoOperativo(uidTaxista);
    await _asegurarViajeActivoIdLegibleAntesClaim(uidTaxista);
    final bloqueoActivo = await _resolverViajeActivoAntesClaim(
      uidTaxista: uidTaxista,
      viajeId: viajeId,
    );
    if (bloqueoActivo != null) {
      return bloqueoActivo;
    }

    final vRef = _col.doc(viajeId);
    final uRef = _db.collection('usuarios').doc(uidTaxista);

    final uSnapPre = await uRef.get();
    final uDataPre = uSnapPre.data() ?? const <String, dynamic>{};
    final rechazoPre = taxistaRechazoAceptarViajePool(uDataPre);
    if (rechazoPre != null) {
      _viajesRepoDebugLog('❌ Taxista no apto (pre-tx): $rechazoPre');
      return rechazoPre;
    }
    final bSnapPre =
        await _db.collection('billeteras_taxista').doc(uidTaxista).get();
    if (!PagosTaxistaRepo.taxistaSinBloqueoPrepagoOperativo(
        uDataPre, bSnapPre.data())) {
      if (uDataPre['tienePagoPendiente'] == true) {
        return 'bloqueado-pago-semanal';
      }
      return 'bloqueado-comision-efectivo';
    }
    final vSnapPre = await vRef.get(const GetOptions(source: Source.server));
    if (!vSnapPre.exists) return 'no-existe';
    final dPre = vSnapPre.data() ?? <String, dynamic>{};
    final prepagoPre =
        PagosTaxistaRepo.codigoRechazoPrepagoInsuficienteComisionViaje(
      billeData: bSnapPre.data(),
      viajeData: dPre,
    );
    if (prepagoPre != null) return prepagoPre;
    final poolModoPre =
        ViajePoolTaxistaGate.poolModoConductorDesdeUsuario(uDataPre);
    if (!ViajePoolTaxistaGate.conductorPuedeClaimViajeEnPool(dPre, poolModoPre)) {
      return 'tipo-servicio-no-coincide';
    }

    final String _telPre =
        (telefono.isNotEmpty ? telefono : (uDataPre['telefono'] ?? ''))
            .toString();
    final String _placPre =
        (placa.isNotEmpty ? placa : (uDataPre['placa'] ?? '')).toString();
    final String _tipoPre = (tipoVehiculo.isNotEmpty
            ? tipoVehiculo
            : (uDataPre['tipoVehiculo'] ?? ''))
        .toString();
    final String _marcaPre =
        (uDataPre['marca'] ?? uDataPre['vehiculoMarca'] ?? '').toString();
    final String _modeloPre =
        (uDataPre['modelo'] ?? uDataPre['vehiculoModelo'] ?? '').toString();
    final String _colorPre =
        (uDataPre['color'] ?? uDataPre['vehiculoColor'] ?? '').toString();
    final String tipoServicioPre = (dPre['tipoServicio'] ?? 'normal').toString();
    String tipoVehiculoFmtPre = _tipoPre;
    if (tipoServicioPre == 'motor') {
      tipoVehiculoFmtPre = '🛵 MOTOR 🛵';
    } else if (tipoServicioPre == 'turismo') {
      tipoVehiculoFmtPre = '🏝️ TURISMO 🏝️';
    } else if (tipoServicioPre == 'normal') {
      tipoVehiculoFmtPre = '🚗 NORMAL';
    } else if (tipoServicioPre == 'bola_ahorro') {
      tipoVehiculoFmtPre = '💚 AHORRA';
    }
    final bancoSnapPre = _snapshotPerfilTaxistaBanco(uDataPre);
    final bool cierraNegBolaPre =
        (dPre['bolaPuebloId'] ?? dPre['bolaId'] ?? '').toString().trim().isNotEmpty ||
        tipoServicioPre == 'bola_ahorro';

    // Sin esta semilla el viaje nace con el taxista en (0,0) y el cliente ve el
    // mapa vacío hasta que el chofer abre la pantalla y el GPS emite el primer
    // ping. La última posición conocida es instantánea y no pide permisos.
    double latSemillaPre = 0.0;
    double lonSemillaPre = 0.0;
    try {
      final Position? ultimaPos = await Geolocator.getLastKnownPosition();
      if (ultimaPos != null &&
          ultimaPos.latitude.abs() > 0.0001 &&
          ultimaPos.longitude.abs() > 0.0001) {
        latSemillaPre = ultimaPos.latitude;
        lonSemillaPre = ultimaPos.longitude;
      }
    } catch (_) {
      // GPS apagado o sin permiso: se queda en 0 y el mapa espera el ping.
    }

    try {
      await _db.runTransaction((tx) async {
        _viajesRepoDebugLog('🟡 TX START claimTripWithReason (solo viaje)');
        final vSnap = await tx.get(vRef);
        if (!vSnap.exists) {
          throw 'no-existe';
        }
        final d = vSnap.data()!;
        final String estadoRaw = (d['estado'] ?? '').toString().trim();
        final String estadoNorm = EstadosViaje.normalizar(estadoRaw);
        if (!ViajePoolTaxistaGate.estadoPermiteClaimPool(
            estadoRaw, estadoNorm)) {
          throw 'estado-no-pendiente';
        }
        final bool yaAsignado =
            ((d['uidTaxista'] ?? '') as String).isNotEmpty ||
                ((d['taxistaId'] ?? '') as String).isNotEmpty;
        if (yaAsignado) throw 'ya-asignado';
        if ((d['canalAsignacion'] ?? '').toString() == 'corporativo_fijo') {
          throw 'corporativo-fijo';
        }
        final now = DateTime.now();
        final tsAA = d['acceptAfter'];
        if (tsAA is Timestamp && now.isBefore(tsAA.toDate())) {
          throw 'acceptAfter-futuro';
        }
        final tsPub = d['publishAt'];
        if (tsPub is Timestamp && tsPub.toDate().isAfter(now)) {
          throw 'publish-futuro';
        }
        final reservadoPor = (d['reservadoPor'] ?? '').toString();
        DateTime? reservadoHasta;
        final rh = d['reservadoHasta'];
        if (rh is Timestamp) reservadoHasta = rh.toDate();
        if (reservadoPor.isNotEmpty &&
            (reservadoHasta == null || reservadoHasta.isAfter(now)) &&
            reservadoPor != uidTaxista) {
          throw 'reservado-otro';
        }

        final vPatch = <String, dynamic>{
          'uidTaxista': uidTaxista,
          'taxistaId': uidTaxista,
          'nombreTaxista': nombreTaxista,
          'telefono': _telPre,
          'placa': _placPre,
          'tipoVehiculo': tipoVehiculoFmtPre,
          'tipoVehiculoOriginal': _tipoPre,
          'marca': _marcaPre,
          'modelo': _modeloPre,
          'color': _colorPre,
          'latTaxista': latSemillaPre,
          'lonTaxista': lonSemillaPre,
          'driverLat': latSemillaPre,
          'driverLon': lonSemillaPre,
          ...bancoSnapPre,
          'estado': EstadosViaje.aceptado,
          'aceptado': true,
          'rechazado': false,
          'activo': true,
          'aceptadoEn': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        };
        if (cierraNegBolaPre) {
          vPatch['bolaNegociacionAbierta'] = false;
        }
        tx.set(vRef, vPatch, SetOptions(merge: true));

        // Dentro de la TX: si esto quedaba fuera y fallaba, el viaje terminaba
        // asignado pero el taxista sin viaje activo, sin pantalla a la que volver.
        tx.set(
          uRef,
          <String, dynamic>{
            'viajeActivoId': viajeId,
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      _viajesRepoDebugLog('✅ Transacción completada');
      await _claimPostProcesoExitoso(
        viajeId: viajeId,
        uidTaxista: uidTaxista,
      );
      return 'ok';
    } on FirebaseException catch (e) {
      _viajesRepoDebugLog(
          '❌ FirebaseException en claimTripWithReason: code=${e.code}, message=${e.message}');
      final String code = e.code.toLowerCase();
      if (code == 'permission-denied' || code == 'permission_denied') {
        if (await _viajeAsignadoATaxistaEnServidor(
          viajeId: viajeId,
          uidTaxista: uidTaxista,
        )) {
          await uRef.set(
            {
              'viajeActivoId': viajeId,
              'updatedAt': FieldValue.serverTimestamp(),
              'actualizadoEn': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          await _claimPostProcesoExitoso(
            viajeId: viajeId,
            uidTaxista: uidTaxista,
          );
          return 'ok';
        }
        _viajesRepoDebugLog(
            '⚠️ claim local permission-denied; intentando aceptarViajeSeguro');
        final String? cf = await _claimViajeIntentarCallableConRetry(
          viajeId: viajeId,
          uidTaxista: uidTaxista,
          nombreTaxista: nombreTaxista,
          telefono: telefono,
          placa: placa,
          tipoVehiculo: tipoVehiculo,
        );
        return _claimResolverTrasFalloPermiso(
          viajeId: viajeId,
          uidTaxista: uidTaxista,
          nombreTaxista: nombreTaxista,
          telefono: telefono,
          placa: placa,
          tipoVehiculo: tipoVehiculo,
          cfResult: cf,
          codigoPermiso: e.code,
        );
      }
      return 'permiso:${e.code}';
    } catch (e) {
      _viajesRepoDebugLog('❌ ERROR GENERAL en claimTripWithReason: $e');
      if (e == 'tipo-servicio-no-coincide') {
        return 'tipo-servicio-no-coincide';
      }
      if (e is String) return e;
      final String msg = e.toString().toLowerCase();
      if (msg.contains('permission-denied') ||
          msg.contains('permission_denied')) {
        _viajesRepoDebugLog(
            '⚠️ claim local permission-denied (genérico); intentando aceptarViajeSeguro');
        final String? cf = await _claimViajeIntentarCallableConRetry(
          viajeId: viajeId,
          uidTaxista: uidTaxista,
          nombreTaxista: nombreTaxista,
          telefono: telefono,
          placa: placa,
          tipoVehiculo: tipoVehiculo,
        );
        return _claimResolverTrasFalloPermiso(
          viajeId: viajeId,
          uidTaxista: uidTaxista,
          nombreTaxista: nombreTaxista,
          telefono: telefono,
          placa: placa,
          tipoVehiculo: tipoVehiculo,
          cfResult: cf,
          codigoPermiso: 'permission-denied',
        );
      }
      return e.toString();
    }
  }

  static Future<void> reservarComoSiguiente({
    required String viajeId,
    required String uidTaxista,
    int ttlMin = 120,
  }) async {
    await ensureSiguienteCoherente(uidTaxista);

    try {
      final bool ok = await _reservarSiguientePorCallable(
        viajeId: viajeId,
        uidTaxista: uidTaxista,
        ttlMin: ttlMin,
      );
      if (ok) return;
    } on FirebaseFunctionsException catch (e) {
      if (!_reservaCallableNoDisponible(e)) {
        throw StateError(
          taxistaMensajeReservarSiguienteFallido(
            e.message ?? e.code,
          ),
        );
      }
      _viajesRepoDebugLog(
        '⚠️ reservarSiguienteViaje CF no disponible (${e.code}); intento transacción cliente',
      );
    } on StateError {
      rethrow;
    } catch (e) {
      _viajesRepoDebugLog('⚠️ reservarSiguienteViaje CF error: $e');
    }

    await _reservarComoSiguienteTransaccion(
      viajeId: viajeId,
      uidTaxista: uidTaxista,
      ttlMin: ttlMin,
    );
  }

  static bool _reservaCallableNoDisponible(FirebaseFunctionsException e) {
    final String c = e.code.toLowerCase();
    return c == 'not-found' ||
        c == 'unimplemented' ||
        c == 'unavailable' ||
        c == 'deadline-exceeded';
  }

  /// CF no desplegada o sin red (p. ej. plan Spark sin Blaze): operar vía Firestore cliente.
  static bool _callableOperacionViajeSinServidor(Object e) {
    if (e is FirebaseFunctionsException) {
      final String c = e.code.toLowerCase().trim();
      return c == 'not-found' ||
          c == 'unimplemented' ||
          c == 'unavailable' ||
          c == 'deadline-exceeded' ||
          c == 'internal' ||
          c == 'aborted' ||
          c == 'resource-exhausted';
    }
    final String msg = e.toString().toLowerCase();
    return msg.contains('not-found') ||
        msg.contains('not_found') ||
        msg.contains('unimplemented') ||
        msg.contains('unavailable') ||
        msg.contains('deadline-exceeded') ||
        msg.contains('deadline_exceeded');
  }

  static Future<bool> _reservarSiguientePorCallable({
    required String viajeId,
    required String uidTaxista,
    required int ttlMin,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('reservarSiguienteViaje');
    final HttpsCallableResult<dynamic> res = await callable.call(
      <String, dynamic>{
        'viajeId': viajeId,
        'uidTaxista': uidTaxista,
        'ttlMin': ttlMin,
      },
    );
    final dynamic raw = res.data;
    if (raw is! Map) return false;
    return raw['ok'] == true;
  }

  static Future<void> _reservarComoSiguienteTransaccion({
    required String viajeId,
    required String uidTaxista,
    required int ttlMin,
  }) async {
    final ref = _col.doc(viajeId);
    final uRef = _db.collection('usuarios').doc(uidTaxista);
    final int? maxMetrosEncadenamiento =
        await _maxMetrosEncadenamientoDesdeConfig();

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) throw Exception('El viaje no existe');
        final d = snap.data()!;

        final String estado = (d['estado'] ?? '').toString();
        final String uidAsignado = (d['uidTaxista'] ?? '').toString();
        final String reservadoPor = (d['reservadoPor'] ?? '').toString();
        final Timestamp? reservadoHasta = d['reservadoHasta'];
        final bool reservaVigente = reservadoPor.isNotEmpty &&
            (reservadoHasta == null ||
                reservadoHasta.compareTo(Timestamp.now()) > 0);

        final bool viajeLibre = uidAsignado.isEmpty;
        final bool estadoPermitido = (estado == EstadosViaje.pendiente ||
            estado == EstadosViaje.pendientePago ||
            estado == 'pendiente_admin');
        if (!estadoPermitido ||
            !viajeLibre ||
            (reservaVigente && reservadoPor != uidTaxista)) {
          throw StateError('El viaje no está disponible para reservar.');
        }

        final uSnap = await tx.get(uRef);
        final uData = uSnap.data() ?? <String, dynamic>{};
        final rechazo = taxistaRechazoAceptarViajePool(uData);
        if (rechazo != null) {
          throw StateError(taxistaMensajeReservarSiguienteFallido(rechazo));
        }
        final bSnapRes =
            await tx.get(_db.collection('billeteras_taxista').doc(uidTaxista));
        if (!PagosTaxistaRepo.taxistaSinBloqueoPrepagoOperativo(
            uData, bSnapRes.data())) {
          throw StateError(PagosTaxistaRepo.mensajeRecargaTomarViajes);
        }
        final String viajeActivoId = (uData['viajeActivoId'] ?? '').toString();
        if (viajeActivoId.isEmpty) {
          throw StateError(
              'Primero debes tener un viaje activo para reservar el siguiente.');
        }

        final String siguienteViajeId =
            (uData['siguienteViajeId'] ?? '').toString();
        if (siguienteViajeId.isNotEmpty && siguienteViajeId != viajeId) {
          throw StateError('Ya tienes un viaje reservado en cola.');
        }

        final String poolModo =
            ViajePoolTaxistaGate.poolModoConductorDesdeUsuario(uData);
        if (!ViajePoolTaxistaGate.conductorPuedeClaimViajeEnPool(d, poolModo)) {
          throw StateError(
            taxistaMensajeReservarSiguienteFallido('tipo-servicio-no-coincide'),
          );
        }
        if (!ViajePoolTaxistaGate.ventanaPublicacionYAceptacionOk(d)) {
          throw StateError(
            taxistaMensajeReservarSiguienteFallido('acceptAfter-futuro'),
          );
        }

        if (maxMetrosEncadenamiento != null && maxMetrosEncadenamiento > 0) {
          final actRef = _col.doc(viajeActivoId);
          final actSnap = await tx.get(actRef);
          final destino =
              _coordsReferenciaEncadenamientoViajeActivo(actSnap.data());
          final pickupCand = _coordsPickupClienteViaje(d);
          if (destino != null && pickupCand != null) {
            final double m = Geolocator.distanceBetween(
              destino.$1,
              destino.$2,
              pickupCand.$1,
              pickupCand.$2,
            );
            if (m > maxMetrosEncadenamiento + 1e-6) {
              throw StateError(
                'La nueva recogida está demasiado lejos del destino de tu viaje actual '
                '(${m.toStringAsFixed(0)} m; máximo para encadenar: $maxMetrosEncadenamiento m).',
              );
            }
          }
        }

        final vence =
            Timestamp.fromDate(DateTime.now().add(Duration(minutes: ttlMin)));

        tx.update(ref, {
          'reservadoPor': uidTaxista,
          'reservadoHasta': vence,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        });
        tx.set(
            uRef,
            {
              'siguienteViajeId': viajeId,
              'updatedAt': FieldValue.serverTimestamp(),
              'actualizadoEn': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
        final cref = uRef.collection('cola_viajes').doc(viajeId);
        tx.set(
          cref,
          {
            'viajeId': viajeId,
            'slot': 0,
            'estado': 'pendiente',
            'tipo': _tipoColaViajeParaCola(d),
            'createdAt': FieldValue.serverTimestamp(),
            'source': 'reservarComoSiguiente',
          },
          SetOptions(merge: true),
        );
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'permission_denied') {
        throw StateError(
          'No se pudo reservar el siguiente viaje. Actualiza la app o intenta en unos segundos.',
        );
      }
      rethrow;
    }
  }

  static String _tipoColaViajeParaCola(Map<String, dynamic> d) {
    final s = (d['tipoServicio'] ?? '').toString().toLowerCase();
    if (s == 'pool') return 'pool';
    return 'normal';
  }

  static Future<void> liberarReserva({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _col.doc(viajeId);
    final uRef = _db.collection('usuarios').doc(uidTaxista);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');

      final d = snap.data()!;
      final String reservadoPor = (d['reservadoPor'] ?? '').toString();
      if (reservadoPor != uidTaxista) {
        throw StateError('No puedes liberar una reserva que no es tuya.');
      }

      tx.update(ref, {
        'reservadoPor': '',
        'reservadoHasta': null,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      tx.set(
          uRef,
          {
            'siguienteViajeId': '',
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      final cref = uRef.collection('cola_viajes').doc(viajeId);
      final cSnap = await tx.get(cref);
      if (cSnap.exists) {
        tx.delete(cref);
      }
    });
  }

  /// Promueve el siguiente viaje en cola vía Cloud Function (hidrata legacy + subcolección).
  static Future<PromoverColaTaxistaOutcome> promoverColaTrasFinalizarTaxista({
    required String uidTaxista,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('promoverSiguienteViaje');
      final res = await callable.call(<String, dynamic>{});
      final raw = res.data;
      if (raw is! Map) {
        return const PromoverColaTaxistaOutcome(
          promotedViajeId: null,
          code: 'invalid_response',
          message: 'Respuesta inválida del servidor.',
        );
      }
      final data = Map<String, dynamic>.from(raw);
      final ok = data['ok'] == true;
      final id = (data['promotedViajeId'] ?? '').toString().trim();
      final code = (data['code'] ?? '').toString();
      final message = data['message']?.toString();
      if (!ok) {
        return PromoverColaTaxistaOutcome(
          promotedViajeId: null,
          code: code.isEmpty ? 'error' : code,
          message: message,
        );
      }
      return PromoverColaTaxistaOutcome(
        promotedViajeId: id.isEmpty ? null : id,
        code: code.isEmpty ? 'promoted' : code,
        message: message,
      );
    } on FirebaseFunctionsException catch (e) {
      return PromoverColaTaxistaOutcome(
        promotedViajeId: null,
        code: 'functions_${e.code}',
        message: e.message,
      );
    } catch (e) {
      return PromoverColaTaxistaOutcome(
        promotedViajeId: null,
        code: 'error',
        message: e.toString(),
      );
    }
  }

  /// Tras login: si no hay viaje activo y hay cola/reserva legacy, intenta promover (best-effort).
  static Future<void> intentarPromoverColaTrasInicioSesionTaxista(
      String uidTaxista) async {
    if (uidTaxista.isEmpty) return;
    try {
      final u = await _db.collection('usuarios').doc(uidTaxista).get();
      final m = u.data() ?? <String, dynamic>{};
      final activo = (m['viajeActivoId'] ?? '').toString().trim();
      if (activo.isNotEmpty) return;
      final sig = (m['siguienteViajeId'] ?? '').toString().trim();
      final enc = (m['viajeEncoladoId'] ?? '').toString().trim();
      if (sig.isNotEmpty || enc.isNotEmpty) {
        await promoverColaTrasFinalizarTaxista(uidTaxista: uidTaxista);
        return;
      }
      final cola = await _db
          .collection('usuarios')
          .doc(uidTaxista)
          .collection('cola_viajes')
          .where('estado', isEqualTo: 'pendiente')
          .limit(1)
          .get();
      if (cola.docs.isEmpty) return;
      await promoverColaTrasFinalizarTaxista(uidTaxista: uidTaxista);
    } catch (_) {
      /* best-effort */
    }
  }

  static Future<void> marcarEnCaminoPickup({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final id = viajeId.trim();
    if (id.isEmpty) throw Exception('El viaje no existe');

    try {
      await _marcarEnCaminoPickupLocal(
        viajeId: id,
        uidTaxista: uidTaxista,
      );
      return;
    } catch (eLocal) {
      final bool permiso = eLocal is FirebaseException &&
          (eLocal.code == 'permission-denied' ||
              eLocal.code == 'permission_denied');
      if (!permiso) rethrow;
      _viajesRepoDebugLog(
        '⚠️ marcarEnCaminoPickup local permission-denied; intentando CF',
      );
    }

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('marcarEnCaminoPickupSeguro');
      await callable.call(<String, dynamic>{'viajeId': id});
    } catch (e) {
      if (_callableOperacionViajeSinServidor(e)) {
        _viajesRepoDebugLog(
          '⚠️ marcarEnCaminoPickupSeguro no disponible; reintento local',
        );
        await _marcarEnCaminoPickupLocal(
          viajeId: id,
          uidTaxista: uidTaxista,
        );
        return;
      }
      rethrow;
    }
  }

  static Future<void> _marcarEnCaminoPickupLocal({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _col.doc(viajeId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');
      final d = snap.data()!;
      final String asignado = (d['uidTaxista'] ?? d['taxistaId'] ?? '')
          .toString()
          .trim();
      if (asignado.isEmpty || asignado != uidTaxista) {
        throw Exception('No autorizado');
      }
      final String estado = (d['estado'] ?? '').toString();
      if (estado == EstadosViaje.enCaminoPickup ||
          EstadosViaje.esEnCaminoPickup(estado)) {
        return;
      }
      if (!EstadosViaje.puedeTransicionar(
          estado, EstadosViaje.enCaminoPickup)) {
        throw Exception('Estado inválido para en_camino_pickup');
      }
      tx.set(
        ref,
        {
          'estado': EstadosViaje.enCaminoPickup,
          'activo': true,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  static bool _viajeDocTieneAbordoConfirmado(Map<String, dynamic> d) {
    final String est = EstadosViaje.normalizar((d['estado'] ?? '').toString());
    if (EstadosViaje.esEnCurso(est) || EstadosViaje.esAbordo(est)) return true;
    if (d['clienteAbordo'] == true) return true;
    final dynamic ex = d['extras'];
    return ex is Map && ex['clienteAbordo'] == true;
  }

  static Future<void> _verificarMarcarClienteAbordoEnServidor({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final String id = viajeId.trim();
    if (id.isEmpty) return;

    for (int intento = 0; intento < 3; intento++) {
      try {
        final DocumentSnapshot<Map<String, dynamic>> snap = await _col
            .doc(id)
            .get(const GetOptions(source: Source.server));
        if (!snap.exists) return;
        final Map<String, dynamic> d = snap.data() ?? <String, dynamic>{};
        if (_viajeDocTieneAbordoConfirmado(d)) return;
      } catch (e) {
        _viajesRepoDebugLog(
          '⚠️ verificar marcarClienteAbordo intento=$intento error: $e',
        );
      }

      if (intento >= 2) break;

      try {
        await _marcarClienteAbordoLocal(
          viajeId: id,
          uidTaxista: uidTaxista,
        );
      } catch (eLocal) {
        final bool permiso = eLocal is FirebaseException &&
            (eLocal.code == 'permission-denied' ||
                eLocal.code == 'permission_denied');
        if (!permiso) rethrow;
        try {
          final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
              .httpsCallable('marcarClienteAbordoSeguro');
          await callable.call(<String, dynamic>{'viajeId': id});
        } catch (eCf) {
          if (!_callableOperacionViajeSinServidor(eCf)) rethrow;
        }
      }
      await Future<void>.delayed(Duration(milliseconds: 320 * (intento + 1)));
    }
  }

  static Future<void> marcarClienteAbordo({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final id = viajeId.trim();
    if (id.isEmpty) throw Exception('El viaje no existe');

    // Backend primero: el PIN de abordaje y el estado corporativo (en_origen_esperando)
    // solo los puede fijar `marcarClienteAbordoSeguro`.
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('marcarClienteAbordoSeguro');
      await callable.call(<String, dynamic>{'viajeId': id});
    } catch (eCf) {
      final bool sinServidor = _callableOperacionViajeSinServidor(eCf);
      final bool permisoCf = eCf is FirebaseFunctionsException &&
          eCf.code.toLowerCase().trim() == 'permission-denied';
      if (!sinServidor && !permisoCf) rethrow;
      _viajesRepoDebugLog(
        '⚠️ marcarClienteAbordoSeguro no disponible ($eCf); abordo local',
      );
      await _marcarClienteAbordoLocal(
        viajeId: id,
        uidTaxista: uidTaxista,
      );
    }

    await _marcarClienteAbordoPostEfectos(
      viajeId: id,
      uidTaxista: uidTaxista,
    );

    await _verificarMarcarClienteAbordoEnServidor(
      viajeId: id,
      uidTaxista: uidTaxista,
    );
  }

  static Future<void> _marcarClienteAbordoLocal({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _col.doc(viajeId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');
      final d = snap.data()!;
      final String uidDoc =
          (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString().trim();
      if (uidDoc.isEmpty || uidDoc != uidTaxista) {
        throw Exception('No autorizado');
      }
      final String estado = (d['estado'] ?? '').toString();
      final String estadoNorm = EstadosViaje.normalizar(estado);
      if (estadoNorm == EstadosViaje.enCurso) {
        return;
      }
      if (estadoNorm == EstadosViaje.aBordo) {
        if (d['clienteAbordo'] == true) return;
        tx.set(
          ref,
          <String, dynamic>{
            'clienteAbordo': true,
            'clienteAbordoEn': FieldValue.serverTimestamp(),
            'pickupConfirmadoEn': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        return;
      }
      if (!EstadosViaje.puedeTransicionar(estado, EstadosViaje.aBordo) &&
          !EstadosViaje.esAceptado(estado)) {
        throw Exception('Estado inválido para a_bordo');
      }
      // El PIN lo emite el backend (`marcarClienteAbordoSeguro` /
      // `ensureViajeCodigoVerificacion`): aquí no se toca `codigoVerificacion*`.
      final Map<String, dynamic> patch = <String, dynamic>{
        'estado': EstadosViaje.aBordo,
        'clienteAbordo': true,
        'clienteAbordoEn': FieldValue.serverTimestamp(),
        'pickupConfirmadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      };
      if (d['activo'] != true) {
        patch['activo'] = true;
      }
      tx.set(ref, patch, SetOptions(merge: true));
    });
  }

  static Future<void> _marcarClienteAbordoPostEfectos({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _col.doc(viajeId);
    try {
      final post = await ref.get();
      final Map<String, dynamic> d = post.data() ?? <String, dynamic>{};
      final tipo = (d['tipoServicio'] ?? '').toString().trim();
      if (tipo == 'bola_ahorro') {
        unawaited(
            BolaPuebloFirestoreSync.syncBolaPickupConfirmadaDesdeViaje(viajeId));
      }
      // Abordo resuelto por el fallback local: el PIN todavía no existe.
      if (_pinExistenteEnMap(d) == null) {
        unawaited(ensureCodigoVerificacionViaje(viajeId));
      }
    } catch (_) {}

    try {
      await _limpiarOtrosActivosDelTaxista(uidTaxista, exceptoId: viajeId);
    } catch (_) {
      /* no bloquear abordaje */
    }
  }

  /// Tras acordar tarifa Bola (viaje espejo): activa el viaje y enlaza `viajeActivoId`
  /// del participante en sesión (cliente o taxista) para el shell y [ViajeEnCurso*].
  /// Devuelve el id del espejo enlazado o `null` si aún no está listo.
  static Future<String?> enlazarViajeEspejoBolaOperativo({
    required String bolaId,
  }) async {
    final String bid = bolaId.trim();
    if (bid.isEmpty) return null;
    final String currentUid =
        (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (currentUid.isEmpty) return null;

    for (int attempt = 0; attempt < 8; attempt++) {
      try {
        final DocumentSnapshot<Map<String, dynamic>> bolaSnap =
            await _db.collection('bolas_pueblo').doc(bid).get(
                  attempt == 0
                      ? const GetOptions()
                      : const GetOptions(source: Source.server),
                );
        if (!bolaSnap.exists) return null;
        final Map<String, dynamic> bd = bolaSnap.data() ?? <String, dynamic>{};
        final String estadoBola = (bd['estado'] ?? '').toString().trim();
        if (estadoBola != 'acordada' && estadoBola != 'en_curso') {
          if (attempt < 7) {
            await Future<void>.delayed(const Duration(milliseconds: 280));
            continue;
          }
          return null;
        }

        final String uidTx = (bd['uidTaxista'] ?? '').toString().trim();
        final String uidCli = (bd['uidCliente'] ?? '').toString().trim();
        final bool soyTaxista = currentUid == uidTx;
        final bool soyCliente = currentUid == uidCli;
        if (!soyTaxista && !soyCliente) return null;

        String viajeId = (bd['viajeEspejoId'] ?? '').toString().trim();
        if (viajeId.isEmpty) {
          final QuerySnapshot<Map<String, dynamic>> q = await _col
              .where('bolaPuebloId', isEqualTo: bid)
              .limit(1)
              .get(
                attempt == 0
                    ? const GetOptions()
                    : const GetOptions(source: Source.server),
              );
          if (q.docs.isEmpty) {
            if (attempt < 7) {
              await Future<void>.delayed(const Duration(milliseconds: 280));
              continue;
            }
            return null;
          }
          viajeId = q.docs.first.id;
        }

        final DocumentSnapshot<Map<String, dynamic>> vSnap =
            await _col.doc(viajeId).get(
                  attempt == 0
                      ? const GetOptions()
                      : const GetOptions(source: Source.server),
                );
        if (!vSnap.exists) {
          if (attempt < 7) {
            await Future<void>.delayed(const Duration(milliseconds: 280));
            continue;
          }
          return null;
        }

        final Map<String, dynamic> vd = vSnap.data() ?? <String, dynamic>{};
        final String estadoViaje =
            EstadosViaje.normalizar((vd['estado'] ?? '').toString());
        final Map<String, dynamic> patchViaje = <String, dynamic>{
          'activo': true,
          'bolaNegociacionAbierta': false,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        };
        if (uidTx.isNotEmpty) {
          patchViaje['uidTaxista'] = uidTx;
          patchViaje['taxistaId'] = uidTx;
        }
        if (uidCli.isNotEmpty) {
          patchViaje['uidCliente'] = uidCli;
          patchViaje['clienteId'] = uidCli;
        }
        if (estadoViaje == EstadosViaje.pendiente ||
            estadoViaje == 'buscando' ||
            (uidTx.isNotEmpty && !EstadosViaje.activos.contains(estadoViaje))) {
          patchViaje['estado'] = EstadosViaje.aceptado;
          patchViaje['aceptado'] = true;
        }
        final String codigoViaje =
            (vd['codigoVerificacion'] ?? vd['codigo_verificacion'] ?? '')
                .toString()
                .trim();
        final String codigoBola =
            (bd['codigoVerificacionBola'] ?? '').toString().trim();
        if (codigoViaje.isEmpty && codigoBola.isNotEmpty) {
          patchViaje['codigoVerificacion'] = codigoBola;
          patchViaje['codigoVerificado'] = vd['codigoVerificado'] == true;
        }
        await _col.doc(viajeId).set(patchViaje, SetOptions(merge: true));

        if ((bd['viajeEspejoId'] ?? '').toString().trim().isEmpty) {
          await _db.collection('bolas_pueblo').doc(bid).set(<String, dynamic>{
            'viajeEspejoId': viajeId,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        final Set<String> participantes = <String>{
          if (uidTx.isNotEmpty) uidTx,
          if (uidCli.isNotEmpty) uidCli,
        };
        for (final String uid in participantes) {
          await _db.collection('usuarios').doc(uid).set(<String, dynamic>{
            'viajeActivoId': viajeId,
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        if (uidTx.isNotEmpty) {
          await _limpiarOtrosActivosDelTaxista(uidTx, exceptoId: viajeId);
        }

        _viajesRepoDebugLog(
          '[BOLA_AHORRO] enlazarViajeEspejo ok bola=$bid viaje=$viajeId uid=$currentUid intento=$attempt',
        );
        return viajeId;
      } catch (e, st) {
        _viajesRepoDebugLog(
          '[BOLA_AHORRO] enlazarViajeEspejo intento=$attempt error $e\n$st',
        );
        if (attempt < 7) {
          await Future<void>.delayed(const Duration(milliseconds: 280));
        }
      }
    }
    return null;
  }

  /// Inicio de viaje autoritativo en backend: el PIN se valida y `codigoVerificado`
  /// se escribe solo dentro de `iniciarViajeSeguro`. Sin fallback local: una app
  /// manipulada no puede pasar el viaje a `en_curso` sin el código del pasajero.
  static Future<void> iniciarViaje({
    required String viajeId,
    required String uidTaxista,
    String? pinVerificacion,
  }) async {
    final String id = viajeId.trim();
    if (id.isEmpty) throw Exception('El viaje no existe');
    final String pin = (pinVerificacion ?? '').replaceAll(RegExp(r'\D'), '');

    await _invocarIniciarViajeSeguro(viajeId: id, pin: pin);

    unawaited(AnalyticsRai.logTripStarted());
    try {
      await _limpiarOtrosActivosDelTaxista(uidTaxista, exceptoId: id);
    } catch (_) {
      /* no bloquear inicio de viaje */
    }
  }

  /// Códigos transitorios (red, arranque en frío, contención): reintentables sin
  /// riesgo de contar un intento de PIN fallido, que llega como `failed-precondition`.
  static bool _inicioViajeReintentable(FirebaseFunctionsException e) {
    final String c = e.code.toLowerCase().trim();
    return c == 'unavailable' ||
        c == 'deadline-exceeded' ||
        c == 'aborted' ||
        c == 'internal';
  }

  static Future<void> _invocarIniciarViajeSeguro({
    required String viajeId,
    required String pin,
  }) async {
    final HttpsCallable callable =
        FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('iniciarViajeSeguro');
    final Map<String, dynamic> payload = <String, dynamic>{
      'viajeId': viajeId,
      if (pin.isNotEmpty) 'pin': pin,
    };

    for (int intento = 0; intento < 3; intento++) {
      try {
        await callable.call(payload);
        return;
      } on FirebaseFunctionsException catch (e) {
        if (intento == 2 || !_inicioViajeReintentable(e)) rethrow;
        _viajesRepoDebugLog(
          '⚠️ iniciarViajeSeguro ${e.code} (intento ${intento + 1}); reintentando',
        );
        await Future<void>.delayed(
          Duration(milliseconds: 500 * (intento + 1)),
        );
      }
    }
  }

  /// Conductor: registra llegada a una parada (viaje multiparada).
  ///
  /// [legIndex]: parada concreta (orden libre). Si es null, el servidor marca la
  /// primera parada pendiente (compatibilidad con apps anteriores).
  static Future<void> marcarMultiparadaNavAbierta({
    required String viajeId,
    int? legIndex,
  }) async {
    final id = viajeId.trim();
    if (id.isEmpty) throw Exception('Viaje inválido');
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('marcarMultiparadaNavAbiertaSeguro');
      final Map<String, dynamic> payload = <String, dynamic>{
        'viajeId': id,
        'accion': legIndex == null
            ? 'marcar_recogida_abierta'
            : 'marcar_abierta',
      };
      if (legIndex != null && legIndex >= 0) {
        payload['legIndex'] = legIndex;
      }
      await callable.call(payload);
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) throw Exception(msg);
      throw Exception(e.code);
    }
  }

  static Future<void> registrarLegMultiparadaCompletada({
    required String viajeId,
    int? legIndex,
    double? latConfirmacion,
    double? lonConfirmacion,
  }) async {
    final id = viajeId.trim();
    if (id.isEmpty) throw Exception('Viaje inválido');
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('registrarLegMultiparadaSeguro');
      final Map<String, dynamic> payload = <String, dynamic>{'viajeId': id};
      if (legIndex != null && legIndex >= 0) {
        payload['legIndex'] = legIndex;
      }
      if (latConfirmacion != null &&
          lonConfirmacion != null &&
          latConfirmacion.isFinite &&
          lonConfirmacion.isFinite &&
          !(latConfirmacion == 0 && lonConfirmacion == 0)) {
        payload['lat'] = latConfirmacion;
        payload['lon'] = lonConfirmacion;
      }
      await callable.call(payload);
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) throw Exception(msg);
      throw Exception(e.code);
    }
  }

  /// Ida y vuelta: arranca el regreso o lo cancela devolviendo el recargo.
  ///
  /// Devuelve el precio en centavos si el cierre sin regreso bajó la tarifa.
  static Future<int?> registrarRegresoIdaVuelta({
    required String viajeId,
    required bool iniciar,
  }) async {
    final id = viajeId.trim();
    if (id.isEmpty) throw Exception('Viaje inválido');
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('registrarRegresoIdaVuelta');
      final res = await callable.call(<String, dynamic>{
        'viajeId': id,
        'accion': iniciar ? 'iniciar' : 'cancelar',
      });
      final dynamic cents = (res.data is Map)
          ? (res.data as Map)['precioCents']
          : null;
      return cents is num ? cents.toInt() : null;
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) throw Exception(msg);
      throw Exception(e.code);
    }
  }

  static bool _usuarioParticipaViajeDoc(Map<String, dynamic>? d, String uid) {
    if (d == null) return false;
    final u = uid.trim();
    final c1 = (d['uidCliente'] ?? '').toString().trim();
    final c2 = (d['clienteId'] ?? '').toString().trim();
    final t1 = (d['uidTaxista'] ?? '').toString().trim();
    final t2 = (d['taxistaId'] ?? '').toString().trim();
    return c1 == u || c2 == u || t1 == u || t2 == u;
  }

  /// Viaje asignado y operativo (aceptado → en curso), `activo == true`.
  static bool _viajeDocEnFlujoActivo(Map<String, dynamic>? d) {
    if (d == null) return false;
    if (d['activo'] != true) return false;
    final n = EstadosViaje.normalizar((d['estado'] ?? '').toString());
    return EstadosViaje.activos.contains(n);
  }

  static bool _viajeDocEsProductoBola(Map<String, dynamic> d) {
    if ((d['tipoServicio'] ?? '').toString().trim() == 'bola_ahorro') {
      return true;
    }
    return ViajePoolTaxistaGate.bolaPuebloIdDesdeViajeDoc(d).isNotEmpty;
  }

  static Future<bool> _espejoBolaTableroOperativo(
      Map<String, dynamic> vd) async {
    final String bolaId =
        (vd['bolaPuebloId'] ?? vd['bolaId'] ?? '').toString().trim();
    final bool esBola =
        (vd['tipoServicio'] ?? '').toString().trim() == 'bola_ahorro' ||
            bolaId.isNotEmpty;
    if (!esBola) return true;
    if (bolaId.isEmpty) return true;
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await _db.collection('bolas_pueblo').doc(bolaId).get();
      if (!snap.exists) return false;
      final String e = (snap.data()?['estado'] ?? '').toString().trim();
      return e != 'cancelada' && e != 'finalizada';
    } catch (_) {
      return true;
    }
  }

  static Future<void> _liberarEspejoBolaHuerfano({
    required String uid,
    required String viajeId,
    required Map<String, dynamic> data,
  }) async {
    if (BolaAhorroPoolIsolation.bloquearInterferenciaEnFlujoPool()) return;
    final String bolaId =
        (data['bolaPuebloId'] ?? data['bolaId'] ?? '').toString().trim();
    final bool esBola =
        (data['tipoServicio'] ?? '').toString().trim() == 'bola_ahorro' ||
            bolaId.isNotEmpty;
    if (!esBola) return;

    var muerta = false;
    if (bolaId.isEmpty) {
      final String est =
          EstadosViaje.normalizar((data['estado'] ?? '').toString());
      muerta = EstadosViaje.esTerminal(est) ||
          data['completado'] == true ||
          data['activo'] != true;
    } else {
      try {
        final DocumentSnapshot<Map<String, dynamic>> bSnap =
            await _db.collection('bolas_pueblo').doc(bolaId).get();
        if (!bSnap.exists) {
          muerta = true;
        } else {
          final String be =
              (bSnap.data()?['estado'] ?? '').toString().trim();
          muerta = be == 'cancelada' || be == 'finalizada';
        }
      } catch (_) {}
    }
    if (!muerta) return;

    try {
      await _db.collection('usuarios').doc(uid).set(<String, dynamic>{
        'viajeActivoId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}

    if (data['activo'] == true) {
      try {
        await _db.collection('viajes').doc(viajeId).set(<String, dynamic>{
          'activo': false,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  /// Documento `viajes` donde el usuario es cliente o taxista y el estado es **en ruta al destino**
  /// (`en_curso` normalizado), o bien `usuarios.viajeActivoId` apunta a un viaje aún en [EstadosViaje.activos].
  static Future<DocumentSnapshot<Map<String, dynamic>>?> getViajeActivoParaUsuario(
      String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return null;
    print('[VIAJE_ACTIVO] getViajeActivoParaUsuario start uid=$u');
    try {
      final userSnap = await _db.collection('usuarios').doc(u).get();
      final vid = (userSnap.data()?['viajeActivoId'] ?? '').toString().trim();
      if (vid.isNotEmpty) {
        DocumentSnapshot<Map<String, dynamic>>? vSnap;
        try {
          vSnap = await _col
              .doc(vid)
              .get(const GetOptions(source: Source.server));
        } catch (e) {
          print(
            '[VIAJE_ACTIVO] getViajeActivoParaUsuario viajeActivoId read $vid: $e',
          );
          if (await viajeDocAusenteOInaccesibleParaCliente(vid)) {
            try {
              await _db.collection('usuarios').doc(u).set(<String, dynamic>{
                'viajeActivoId': '',
                'siguienteViajeId': '',
                'updatedAt': FieldValue.serverTimestamp(),
                'actualizadoEn': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
              print(
                '[VIAJE_ACTIVO] getViajeActivoParaUsuario limpió viajeActivoId huérfano $vid',
              );
            } catch (clearErr) {
              print(
                '[VIAJE_ACTIVO] getViajeActivoParaUsuario limpiar huérfano: $clearErr',
              );
            }
          }
        }
        if (vSnap != null) {
          if (vSnap.exists && _usuarioParticipaViajeDoc(vSnap.data(), u)) {
            if (await viajeQueryMatchEsFantasmaParaCliente(vid)) {
              print(
                '[VIAJE_ACTIVO] getViajeActivoParaUsuario viajeActivoId fantasma $vid',
              );
              try {
                await _db.collection('usuarios').doc(u).set(<String, dynamic>{
                  'viajeActivoId': '',
                  'siguienteViajeId': '',
                  'updatedAt': FieldValue.serverTimestamp(),
                  'actualizadoEn': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
              } catch (_) {}
            } else {
            final Map<String, dynamic> d =
                vSnap.data() ?? <String, dynamic>{};
            final bool overlayOk =
                ViajePoolTaxistaGate.viajeDocDebeMostrarOverlayShell(d, u) ||
                    _viajeDocEnFlujoActivo(d);
            final bool esBola = _viajeDocEsProductoBola(d);
            if (esBola) {
              if (await _espejoBolaTableroOperativo(d) && overlayOk) {
                print('[VIAJE_ACTIVO] match viajeActivoId=$vid (bola)');
                return vSnap;
              }
              if (!BolaAhorroPoolIsolation.bloquearInterferenciaEnFlujoPool()) {
                await _liberarEspejoBolaHuerfano(
                  uid: u,
                  viajeId: vid,
                  data: d,
                );
              }
            } else if (overlayOk) {
              print('[VIAJE_ACTIVO] match viajeActivoId=$vid');
              return vSnap;
            }
            }
          } else if (!vSnap.exists) {
            try {
              await _db.collection('usuarios').doc(u).set(<String, dynamic>{
                'viajeActivoId': '',
                'updatedAt': FieldValue.serverTimestamp(),
                'actualizadoEn': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            } catch (e) {
              print(
                '[VIAJE_ACTIVO] getViajeActivoParaUsuario limpiar viajeActivoId: $e',
              );
            }
          }
        }
      }

      // Estados más probables primero (cold start cliente suele ser en_curso/a_bordo).
      const List<String> estadosActivosQuery = <String>[
        EstadosViaje.enCurso,
        'encurso',
        'en curso',
        EstadosViaje.aBordo,
        'a_bordo',
        EstadosViaje.aceptado,
        EstadosViaje.enCaminoPickup,
        'en_camino_pickup',
        EstadosViaje.pendiente,
        EstadosViaje.pendientePago,
        'pendiente_admin',
        'buscando',
        'disponible',
      ];
      for (final est in estadosActivosQuery) {
        for (final field
            in <String>['uidCliente', 'clienteId', 'uidTaxista', 'taxistaId']) {
          try {
            final q = await _col
                .where(field, isEqualTo: u)
                .where('estado', isEqualTo: est)
                .limit(5)
                .get(const GetOptions(source: Source.server));
            for (final DocumentSnapshot<Map<String, dynamic>> doc in q.docs) {
              final Map<String, dynamic> qd =
                  doc.data() ?? <String, dynamic>{};
              if (!_usuarioParticipaViajeDoc(qd, u)) continue;
              if (ViajePoolTaxistaGate.esReservaProgramadaLejana(qd)) continue;
              if (await viajeQueryMatchEsFantasmaParaCliente(doc.id)) {
                print(
                  '[VIAJE_ACTIVO] getViajeActivoParaUsuario skip fantasma query id=${doc.id}',
                );
                continue;
              }
              final bool overlayOk =
                  ViajePoolTaxistaGate.viajeDocDebeMostrarOverlayShell(qd, u) ||
                      _viajeDocEnFlujoActivo(qd);
              if (overlayOk) {
                print(
                    '[VIAJE_ACTIVO] match query field=$field estado=$est id=${doc.id}');
                return doc;
              }
            }
          } catch (e) {
            print(
              '[VIAJE_ACTIVO] getViajeActivoParaUsuario query $field/$est: $e',
            );
          }
        }
      }
    } catch (e) {
      print('[VIAJE_ACTIVO] getViajeActivoParaUsuario error: $e');
    }
    print('[VIAJE_ACTIVO] getViajeActivoParaUsuario → null');
    return null;
  }

  /// Cierra el viaje **solo** vía callable HTTPS `completarViajePorTaxista` (región `us-central1`).
  /// No escribe el documento del viaje desde el cliente (evita permission-denied en reglas).
  ///
  /// [uidTaxista] opcional (p. ej. widgets admin); por defecto se usa el usuario autenticado.
  /// Cada intento lógico usa una `idempotencyKey` nueva (reintentos tras `failed-precondition`).
  ///
  /// Si tras `failed-precondition` el documento ya está completado (carrera u otro cliente),
  /// devuelve [CompletarViajeTaxistaOutcome.alreadyCompleted] sin relanzar error.
  static Future<CompletarViajeTaxistaOutcome> completarViajePorTaxista(
      String viajeId,
      {String? uidTaxista}) async {
    final String uid =
        (uidTaxista ?? FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) {
      throw Exception('Sesión inválida: no hay taxista autenticado');
    }
    print(
        '[FINALIZAR] completarViajePorTaxista start viajeId=$viajeId uid=$uid');

    Future<void> efectosPostCierreEnServidor({required bool analytics}) async {
      if (analytics) {
        unawaited(AnalyticsRai.logTripCompleted());
      }
      // Best-effort: no bloquear factura/post-viaje si reglas niegan el batch.
      try {
        await _limpiarOtrosActivosDelTaxista(uid);
      } catch (e, st) {
        await ErrorReporting.reportError(
          e,
          stack: st,
          context: 'limpiarOtrosActivos tras completar (ignorado)',
        );
      }

      final String tipoServicioCf =
          ((await _col.doc(viajeId).get()).data()?['tipoServicio'] ?? '')
              .toString();
      if (tipoServicioCf == 'turismo') {
        try {
          await AsignacionTurismoRepo.liberarChofer(uid);
        } catch (e, st) {
          await ErrorReporting.reportError(
            e,
            stack: st,
            context: 'liberarChofer(turismo) tras completar',
          );
        }
      }
    }

    Future<bool> viajeMarcadoCompletadoEnFirestore() async {
      final doc = await _col.doc(viajeId).get();
      final data = doc.data();
      if (data == null) return false;
      final estado =
          EstadosViaje.normalizar((data['estado'] ?? '').toString());
      return data['completado'] == true || EstadosViaje.esCompletado(estado);
    }

    const int kFailedPreconditionPasses = 3;
    const int kTransientMax = 3;

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
        'completarViajePorTaxista',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 120),
        ),
      );

      for (var fpPass = 0; fpPass < kFailedPreconditionPasses; fpPass++) {
        final idemKey =
            'finish_${viajeId}_${uid}_${DateTime.now().microsecondsSinceEpoch}_fp$fpPass';

        FirebaseFunctionsException? failedPrecondition;

        for (var tr = 1; tr <= kTransientMax; tr++) {
          try {
            await callable.call(<String, dynamic>{
              'viajeId': viajeId,
              'idempotencyKey': idemKey,
            });
            await efectosPostCierreEnServidor(analytics: true);
            print('[FINALIZAR] completarViajePorTaxista OK viajeId=$viajeId');
            return CompletarViajeTaxistaOutcome.completedNow;
          } on FirebaseFunctionsException catch (e, _) {
            uxLog(
              'FINALIZAR',
              'callable fpPass=${fpPass + 1}/$kFailedPreconditionPasses '
                  'tr=$tr/$kTransientMax code=${e.code}',
              e,
            );
            final code = e.code.toLowerCase();
            if (code == 'failed-precondition') {
              failedPrecondition = e;
              break;
            }
            if (firebaseFunctionsCodeIsTransient(code) && tr < kTransientMax) {
              await Future<void>.delayed(Duration(milliseconds: 400 * tr));
              continue;
            }
            rethrow;
          }
        }

        if (failedPrecondition != null) {
          print(
            '[FINALIZAR_ERROR] failed-precondition viajeId=$viajeId '
            'pass=${fpPass + 1}/$kFailedPreconditionPasses '
            'msg=${failedPrecondition.message}',
          );
          await Future<void>.delayed(const Duration(seconds: 1));
          if (await viajeMarcadoCompletadoEnFirestore()) {
            await efectosPostCierreEnServidor(analytics: false);
            print(
              '[FINALIZAR] completarViajePorTaxista race: ya completado viajeId=$viajeId',
            );
            return CompletarViajeTaxistaOutcome.alreadyCompleted;
          }
          if (fpPass + 1 >= kFailedPreconditionPasses) {
            throw failedPrecondition;
          }
        }
      }

      throw StateError('completarViajePorTaxista: sin resultado');
    } on FirebaseFunctionsException catch (e, st) {
      print(
          '[FINALIZAR] FirebaseFunctionsException ${e.code} ${e.message}');
      if (_callableOperacionViajeSinServidor(e)) {
        throw Exception(
          'Para finalizar el viaje y emitir la factura hace falta desplegar '
          'Cloud Functions (plan Blaze en Firebase). Las reglas de Firestore ya '
          'están activas; el cierre contable corre en el servidor.',
        );
      }
      await ErrorReporting.reportError(
        e,
        stack: st,
        context: 'completarViajePorTaxista',
      );
      rethrow;
    } catch (e, st) {
      print('[FINALIZAR] completarViajePorTaxista error $e');
      await ErrorReporting.reportError(
        e,
        stack: st,
        context: 'completarViajePorTaxista',
      );
      rethrow;
    }
  }

  // ==============================================================
  //            ADMIN: TRANSFERENCIA CLIENTE -> RAI CONFIRMADA
  // ==============================================================
  static Future<void> confirmarTransferenciaCliente({
    required String viajeId,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('confirmarTransferenciaAdminSeguro');
    await callable.call(<String, dynamic>{'viajeId': viajeId});
  }

  /// Cliente elige o cambia método de pago durante el viaje activo.
  static Future<void> actualizarMetodoPagoViaje({
    required String viajeId,
    required String metodoPago,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('actualizarMetodoPagoViaje');
    await callable.call(<String, dynamic>{
      'viajeId': viajeId,
      'metodoPago': metodoPago.trim().toLowerCase(),
    });
  }

  static Future<void> marcarTransferenciaReportadaCliente({
    required String viajeId,
    required String comprobanteUrl,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('reportarTransferenciaClienteSeguro');
    await callable.call(<String, dynamic>{
      'viajeId': viajeId,
      'comprobanteUrl': comprobanteUrl,
    });
  }

  /// El propio taxista confirma que recibió la transferencia del cliente.
  /// Llama a la callable `confirmarTransferenciaTaxistaSeguro` (ver
  /// `functions/src/finance.ts`). El admin sigue pudiendo validar como
  /// respaldo, esto solo es un atajo para el flujo del taxista.
  static Future<void> confirmarTransferenciaPorTaxista({
    required String viajeId,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('confirmarTransferenciaTaxistaSeguro');
    await callable.call(<String, dynamic>{'viajeId': viajeId});
  }

  /// Conductor: pasajero sin efectivo ni tarjeta (caso extremo). No bloquea al taxista.
  static Future<void> registrarImpagoPasajero({
    required String viajeId,
    String? motivo,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('registrarImpagoPasajeroViaje');
    await callable.call(<String, dynamic>{
      'viajeId': viajeId,
      if (motivo != null && motivo.trim().isNotEmpty) 'motivo': motivo.trim(),
    });
  }

  static Future<void> rechazarTransferenciaCliente({
    required String viajeId,
    required String motivo,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('rechazarTransferenciaAdminSeguro');
    await callable.call(<String, dynamic>{
      'viajeId': viajeId,
      'motivo': motivo.trim(),
    });
  }

  // ==============================================================
  //              ADMIN: RAI -> TAXISTA (PAGO EJECUTADO)
  // ==============================================================
  static Future<void> marcarPagoATaxistaRealizado({
    required String viajeId,
  }) async {
    await _col.doc(viajeId).set({
      'pagoATaxistaPendiente': false,
      'pagoTaxistaPendiente': false,
      'liquidado': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> cancelarPorTaxista({
    required String viajeId,
    required String uidTaxista,
    bool forzar = false,
  }) async {
    // Siempre vía Functions: cancela el viaje, limpia viaje en curso del
    // cliente y del taxista, y notifica al cliente.
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('cancelarViajeTaxistaSeguro');
    final String idemKey =
        'cancel_${viajeId}_${uidTaxista}_${DateTime.now().millisecondsSinceEpoch}_'
        '${forzar ? 'f' : 'n'}';
    try {
      await callable.call(<String, dynamic>{
        'viajeId': viajeId,
        'idempotencyKey': idemKey,
      });
    } on FirebaseFunctionsException catch (e) {
      // Fallback local solo si Functions no responde (no en permission-denied).
      if (e.code == 'unavailable' ||
          e.code == 'deadline-exceeded' ||
          e.code == 'internal' ||
          e.code == 'not-found') {
        await _cancelarPorTaxistaLocalFallback(
          viajeId: viajeId,
          uidTaxista: uidTaxista,
          forzar: forzar,
        );
      } else {
        rethrow;
      }
    }

    // Limpieza extra best-effort: no debe tumbar una cancelación ya OK.
    try {
      await _limpiarOtrosActivosDelTaxista(uidTaxista, exceptoId: viajeId);
    } catch (e, st) {
      await ErrorReporting.reportError(
        e,
        stack: st,
        context: 'cancelarPorTaxista: limpiarOtrosActivos (ignorado)',
      );
    }

    try {
      await AsignacionTurismoRepo.liberarChofer(uidTaxista);
    } catch (e, st) {
      await ErrorReporting.reportError(
        e,
        stack: st,
        context: 'liberarChofer(turismo) tras cancelar (taxista)',
      );
    }
  }

  static Future<void> _cancelarPorTaxistaLocalFallback({
    required String viajeId,
    required String uidTaxista,
    required bool forzar,
  }) async {
    final ref = _col.doc(viajeId);
    final uRef = _db.collection('usuarios').doc(uidTaxista);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');

      final d = snap.data()!;
      final String uidTxDoc =
          ((d['uidTaxista'] ?? '').toString().trim().isNotEmpty)
              ? (d['uidTaxista'] ?? '').toString().trim()
              : (d['taxistaId'] ?? '').toString().trim();
      if (uidTxDoc != uidTaxista) throw Exception('No autorizado');
      final String estado = (d['estado'] ?? '').toString();
      final estNorm = EstadosViaje.normalizar(estado);
      if (!forzar) {
        if (!(estNorm == EstadosViaje.aceptado ||
            estNorm == EstadosViaje.enCaminoPickup)) {
          throw Exception('No se puede cancelar en este estado.');
        }
      }

      DateTime fh;
      final ts = d['fechaHora'];
      if (ts is Timestamp) {
        fh = ts.toDate();
      } else if (ts is DateTime) {
        fh = ts;
      } else if (ts is String) {
        fh = DateTime.tryParse(ts) ?? DateTime.now();
      } else {
        fh = DateTime.now();
      }
      final bool esAhora =
          TripPublishWindows.esAhoraPorFechaPickup(fh, DateTime.now());

      tx.update(ref, <String, dynamic>{
        'estado': EstadosViaje.cancelado,
        'aceptado': false,
        'rechazado': true,
        'activo': false,
        'uidTaxista': '',
        'taxistaId': '',
        'nombreTaxista': '',
        'telefono': '',
        'placa': '',
        'marca': '',
        'modelo': '',
        'color': '',
        'republicado': false,
        'canceladoPor': forzar ? 'taxista_forzado' : 'taxista',
        'canceladoTaxistaEn': FieldValue.serverTimestamp(),
        'esAhora': esAhora,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
        'pickupConfirmadoEn': FieldValue.delete(),
        'inicioEnRutaEn': FieldValue.delete(),
        'finalizadoEn': FieldValue.delete(),
        'ignoradosPor': FieldValue.arrayUnion(<String>[uidTaxista]),
        'reservadoPor': '',
        'reservadoHasta': null,
      });

      tx.set(
        uRef,
        {
          'viajeActivoId': '',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      // No escribir usuarios/{cliente} desde el taxista (permission-denied).
      // Lo limpia onViajeCanceladoPorCliente (Admin SDK).
    });
  }

  /// Lectura autoritativa del viaje (evita caché local desactualizado al cancelar).
  static Future<Map<String, dynamic>?> leerViajeServidor(String viajeId) async {
    final id = viajeId.trim();
    if (id.isEmpty) return null;
    final snap = await _col.doc(id).get(const GetOptions(source: Source.server));
    if (!snap.exists) return null;
    return snap.data();
  }

  static DateTime? _fechaDocViaje(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  /// Reserva programada que aún no entró al pool (sin conductor asignado).
  static bool esReservaProgramadaAntesDelPool(
    Map<String, dynamic> d, {
    DateTime? now,
  }) {
    final DateTime ref = now ?? DateTime.now();
    if (d['programado'] != true && d['esAhora'] == true) return false;

    final String estado =
        EstadosViaje.normalizar((d['estado'] ?? '').toString());
    if (EstadosViaje.esCancelado(estado) ||
        EstadosViaje.esCompletado(estado) ||
        d['completado'] == true) {
      return false;
    }
    if (EstadosViaje.esActivo(estado)) return false;

    final String tid =
        (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString().trim();
    if (tid.isNotEmpty) return false;

    if (EstadosViaje.esPendientePago(estado)) return true;

    final DateTime? acceptAfter = _fechaDocViaje(d['acceptAfter']);
    final DateTime? publishAt = _fechaDocViaje(d['publishAt']);
    final bool acceptAbierto =
        acceptAfter == null || !ref.isBefore(acceptAfter);
    final bool publishAbierto =
        publishAt == null || !ref.isBefore(publishAt);
    return !acceptAbierto || !publishAbierto;
  }

  /// Cancelación directa y rápida: reserva programada antes del pool (sin CF obligatoria).
  static Future<void> cancelarReservaProgramadaPrePoolRadical({
    required String viajeId,
    required String uidCliente,
    String? motivo,
    Map<String, dynamic>? docHint,
  }) async {
    Map<String, dynamic>? doc = docHint;
    try {
      doc ??= await leerViajeServidor(viajeId)
          .timeout(const Duration(seconds: 6));
    } catch (_) {}

    if (doc != null) {
      final String estado =
          EstadosViaje.normalizar((doc['estado'] ?? '').toString());
      if (EstadosViaje.esCancelado(estado)) {
        await _limpiarRefsClienteTrasCancelar(uidCliente, viajeId);
        return;
      }
      if (!esReservaProgramadaAntesDelPool(doc) &&
          !EstadosViaje.esPendientePago(estado)) {
        await cancelarPorCliente(
          viajeId: viajeId,
          uidCliente: uidCliente,
          motivo: motivo,
        ).timeout(const Duration(seconds: 20));
        return;
      }
    }

    try {
      await _cancelarPorClienteLocalFallback(
        viajeId: viajeId,
        uidCliente: uidCliente,
        motivo: motivo,
      ).timeout(const Duration(seconds: 12));
      return;
    } on Exception catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('cerrado') || msg.contains('cancelado')) {
        await _limpiarRefsClienteTrasCancelar(uidCliente, viajeId);
        return;
      }
    } catch (_) {}

    await cancelarPorCliente(
      viajeId: viajeId,
      uidCliente: uidCliente,
      motivo: motivo,
    ).timeout(const Duration(seconds: 20));
  }

  static Future<void> _limpiarRefsClienteTrasCancelar(
    String uidCliente,
    String viajeId,
  ) async {
    try {
      await _db.collection('usuarios').doc(uidCliente).set(
        <String, dynamic>{
          'viajeActivoId': '',
          'siguienteViajeId': '',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  /// Misma regla que [cancelarViajeClienteSeguro] en Functions.
  static bool clienteCancelableSegunDoc(Map<String, dynamic> d) {
    final String estadoRaw = (d['estado'] ?? '').toString();
    final String n = EstadosViaje.normalizar(estadoRaw);
    if (EstadosViaje.esCancelado(n) || EstadosViaje.esCompletado(n)) {
      return false;
    }
    if (d['completado'] == true) return false;
    if (EstadosViaje.esEstadoSinCancelacionApp(estadoRaw)) return false;
    return n == EstadosViaje.pendiente ||
        n == EstadosViaje.pendientePago ||
        n == 'pendiente_admin' ||
        n == 'buscando' ||
        n == 'disponible' ||
        n == EstadosViaje.aceptado ||
        n == EstadosViaje.enCaminoPickup;
  }

  static String mensajeErrorCancelarCliente(Object e) {
    if (e is FirebaseFunctionsException) {
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) return msg;
      switch (e.code) {
        case 'failed-precondition':
          return 'No se puede cancelar este viaje en su estado actual.';
        case 'permission-denied':
          return 'No tienes permiso para cancelar este viaje.';
        case 'not-found':
          return 'El viaje ya no existe.';
        default:
          return 'No se pudo cancelar la reserva. Intenta de nuevo.';
      }
    }
    final s = e.toString();
    final failedIdx = s.indexOf('failed-precondition');
    if (failedIdx >= 0) {
      final bracket = s.indexOf(']', failedIdx);
      if (bracket >= 0 && bracket + 1 < s.length) {
        final tail = s.substring(bracket + 1).trim();
        if (tail.isNotEmpty) {
          return tail.split('\n').first.trim();
        }
      }
    }
    if (s.contains('El viaje ya está cerrado') ||
        s.contains('El viaje ya finalizó')) {
      return 'Este viaje ya fue cancelado o finalizado.';
    }
    return 'No se pudo cancelar la reserva. Intenta de nuevo.';
  }

  static Future<void> cancelarPorCliente({
    required String viajeId,
    required String uidCliente,
    String? motivo,
  }) async {
    // Siempre vía Functions: cancela, limpia viajeActivoId cliente+taxista
    // (evita permission-denied al limpiar el doc del conductor desde la app).
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('cancelarViajeClienteSeguro');
    final String idemKey =
        'cancel_cli_${viajeId}_${uidCliente}_${DateTime.now().millisecondsSinceEpoch}';
    try {
      await callable
          .call(<String, dynamic>{
        'viajeId': viajeId,
        'motivo': (motivo ?? '').trim(),
        'idempotencyKey': idemKey,
      })
          .timeout(const Duration(seconds: 20));
      return;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition') {
        final msg = (e.message ?? '').toLowerCase();
        if (msg.contains('cerrado') ||
            msg.contains('cancelado') ||
            msg.contains('finaliz')) {
          try {
            final fresh = await leerViajeServidor(viajeId);
            if (fresh != null) {
              final n = EstadosViaje.normalizar(
                  (fresh['estado'] ?? '').toString());
              if (EstadosViaje.esCancelado(n)) return;
            }
          } catch (_) {}
        }
        try {
          final fresh = await leerViajeServidor(viajeId);
          if (fresh != null && clienteCancelableSegunDoc(fresh)) {
            await _cancelarPorClienteLocalFallback(
              viajeId: viajeId,
              uidCliente: uidCliente,
              motivo: motivo,
            );
            return;
          }
        } catch (_) {}
      }
      if (e.code == 'unavailable' ||
          e.code == 'deadline-exceeded' ||
          e.code == 'internal' ||
          e.code == 'not-found') {
        await _cancelarPorClienteLocalFallback(
          viajeId: viajeId,
          uidCliente: uidCliente,
          motivo: motivo,
        );
        return;
      }
      rethrow;
    } on TimeoutException {
      await _cancelarPorClienteLocalFallback(
        viajeId: viajeId,
        uidCliente: uidCliente,
        motivo: motivo,
      );
    }
  }

  static Future<void> _cancelarPorClienteLocalFallback({
    required String viajeId,
    required String uidCliente,
    String? motivo,
  }) async {
    final ref = _col.doc(viajeId);
    String uidTaxistaAfter = '';
    String tipoServicioPre = '';

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');

      final d = snap.data()!;
      final String cliente = uidClienteDesdeDocViaje(d);
      if (cliente.isEmpty || cliente != uidCliente) {
        throw Exception('No autorizado');
      }

      final String estado = (d['estado'] ?? '').toString();
      final n = EstadosViaje.normalizar(estado);
      if (EstadosViaje.esCancelado(n)) return;
      if (n == EstadosViaje.completado || d['completado'] == true) {
        throw Exception('El viaje ya está cerrado.');
      }
      if (EstadosViaje.esEstadoSinCancelacionApp(estado)) {
        throw Exception(EstadosViaje.mensajeNoCancelarViajeTrasAbordarApp);
      }
      final bool cancelablePorCliente = n == EstadosViaje.pendiente ||
          n == EstadosViaje.pendientePago ||
          n == 'pendiente_admin' ||
          n == 'buscando' ||
          n == 'disponible' ||
          n == EstadosViaje.aceptado ||
          n == EstadosViaje.enCaminoPickup;
      if (!cancelablePorCliente) {
        throw Exception('No se puede cancelar en este estado.');
      }

      uidTaxistaAfter = (d['uidTaxista'] ?? '').toString();
      tipoServicioPre = (d['tipoServicio'] ?? '').toString();

      tx.update(ref, {
        'estado': EstadosViaje.cancelado,
        'aceptado': false,
        'rechazado': true,
        'activo': false,
        'republicado': false,
        'uidTaxista': '',
        'taxistaId': '',
        'nombreTaxista': '',
        'telefono': '',
        'placa': '',
        'marca': '',
        'modelo': '',
        'color': '',
        'canceladoPor': 'cliente',
        'motivoCancelacion': (motivo ?? '').trim(),
        'canceladoClienteEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    });

    await _limpiarRefsClienteTrasCancelar(uidCliente, viajeId);

    // El trigger onViajeCanceladoPorCliente limpia al taxista (Admin SDK).
    // No escribir usuarios/{taxista} desde el cliente (permission-denied).

    if (tipoServicioPre == 'turismo' && uidTaxistaAfter.isNotEmpty) {
      try {
        await AsignacionTurismoRepo.liberarChofer(uidTaxistaAfter);
      } catch (e, st) {
        await ErrorReporting.reportError(
          e,
          stack: st,
          context: 'liberarChofer(turismo) tras cancelar (cliente)',
        );
      }
    }
  }

  static Future<void> pingGps({
    required String viajeId,
    required String uidTaxista,
    double? lat,
    double? lon,
    double? driverLat,
    double? driverLon,
  }) async {
    final ref = _col.doc(viajeId);
    final payload = <String, dynamic>{
      if (lat != null && lon != null) 'latTaxista': lat,
      if (lat != null && lon != null) 'lonTaxista': lon,
      if (driverLat != null && driverLon != null) 'driverLat': driverLat,
      if (driverLat != null && driverLon != null) 'driverLon': driverLon,
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    };

    await _db.runTransaction((tx) async {
      final s = await tx.get(ref);
      if (!s.exists) throw Exception('No existe el viaje');
      final m = s.data()!;
      if ((m['uidTaxista'] ?? '') != uidTaxista) {
        throw Exception('No autorizado');
      }
      tx.update(ref, payload);
    });
  }

  static Stream<Viaje?> streamEstadoViajePorCliente(String uidCliente) {
    final userRef = _db.collection('usuarios').doc(uidCliente);
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? userSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? viajeDocSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? viajeQuerySub;

    String? lastViajeId;
    bool usingDoc = false;

    Future<void> cancelAll() async {
      await viajeDocSub?.cancel();
      await viajeQuerySub?.cancel();
      viajeDocSub = null;
      viajeQuerySub = null;
      usingDoc = false;
    }

    late final StreamController<Viaje?> controller;
    controller = StreamController<Viaje?>.broadcast(
      onCancel: () async {
        await userSub?.cancel();
        await cancelAll();
        await controller.close();
      },
    );
    // Emisión inicial para evitar estados de "loading" infinito en la UI.
    controller.add(null);

    Future<void> setFromViajeActivoId(String? viajeActivoId) async {
      final id = (viajeActivoId ?? '').toString().trim();
      _diag('cliente stream setFromViajeActivoId id="$id"');
      if (id.isEmpty) {
        await cancelAll();
        lastViajeId = null;
        viajeQuerySub = _col
            .where('uidCliente', isEqualTo: uidCliente)
            .where('estado', whereIn: [
              EstadosViaje.pendiente,
              'buscando',
              EstadosViaje.pendientePago,
              'pendiente_admin',
              'asignado',
              EstadosViaje.aceptado,
              'en_camino',
              EstadosViaje.enCaminoPickup,
              'en_camino_pickup',
              EstadosViaje.aBordo,
              EstadosViaje.enCurso,
            ])
            .orderBy('updatedAt', descending: true)
            .limit(1)
            .snapshots()
            .listen(
              (q) {
                if (q.docs.isEmpty) {
                  controller.add(null);
                  return;
                }
                controller
                    .add(Viaje.fromMap(q.docs.first.id, q.docs.first.data()));
              },
              onError: controller.addError,
            );
        return;
      }

      if (usingDoc && lastViajeId == id) return;
      await cancelAll();
      lastViajeId = id;
      usingDoc = true;

      viajeDocSub = _db.collection('viajes').doc(id).snapshots().listen(
        (vSnap) {
          if (!vSnap.exists) {
            controller.add(null);
            return;
          }
          final data = vSnap.data();
          if (data == null) {
            controller.add(null);
            return;
          }
          final String uidCliDoc = uidClienteDesdeDocViaje(data);
          final String estado =
              EstadosViaje.normalizar((data['estado'] ?? '').toString());
          final bool visible = estado == EstadosViaje.pendiente ||
              estado == EstadosViaje.pendientePago ||
              estado == 'pendiente_admin' ||
              estado == EstadosViaje.aceptado ||
              estado == EstadosViaje.enCaminoPickup ||
              estado == EstadosViaje.aBordo ||
              estado == EstadosViaje.enCurso;
          if (uidCliDoc != uidCliente || !visible) {
            _diag(
                'cliente stream hide doc=$id uidDoc=$uidCliDoc visible=$visible');
            controller.add(null);
            return;
          }
          _diag('cliente stream emit doc=$id');
          controller.add(Viaje.fromMap(vSnap.id, data));
        },
        onError: (Object e) async {
          final String err = e.toString().toLowerCase();
          if (!err.contains('permission-denied')) {
            controller.addError(e);
            return;
          }
          _diag('cliente stream permission-denied doc=$id → query fallback');
          await cancelAll();
          lastViajeId = null;
          viajeQuerySub = _col
              .where('uidCliente', isEqualTo: uidCliente)
              .where('estado', whereIn: [
                EstadosViaje.pendiente,
                'buscando',
                EstadosViaje.pendientePago,
                'pendiente_admin',
                'asignado',
                EstadosViaje.aceptado,
                'en_camino',
                EstadosViaje.enCaminoPickup,
                'en_camino_pickup',
                EstadosViaje.aBordo,
                EstadosViaje.enCurso,
              ])
              .orderBy('updatedAt', descending: true)
              .limit(1)
              .snapshots()
              .listen(
                (q) {
                  if (q.docs.isEmpty) {
                    controller.add(null);
                    return;
                  }
                  controller.add(
                    Viaje.fromMap(q.docs.first.id, q.docs.first.data()),
                  );
                },
                onError: controller.addError,
              );
        },
      );
    }

    userSub = userRef.snapshots().listen(
      (uSnap) async {
        final u = uSnap.data() ?? <String, dynamic>{};
        await setFromViajeActivoId(u['viajeActivoId']);
      },
      onError: (_, __) {
        // Error transitorio de red/índice: degradar a "sin viaje" para UX estable.
        controller.add(null);
      },
    );

    return controller.stream;
  }

  /// Misma regla que [streamViajeEnCursoPorTaxista]: pool/turismo activo (nunca corporativo).
  static bool viajeVisibleEnCursoTaxista(
    Map<String, dynamic> data,
    String uidTaxista,
  ) {
    final String uid = uidTaxista.trim();
    if (uid.isEmpty) return false;
    final String uidTxDoc =
        (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString().trim();
    final String estadoRaw = (data['estado'] ?? '').toString();
    final String estado = EstadosViaje.estadoOperativoViaje(
      estadoRaw: estadoRaw,
      aceptado: data['aceptado'] == true,
      completado: data['completado'] == true,
    );
    final bool esCorpAsignado =
        CorporativoTaxistaService.esViajeCorporativoAsignado(data, uid);
    // Corporativo: pantalla «Mis rutas» / destinos — no overlay pool/turismo.
    if (esCorpAsignado) return false;
    // Turismo: overlay pool turístico (nunca corporativo / Mis rutas).
    if (AsignacionTurismoRepo.esDocumentoViajeTurismo(data)) {
      if (uidTxDoc != uid) return false;
      return data['aceptado'] == true ||
          estado == EstadosViaje.aceptado ||
          estado == EstadosViaje.enCaminoPickup ||
          estado == EstadosViaje.aBordo ||
          estado == EstadosViaje.enCurso;
    }
    final bool estadoActivo = estado == EstadosViaje.aceptado ||
        estado == EstadosViaje.enCaminoPickup ||
        estado == EstadosViaje.aBordo ||
        estado == EstadosViaje.enCurso;
    return uidTxDoc == uid && estadoActivo;
  }

  /// Viaje que realmente ocupa al taxista (activo + en operación). No cuenta
  /// corporativo en cola ni `viajeActivoId` huérfano con estado pendiente.
  static bool viajeOperativoBloqueanteParaTaxista(
    Map<String, dynamic> data,
    String uidTaxista,
  ) {
    final String uid = uidTaxista.trim();
    if (uid.isEmpty) return false;
    // Corporativo informativo: pantalla «Elige tu destino», no bloquea el shell.
    if (CorporativoTaxistaService.esViajeCorporativoAsignado(data, uid) &&
        CorporativoTaxistaService.esModoInformativo(data)) {
      return false;
    }
    if (data['activo'] != true || data['completado'] == true) return false;
    final String uidTxDoc =
        (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString().trim();
    if (uidTxDoc != uid) return false;
    final String estado =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());
    if (estado == EstadosViaje.pendiente ||
        EstadosViaje.esTerminal(estado)) {
      return false;
    }
    return estado == EstadosViaje.aceptado ||
        estado == EstadosViaje.enCaminoPickup ||
        estado == EstadosViaje.aBordo ||
        estado == EstadosViaje.enCurso;
  }

  /// Limpia `viajeActivoId` si el doc no bloquea operación real.
  static Future<void> limpiarViajeActivoSiNoOperativo(String uidTaxista) async {
    await ensureTaxistaLibre(uidTaxista);
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return;
    try {
      final uSnap = await _db.collection('usuarios').doc(uid).get();
      final activo =
          (uSnap.data()?['viajeActivoId'] ?? '').toString().trim();
      if (activo.isEmpty) return;
      final vSnap = await _col.doc(activo).get();
      if (!vSnap.exists ||
          !viajeOperativoBloqueanteParaTaxista(
            vSnap.data() ?? <String, dynamic>{},
            uid,
          )) {
        await _limpiarViajeActivoIdTaxista(uid);
      }
    } catch (_) {}
  }

  /// Tras el claim, `viajeActivoId` puede actualizarse antes que `uidTaxista` en el doc.
  /// Nunca emitir `null` al fallar el retry si el taxista sigue con ese viajeActivoId
  /// (multiparada: docs grandes / `activo` tarde → antes te sacaba a "sin viaje").
  static Future<void> _reintentarEmitViajeTaxistaEnCurso({
    required StreamController<Viaje?> controller,
    required String viajeId,
    required String uidTaxista,
  }) async {
    // No vaciar la UI por un hueco transitorio mientras Firestore reconcilia el doc.
    for (int i = 0; i < 16; i++) {
      await Future<void>.delayed(Duration(milliseconds: 250 + (i * 50)));
      if (controller.isClosed) return;
      try {
        final DocumentSnapshot<Map<String, dynamic>> snap = await _db
            .collection('viajes')
            .doc(viajeId)
            .get(const GetOptions(source: Source.server));
        if (!snap.exists) continue;
        final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};
        if (viajeVisibleEnCursoTaxista(data, uidTaxista)) {
          if (!controller.isClosed) {
            try {
              controller.add(Viaje.fromMap(snap.id, data));
            } catch (e) {
              _diag('taxista retry fromMap error viaje=$viajeId: $e');
            }
          }
          return;
        }
      } catch (_) {}
    }
    if (controller.isClosed) return;
    try {
      final DocumentSnapshot<Map<String, dynamic>> uSnap =
          await _db.collection('usuarios').doc(uidTaxista).get();
      final String activoId =
          (uSnap.data()?['viajeActivoId'] ?? '').toString().trim();
      if (activoId == viajeId) {
        _diag(
            'taxista retry timeout con viajeActivoId=$viajeId → último intento');
        try {
          final DocumentSnapshot<Map<String, dynamic>> snap = await _db
              .collection('viajes')
              .doc(viajeId)
              .get(const GetOptions(source: Source.server));
          if (snap.exists && !controller.isClosed) {
            final Map<String, dynamic> data =
                snap.data() ?? <String, dynamic>{};
            if (viajeVisibleEnCursoTaxista(data, uidTaxista)) {
              controller.add(Viaje.fromMap(snap.id, data));
            }
          }
        } catch (e) {
          _diag('taxista retry último intento error viaje=$viajeId: $e');
        }
        return;
      }
    } catch (_) {}
    if (!controller.isClosed) {
      controller.add(null);
    }
  }

  static Stream<Viaje?> streamViajeEnCursoPorTaxista(String uidTaxista) {
    // Fuente de verdad:
    // - En flows "correctos" el taxista guarda el viaje actual en `usuarios/{uid}.viajeActivoId`.
    // - Evita el problema de ambigüedad de `where(uidTaxista)+where(activo:true)+limit(1)`
    //   cuando existan 2 viajes activos por carreras/legacy.
    //
    // Fallback:
    // - Si `viajeActivoId` está vacío, conservamos el comportamiento legacy con la query ambigua,
    //   para no romper usuarios/instancias antiguas.
    final userRef = _db.collection('usuarios').doc(uidTaxista);

    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? userSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? viajeDocSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? viajeQuerySub;

    String? lastViajeId;
    bool usingDoc = false;
    Viaje? lastEmitted;

    Future<void> cancelAll() async {
      await viajeDocSub?.cancel();
      await viajeQuerySub?.cancel();
      viajeDocSub = null;
      viajeQuerySub = null;
      usingDoc = false;
    }

    late final StreamController<Viaje?> controller;
    controller = StreamController<Viaje?>.broadcast(
      onListen: () {
        if (!controller.isClosed) {
          controller.add(lastEmitted);
        }
      },
      onCancel: () async {
        await userSub?.cancel();
        await cancelAll();
        await controller.close();
      },
    );

    void emitViaje(Viaje? v) {
      lastEmitted = v;
      if (!controller.isClosed) {
        controller.add(v);
      }
    }

    Future<void> setFromViajeActivoId(String? viajeActivoId) async {
      final id = (viajeActivoId ?? '').toString().trim();
      _diag('taxista stream setFromViajeActivoId id="$id"');
      if (id.isEmpty) {
        // Fallback legacy
        await cancelAll();
        lastViajeId = null;
        viajeQuerySub = _col
            .where('uidTaxista', isEqualTo: uidTaxista)
            .where('activo', isEqualTo: true)
            .limit(1)
            .snapshots()
            .listen(
          (q) {
            if (q.docs.isEmpty) {
              emitViaje(null);
              return;
            }
            for (final doc in q.docs) {
              final data = doc.data();
              if (viajeVisibleEnCursoTaxista(data, uidTaxista)) {
                emitViaje(Viaje.fromMap(doc.id, data));
                return;
              }
            }
            emitViaje(null);
          },
          onError: controller.addError,
        );
        return;
      }

      if (usingDoc && lastViajeId == id) return;
      await cancelAll();
      lastViajeId = id;
      usingDoc = true;

      viajeDocSub = _db.collection('viajes').doc(id).snapshots().listen(
        (vSnap) {
          if (!vSnap.exists) {
            unawaited(_db.collection('usuarios').doc(uidTaxista).set(
              <String, dynamic>{
                'viajeActivoId': '',
                'updatedAt': FieldValue.serverTimestamp(),
                'actualizadoEn': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            ));
            emitViaje(null);
            return;
          }
          final data = vSnap.data();
          if (data == null) {
            emitViaje(null);
            return;
          }
          if (!viajeVisibleEnCursoTaxista(data, uidTaxista)) {
            final String uidTxDoc =
                (data['uidTaxista'] ?? data['taxistaId'] ?? '')
                    .toString()
                    .trim();
            final String estado =
                EstadosViaje.normalizar((data['estado'] ?? '').toString());
            _diag(
                'taxista stream hide doc=$id uidDoc=$uidTxDoc estado=$estado → retry');
            if (CorporativoTaxistaService.esViajeCorporativoAsignado(
              data,
              uidTaxista,
            )) {
              unawaited(_limpiarViajeActivoIdTaxista(uidTaxista));
            }
            unawaited(_liberarEspejoBolaHuerfano(
              uid: uidTaxista,
              viajeId: id,
              data: data,
            ));
            emitViaje(null);
            unawaited(_reintentarEmitViajeTaxistaEnCurso(
              controller: controller,
              viajeId: id,
              uidTaxista: uidTaxista,
            ));
            return;
          }
          _diag('taxista stream emit doc=$id');
          try {
            emitViaje(Viaje.fromMap(vSnap.id, data));
          } catch (e) {
            _diag('taxista stream fromMap error doc=$id: $e');
            unawaited(_reintentarEmitViajeTaxistaEnCurso(
              controller: controller,
              viajeId: id,
              uidTaxista: uidTaxista,
            ));
          }
        },
        onError: controller.addError,
      );
    }

    userSub = userRef.snapshots().listen(
      (uSnap) async {
        final u = uSnap.data() ?? <String, dynamic>{};
        await setFromViajeActivoId(u['viajeActivoId']);
      },
      onError: (_) {
        // Error transitorio de red: mantener último viaje emitido (evita parpadeo).
        if (lastEmitted == null && !controller.isClosed) {
          controller.add(null);
        }
      },
    );

    return controller.stream;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPoolAhora() {
    return _col
        .where('estado', whereIn: [
          EstadosViaje.pendiente,
          'buscando',
          EstadosViaje.pendientePago
        ])
        .where('uidTaxista', isEqualTo: '')
        .where('esAhora', isEqualTo: true)
        .where('publishAt', isLessThanOrEqualTo: Timestamp.now())
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPoolProgramados() {
    return _col
        .where('estado', whereIn: [
          EstadosViaje.pendiente,
          'buscando',
          EstadosViaje.pendientePago
        ])
        .where('uidTaxista', isEqualTo: '')
        .where('esAhora', isEqualTo: false)
        .where('publishAt', isLessThanOrEqualTo: Timestamp.now())
        .orderBy('fechaHora', descending: false)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>>
      streamProgramadosAceptadosTaxista(String uidTaxista) {
    return _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('estado', isEqualTo: EstadosViaje.aceptado)
        .where('fechaHora', isGreaterThan: Timestamp.now())
        .orderBy('fechaHora', descending: false)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamActivosTaxistaRaw(
      String uidTaxista) {
    return _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('activo', isEqualTo: true)
        .limit(1)
        .snapshots();
  }

  /// Limpieza defensiva de consistencia de activos del taxista:
  /// - Si hay varios activos para un taxista, conserva solo uno.
  /// - No depende de lectura del perfil del cliente (evita falsos negativos por permisos).
  /// - Alinea `usuarios/{uidTaxista}.viajeActivoId` al viaje válido (o vacío).
  static Future<void> reconciliarActivosTaxista(String uidTaxista) async {
    final qs = await _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('activo', isEqualTo: true)
        .get();

    if (qs.docs.isEmpty) {
      await _db.collection('usuarios').doc(uidTaxista).set({
        'viajeActivoId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final docs = [...qs.docs];
    docs.sort((a, b) {
      final ta = a.data()['updatedAt'];
      final tb = b.data()['updatedAt'];
      final da = ta is Timestamp
          ? ta.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0);
      final db = tb is Timestamp
          ? tb.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });

    String? keepId;
    final batch = _db.batch();
    for (final d in docs) {
      final m = d.data();
      final String estado =
          EstadosViaje.normalizar((m['estado'] ?? '').toString());
      final bool estadoActivo = estado == EstadosViaje.aceptado ||
          estado == EstadosViaje.enCaminoPickup ||
          estado == EstadosViaje.aBordo ||
          estado == EstadosViaje.enCurso;
      final String uidTx = (m['uidTaxista'] ?? m['taxistaId'] ?? '').toString();
      final bool isValid = estadoActivo && uidTx == uidTaxista;
      if (isValid && keepId == null) {
        keepId = d.id;
        continue;
      }

      batch.update(d.reference, {
        'activo': false,
        'aceptado': false,
        'rechazado': true,
        'estado': EstadosViaje.cancelado,
        'uidTaxista': '',
        'taxistaId': '',
        'nombreTaxista': '',
        'telefono': '',
        'placa': '',
        'marca': '',
        'modelo': '',
        'color': '',
        'canceladoPor': 'sistema_inconsistencia',
        'motivoCancelacion': 'desfase_cliente_taxista',
        'actualizadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'reservadoPor': '',
        'reservadoHasta': null,
      });
    }

    batch.set(
      _db.collection('usuarios').doc(uidTaxista),
      {
        'viajeActivoId': keepId ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Otros docs “activo” del taxista: se cancelan (no republicar a pendiente).
  static Future<void> _limpiarOtrosActivosDelTaxista(
    String uidTaxista, {
    String? exceptoId,
  }) async {
    final qs = await _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('activo', isEqualTo: true)
        .get();
    if (qs.docs.isEmpty) return;

    final batch = _db.batch();
    for (final d in qs.docs) {
      if (exceptoId != null && d.id == exceptoId) continue;
      batch.update(d.reference, {
        'estado': EstadosViaje.cancelado,
        'aceptado': false,
        'rechazado': true,
        'activo': false,
        'uidTaxista': '',
        'taxistaId': '',
        'nombreTaxista': '',
        'telefono': '',
        'placa': '',
        'marca': '',
        'modelo': '',
        'color': '',
        'republicado': false,
        'canceladoPor': 'taxista',
        'canceladoTaxistaEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
        'pickupConfirmadoEn': FieldValue.delete(),
        'inicioEnRutaEn': FieldValue.delete(),
        'finalizadoEn': FieldValue.delete(),
        'reservadoPor': '',
        'reservadoHasta': null,
      });
    }
    await batch.commit();
  }
}
