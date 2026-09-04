// lib/servicios/active_trip_service.dart
//
// Fuente única para saber si taxista o cliente tienen un viaje operativo activo
// (misma semántica que [ViajesRepo.getViajeActivoParaUsuario]).
//
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/rai_local_read_cache.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';

/// Servicio central para shells y pantallas de “solicitud / home”.
class ActiveTripService {
  ActiveTripService._();

  /// TTL estándar del overlay de viaje en curso (cliente). Renovable con pulso.
  static const Duration kOverlayClienteViajeActivo = Duration(minutes: 5);

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Evita que el shell quite [ViajeEnCursoCliente] en el instante en que
  /// `viajeActivoId` ya se limpió pero aún corre factura / post-viaje.
  static int _mantenerOverlayViajeHastaMs = 0;
  static int _bloquearShellSinViajeHastaMs = 0;
  static int _forzarInicioClienteHastaMs = 0;

  /// Fuerza rebuild de [TaxistaShell] / [ClienteShell] tras aceptar viaje u overlay.
  static final ValueNotifier<int> shellRebuildTick = ValueNotifier<int>(0);

  static void notificarRebuildShell() {
    shellRebuildTick.value++;
  }

  /// Tras «Aceptar viaje»: evita que [TaxistaShell] vuelva al pool por snapshots
  /// intermedios (viajeActivoId antes que uidTaxista en el doc).
  static void bloquearShellTaxistaTrasAceptar(
    Duration duracion, {
    String? viajeId,
  }) {
    final int hasta = DateTime.now().add(duracion).millisecondsSinceEpoch;
    if (hasta > _bloquearShellSinViajeHastaMs) {
      _bloquearShellSinViajeHastaMs = hasta;
      print(
          '[VIAJE_ACTIVO] ActiveTripService.bloquearShellTaxistaTrasAceptar ${duracion.inSeconds}s');
    }
    final String vid = (viajeId ?? '').trim();
    if (vid.isNotEmpty) {
      _viajeOperativoTaxistaConocido = vid;
      final String? uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.trim().isNotEmpty) {
        unawaited(RaiLocalReadCache.rememberActiveTripId(uid, vid));
      }
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

  static int _clienteFlujoSolicitudViajeDepth = 0;

  /// Cliente en [ProgramarViaje] / cotización: no robar pantalla con overlay de viaje activo.
  static bool get clienteSuprimirOverlayViajeActivo =>
      _clienteFlujoSolicitudViajeDepth > 0;

  static void entrarClienteFlujoSolicitudViaje() {
    _clienteFlujoSolicitudViajeDepth++;
    notificarRebuildShell();
  }

  static void salirClienteFlujoSolicitudViaje() {
    if (_clienteFlujoSolicitudViajeDepth <= 0) return;
    _clienteFlujoSolicitudViajeDepth--;
    notificarRebuildShell();
  }

  /// Tras «Confirmar viaje»: [ProgramarViaje] puede seguir en la pila del tab;
  /// sin esto el shell no muestra overlay aunque [mantenerOverlayViajeEnShell].
  static void restablecerClienteFlujoSolicitudViaje() {
    if (_clienteFlujoSolicitudViajeDepth == 0) return;
    _clienteFlujoSolicitudViajeDepth = 0;
    notificarRebuildShell();
    print(
      '[VIAJE_ACTIVO] restablecerClienteFlujoSolicitudViaje → overlay permitido',
    );
  }

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

  /// Indica si el cliente ya está en seguimiento (overlay, pantalla montada o ruta).
  static bool clienteYaEstaEnViajeEnCurso({
    required bool overlayActivo,
    required bool pantallaViajeMontada,
    required bool rutaNombradaEsViaje,
  }) {
    return overlayActivo || pantallaViajeMontada || rutaNombradaEsViaje;
  }

  /// Documento del viaje activo, o `null`.
  static Future<DocumentSnapshot<Map<String, dynamic>>?> obtenerDocumentoViajeActivo(
      String uid) {
    return ViajesRepo.getViajeActivoParaUsuario(uid);
  }

  /// Cliente o taxista con viaje operativo (viajeActivoId + doc, o query como en pool).
  static Future<bool> usuarioTieneViajeEnSeguimiento(String uid) async {
    final String u = uid.trim();
    if (u.isEmpty) return false;
    try {
      final DocumentSnapshot<Map<String, dynamic>> userSnap =
          await _db.collection('usuarios').doc(u).get();
      final String vid =
          (userSnap.data()?['viajeActivoId'] ?? '').toString().trim();
      if (vid.isNotEmpty) {
        if (viajeClienteDescartadoEnSesion(vid)) return false;
        final bool porActivoId = await _viajeEnSeguimientoDesdeDocId(vid, u);
        if (porActivoId) return true;
      }
    } catch (e) {
      print('[VIAJE_ACTIVO] usuarioTieneViajeEnSeguimiento viajeActivoId: $e');
    }
    return _usuarioTieneViajeEnSeguimientoPorQuery(u);
  }

  /// Misma búsqueda que [ViajesRepo.getViajeActivoParaUsuario] cuando el GET
  /// directo al doc falla (p. ej. `permission-denied` transitorio en cold start).
  static Future<bool> _usuarioTieneViajeEnSeguimientoPorQuery(String u) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>>? doc =
          await ViajesRepo.getViajeActivoParaUsuario(u);
      if (doc == null || !doc.exists) return false;
      if (viajeClienteDescartadoEnSesion(doc.id)) return false;
      if (await ViajesRepo.viajeQueryMatchEsFantasmaParaCliente(doc.id)) {
        print(
          '[VIAJE_ACTIVO] usuarioTieneViajeEnSeguimiento skip fantasma id=${doc.id}',
        );
        return false;
      }
      final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
      if (!_usuarioParticipaViajeDoc(d, u)) return false;
      if (!viajeDocCuentaComoSeguimientoParaUsuario(d, u)) {
        return false;
      }
      final String st =
          EstadosViaje.normalizar((d['estado'] ?? '').toString());
      if (d['completado'] == true || EstadosViaje.esTerminal(st)) {
        return false;
      }
      unawaited(RaiLocalReadCache.rememberActiveTripId(u, doc.id));
      final bool esCliente =
          (d['uidCliente'] ?? '').toString().trim() == u ||
          (d['clienteId'] ?? '').toString().trim() == u;
      if (esCliente) {
        unawaited(repararViajeActivoClienteSiHuerfano(u, viajeIdHint: doc.id));
      } else {
        registrarViajeOperativoTaxista(doc.id);
      }
      print(
        '[VIAJE_ACTIVO] usuarioTieneViajeEnSeguimiento query match id=${doc.id}',
      );
      return true;
    } catch (e) {
      print('[VIAJE_ACTIVO] usuarioTieneViajeEnSeguimiento query fallback: $e');
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
      } catch (e) {
        if (_esFirestorePermisoDenegado(e)) {
          if (viajeClienteDescartadoEnSesion(vid)) return false;
          if (await ViajesRepo.viajeDocAusenteOInaccesibleParaCliente(vid)) {
            return false;
          }
          return _usuarioTieneViajeEnSeguimientoPorQuery(uid);
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    if (debeBloquearShellSinViajeTaxista) return true;
    return _usuarioTieneViajeEnSeguimientoPorQuery(uid);
  }

  static bool _esFirestorePermisoDenegado(Object e) {
    if (e is FirebaseException) {
      return e.code == 'permission-denied' || e.code == 'permission_denied';
    }
    final String s = e.toString().toLowerCase();
    return s.contains('permission-denied') || s.contains('permission_denied');
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

  /// Misma lógica relajada que [ViajesRepo.getViajeActivoParaUsuario] al
  /// aceptar un doc devuelto por query (p. ej. `canceladoPor` legado + en_curso).
  static bool viajeDocCuentaComoSeguimientoParaUsuario(
    Map<String, dynamic> d,
    String uid,
  ) {
    final String u = uid.trim();
    if (u.isEmpty) return false;
    if (!_usuarioParticipaViajeDoc(d, u)) return false;
    final String st =
        EstadosViaje.normalizar((d['estado'] ?? '').toString());
    if (d['completado'] == true || EstadosViaje.esTerminal(st)) {
      return false;
    }
    if (ViajePoolTaxistaGate.viajeDocDebeMostrarOverlayShell(d, u)) {
      return true;
    }
    if (EstadosViaje.activos.contains(st)) return true;
    return false;
  }

  /// Cliente con viaje operativo (viajeActivoId + doc, o query cuando GET falla).
  static Future<bool> clienteTieneViajeEnSeguimiento(String uid) async {
    return usuarioTieneViajeEnSeguimiento(uid);
  }

  /// `true` si hay un viaje activo verificado en servidor (cliente o taxista).
  static Future<bool> tieneViajeActivo(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return false;
    if (debeForzarInicioClienteShell && flujoPostViajeClienteActivo) {
      print(
          '[VIAJE_ACTIVO] ActiveTripService.tieneViajeActivo($u) → false (post-viaje)');
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
    if (clienteSuprimirOverlayViajeActivo) {
      print(
        '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) '
        '→ false (flujo solicitud / cotización)',
      );
      return false;
    }
    if (debeForzarInicioClienteShell && flujoPostViajeClienteActivo) {
      print(
          '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) → false (post-viaje)');
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
        if (debeBloquearShellSinViajeTaxista ||
            debeMantenerOverlayViajeEnShell) {
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
        // Cliente ya está en ViajeEnCurso: un snapshot vacío / permission-denied
        // NO debe cancelar overlay ni mandar al Home (p. ej. al aceptar el taxista).
        if (retomarClienteEnCurso && !flujoPostViajeClienteActivo) {
          print(
            '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) '
            '→ true (pantalla viaje montada, snapshot transitorio)',
          );
          return true;
        }
        if (retomarTaxistaEnCurso && debeBloquearShellSinViajeTaxista) {
          print(
            '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) '
            '→ true (taxista en curso montado, snapshot transitorio)',
          );
          return true;
        }
        if (debeBloquearShellSinViajeTaxista) {
          final String conocido = _viajeOperativoTaxistaConocido.trim();
          if (conocido.isNotEmpty) {
            print(
              '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) '
              '→ true (bloqueo taxista + viaje conocido)',
            );
            return true;
          }
          try {
            final String? cached =
                await RaiLocalReadCache.lastKnownActiveTripId(u);
            if ((cached ?? '').trim().isNotEmpty) {
              print(
                '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) '
                '→ true (bloqueo taxista + caché)',
              );
              return true;
            }
          } catch (_) {}
          print(
            '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) '
            '→ true (bloqueo taxista tras aceptar, pool transitorio)',
          );
          return true;
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
    if (!ok) {
      final bool porQuery = await _usuarioTieneViajeEnSeguimientoPorQuery(u);
      if (porQuery) {
        mantenerOverlayViajeEnShell(kOverlayClienteViajeActivo);
        notificarRebuildShell();
        print(
          '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) '
          '→ true (query cold start)',
        );
        return true;
      }
      // Viaje en curso montado: no mandar al Home por permission-denied / snapshot vacío
      // cuando el TTL del overlay ya expiró en viajes largos.
      if (retomarClienteEnCurso && !flujoPostViajeClienteActivo) {
        mantenerOverlayViajeEnShell(kOverlayClienteViajeActivo);
        print(
          '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) '
          '→ true (pantalla montada, pool transitorio sin overlay TTL)',
        );
        return true;
      }
    }
    print('[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) → $ok');
    if (ok) {
      final String vid = (await _db.collection('usuarios').doc(u).get())
              .data()?['viajeActivoId']
              ?.toString()
              .trim() ??
          '';
      if (vid.isNotEmpty && viajeClienteDescartadoEnSesion(vid)) {
        print(
          '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) '
          '→ false (viaje descartado en sesión)',
        );
        return false;
      }
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

  // --- Cliente: pausa voluntaria, post-viaje, bootstrap --------------------

  static const Duration kFlujoPostViajeClienteDuracion =
      Duration(minutes: 20);

  static String _flujoPostViajeClienteViajeId = '';
  static String _viajeOperativoClienteConocido = '';
  static String _viajeIdPausaVoluntariaCliente = '';
  static String _forzarInicioClienteShellForzadoViajeId = '';
  static int _retomarClienteGeneracion = 0;
  static bool _retomarClienteEnCurso = false;
  static int _bannerPausaGraciaHastaMs = 0;
  static final Set<String> _viajesClienteDescartadosSesion = <String>{};
  static final Map<String, Map<String, dynamic>> _bootstrapViajeCliente =
      <String, Map<String, dynamic>>{};

  static bool get flujoPostViajeClienteActivo =>
      _flujoPostViajeClienteViajeId.isNotEmpty;

  static String get flujoPostViajeClienteViajeId =>
      _flujoPostViajeClienteViajeId;

  static bool flujoPostViajeClienteBloquea(String viajeId) {
    final String id = viajeId.trim();
    if (id.isEmpty) return false;
    return _flujoPostViajeClienteViajeId == id;
  }

  static void marcarFlujoPostViajeCliente(String viajeId) {
    final String id = viajeId.trim();
    if (id.isEmpty) return;
    _flujoPostViajeClienteViajeId = id;
    forzarInicioClienteShell(duracion: kFlujoPostViajeClienteDuracion);
    cancelarMantenimientoOverlayViaje();
    notificarRebuildShell();
  }

  static void cerrarFlujoPostViajeCliente() {
    _flujoPostViajeClienteViajeId = '';
    cancelarForzarInicioClienteShellForzado();
    if (!debeMostrarBannerPausaCliente) {
      cancelarForzarInicioClienteShell();
    }
    notificarRebuildShell();
  }

  static void prepararSalidaClientePostViaje({required String viajeId}) {
    marcarFlujoPostViajeCliente(viajeId);
    _retomarClienteEnCurso = false;
  }

  static void registrarViajeOperativoCliente(String viajeId) {
    final String id = viajeId.trim();
    if (id.isEmpty) return;
    _viajeOperativoClienteConocido = id;
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.trim().isNotEmpty) {
      unawaited(RaiLocalReadCache.rememberActiveTripId(uid, id));
    }
    if (_flujoPostViajeClienteViajeId.isNotEmpty &&
        _flujoPostViajeClienteViajeId != id) {
      _flujoPostViajeClienteViajeId = '';
      cancelarForzarInicioClienteShell();
    }
    if (_forzarInicioClienteShellForzadoViajeId.isNotEmpty &&
        _forzarInicioClienteShellForzadoViajeId != id) {
      cancelarForzarInicioClienteShellForzado();
    }
    notificarRebuildShell();
  }

  static String get viajeOperativoClienteConocido =>
      _viajeOperativoClienteConocido;

  static String get viajeIdPausaVoluntariaCliente =>
      _viajeIdPausaVoluntariaCliente;

  static String resolverViajeIdClienteParaPausa({String? preferido}) {
    final String p = (preferido ?? '').trim();
    if (p.isNotEmpty) return p;
    if (_viajeOperativoClienteConocido.isNotEmpty) {
      return _viajeOperativoClienteConocido;
    }
    return _viajeIdPausaVoluntariaCliente;
  }

  /// Post-viaje (factura/calificar): home sin reabrir overlay hasta terminar flujo.
  static bool get clientePostViajeEnHome =>
      debeForzarInicioClienteShell && flujoPostViajeClienteActivo;

  /// Banner de rescate: viaje operativo pero overlay no visible (fallo UI).
  static bool get debeMostrarBannerRecuperacionViaje {
    if (flujoPostViajeClienteActivo) return false;
    if (clienteSuprimirOverlayViajeActivo) return false;
    if (debeMantenerOverlayViajeEnShell) return false;
    if (retomarClienteEnCurso) return false;
    final String vid = resolverViajeIdClienteParaPausa();
    return vid.isNotEmpty && !viajeClienteDescartadoEnSesion(vid);
  }

  static void activarPausaVoluntariaClienteShell({String? viajeId}) {
    // Modelo viaje pegado: sin pausa en home (Mis viajes = rescate).
    print(
      '[VIAJE_ACTIVO] activarPausaVoluntaria omitido (viaje pegado) vid=${viajeId ?? ''}',
    );
  }

  /// Limpia pausa obsoleta en disco al arrancar (migración a viaje pegado).
  static Future<void> prepararModeloViajePegadoCliente(String uid) async {
    final String u = uid.trim();
    if (u.isEmpty) return;
    await limpiarPausaVoluntariaClientePersistida(u);
    if (!flujoPostViajeClienteActivo) {
      cancelarForzarInicioClienteShell();
      _viajeIdPausaVoluntariaCliente = '';
    }
  }

  /// Cold start: si el cliente pausó con atrás, quedarse en home + banner (sin overlay).
  static Future<void> restaurarPausaVoluntariaClienteSiAplica(String uid) async {
    final String u = uid.trim();
    if (u.isEmpty) return;
    final String paused =
        (await RaiLocalReadCache.lastKnownClientePausaVoluntaria(u) ?? '')
            .trim();
    if (paused.isEmpty) return;
    if (viajeClienteDescartadoEnSesion(paused)) {
      await RaiLocalReadCache.clearClientePausaVoluntaria(u);
      return;
    }
    if (await ViajesRepo.viajeDocAusenteOInaccesibleParaCliente(paused)) {
      await RaiLocalReadCache.clearClientePausaVoluntaria(u);
      return;
    }
    _viajeIdPausaVoluntariaCliente = paused;
    _viajeOperativoClienteConocido = paused;
    forzarInicioClienteShell(duracion: const Duration(hours: 24));
    _bannerPausaGraciaHastaMs =
        DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch;
    cancelarMantenimientoOverlayViaje();
    print(
      '[VIAJE_ACTIVO] pausa voluntaria restaurada desde disco vid=$paused',
    );
  }

  static Future<bool> clienteDebePermanecerEnHomePorPausa(
    String uid,
    String viajeId,
  ) async {
    final String u = uid.trim();
    final String id = viajeId.trim();
    if (u.isEmpty || id.isEmpty) return false;
    if (debeForzarInicioClienteShell && !flujoPostViajeClienteActivo) {
      return true;
    }
    final String paused =
        (await RaiLocalReadCache.lastKnownClientePausaVoluntaria(u) ?? '')
            .trim();
    if (paused.isEmpty || paused != id) return false;
    activarPausaVoluntariaClienteShell(viajeId: id);
    return true;
  }

  static Future<void> limpiarPausaVoluntariaClientePersistida([String? uid]) async {
    final String u =
        (uid ?? FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (u.isEmpty) return;
    await RaiLocalReadCache.clearClientePausaVoluntaria(u);
  }

  static bool get debeMostrarBannerPausaCliente =>
      !flujoPostViajeClienteActivo &&
      (_viajeIdPausaVoluntariaCliente.isNotEmpty ||
          _viajeOperativoClienteConocido.isNotEmpty ||
          debeForzarInicioClienteShell);

  /// Sembrar id para banner «Retomar» tras cold start sin overlay.
  /// Reserva lejana en home: sin banner «Retomar», sin bloqueo de overlay.
  static void liberarReservaProgramadaLejanaEnHome({String? viajeId}) {
    cancelarForzarInicioClienteShell();
    cancelarMantenimientoOverlayViaje();
    final String id = (viajeId ?? '').trim();
    if (id.isNotEmpty) {
      if (_viajeOperativoClienteConocido == id) {
        _viajeOperativoClienteConocido = '';
      }
      if (_viajeIdPausaVoluntariaCliente == id) {
        _viajeIdPausaVoluntariaCliente = '';
      }
    }
    _bannerPausaGraciaHastaMs = 0;
    notificarRebuildShell();
  }

  static void sembrarViajeClienteParaRetomarEnHome(
    String viajeId, {
    Map<String, dynamic>? docHint,
  }) {
    final String id = viajeId.trim();
    if (id.isEmpty || flujoPostViajeClienteBloquea(id)) return;
    final Map<String, dynamic>? d =
        docHint ?? peekResumenViajeCliente(id);
    if (d != null &&
        ViajePoolTaxistaGate.esReservaProgramadaLejana(d)) {
      liberarReservaProgramadaLejanaEnHome(viajeId: id);
      return;
    }
    _viajeOperativoClienteConocido = id;
    _viajeIdPausaVoluntariaCliente = id;
    _bannerPausaGraciaHastaMs =
        DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch;
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.trim().isNotEmpty) {
      unawaited(
        RaiLocalReadCache.rememberClientePausaVoluntaria(uid.trim(), id),
      );
    }
    notificarRebuildShell();
  }

  /// Resuelve viaje activo del cliente (query + caché) y prepara overlay o retomar.
  static Future<String?> hidratarViajeActivoCliente(String uid) async {
    final String u = uid.trim();
    if (u.isEmpty) return null;
    try {
      final DocumentSnapshot<Map<String, dynamic>>? doc =
          await obtenerDocumentoViajeActivo(u);
      if (doc == null || !doc.exists) {
        final String cached =
            (await RaiLocalReadCache.lastKnownActiveTripId(u) ?? '').trim();
        if (cached.isNotEmpty &&
            !viajeClienteDescartadoEnSesion(cached) &&
            !flujoPostViajeClienteBloquea(cached)) {
          final Map<String, dynamic>? peek =
              peekResumenViajeCliente(cached);
          if (peek != null &&
              ViajePoolTaxistaGate.esReservaProgramadaLejana(peek)) {
            liberarReservaProgramadaLejanaEnHome(viajeId: cached);
            return cached;
          }
          sembrarViajeClienteParaRetomarEnHome(cached, docHint: peek);
          return cached;
        }
        return null;
      }
      final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
      if (!viajeDocCuentaComoSeguimientoParaUsuario(d, u)) return null;
      if (ViajePoolTaxistaGate.clienteDebeVerConfirmacionProgramado(d)) {
        sembrarBootstrapViajeCliente(doc.id, d);
        unawaited(RaiLocalReadCache.rememberActiveTripId(u, doc.id));
        liberarReservaProgramadaLejanaEnHome(viajeId: doc.id);
        return doc.id;
      }
      registrarViajeOperativoCliente(doc.id);
      unawaited(RaiLocalReadCache.rememberActiveTripId(u, doc.id));
      sembrarBootstrapViajeCliente(doc.id, d);
      return doc.id;
    } catch (e) {
      print('[VIAJE_ACTIVO] hidratarViajeActivoCliente error: $e');
      return null;
    }
  }

  static bool get enGraciaBannerPausaCliente =>
      DateTime.now().millisecondsSinceEpoch < _bannerPausaGraciaHastaMs;

  static bool viajeClienteDescartadoEnSesion(String viajeId) =>
      _viajesClienteDescartadosSesion.contains(viajeId.trim());

  static void markClienteTripScreenMounted() {
    _retomarClienteEnCurso = true;
    _retomarClienteGeneracion++;
    unawaited(limpiarPausaVoluntariaClientePersistida());
    if (!flujoPostViajeClienteActivo) {
      cancelarForzarInicioClienteShell();
      mantenerOverlayViajeEnShell(const Duration(minutes: 30));
    }
    notificarRebuildShell();
  }

  static void markClienteTripScreenUnmounted() {
    _retomarClienteEnCurso = false;
  }

  static bool get retomarClienteEnCurso => _retomarClienteEnCurso;

  static int get retomarClienteGeneracion => _retomarClienteGeneracion;

  static String _viajeOperativoTaxistaConocido = '';
  static bool _retomarTaxistaEnCurso = false;

  static String get viajeOperativoTaxistaConocido =>
      _viajeOperativoTaxistaConocido;

  static bool get retomarTaxistaEnCurso => _retomarTaxistaEnCurso;

  static void registrarViajeOperativoTaxista(String viajeId) {
    final String id = viajeId.trim();
    if (id.isEmpty) return;
    _viajeOperativoTaxistaConocido = id;
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.trim().isNotEmpty) {
      unawaited(RaiLocalReadCache.rememberActiveTripId(uid, id));
    }
    notificarRebuildShell();
  }

  static void markTaxistaTripScreenMounted() {
    _retomarTaxistaEnCurso = true;
    bloquearShellTaxistaTrasAceptar(const Duration(minutes: 30));
    notificarRebuildShell();
  }

  static void markTaxistaTripScreenUnmounted() {
    _retomarTaxistaEnCurso = false;
  }

  /// Tras factura/post-viaje: limpia overlay, bloqueo y caché antes de volver al pool.
  /// Evita quedar en «Cargando tu viaje…» con un viaje ya completado (turismo/pool).
  static Future<void> prepararSalidaTaxistaAlInicio({
    String? viajeIdCompletado,
  }) async {
    final String vid = (viajeIdCompletado ?? '').trim();
    markTaxistaTripScreenUnmounted();
    cancelarBloqueoShellTaxista();
    cancelarMantenimientoOverlayViaje();
    if (vid.isNotEmpty && _viajeOperativoTaxistaConocido == vid) {
      _viajeOperativoTaxistaConocido = '';
    } else if (vid.isEmpty) {
      _viajeOperativoTaxistaConocido = '';
    }
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.trim().isNotEmpty) {
      final String u = uid.trim();
      await ViajesRepo.limpiarViajeActivoSiNoOperativo(u);
      await RaiLocalReadCache.clearActiveTripId(u);
    }
    notificarRebuildShell();
    print(
      '[VIAJE_ACTIVO] prepararSalidaTaxistaAlInicio vid=${vid.isEmpty ? "—" : vid}',
    );
  }

  static Future<bool> viajeDocSigueOperativoParaTaxista(
    String viajeId,
    String uid,
  ) async {
    final String id = viajeId.trim();
    final String u = uid.trim();
    if (id.isEmpty || u.isEmpty) return false;
    try {
      final DocumentSnapshot<Map<String, dynamic>> vSnap =
          await _db.collection('viajes').doc(id).get();
      if (!vSnap.exists) return false;
      return ViajesRepo.viajeVisibleEnCursoTaxista(
        vSnap.data() ?? <String, dynamic>{},
        u,
      );
    } catch (e) {
      print('[VIAJE_ACTIVO] viajeDocSigueOperativoParaTaxista error: $e');
      return false;
    }
  }

  static bool pausaClienteBloqueadaPorRetomar({int? generacionInicio}) {
    if (!_retomarClienteEnCurso) return false;
    if (generacionInicio == null) return true;
    return generacionInicio != _retomarClienteGeneracion;
  }

  static void cancelarForzarInicioClienteShellForzado() {
    _forzarInicioClienteShellForzadoViajeId = '';
    if (!flujoPostViajeClienteActivo && !debeMostrarBannerPausaCliente) {
      cancelarForzarInicioClienteShell();
    }
    notificarRebuildShell();
  }

  static Future<bool> viajeDocSigueOperativoParaCliente(
    String viajeId,
    String uid,
  ) async {
    final String id = viajeId.trim();
    final String u = uid.trim();
    if (id.isEmpty || u.isEmpty) return false;
    try {
      final DocumentSnapshot<Map<String, dynamic>> vSnap =
          await _db.collection('viajes').doc(id).get();
      if (!vSnap.exists) return false;
      final Map<String, dynamic> d = vSnap.data() ?? <String, dynamic>{};
      final bool esCliente = (d['uidCliente'] ?? '').toString().trim() == u ||
          (d['clienteId'] ?? '').toString().trim() == u;
      if (!esCliente) return false;
      final String st =
          EstadosViaje.normalizar((d['estado'] ?? '').toString());
      if (d['completado'] == true || EstadosViaje.esTerminal(st)) {
        return false;
      }
      return ViajePoolTaxistaGate.viajeDocDebeMostrarOverlayShell(d, u);
    } catch (e) {
      print('[VIAJE_ACTIVO] viajeDocSigueOperativoParaCliente error: $e');
      if (_esFirestorePermisoDenegado(e)) {
        final bool ausente =
            await ViajesRepo.viajeDocAusenteOInaccesibleParaCliente(id);
        print(
          '[VIAJE_ACTIVO] viajeDocSigueOperativoParaCliente → ${!ausente} '
          '(permission-denied, ausente=$ausente)',
        );
        return !ausente;
      }
      try {
        final DocumentSnapshot<Map<String, dynamic>>? doc =
            await ViajesRepo.getViajeActivoParaUsuario(u);
        if (doc != null && doc.id == id) {
          print(
            '[VIAJE_ACTIVO] viajeDocSigueOperativoParaCliente → true (query fallback)',
          );
          return true;
        }
      } catch (_) {}
      final String cached =
          (await RaiLocalReadCache.lastKnownActiveTripId(u) ?? '').trim();
      if (cached == id) {
        print(
          '[VIAJE_ACTIVO] viajeDocSigueOperativoParaCliente → true (caché local)',
        );
        return true;
      }
      return false;
    }
  }

  static Future<String?> repararViajeActivoClienteSiHuerfano(
    String uid, {
    String? viajeIdHint,
  }) async {
    final String u = uid.trim();
    if (u.isEmpty) return null;
    final String hint = (viajeIdHint ?? '').trim();
    if (hint.isEmpty) return null;
    if (viajeClienteDescartadoEnSesion(hint)) return null;
    if (await ViajesRepo.viajeDocAusenteOInaccesibleParaCliente(hint)) {
      return null;
    }
    if (!await viajeDocSigueOperativoParaCliente(hint, u)) return null;
    try {
      final DocumentSnapshot<Map<String, dynamic>> userSnap =
          await _db.collection('usuarios').doc(u).get();
      final String activo =
          (userSnap.data()?['viajeActivoId'] ?? '').toString().trim();
      if (activo != hint) {
        await _db.collection('usuarios').doc(u).set({
          'viajeActivoId': hint,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      registrarViajeOperativoCliente(hint);
      return hint;
    } catch (e) {
      print('[VIAJE_ACTIVO] repararViajeActivoClienteSiHuerfano error: $e');
      return null;
    }
  }

  static Future<bool> clienteViajeActivoImpideNuevoPedido(
    String uid, {
    bool nuevoEsAhora = true,
  }) async {
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
      if (!vSnap.exists) {
        if (await ViajesRepo.viajeDocAusenteOInaccesibleParaCliente(vid)) {
          unawaited(liberarClienteTrasViajeEliminado(vid, uid: u));
        }
        return false;
      }

      final Map<String, dynamic> d = vSnap.data() ?? <String, dynamic>{};
      return ViajePoolTaxistaGate.clienteViajeExistenteBloqueaNuevoPedido(
        d,
        u,
        nuevoEsAhora: nuevoEsAhora,
      );
    } catch (e) {
      print('[VIAJE_ACTIVO] clienteViajeActivoImpideNuevoPedido error: $e');
      if (_esFirestorePermisoDenegado(e)) {
        try {
          final DocumentSnapshot<Map<String, dynamic>> userSnap =
              await _db.collection('usuarios').doc(u).get();
          final String vid =
              (userSnap.data()?['viajeActivoId'] ?? '').toString().trim();
          if (vid.isNotEmpty &&
              await ViajesRepo.viajeDocAusenteOInaccesibleParaCliente(vid)) {
            unawaited(liberarClienteTrasViajeEliminado(vid, uid: u));
          }
        } catch (_) {}
      }
      return false;
    }
  }

  /// Viaje borrado en consola / `viajeActivoId` huérfano: limpia pausa, banner y caché.
  static Future<void> liberarClienteTrasViajeEliminado(
    String viajeId, {
    String? uid,
  }) async {
    final String id = viajeId.trim();
    if (id.isNotEmpty) {
      _viajesClienteDescartadosSesion.add(id);
      if (_flujoPostViajeClienteViajeId == id) {
        cerrarFlujoPostViajeCliente();
      }
      if (_viajeOperativoClienteConocido == id) {
        _viajeOperativoClienteConocido = '';
      }
      if (_viajeIdPausaVoluntariaCliente == id) {
        _viajeIdPausaVoluntariaCliente = '';
      }
      if (_forzarInicioClienteShellForzadoViajeId == id) {
        cancelarForzarInicioClienteShellForzado();
      }
      _bootstrapViajeCliente.remove(id);
    }
    cancelarForzarInicioClienteShell();
    _bannerPausaGraciaHastaMs = 0;
    cancelarMantenimientoOverlayViaje();
    final String u = (uid ?? FirebaseAuth.instance.currentUser?.uid ?? '')
        .trim();
    if (u.isNotEmpty) {
      unawaited(RaiLocalReadCache.clearActiveTripId(u));
      unawaited(limpiarPausaVoluntariaClientePersistida(u));
      try {
        await _limpiarViajeActivoFirestore(u);
      } catch (e) {
        print('[VIAJE_ACTIVO] liberarClienteTrasViajeEliminado limpiar uid: $e');
      }
    }
    notificarRebuildShell();
    print('[VIAJE_ACTIVO] liberarClienteTrasViajeEliminado ($id)');
  }

  static Future<String> _leerViajeActivoIdUsuario(String uid) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> userSnap =
          await _db.collection('usuarios').doc(uid.trim()).get(
                const GetOptions(source: Source.server),
              );
      return (userSnap.data()?['viajeActivoId'] ?? '').toString().trim();
    } catch (e) {
      print('[VIAJE_ACTIVO] _leerViajeActivoIdUsuario: $e');
      return '';
    }
  }

  /// Al abrir home / banner: limpia `viajeActivoId` huérfano o pausa fantasma.
  static Future<bool> reconciliarViajeActivoHuerfanoCliente(String uid) async {
    final String u = uid.trim();
    if (u.isEmpty) return false;

    if (retomarClienteEnCurso) {
      print(
        '[VIAJE_ACTIVO] reconciliarViajeActivoHuerfanoCliente omitido (viaje montado)',
      );
      return false;
    }

    // Pausa voluntaria (flecha atrás): el viaje sigue en servidor; no limpiar.
    if (clientePostViajeEnHome) {
      print(
        '[VIAJE_ACTIVO] reconciliarViajeActivoHuerfanoCliente omitido (post-viaje)',
      );
      return false;
    }

    final String activoFirestore = await _leerViajeActivoIdUsuario(u);
    final String vid = resolverViajeIdClienteParaPausa(
      preferido: activoFirestore,
    );
    if (vid.isEmpty) {
      if (_viajeIdPausaVoluntariaCliente.isNotEmpty ||
          _viajeOperativoClienteConocido.isNotEmpty ||
          debeForzarInicioClienteShell) {
        cancelarForzarInicioClienteShell();
        _viajeIdPausaVoluntariaCliente = '';
        _viajeOperativoClienteConocido = '';
        _bannerPausaGraciaHastaMs = 0;
        notificarRebuildShell();
      }
      return false;
    }
    if (viajeClienteDescartadoEnSesion(vid)) return true;

    final bool ausente =
        await ViajesRepo.viajeDocAusenteOInaccesibleParaCliente(vid);
    if (ausente) {
      await liberarClienteTrasViajeEliminado(vid, uid: u);
      return true;
    }

    if (await viajeDocSigueOperativoParaCliente(vid, u)) {
      return false;
    }

    await liberarClienteTrasViajeEliminado(vid, uid: u);
    return true;
  }

  /// Confirma en servidor que el documento del viaje ya no existe (o el uid ya no lo referencia).
  static Future<bool> confirmarViajeAusenteEnFirestore(
    String viajeId, {
    String? uid,
  }) async {
    final String id = viajeId.trim();
    if (id.isEmpty) return true;

    for (int i = 0; i < 3; i++) {
      try {
        final DocumentSnapshot<Map<String, dynamic>> snap =
            await _db.collection('viajes').doc(id).get(
                  const GetOptions(source: Source.server),
                );
        if (!snap.exists) return true;
        return false;
      } on FirebaseException catch (e) {
        if (!_esFirestorePermisoDenegado(e)) rethrow;
      } catch (e) {
        if (!_esFirestorePermisoDenegado(e)) {
          print('[VIAJE_ACTIVO] confirmarViajeAusenteEnFirestore: $e');
        }
      }
      if (i < 2) {
        await Future<void>.delayed(Duration(milliseconds: 450 * (i + 1)));
      }
    }

    final String u = (uid ?? FirebaseAuth.instance.currentUser?.uid ?? '')
        .trim();
    if (u.isNotEmpty) {
      if (await ViajesRepo.viajeDocAusenteOInaccesibleParaCliente(id)) {
        return true;
      }
    }

    return false;
  }

  static void liberarClienteTrasCancelacionOViajeTerminal(String viajeId) {
    final String id = viajeId.trim();
    if (id.isEmpty) return;
    _viajesClienteDescartadosSesion.add(id);
    if (_flujoPostViajeClienteViajeId == id) {
      cerrarFlujoPostViajeCliente();
    }
    if (_viajeOperativoClienteConocido == id) {
      _viajeOperativoClienteConocido = '';
    }
    if (_viajeIdPausaVoluntariaCliente == id) {
      _viajeIdPausaVoluntariaCliente = '';
    }
    if (_forzarInicioClienteShellForzadoViajeId == id) {
      cancelarForzarInicioClienteShellForzado();
    }
    _bootstrapViajeCliente.remove(id);
    cancelarMantenimientoOverlayViaje();
    cancelarForzarInicioClienteShell();
    _bannerPausaGraciaHastaMs = 0;
    notificarRebuildShell();
  }

  static void sembrarBootstrapViajeCliente(
    String viajeId,
    Map<String, dynamic> data,
  ) {
    final String id = viajeId.trim();
    if (id.isEmpty || data.isEmpty) return;
    _bootstrapViajeCliente[id] = Map<String, dynamic>.from(data);
  }

  static Map<String, dynamic>? tomarBootstrapViajeCliente(String viajeId) {
    final String id = viajeId.trim();
    if (id.isEmpty) return null;
    return _bootstrapViajeCliente.remove(id);
  }

  static Map<String, dynamic>? peekResumenViajeCliente(String viajeId) {
    final String id = viajeId.trim();
    if (id.isEmpty) return null;
    final Map<String, dynamic>? d = _bootstrapViajeCliente[id];
    if (d == null) return null;
    return Map<String, dynamic>.from(d);
  }
}
