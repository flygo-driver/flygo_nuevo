import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/asignacion_turismo_repo.dart';
import 'package:flygo_nuevo/servicios/notification_service.dart';
import 'package:flygo_nuevo/servicios/pool_timbre_session_guard.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';
import 'package:flygo_nuevo/servicios/taxista_pool_timbre_dedupe.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';

/// Timbre global del pool turístico mientras el taxista usa la app (aunque no esté en la pantalla del pool).
class TaxistaTurismoPoolTimbreListener extends StatefulWidget {
  const TaxistaTurismoPoolTimbreListener({super.key, required this.child});

  final Widget child;

  @override
  State<TaxistaTurismoPoolTimbreListener> createState() =>
      _TaxistaTurismoPoolTimbreListenerState();
}

class _TaxistaTurismoPoolTimbreListenerState
    extends State<TaxistaTurismoPoolTimbreListener> with WidgetsBindingObserver {
  static const List<String> _kEstadosPend = <String>[
    EstadosViaje.pendiente,
    'pendiente_pago',
    'pendientePago',
    'pendiente_admin',
  ];

  StreamSubscription<fs.DocumentSnapshot<Map<String, dynamic>>>? _choferSub;
  StreamSubscription<fs.QuerySnapshot<Map<String, dynamic>>>? _subAhora;
  StreamSubscription<fs.QuerySnapshot<Map<String, dynamic>>>? _subProg;

  bool _turismoAprobado = false;
  bool _appEnForeground = true;
  bool _ignorarPrimeraAhora = true;
  bool _ignorarPrimeraProg = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _arrancar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _choferSub?.cancel();
    _subAhora?.cancel();
    _subProg?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appEnForeground = state == AppLifecycleState.resumed;
  }

  void _arrancar() {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    _choferSub?.cancel();
    _choferSub = fs.FirebaseFirestore.instance
        .collection('choferes_turismo')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      final String estado =
          (snap.data()?['estado'] ?? '').toString().trim().toLowerCase();
      final bool aprobado = estado == 'aprobado' || estado == 'activo';
      if (aprobado == _turismoAprobado) return;
      _turismoAprobado = aprobado;
      if (aprobado) {
        _arrancarQueries();
      } else {
        _subAhora?.cancel();
        _subProg?.cancel();
        _subAhora = null;
        _subProg = null;
      }
    });
  }

  void _arrancarQueries() {
    _subAhora?.cancel();
    _subProg?.cancel();
    _ignorarPrimeraAhora = true;
    _ignorarPrimeraProg = true;

    final fs.Query<Map<String, dynamic>> qAhora = fs.FirebaseFirestore.instance
        .collection('viajes')
        .where('estado', whereIn: _kEstadosPend)
        .where('uidTaxista', isEqualTo: '')
        .where('esAhora', isEqualTo: true)
        .where('publishAt', isLessThanOrEqualTo: fs.Timestamp.now())
        .where('acceptAfter', isLessThanOrEqualTo: fs.Timestamp.now())
        .where(
          'canalAsignacion',
          isEqualTo: AsignacionTurismoRepo.canalTurismoPool,
        )
        .orderBy('publishAt', descending: false);

    final fs.Query<Map<String, dynamic>> qProg = fs.FirebaseFirestore.instance
        .collection('viajes')
        .where('estado', whereIn: _kEstadosPend)
        .where('uidTaxista', isEqualTo: '')
        .where('esAhora', isEqualTo: false)
        .where('publishAt', isLessThanOrEqualTo: fs.Timestamp.now())
        .where('acceptAfter', isLessThanOrEqualTo: fs.Timestamp.now())
        .where(
          'canalAsignacion',
          isEqualTo: AsignacionTurismoRepo.canalTurismoPool,
        )
        .orderBy('fechaHora', descending: false);

    _subAhora = qAhora.limit(120).snapshots().listen((snap) async {
      if (!_appEnForeground || !_turismoAprobado) return;
      if (_ignorarPrimeraAhora) {
        _ignorarPrimeraAhora = false;
        return;
      }
      await _procesarSnap(snap);
    });

    _subProg = qProg.limit(200).snapshots().listen((snap) async {
      if (!_appEnForeground || !_turismoAprobado) return;
      if (_ignorarPrimeraProg) {
        _ignorarPrimeraProg = false;
        return;
      }
      await _procesarSnap(snap);
    });
  }

  Future<void> _procesarSnap(fs.QuerySnapshot<Map<String, dynamic>> snap) async {
    if (!PoolTimbreSessionGuard.timbrePoolPermitido) return;
    final String myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (myUid.isEmpty) return;
    if (!await RolesService.getDisponibilidad(myUid)) return;

    final List<fs.QueryDocumentSnapshot<Map<String, dynamic>>> nuevas =
        <fs.QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in snap.docs) {
      final data = d.data();
      if (!ViajePoolTaxistaGate.esTurismoPoolTomable(data)) continue;
      final String clave = 'turismo_${d.id}';
      if (!TaxistaPoolTimbreDedupe.instance.marcarSiNuevo(clave)) continue;
      nuevas.add(d);
    }
    if (nuevas.isEmpty) return;

    await NotificationService.I.playPoolOfferSoundInApp();
    for (final d in nuevas) {
      final data = d.data();
      await NotificationService.I.vibratePoolOfferInApp();
      if (_viajeTienePrecioReal(data)) {
        await NotificationService.I.notifyNuevoViaje(
          viajeId: d.id,
          titulo: 'Nuevo viaje turístico',
          cuerpo:
              '${(data['origen'] ?? 'Origen')} → ${(data['destino'] ?? 'Destino')}',
          skipSound: true,
        );
      }
    }
  }

  bool _viajeTienePrecioReal(Map<String, dynamic> data) {
    final dynamic pc = data['precio_cents'];
    if (pc is num && pc > 0) return true;
    double n(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().trim().replaceAll(',', '.')) ?? 0;
    }

    return n(data['precio']) > 0.009 ||
        n(data['precioFinal'] ?? data['total']) > 0.009;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
