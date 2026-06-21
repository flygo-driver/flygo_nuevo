// Notifica al otro participante cuando la bola pasa a `cancelada` (acuerdo roto).
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flygo_nuevo/app_flavor.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';

class BolaCancelacionListener extends StatefulWidget {
  const BolaCancelacionListener({super.key, required this.child});

  final Widget child;

  @override
  State<BolaCancelacionListener> createState() =>
      _BolaCancelacionListenerState();
}

class _BolaCancelacionListenerState extends State<BolaCancelacionListener> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subComoTaxista;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subComoCliente;
  bool _primeraEmisionTaxista = true;
  bool _primeraEmisionCliente = true;
  String? _ultimaBolaNotificada;
  bool _navegacionEnCurso = false;

  @override
  void initState() {
    super.initState();
    _arrancar();
  }

  void _arrancar() {
    final User? u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final String uid = u.uid.trim();

    _subComoTaxista = FirebaseFirestore.instance
        .collection('bolas_pueblo')
        .where('uidTaxista', isEqualTo: uid)
        .where('estado', isEqualTo: 'cancelada')
        .limit(5)
        .snapshots()
        .listen(
          (snap) => _onSnap(snap, uid, comoTaxista: true),
          onError: (_) {},
        );

    _subComoCliente = FirebaseFirestore.instance
        .collection('bolas_pueblo')
        .where('uidCliente', isEqualTo: uid)
        .where('estado', isEqualTo: 'cancelada')
        .limit(5)
        .snapshots()
        .listen(
          (snap) => _onSnap(snap, uid, comoTaxista: false),
          onError: (_) {},
        );
  }

  bool _canceladaReciente(Map<String, dynamic> d, {int segundos = 180}) {
    final dynamic t = d['canceladaEn'] ?? d['updatedAt'];
    DateTime? dt;
    if (t is Timestamp) dt = t.toDate();
    if (t is DateTime) dt = t;
    if (dt == null) return true;
    return DateTime.now().difference(dt).inSeconds <= segundos;
  }

  void _onSnap(
    QuerySnapshot<Map<String, dynamic>> snap,
    String uid, {
    required bool comoTaxista,
  }) {
    if (!mounted) return;

    final bool primera =
        comoTaxista ? _primeraEmisionTaxista : _primeraEmisionCliente;
    if (primera) {
      if (comoTaxista) {
        _primeraEmisionTaxista = false;
      } else {
        _primeraEmisionCliente = false;
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
      if ((d['estado'] ?? '').toString().trim() != 'cancelada') continue;

      final String canceladaPor =
          (d['canceladaPor'] ?? '').toString().trim();
      if (canceladaPor.isNotEmpty && canceladaPor == uid) continue;
      if (!_canceladaReciente(d)) continue;
      if (_ultimaBolaNotificada == change.doc.id || _navegacionEnCurso) {
        continue;
      }

      _ultimaBolaNotificada = change.doc.id;
      final String msg = canceladaPor.isEmpty
          ? 'El acuerdo Bola Ahorro fue cancelado.'
          : (comoTaxista
              ? 'El pasajero canceló el acuerdo Bola Ahorro.'
              : 'El conductor canceló el acuerdo Bola Ahorro.');

      SchedulerBinding.instance.addPostFrameCallback((_) {
        unawaited(_notificarYSalir(msg));
      });
      break;
    }
  }

  Future<void> _notificarYSalir(String mensaje) async {
    if (!mounted || _navegacionEnCurso) return;
    _navegacionEnCurso = true;
    try {
      ActiveTripService.cancelarMantenimientoOverlayViaje();
      final NavigatorState? nav = NavigationService.navigatorKey.currentState;
      if (nav != null && nav.mounted) {
        ScaffoldMessenger.of(nav.context).showSnackBar(
          SnackBar(
            content: Text(mensaje),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      if (isConductorFlavor) {
        await NavigationService.irAlInicioTaxista(context: context);
      } else if (isClienteFlavor) {
        await NavigationService.irAlInicioCliente(context: context);
      } else if (nav != null && nav.mounted) {
        await NavigationService.salirModoViajeBola(nav.context);
      }
    } catch (_) {
    } finally {
      if (mounted) _navegacionEnCurso = false;
    }
  }

  @override
  void dispose() {
    _subComoTaxista?.cancel();
    _subComoCliente?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
