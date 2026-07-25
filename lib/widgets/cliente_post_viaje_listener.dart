// lib/widgets/cliente_post_viaje_listener.dart
//
// Abre factura + [PostViajeClienteFlow] al detectar el cierre.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flygo_nuevo/navegacion/post_viaje_cliente_nav.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/firebase_auth_resolve.dart';
import 'package:flygo_nuevo/widgets/cliente_post_viaje_reopen_guard.dart';

class ClientePostViajeListener extends StatefulWidget {
  final Widget child;

  const ClientePostViajeListener({super.key, required this.child});

  @override
  State<ClientePostViajeListener> createState() =>
      _ClientePostViajeListenerState();
}

class _ClientePostViajeListenerState extends State<ClientePostViajeListener> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subCompletados;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subUsuario;
  bool _primeraEmisionCompletados = true;
  String? _ultimoViajeOfrecido;
  String? _ultimoViajeActivoId;
  bool _flujoPostViajeEnCurso = false;

  @override
  void initState() {
    super.initState();
    unawaited(_arrancarCuandoAuthListo());
  }

  Future<void> _arrancarCuandoAuthListo() async {
    await ClientePostViajeReopenGuard.hydrateFromPrefs();
    final User? u = await resolveFirebaseUser(
      timeout: const Duration(seconds: 8),
    );
    if (!mounted || u == null) return;
    _arrancar(u);
  }

  void _arrancar(User u) {

    final Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('viajes')
        .where(
          Filter.or(
            Filter('uidCliente', isEqualTo: u.uid),
            Filter('clienteId', isEqualTo: u.uid),
          ),
        )
        .where('completado', isEqualTo: true)
        .orderBy('finalizadoEn', descending: true)
        .limit(1);

    _subCompletados = q.snapshots().listen(
      _onViajesCompletadosSnap,
      onError: (_) {},
    );

    _subUsuario = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(u.uid)
        .snapshots()
        .listen(
      (DocumentSnapshot<Map<String, dynamic>> snap) {
        unawaited(_onUsuarioSnap(snap));
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

  /// Recuperación al abrir la app: solo si el cierre fue hace unos segundos.
  bool _finalizacionHaceSegundos(Map<String, dynamic> d, {int segundos = 90}) {
    final dynamic fin = d['finalizadoEn'] ?? d['updatedAt'];
    DateTime? dt;
    if (fin is Timestamp) dt = fin.toDate();
    if (fin is DateTime) dt = fin;
    if (dt == null) return false;
    return DateTime.now().difference(dt).inSeconds <= segundos;
  }

  Future<void> _onUsuarioSnap(DocumentSnapshot<Map<String, dynamic>> snap) async {
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
      if (!_viajeCompletado(d)) return;
      _ofrecerPostViajeSiCorresponde(lost, d);
    } catch (_) {}
  }

  void _onViajesCompletadosSnap(QuerySnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;

    if (_primeraEmisionCompletados) {
      _primeraEmisionCompletados = false;
      if (snap.docs.isNotEmpty) {
        final QueryDocumentSnapshot<Map<String, dynamic>> doc = snap.docs.first;
        final Map<String, dynamic> d = doc.data();
        if (_viajeCompletado(d) && _finalizacionHaceSegundos(d)) {
          unawaited(_ofrecerPostViajeSiCorresponde(doc.id, d));
        }
      }
      return;
    }

    for (final DocumentChange<Map<String, dynamic>> change in snap.docChanges) {
      if (change.type != DocumentChangeType.added &&
          change.type != DocumentChangeType.modified) {
        continue;
      }
      final Map<String, dynamic>? raw = change.doc.data();
      if (raw == null) continue;
      final Map<String, dynamic> d = raw;
      if (!_viajeCompletado(d)) continue;
      unawaited(_ofrecerPostViajeSiCorresponde(change.doc.id, d));
    }
  }

  Future<void> _ofrecerPostViajeSiCorresponde(
    String id,
    Map<String, dynamic> d,
  ) async {
    if (CorporativoTaxistaService.debeOcultarEnAppCliente(d)) {
      final String? uid = FirebaseAuth.instance.currentUser?.uid;
      await ClientePostViajeReopenGuard.markCompleted(
        viajeId: id,
        uidCliente: uid,
      );
      return;
    }
    if (await ClientePostViajeReopenGuard.shouldSuppressAsync(id, viajeData: d)) {
      return;
    }
    if (!mounted) return;
    if (_ultimoViajeOfrecido == id || _flujoPostViajeEnCurso) return;

    _ultimoViajeOfrecido = id;
    _flujoPostViajeEnCurso = true;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      unawaited(_abrirPostViaje(id, d));
    });
  }

  Future<void> _abrirPostViaje(
    String viajeId,
    Map<String, dynamic> data,
  ) async {
    try {
      if (!mounted) return;
      if (await ClientePostViajeReopenGuard.shouldSuppressAsync(
        viajeId,
        viajeData: data,
      )) {
        return;
      }
      final NavigatorState? nav = NavigationService.navigatorKey.currentState;
      if (nav == null) return;

      if (!nav.mounted) return;
      ActiveTripService.cancelarMantenimientoOverlayViaje();
      ClientePostViajeReopenGuard.markOpened(viajeId);
      await PostViajeClienteNav.abrirFacturaYFlujo(
        viajeId: viajeId,
        viajeDataSemilla: Map<String, dynamic>.from(data),
      );
      final String? uid = FirebaseAuth.instance.currentUser?.uid;
      await ClientePostViajeReopenGuard.markCompleted(
        viajeId: viajeId,
        uidCliente: uid,
      );
    } finally {
      ActiveTripService.cancelarMantenimientoOverlayViaje();
      if (mounted) {
        _flujoPostViajeEnCurso = false;
      }
    }
  }

  @override
  void dispose() {
    _subCompletados?.cancel();
    _subUsuario?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
