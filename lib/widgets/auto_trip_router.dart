import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_en_curso_cliente.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';

/// ===== Estados que usaremos =====
/// Taxista: ok
const _estadosTaxista = <String>[
  'asignado',
  'aceptado',
  'en_camino_pickup',
  'enCaminoPickup',
  'a_bordo',
  'en_curso',
  'enCurso',
];

/// Cliente:
/// IMPORTANTE: NO incluimos 'pendiente' porque eso hace que viajes programados
/// (que suelen estar "pendiente") te manden a ViajeEnCurso.
const _estadosClienteActivos = <String>[
  'pendiente',
  'asignado',
  'aceptado',
  'en_camino_pickup',
  'enCaminoPickup',
  'a_bordo',
  'en_curso',
  'enCurso',
];

bool _estadoClienteEsActivo(String estado) {
  final e = estado.trim();
  return _estadosClienteActivos.contains(e);
}

bool _clienteDebeEntrarViajeEnCurso(Map<String, dynamic> v) {
  final String estado = (v['estado'] ?? '').toString().trim();
  if (_estadoClienteEsActivo(estado) && estado != 'pendiente') return true;

  // Para UX tipo InDrive: si el viaje acaba de crearse para "ahora"
  // y quedó en pendiente mientras toma conductor, igual entramos al seguimiento.
  final bool esPendiente = estado == 'pendiente';
  if (!esPendiente) return false;

  final bool programado = v['programado'] == true;
  final bool esAhora = v['esAhora'] == true;
  return !programado || esAhora;
}

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

    await _sub?.cancel();
    _sub = qFinal.snapshots().listen((snap) async {
      if (!mounted || _navegando) return;
      if (snap.docs.isEmpty) return;
      final v = snap.docs.first.data();
      if (ViajePoolTaxistaGate.esViajeEspejoBolaParaFlujo(v)) return;
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

/// ===== CLIENTE =====
/// 1) Escucha usuarios/{uid}.siguienteViajeId para navegar INMEDIATO tras crear.
/// 2) Respaldo: query de viaje activo por estado para el cliente.
/// Navega a ViajeEnCursoCliente vía pushReplacement para evitar apilar pantallas.
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

    final userRef =
        FirebaseFirestore.instance.collection('usuarios').doc(u.uid);

    // (1) Navegación pos-creación: siguienteViajeId
    // FIX: Solo navega si el viaje existe Y está en estado activo real (no "pendiente").
    await _subUser?.cancel();
    _subUser = userRef.snapshots().listen((snap) async {
      if (!mounted || _navegando) return;

      final data = snap.data();
      final String siguiente =
          (data?['siguienteViajeId'] ?? '').toString().trim();
      if (siguiente.isEmpty) return;

      try {
        final vref =
            FirebaseFirestore.instance.collection('viajes').doc(siguiente);
        final vsnap = await vref.get();
        if (!vsnap.exists) return;

        final v = vsnap.data() as Map<String, dynamic>;
        if (ViajePoolTaxistaGate.esViajeEspejoBolaParaFlujo(v)) return;
        if (_clienteDebeEntrarViajeEnCurso(v)) {
          _goOnce(() async {
            await Navigator.of(context, rootNavigator: true)
                .pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const ViajeEnCursoCliente()),
              (route) => false,
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
        .where('estado', whereIn: _estadosClienteActivos)
        .orderBy('updatedAt', descending: true)
        .limit(1);

    final qFallback = FirebaseFirestore.instance
        .collection('viajes')
        .where('uidCliente', isEqualTo: u.uid)
        .where('estado', whereIn: _estadosClienteActivos)
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

    await _subActivos?.cancel();
    _subActivos = qFinal.snapshots().listen((snap) async {
      if (!mounted || _navegando) return;
      if (snap.docs.isEmpty) return;
      final v = snap.docs.first.data();
      if (ViajePoolTaxistaGate.esViajeEspejoBolaParaFlujo(v)) return;
      if (!_clienteDebeEntrarViajeEnCurso(v)) return;
      _goOnce(() async {
        await Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ViajeEnCursoCliente()),
          (route) => false,
        );
      });
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
