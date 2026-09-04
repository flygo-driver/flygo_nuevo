import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';

/// Estados operativos del taxista para auto-navegación al viaje en curso.
const _estadosTaxista = <String>[
  'asignado',
  'aceptado',
  'en_camino_pickup',
  'enCaminoPickup',
  'a_bordo',
  'en_curso',
  'enCurso',
];

/// Navegación automática del taxista hacia [ViajeEnCursoTaxista].
///
/// El cliente usa [ClienteShell] + overlay ([NavigationService]); no montar
/// un router paralelo que compita con `pushAndRemoveUntil`.
class TaxistaTripRouter extends StatefulWidget {
  final Widget child;
  const TaxistaTripRouter({super.key, required this.child});

  @override
  State<TaxistaTripRouter> createState() => _TaxistaTripRouterState();
}

class _TaxistaTripRouterState extends State<TaxistaTripRouter> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  bool _navegando = false;
  DateTime _ultimaAccion = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _arrancar();
  }

  Future<void> _arrancar() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    // Query “preferida” (puede requerir índice)
    final qPreferida = FirebaseFirestore.instance
        .collection('viajes')
        .where('uidTaxista', isEqualTo: u.uid)
        .where('activo', isEqualTo: true)
        .where('estado', whereIn: _estadosTaxista)
        .orderBy('updatedAt', descending: true)
        .limit(1);

    // Fallback sin orderBy (casi nunca requiere índice)
    final qFallback = FirebaseFirestore.instance
        .collection('viajes')
        .where('uidTaxista', isEqualTo: u.uid)
        .where('activo', isEqualTo: true)
        .where('estado', whereIn: _estadosTaxista)
        .limit(1);

    Query<Map<String, dynamic>> qFinal = qPreferida;

    // Probamos índice una vez para decidir
    try {
      await qPreferida.limit(1).get(const GetOptions(source: Source.server));
    } on FirebaseException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      if (e.code == 'failed-precondition' || msg.contains('index')) {
        qFinal = qFallback;
      }
    } catch (_) {
      // si algo raro pasa, mantenemos la preferida
    }

    await _sub?.cancel();
    _sub = qFinal.snapshots().listen((snap) async {
      if (!mounted || _navegando) return;
      if (snap.docs.isEmpty) return;
      final v = snap.docs.first.data();
      if (v['taxistaLiberado'] == true) return;
      final estado = EstadosViaje.normalizar((v['estado'] ?? '').toString());
      if (estado == EstadosViaje.esperandoCodigoEncargado ||
          estado == EstadosViaje.codigoBloqueado ||
          estado == EstadosViaje.canceladoPorTiempo) {
        return;
      }
      if (ViajePoolTaxistaGate.debeUsarFlujoBolaPuebloEnLugarDeViajeEnCurso(v)) {
        return;
      }
      _goOnce(() async {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ViajeEnCursoTaxista()),
        );
      });
    }, onError: (_) {
      // Silencioso: no rompemos el home si hay error transitorio
    });
  }

  void _goOnce(Future<void> Function() nav) {
    if (_navegando) return;
    final now = DateTime.now();
    if (now.difference(_ultimaAccion).inMilliseconds < 500) return;
    _ultimaAccion = now;

    _navegando = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await nav();
      } finally {
        if (mounted) _navegando = false;
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
