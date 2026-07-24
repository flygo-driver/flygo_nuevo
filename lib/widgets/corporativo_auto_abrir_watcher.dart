import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/rai_local_read_cache.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

/// Promueve y activa el shell cuando el encargado publica una ruta corporativa
/// lista para abrir (p. ej. «Enviar ahora» ~10 min antes de la recogida).
class CorporativoAutoAbrirWatcher extends StatefulWidget {
  const CorporativoAutoAbrirWatcher({super.key, required this.child});

  final Widget child;

  @override
  State<CorporativoAutoAbrirWatcher> createState() =>
      _CorporativoAutoAbrirWatcherState();
}

class _CorporativoAutoAbrirWatcherState extends State<CorporativoAutoAbrirWatcher> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _opSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  bool _promoviendo = false;
  String _ultimoViajePromovido = '';
  DateTime _ultimaPromocion = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _arrancar();
  }

  Future<void> _arrancar() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await CorporativoTaxistaService.cargarDismissCorpPersistido();

    await _opSub?.cancel();
    _opSub = FirebaseFirestore.instance
        .collection('chofer_operacion')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      unawaited(_evaluarOperacion(uid, snap.data()));
    });

    await _userSub?.cancel();
    _userSub = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      unawaited(_evaluarUsuario(uid, snap.data()));
    });
  }

  Future<void> _evaluarOperacion(
    String uid,
    Map<String, dynamic>? op,
  ) async {
    if (op == null) return;

    final viajesHoy = op['viajesHoy'];
    if (viajesHoy is List) {
      for (final item in viajesHoy) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        if (m['completadoHoy'] == true) continue;
        if ((m['estadoOperacion'] ?? '').toString() == 'completado') continue;
        final id = (m['viajeId'] ?? '').toString().trim();
        if (id.isNotEmpty) {
          await _intentarPromover(
            uid,
            id,
            listoSegunOperacion: m['listoParaAbrir'] == true,
          );
        }
      }
    }

    final rutas = op['rutasFijas'] ?? op['rutasActivasLista'];
    if (rutas is List) {
      for (final item in rutas) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        if (m['completadoHoy'] == true) continue;
        if ((m['estadoOperacion'] ?? '').toString() == 'completado') continue;
        if (m['listoParaAbrir'] != true) continue;
        final id = (m['viajeHoyId'] ?? '').toString().trim();
        if (id.isNotEmpty) {
          await _intentarPromover(
            uid,
            id,
            listoSegunOperacion: true,
          );
        }
      }
    }
  }

  Future<void> _evaluarUsuario(
    String uid,
    Map<String, dynamic>? u,
  ) async {
    if (u == null) return;
    final activo = (u['viajeActivoId'] ?? '').toString().trim();
    if (activo.isNotEmpty) return;

    for (final raw in [u['siguienteViajeId']]) {
      final id = (raw ?? '').toString().trim();
      if (id.isEmpty) continue;
      await _intentarPromover(uid, id);
    }
  }

  Future<void> _intentarPromover(
    String uid,
    String viajeId, {
    bool listoSegunOperacion = false,
  }) async {
    if (_promoviendo) return;
    final id = viajeId.trim();
    if (id.isEmpty) return;

    final ahora = DateTime.now();
    if (_ultimoViajePromovido == id &&
        ahora.difference(_ultimaPromocion).inSeconds < 8) {
      return;
    }

    _promoviendo = true;
    try {
      final vSnap = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(id)
          .get();
      if (!vSnap.exists) return;
      final d = vSnap.data() ?? <String, dynamic>{};
      if (!CorporativoTaxistaService.esViajeCorporativoAsignado(d, uid)) {
        return;
      }
      if (CorporativoTaxistaService.viajeCorporativoInformativoCerradoParaChofer(d)) {
        return;
      }
      if (CorporativoTaxistaService.viajeCorporativoSuperseded(d)) {
        return;
      }
      if (!await CorporativoTaxistaService.viajeCorporativoEmpresaVigente(d)) {
        return;
      }
      if (CorporativoTaxistaService.rutaCorpInformativaDismissedRecientemente(id)) {
        return;
      }
      if (CorporativoTaxistaService.esModoInformativo(d)) {
        if (!CorporativoTaxistaService.corporativoListoParaAbrirEnCurso(
          d,
          listoSegunOperacion: listoSegunOperacion,
        )) {
          return;
        }
        if (await CorporativoTaxistaService
            .taxistaTieneViajeNoCorporativoBloqueante(uid, exceptViajeId: id)) {
          await CorporativoTaxistaService.encolarViajeCorporativoInformativo(
            uidTaxista: uid,
            viajeId: id,
          );
          return;
        }
        _ultimoViajePromovido = id;
        _ultimaPromocion = ahora;
        ActiveTripService.cancelarMantenimientoOverlayViaje();
        ActiveTripService.cancelarBloqueoShellTaxista();
        await ViajesRepo.limpiarViajeActivoSiNoOperativo(uid);
        await RaiLocalReadCache.clearActiveTripId(uid);
        ActiveTripService.notificarRebuildShell();
        await NavigationService.abrirViajeCorporativoTaxista(
          uidTaxista: uid,
          viajeId: id,
        );
        return;
      }
      if (!CorporativoTaxistaService.corporativoListoParaAbrirEnCurso(
        d,
        listoSegunOperacion: listoSegunOperacion,
      )) {
        return;
      }
      if (await CorporativoTaxistaService
          .taxistaTieneViajeNoCorporativoBloqueante(uid, exceptViajeId: id)) {
        await CorporativoTaxistaService.encolarViajeCorporativoInformativo(
          uidTaxista: uid,
          viajeId: id,
        );
        return;
      }
      _ultimoViajePromovido = id;
      _ultimaPromocion = ahora;
      ActiveTripService.cancelarMantenimientoOverlayViaje();
      ActiveTripService.cancelarBloqueoShellTaxista();
      await ViajesRepo.limpiarViajeActivoSiNoOperativo(uid);
      await RaiLocalReadCache.clearActiveTripId(uid);
      ActiveTripService.notificarRebuildShell();
      await NavigationService.abrirViajeCorporativoTaxista(
        uidTaxista: uid,
        viajeId: id,
      );
    } catch (e) {
      debugPrint('[CORP] auto-abrir watcher: $e');
    } finally {
      _promoviendo = false;
    }
  }

  @override
  void dispose() {
    _opSub?.cancel();
    _userSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
