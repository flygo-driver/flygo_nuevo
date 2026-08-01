// lib/servicios/active_trip_service.dart
//
// Fuente única para saber si taxista o cliente tienen un viaje operativo activo
// (misma semántica que [ViajesRepo.getViajeActivoParaUsuario]).
//
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
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
  static int _forzarInicioClienteHastaMs = 0;
  static int _forzarInicioTaxistaBolaHastaMs = 0;
  static String _bolaIdTaxistaPausado = '';

  /// Fuerza rebuild de [TaxistaShell] / [ClienteShell] tras aceptar viaje u overlay.
  static final ValueNotifier<int> shellRebuildTick = ValueNotifier<int>(0);

  static void notificarRebuildShell() {
    shellRebuildTick.value++;
  }

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
    notificarRebuildShell();
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
    notificarRebuildShell();
  }

  static bool get debeMantenerOverlayViajeEnShell =>
      DateTime.now().millisecondsSinceEpoch < _mantenerOverlayViajeHastaMs;

  /// Libera el modo “pantalla completa viaje” (p. ej. al abrir post-viaje o volver al home).
  /// Sin esto, [ClienteShell] puede seguir mostrando [ViajeEnCursoCliente] ~90s aunque el viaje ya cerró.
  static void cancelarMantenimientoOverlayViaje() {
    _mantenerOverlayViajeHastaMs = 0;
    _bloquearShellSinViajeHastaMs = 0;
    notificarRebuildShell();
  }

  static Future<void> _limpiarViajeActivoFirestore(String uid) async {
    final String u = uid.trim();
    if (u.isEmpty) return;
    try {
      await _db.collection('usuarios').doc(u).set({
        'viajeActivoId': '',
        'siguienteViajeId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('[VIAJE_ACTIVO] limpiar viajeActivoId error: $e');
    }
  }

  /// Antes de [NavigationService.irAlInicioCliente]: quita overlay y, si corresponde,
  /// limpia `viajeActivoId` para que el shell no vuelva a abrir turismo / viaje en curso.
  static Future<void> prepararSalidaClienteAlInicio({
    required String uid,
    String? viajeId,
    bool forzarLimpieza = false,
  }) async {
    cancelarMantenimientoOverlayViaje();
    final String u = uid.trim();
    if (u.isEmpty) {
      notificarRebuildShell();
      return;
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> userSnap =
          await _db.collection('usuarios').doc(u).get();
      final String activo =
          (userSnap.data()?['viajeActivoId'] ?? '').toString().trim();
      if (activo.isEmpty) {
        notificarRebuildShell();
        return;
      }

      final String? vid = viajeId?.trim();
      if (!forzarLimpieza &&
          vid != null &&
          vid.isNotEmpty &&
          activo != vid) {
        notificarRebuildShell();
        return;
      }

      bool debeLimpiar = forzarLimpieza;
      if (!debeLimpiar) {
        final DocumentSnapshot<Map<String, dynamic>> vSnap =
            await _db.collection('viajes').doc(activo).get();
        if (!vSnap.exists) {
          debeLimpiar = true;
        } else {
          final Map<String, dynamic> d = vSnap.data() ?? <String, dynamic>{};
          final String st =
              EstadosViaje.normalizar((d['estado'] ?? '').toString());
          debeLimpiar =
              d['completado'] == true || EstadosViaje.esTerminal(st);
        }
      }

      if (debeLimpiar) {
        await _limpiarViajeActivoFirestore(u);
      }
    } catch (e) {
      print('[VIAJE_ACTIVO] prepararSalidaClienteAlInicio error: $e');
    }
    notificarRebuildShell();
  }

  /// Tras «Volver al inicio»: el stream no debe reabrir viaje en curso aunque
  /// `viajeActivoId` tarde en limpiarse en Firestore.
  static void forzarInicioClienteShell({
    Duration duracion = const Duration(seconds: 120),
  }) {
    final int hasta = DateTime.now().add(duracion).millisecondsSinceEpoch;
    if (hasta > _forzarInicioClienteHastaMs) {
      _forzarInicioClienteHastaMs = hasta;
    }
    cancelarMantenimientoOverlayViaje();
    print(
        '[VIAJE_ACTIVO] ActiveTripService.forzarInicioClienteShell ${duracion.inSeconds}s');
  }

  static bool get debeForzarInicioClienteShell =>
      DateTime.now().millisecondsSinceEpoch < _forzarInicioClienteHastaMs;

  static void cancelarForzarInicioClienteShell() {
    _forzarInicioClienteHastaMs = 0;
  }

  /// Tras salir del tablero Bola con viaje operativo (acordada/en_curso): tabs
  /// visibles y banner «Retomar» — sin overlay de viaje pool normal.
  static void forzarInicioTaxistaShellBola({
    required String bolaId,
    Duration duracion = const Duration(hours: 24),
  }) {
    final int hasta = DateTime.now().add(duracion).millisecondsSinceEpoch;
    if (hasta > _forzarInicioTaxistaBolaHastaMs) {
      _forzarInicioTaxistaBolaHastaMs = hasta;
    }
    _bolaIdTaxistaPausado = bolaId.trim();
    cancelarMantenimientoOverlayViaje();
    cancelarBloqueoShellTaxista();
    print(
      '[VIAJE_ACTIVO] ActiveTripService.forzarInicioTaxistaShellBola '
      'bola=$bolaId ${duracion.inSeconds}s',
    );
    notificarRebuildShell();
  }

  static bool get debeForzarInicioTaxistaShellBola =>
      DateTime.now().millisecondsSinceEpoch < _forzarInicioTaxistaBolaHastaMs;

  static String get bolaIdTaxistaPausado => _bolaIdTaxistaPausado;

  static void cancelarForzarInicioTaxistaShellBola() {
    _forzarInicioTaxistaBolaHastaMs = 0;
    _bolaIdTaxistaPausado = '';
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
    if (c1 == u || c2 == u || t1 == u || t2 == u) return true;
    return CorporativoTaxistaService.esViajeCorporativoAsignado(d, u);
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
      if (!ViajePoolTaxistaGate.viajeDocDebeMostrarOverlayShell(d, u)) {
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
    if (debeForzarInicioClienteShell) {
      print(
          '[VIAJE_ACTIVO] ActiveTripService.tieneViajeActivo($u) → false (forzar inicio)');
      return false;
    }
    final bool ok = await usuarioTieneViajeEnSeguimiento(u);
    print('[VIAJE_ACTIVO] ActiveTripService.tieneViajeActivo($u) → $ok');
    return ok;
  }

  /// Emite al cambiar `usuarios/{uid}`, el viaje enlazado o el bloqueo post-aceptación.
  static Stream<bool> streamTieneViajeActivo(String uid) {
    final String u = uid.trim();
    if (u.isEmpty) return Stream<bool>.value(false);

    return _db.collection('usuarios').doc(u).snapshots().asyncExpand(
      (DocumentSnapshot<Map<String, dynamic>> userSnap) {
        final String vid =
            (userSnap.data()?['viajeActivoId'] ?? '').toString().trim();

        return Stream<bool>.multi((MultiStreamController<bool> controller) {
          Future<void> emit() async {
            if (controller.isClosed) return;
            final bool ok = await _evalTieneViajeActivoStream(u);
            if (!controller.isClosed) {
              controller.add(ok);
            }
          }

          void onShellTick() => unawaited(emit());

          shellRebuildTick.addListener(onShellTick);
          StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? subViaje;
          if (vid.isNotEmpty) {
            subViaje = _db
                .collection('viajes')
                .doc(vid)
                .snapshots()
                .listen((_) => unawaited(emit()));
          }

          unawaited(emit());

          controller.onCancel = () async {
            shellRebuildTick.removeListener(onShellTick);
            await subViaje?.cancel();
          };
        });
      },
    ).distinct();
  }

  static Future<bool> _evalTieneViajeActivoStream(String u) async {
    if (debeForzarInicioClienteShell) {
      print(
          '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) → false (forzar inicio)');
      return false;
    }
    if (debeMantenerOverlayViajeEnShell || debeBloquearShellSinViajeTaxista) {
      try {
        final uSnap = await _db.collection('usuarios').doc(u).get();
        final vid =
            (uSnap.data()?['viajeActivoId'] ?? '').toString().trim();
        if (vid.isNotEmpty) {
          final vSnap = await _db.collection('viajes').doc(vid).get();
          final d = vSnap.data() ?? <String, dynamic>{};
          if (CorporativoTaxistaService.corpAsignadoUsaPantallaPropia(d, u)) {
            cancelarBloqueoShellTaxista();
            cancelarMantenimientoOverlayViaje();
            unawaited(RaiLocalReadCache.clearActiveTripId(u));
            print(
              '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) '
              '→ false (corp, sin overlay)',
            );
            return false;
          }
        }
      } catch (_) {}
      final String? corpOp =
          await CorporativoTaxistaService.idViajeCorporativoOperativoParaChofer(
        u,
      );
      if (corpOp != null && corpOp.isNotEmpty) {
        cancelarBloqueoShellTaxista();
        cancelarMantenimientoOverlayViaje();
        unawaited(RaiLocalReadCache.clearActiveTripId(u));
        print(
          '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) '
          '→ false (corp operativo, sin overlay)',
        );
        return false;
      }
      final String? corpInfo =
          await CorporativoTaxistaService.idViajeCorporativoInformativoParaChofer(
        u,
      );
      if (corpInfo != null && corpInfo.isNotEmpty) {
        cancelarBloqueoShellTaxista();
        cancelarMantenimientoOverlayViaje();
        unawaited(RaiLocalReadCache.clearActiveTripId(u));
        print(
          '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) '
          '→ false (corp informativo, sin overlay)',
        );
        return false;
      }
      final bool pool = await usuarioTieneViajeEnSeguimiento(u);
      if (!pool) {
        if (debeBloquearShellSinViajeTaxista) {
          for (int i = 0; i < 10; i++) {
            await Future<void>.delayed(
              Duration(milliseconds: 60 * (i + 1)),
            );
            if (await usuarioTieneViajeEnSeguimiento(u)) {
              print(
                '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) '
                '→ true (overlay/bloqueo + pool tras retry)',
              );
              return true;
            }
          }
        }
        cancelarBloqueoShellTaxista();
        cancelarMantenimientoOverlayViaje();
        unawaited(RaiLocalReadCache.clearActiveTripId(u));
        print(
          '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) '
          '→ false (overlay/bloqueo sin viaje pool)',
        );
        return false;
      }
      print(
          '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) → true (overlay/bloqueo + pool)');
      return true;
    }
    final bool ok = await usuarioTieneViajeEnSeguimiento(u);
    print('[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) → $ok');
    if (ok) {
      final String vid = (await _db.collection('usuarios').doc(u).get())
              .data()?['viajeActivoId']
              ?.toString()
              .trim() ??
          '';
      if (vid.isNotEmpty) {
        try {
          final vSnap = await _db.collection('viajes').doc(vid).get();
          final d = vSnap.data() ?? <String, dynamic>{};
          if (CorporativoTaxistaService.corpAsignadoUsaPantallaPropia(d, u)) {
            cancelarBloqueoShellTaxista();
            cancelarMantenimientoOverlayViaje();
            unawaited(RaiLocalReadCache.clearActiveTripId(u));
            print(
              '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) '
              '→ false (corp en seguimiento, sin overlay)',
            );
            return false;
          }
          if (CorporativoTaxistaService.esViajeCorporativoAsignado(d, u) &&
              CorporativoTaxistaService.esModoInformativo(d)) {
            unawaited(RaiLocalReadCache.clearActiveTripId(u));
          } else {
            unawaited(RaiLocalReadCache.rememberActiveTripId(u, vid));
          }
        } catch (_) {
          unawaited(RaiLocalReadCache.rememberActiveTripId(u, vid));
        }
      }
    }
    return ok;
  }
}
