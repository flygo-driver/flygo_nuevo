// lib/widgets/bola_post_factura_listener.dart
//
// Si una Bola Ahorro pura (sin viaje espejo) pasa a `finalizada` mientras la
// contraparte no está en el diálogo de confirmación, abre [FacturaBolaPueblo]
// de inmediato (sin espera artificial).
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flygo_nuevo/pantallas/comun/factura_bola_pueblo.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/widgets/bola_post_factura_reopen_guard.dart';

class BolaPostFacturaListener extends StatefulWidget {
  final Widget child;

  const BolaPostFacturaListener({super.key, required this.child});

  @override
  State<BolaPostFacturaListener> createState() =>
      _BolaPostFacturaListenerState();
}

class _BolaPostFacturaListenerState extends State<BolaPostFacturaListener> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subComoCliente;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subComoTaxista;
  bool _primeraEmisionCliente = true;
  bool _primeraEmisionTaxista = true;
  String? _ultimaBolaOfrecida;
  bool _facturaEnCurso = false;

  @override
  void initState() {
    super.initState();
    _arrancar();
  }

  void _arrancar() {
    final User? u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final Query<Map<String, dynamic>> qCliente = FirebaseFirestore.instance
        .collection('bolas_pueblo')
        .where('uidCliente', isEqualTo: u.uid)
        .where('estado', isEqualTo: 'finalizada')
        .orderBy('finalizadaEn', descending: true)
        .limit(1);

    final Query<Map<String, dynamic>> qTaxista = FirebaseFirestore.instance
        .collection('bolas_pueblo')
        .where('uidTaxista', isEqualTo: u.uid)
        .where('estado', isEqualTo: 'finalizada')
        .orderBy('finalizadaEn', descending: true)
        .limit(1);

    _subComoCliente = qCliente.snapshots().listen(
      (QuerySnapshot<Map<String, dynamic>> snap) {
        _onBolasSnap(snap, u.uid, comoCliente: true);
      },
      onError: (_) {},
    );

    _subComoTaxista = qTaxista.snapshots().listen(
      (QuerySnapshot<Map<String, dynamic>> snap) {
        _onBolasSnap(snap, u.uid, comoCliente: false);
      },
      onError: (_) {},
    );
  }

  bool _debeOfrecerFacturaBola(Map<String, dynamic> d) {
    return (d['estado'] ?? '').toString().trim().toLowerCase() == 'finalizada';
  }

  /// Solo al abrir la app: recupera factura si acaba de cerrarse hace segundos
  /// y el usuario aún no la vio (p. ej. reinició la app al instante).
  bool _finalizacionHaceSegundos(Map<String, dynamic> d, {int segundos = 90}) {
    final dynamic fin = d['finalizadaEn'] ?? d['updatedAt'];
    DateTime? dt;
    if (fin is Timestamp) dt = fin.toDate();
    if (fin is DateTime) dt = fin;
    if (dt == null) return false;
    return DateTime.now().difference(dt).inSeconds <= segundos;
  }

  void _onBolasSnap(
    QuerySnapshot<Map<String, dynamic>> snap,
    String uid, {
    required bool comoCliente,
  }) {
    if (!mounted) return;

    final bool primera =
        comoCliente ? _primeraEmisionCliente : _primeraEmisionTaxista;
    if (primera) {
      if (comoCliente) {
        _primeraEmisionCliente = false;
      } else {
        _primeraEmisionTaxista = false;
      }
      if (snap.docs.isNotEmpty) {
        final QueryDocumentSnapshot<Map<String, dynamic>> doc = snap.docs.first;
        final Map<String, dynamic> d = doc.data();
        if (_debeOfrecerFacturaBola(d) &&
            _finalizacionHaceSegundos(d) &&
            !BolaPostFacturaReopenGuard.shouldSuppressListenerPush(doc.id)) {
          _ofrecerFacturaSiCorresponde(doc.id, d, uid);
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
      if (!_debeOfrecerFacturaBola(d)) continue;
      _ofrecerFacturaSiCorresponde(change.doc.id, d, uid);
    }
  }

  void _ofrecerFacturaSiCorresponde(
    String bolaId,
    Map<String, dynamic> d,
    String uid,
  ) {
    if (BolaPostFacturaReopenGuard.shouldSuppressListenerPush(bolaId)) {
      return;
    }
    if (_ultimaBolaOfrecida == bolaId || _facturaEnCurso) return;

    _ultimaBolaOfrecida = bolaId;
    _facturaEnCurso = true;
    BolaPostFacturaReopenGuard.markOpened(bolaId);

    final String uidTx = (d['uidTaxista'] ?? '').toString().trim();
    final String role = uid.trim() == uidTx ? 'taxista' : 'cliente';

    SchedulerBinding.instance.addPostFrameCallback((_) {
      unawaited(_abrirFactura(bolaId, role));
    });
  }

  Future<void> _abrirFactura(String bolaId, String role) async {
    try {
      if (!mounted) return;
      final NavigatorState? nav = NavigationService.navigatorKey.currentState;
      if (nav == null || !nav.mounted) return;

      await FacturaBolaPueblo.mostrar(
        nav.context,
        bolaId: bolaId,
        role: role,
      );
    } catch (_) {
    } finally {
      if (mounted) {
        _facturaEnCurso = false;
      }
    }
  }

  @override
  void dispose() {
    _subComoCliente?.cancel();
    _subComoTaxista?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
