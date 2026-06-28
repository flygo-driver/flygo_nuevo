// Recupera factura + post-viaje taxista si la app se reabre tras completar.
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flygo_nuevo/navegacion/post_viaje_taxista_nav.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/firebase_auth_resolve.dart';

class TaxistaPostViajeListener extends StatefulWidget {
  const TaxistaPostViajeListener({super.key, required this.child});

  final Widget child;

  @override
  State<TaxistaPostViajeListener> createState() =>
      _TaxistaPostViajeListenerState();
}

class _TaxistaPostViajeListenerState extends State<TaxistaPostViajeListener> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subUsuario;
  String? _ultimoViajeActivoId;
  String? _ultimoViajeOfrecido;
  bool _flujoPostViajeEnCurso = false;

  @override
  void initState() {
    super.initState();
    unawaited(_arrancarCuandoAuthListo());
  }

  Future<void> _arrancarCuandoAuthListo() async {
    final User? u = await resolveFirebaseUser(
      timeout: const Duration(seconds: 8),
    );
    if (!mounted || u == null) return;
    _subUsuario = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(u.uid)
        .snapshots()
        .listen(
      (DocumentSnapshot<Map<String, dynamic>> snap) {
        unawaited(_onUsuarioSnap(snap, u.uid));
      },
      onError: (_) {},
    );
  }

  bool _viajeCompletado(Map<String, dynamic> d) {
    if (d['completado'] != true) return false;
    final String st =
        EstadosViaje.normalizar((d['estado'] ?? '').toString());
    return st == EstadosViaje.completado || d['completado'] == true;
  }

  bool _finalizacionHaceSegundos(Map<String, dynamic> d, {int segundos = 90}) {
    final dynamic fin = d['finalizadoEn'] ?? d['updatedAt'];
    DateTime? dt;
    if (fin is Timestamp) dt = fin.toDate();
    if (fin is DateTime) dt = fin;
    if (dt == null) return false;
    return DateTime.now().difference(dt).inSeconds <= segundos;
  }

  Future<void> _onUsuarioSnap(
    DocumentSnapshot<Map<String, dynamic>> snap,
    String uid,
  ) async {
    if (!mounted) return;
    final String vid =
        (snap.data()?['viajeActivoId'] ?? '').toString().trim();
    if (vid.isNotEmpty) {
      _ultimoViajeActivoId = vid;
      return;
    }
    final String lost = (_ultimoViajeActivoId ?? '').trim();
    if (lost.isEmpty) return;
    _ultimoViajeActivoId = null;

    try {
      final DocumentSnapshot<Map<String, dynamic>> vSnap =
          await FirebaseFirestore.instance.collection('viajes').doc(lost).get();
      if (!mounted || !vSnap.exists) return;
      final Map<String, dynamic> d = vSnap.data() ?? <String, dynamic>{};
      if (!_viajeCompletado(d) || !_finalizacionHaceSegundos(d)) return;
      final String tid =
          (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString().trim();
      if (tid != uid) return;
      _ofrecerPostViajeSiCorresponde(lost, d, uid);
    } catch (_) {}
  }

  void _ofrecerPostViajeSiCorresponde(
    String id,
    Map<String, dynamic> d,
    String uid,
  ) {
    if (!mounted) return;
    if (_ultimoViajeOfrecido == id || _flujoPostViajeEnCurso) return;
    _ultimoViajeOfrecido = id;
    _flujoPostViajeEnCurso = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      unawaited(_abrirPostViaje(id, d, uid));
    });
  }

  Future<void> _abrirPostViaje(
    String viajeId,
    Map<String, dynamic> data,
    String uidTaxista,
  ) async {
    try {
      if (!mounted) return;
      ActiveTripService.cancelarMantenimientoOverlayViaje();
      await PostViajeTaxistaNav.abrirFacturaYFlujo(
        viajeId: viajeId,
        uidTaxista: uidTaxista,
        viajeDataSemilla: Map<String, dynamic>.from(data),
      );
    } finally {
      ActiveTripService.cancelarMantenimientoOverlayViaje();
      if (mounted) _flujoPostViajeEnCurso = false;
    }
  }

  @override
  void dispose() {
    _subUsuario?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
