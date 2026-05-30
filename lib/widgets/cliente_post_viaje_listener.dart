// lib/widgets/cliente_post_viaje_listener.dart
//
// Si el viaje termina mientras el cliente está en el flujo principal (home visible),
// abre factura (paridad con [ViajeEnCursoCliente]) y luego [PostViajeClienteFlow].
// No dispara si hay otra ruta encima (ej. Viaje en curso), para no competir con su pushReplacement.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flygo_nuevo/pantallas/cliente/post_viaje_cliente_flow.dart';
import 'package:flygo_nuevo/pantallas/comun/factura_viaje.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/widgets/cliente_post_viaje_reopen_guard.dart';

class ClientePostViajeListener extends StatefulWidget {
  final Widget child;

  const ClientePostViajeListener({super.key, required this.child});

  @override
  State<ClientePostViajeListener> createState() =>
      _ClientePostViajeListenerState();
}

class _ClientePostViajeListenerState extends State<ClientePostViajeListener> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  String? _ultimoViajeOfrecido;
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

    _sub = q.snapshots().listen(_onViajesSnap, onError: (_) {});
  }

  void _onViajesSnap(QuerySnapshot<Map<String, dynamic>> snap) {
    if (!mounted || snap.docs.isEmpty) return;

    final Map<String, dynamic> d = snap.docs.first.data();
    final String id = snap.docs.first.id;

    if (ClientePostViajeReopenGuard.shouldSuppressListenerPush(id)) {
      return;
    }

    if (_ultimoViajeOfrecido == id || _flujoPostViajeEnCurso) return;

    final Timestamp? finTs = d['finalizadoEn'] as Timestamp?;
    if (finTs == null) return;
    final bool reciente =
        DateTime.now().difference(finTs.toDate()).inMinutes <= 10;
    if (!reciente) return;

    if (ActiveTripService.debeMantenerOverlayViajeEnShell) {
      return;
    }

    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (route?.isCurrent != true) {
      return;
    }

    _ultimoViajeOfrecido = id;
    _flujoPostViajeEnCurso = true;
    ClientePostViajeReopenGuard.markOpened(id);

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
      if (mounted) {
        _flujoPostViajeEnCurso = false;
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
