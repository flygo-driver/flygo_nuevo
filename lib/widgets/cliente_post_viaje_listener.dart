// lib/widgets/cliente_post_viaje_listener.dart
//
// Si el viaje termina mientras el cliente está en el flujo principal (home visible),
// abre factura (paridad con [ViajeEnCursoCliente]) y luego [PostViajeClienteFlow]
// de inmediato al detectar el cierre.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flygo_nuevo/pantallas/cliente/post_viaje_cliente_flow.dart';
import 'package:flygo_nuevo/pantallas/comun/factura_viaje.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
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
    _arrancar();
  }

  void _arrancar() {
    final User? u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

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
      _ofrecerFacturaSiCorresponde(lost, d);
    } catch (_) {}
  }

  void _onViajesCompletadosSnap(QuerySnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;

    if (_primeraEmisionCompletados) {
      _primeraEmisionCompletados = false;
      if (snap.docs.isNotEmpty) {
        final QueryDocumentSnapshot<Map<String, dynamic>> doc = snap.docs.first;
        final Map<String, dynamic> d = doc.data();
        if (_viajeCompletado(d) &&
            _finalizacionHaceSegundos(d) &&
            !ClientePostViajeReopenGuard.shouldSuppressListenerPush(doc.id)) {
          _ofrecerFacturaSiCorresponde(doc.id, d);
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
      _ofrecerFacturaSiCorresponde(change.doc.id, d);
    }
  }

  void _ofrecerFacturaSiCorresponde(String id, Map<String, dynamic> d) {
    if (ClientePostViajeReopenGuard.shouldSuppressListenerPush(id)) {
      return;
    }
    if (_ultimoViajeOfrecido == id || _flujoPostViajeEnCurso) return;

    // ViajeEnCursoCliente ya está mostrando factura en overlay.
    if (ActiveTripService.debeMantenerOverlayViajeEnShell) {
      return;
    }

    _ultimoViajeOfrecido = id;
    _flujoPostViajeEnCurso = true;
    ClientePostViajeReopenGuard.markOpened(id);
    ActiveTripService.mantenerOverlayViajeEnShell(const Duration(seconds: 90));

    SchedulerBinding.instance.addPostFrameCallback((_) {
      unawaited(_abrirFacturaYPostViaje(id, d));
    });
  }

  Future<void> _abrirFacturaYPostViaje(
    String viajeId,
    Map<String, dynamic> data,
  ) async {
    try {
      if (!mounted) return;
      final NavigatorState? nav = NavigationService.navigatorKey.currentState;
      if (nav == null) return;

      try {
        await FacturaViaje.mostrar(
          nav.context,
          viajeId: viajeId,
          role: 'cliente',
        );
      } catch (_) {}

      if (!nav.mounted) return;
      await nav.push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => PostViajeClienteFlow(
            viajeId: viajeId,
            viajeDataSemilla: Map<String, dynamic>.from(data),
          ),
        ),
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
