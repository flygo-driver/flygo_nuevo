// lib/servicios/active_trip_service.dart
//
// Fuente única para saber si taxista o cliente tienen un viaje operativo activo
// (misma semántica que [ViajesRepo.getViajeActivoParaUsuario]).
//
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/servicios/rai_local_read_cache.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';

/// Servicio central para shells y pantallas de “solicitud / home”.
class ActiveTripService {
  ActiveTripService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Evita que el shell quite [ViajeEnCursoCliente] en el instante en que
  /// `viajeActivoId` ya se limpió pero aún corre factura / post-viaje.
  static int _mantenerOverlayViajeHastaMs = 0;
  static int _bloquearShellSinViajeHastaMs = 0;

  /// Tras «Aceptar viaje»: evita que [TaxistaShell] vuelva al pool por snapshots
  /// intermedios (viajeActivoId antes que uidTaxista en el doc).
  static void bloquearShellTaxistaTrasAceptar(Duration duracion) {
    final int hasta = DateTime.now().add(duracion).millisecondsSinceEpoch;
    if (hasta > _bloquearShellSinViajeHastaMs) {
      _bloquearShellSinViajeHastaMs = hasta;
      print(
          '[VIAJE_ACTIVO] ActiveTripService.bloquearShellTaxistaTrasAceptar ${duracion.inSeconds}s');
    }
    mantenerOverlayViajeEnShell(duracion);
  }

  static bool get debeBloquearShellSinViajeTaxista =>
      DateTime.now().millisecondsSinceEpoch < _bloquearShellSinViajeHastaMs;

  static void cancelarBloqueoShellTaxista() {
    _bloquearShellSinViajeHastaMs = 0;
  }

  /// Mantiene el overlay de “viaje en curso” en el shell aunque el stream diga
  /// `false` (p. ej. transición a factura).
  static void mantenerOverlayViajeEnShell(Duration duracion) {
    final int hasta =
        DateTime.now().add(duracion).millisecondsSinceEpoch;
    if (hasta > _mantenerOverlayViajeHastaMs) {
      _mantenerOverlayViajeHastaMs = hasta;
      print(
          '[VIAJE_ACTIVO] ActiveTripService.mantenerOverlayViajeEnShell ${duracion.inSeconds}s');
    }
  }

  static bool get debeMantenerOverlayViajeEnShell =>
      DateTime.now().millisecondsSinceEpoch < _mantenerOverlayViajeHastaMs;

  /// Libera el modo “pantalla completa viaje” (p. ej. al abrir post-viaje o volver al home).
  /// Sin esto, [ClienteShell] puede seguir mostrando [ViajeEnCursoCliente] ~90s aunque el viaje ya cerró.
  static void cancelarMantenimientoOverlayViaje() {
    _mantenerOverlayViajeHastaMs = 0;
    _bloquearShellSinViajeHastaMs = 0;
  }

  /// Documento del viaje activo, o `null`.
  static Future<DocumentSnapshot<Map<String, dynamic>>?> obtenerDocumentoViajeActivo(
      String uid) {
    return ViajesRepo.getViajeActivoParaUsuario(uid);
  }

  /// Cliente o taxista con `viajeActivoId` y viaje no terminal (incluye **pendiente** buscando conductor).
  static Future<bool> usuarioTieneViajeEnSeguimiento(String uid) async {
    final String u = uid.trim();
    if (u.isEmpty) return false;
    try {
      final DocumentSnapshot<Map<String, dynamic>> userSnap =
          await _db.collection('usuarios').doc(u).get();
      final String vid =
          (userSnap.data()?['viajeActivoId'] ?? '').toString().trim();
      if (vid.isEmpty) return false;

      return _viajeEnSeguimientoDesdeDocId(vid, u);
    } catch (e) {
      print('[VIAJE_ACTIVO] usuarioTieneViajeEnSeguimiento error: $e');
      return false;
    }
  }

