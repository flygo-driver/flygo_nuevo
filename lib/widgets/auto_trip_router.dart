import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_en_curso_cliente.dart';

/// ===== Estados que usaremos =====
const _estadosTaxista = <String>[
  'asignado',
  'aceptado',
  'en_camino_pickup',
  'enCaminoPickup',
  'a_bordo',
  'en_curso',
  'enCurso',
];

const _estadosCliente = <String>[
  'pendiente',
  'asignado',
  'aceptado',
  'en_camino_pickup',
  'enCaminoPickup',
  'a_bordo',
  'en_curso',
  'enCurso',
];

/// ===== TAXISTA =====
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

    _sub?.cancel();
    _sub = qFinal.snapshots().listen((snap) async {
      if (!mounted || _navegando) return;
      if (snap.docs.isNotEmpty) {
        _goOnce(() async {
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ViajeEnCursoTaxista()),
          );
        });
      }
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

/// ===== CLIENTE =====
/// 1) Escucha usuarios/{uid}.siguienteViajeId para navegar INMEDIATO tras crear.
/// 2) Respaldo: query de viaje activo por estado para el cliente.
/// Navega a /viaje_en_curso_cliente vía pushReplacement para evitar apilar pantallas.
class ClienteTripRouter extends StatefulWidget {
  final Widget child;
  const ClienteTripRouter({super.key, required this.child});
  @override
  State<ClienteTripRouter> createState() => _ClienteTripRouterState();
}

class _ClienteTripRouterState extends State<ClienteTripRouter> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subUser;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subActivos;
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

    final userRef = FirebaseFirestore.instance.collection('usuarios').doc(u.uid);

    // (1) Fallback inmediato pos-creación/promoción: siguienteViajeId
    _subUser?.cancel();
    _subUser = userRef.snapshots().listen((snap) async {
      if (!mounted || _navegando) return;
      final data = snap.data();
      final String siguiente = (data?['siguienteViajeId'] ?? '').toString();
      if (siguiente.isEmpty) return;

      // Confirmamos que el viaje existe (evita navegar por un id obsoleto)
      try {
        final vref = FirebaseFirestore.instance.collection('viajes').doc(siguiente);
        final vsnap = await vref.get();
        if (vsnap.exists) {
          _goOnce(() async {
            await Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const ViajeEnCursoCliente()),
            );
          });
        }
      } catch (_) {
        // ignora errores transitorios
      }
    });

    // (2) Respaldo: query por estados activos + orden (con fallback si falta índice)
    final qPreferida = FirebaseFirestore.instance
        .collection('viajes')
        .where('uidCliente', isEqualTo: u.uid)
        .where('estado', whereIn: _estadosCliente)
        .orderBy('updatedAt', descending: true)
        .limit(1);

    final qFallback = FirebaseFirestore.instance
        .collection('viajes')
        .where('uidCliente', isEqualTo: u.uid)
        .where('estado', whereIn: _estadosCliente)
        .limit(1);

    Query<Map<String, dynamic>> qFinal = qPreferida;

    try {
      await qPreferida.limit(1).get(const GetOptions(source: Source.server));
    } on FirebaseException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      if (e.code == 'failed-precondition' || msg.contains('index')) {
        qFinal = qFallback;
      }
    } catch (_) {}

    _subActivos?.cancel();
    _subActivos = qFinal.snapshots().listen((snap) async {
      if (!mounted || _navegando) return;
      if (snap.docs.isNotEmpty) {
        _goOnce(() async {
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ViajeEnCursoCliente()),
          );
        });
      }
    }, onError: (_) {
      // Si falta índice o hay error, no rompemos la UI
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
    _subUser?.cancel();
    _subActivos?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