  static Future<bool> _viajeEnSeguimientoDesdeDocId(String vid, String uid) async {
    for (int i = 0; i < 12; i++) {
      try {
        final DocumentSnapshot<Map<String, dynamic>> vSnap =
            await _db.collection('viajes').doc(vid).get(
                  i == 0
                      ? const GetOptions()
                      : const GetOptions(source: Source.server),
                );
        if (!vSnap.exists) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        final Map<String, dynamic> d = vSnap.data() ?? <String, dynamic>{};
        if (!_usuarioParticipaViajeDoc(d, uid)) {
          final String t1 = (d['uidTaxista'] ?? '').toString().trim();
          final String t2 = (d['taxistaId'] ?? '').toString().trim();
          if (t1.isEmpty && t2.isEmpty) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            continue;
          }
          return false;
        }
        if (!ViajePoolTaxistaGate.viajeDocDebeMostrarOverlayShell(d, uid)) {
          return false;
        }
        final String st =
            EstadosViaje.normalizar((d['estado'] ?? '').toString());
        if (d['completado'] == true || EstadosViaje.esTerminal(st)) {
          return false;
        }
        return true;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    return debeBloquearShellSinViajeTaxista;
  }

  static bool _usuarioParticipaViajeDoc(Map<String, dynamic> d, String uid) {
    final String u = uid.trim();
    final String c1 = (d['uidCliente'] ?? '').toString().trim();
    final String c2 = (d['clienteId'] ?? '').toString().trim();
    final String t1 = (d['uidTaxista'] ?? '').toString().trim();
    final String t2 = (d['taxistaId'] ?? '').toString().trim();
    return c1 == u || c2 == u || t1 == u || t2 == u;
  }

  /// Cliente con `viajeActivoId` y viaje no terminal (incluye **pendiente** buscando conductor).
  static Future<bool> clienteTieneViajeEnSeguimiento(String uid) async {
    final String u = uid.trim();
    if (u.isEmpty) return false;
    try {
      final DocumentSnapshot<Map<String, dynamic>> userSnap =
          await _db.collection('usuarios').doc(u).get();
      final String vid =
          (userSnap.data()?['viajeActivoId'] ?? '').toString().trim();
      if (vid.isEmpty) return false;

      final DocumentSnapshot<Map<String, dynamic>> vSnap =
          await _db.collection('viajes').doc(vid).get();
      if (!vSnap.exists) return false;
      final Map<String, dynamic> d = vSnap.data() ?? <String, dynamic>{};
      final bool esCliente = (d['uidCliente'] ?? '').toString().trim() == u ||
          (d['clienteId'] ?? '').toString().trim() == u;
      if (!esCliente) return false;

      final String st = EstadosViaje.normalizar((d['estado'] ?? '').toString());
      if (d['completado'] == true || EstadosViaje.esTerminal(st)) {
        return false;
      }
      return true;
    } catch (e) {
      print('[VIAJE_ACTIVO] clienteTieneViajeEnSeguimiento error: $e');
      return false;
    }
  }

  /// `true` si hay un viaje activo verificado en servidor (cliente o taxista).
  static Future<bool> tieneViajeActivo(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return false;
    final bool ok = await usuarioTieneViajeEnSeguimiento(u);
    print('[VIAJE_ACTIVO] ActiveTripService.tieneViajeActivo($u) → $ok');
    return ok;
  }

  /// Emite `true`/`false` al cambiar `usuarios/{uid}` o el propio viaje enlazado
  /// (vía nueva lectura con [ViajesRepo.getViajeActivoParaUsuario]).
  static Stream<bool> streamTieneViajeActivo(String uid) {
    final u = uid.trim();
    if (u.isEmpty) return Stream<bool>.value(false);
    // Reduce lecturas a [getViajeActivoParaUsuario] cuando solo cambian campos
    // irrelevantes del perfil (misma huella de viaje activo).
    return _db
        .collection('usuarios')
        .doc(u)
        .snapshots()
        .map((DocumentSnapshot<Map<String, dynamic>> s) {
          final d = s.data();
          final vid = (d?['viajeActivoId'] ?? '').toString().trim();
          final ts = d?['updatedAt'] ?? d?['actualizadoEn'];
          return '$vid|${ts?.toString() ?? ''}';
        })
        .distinct()
        .asyncMap((_) async {
          if (debeMantenerOverlayViajeEnShell ||
              debeBloquearShellSinViajeTaxista) {
            print(
                '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) → true (overlay/bloqueo taxista)');
            return true;
          }
          final bool ok = await usuarioTieneViajeEnSeguimiento(u);
          print(
              '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) → $ok');
          if (ok) {
            final String vid = (await _db.collection('usuarios').doc(u).get())
                .data()?['viajeActivoId']
                ?.toString()
                .trim() ??
                '';
            if (vid.isNotEmpty) {
              unawaited(RaiLocalReadCache.rememberActiveTripId(u, vid));
            }
          }
          return ok;
        });
  }
}
