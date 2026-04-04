// lib/widgets/viajes_cercanos_taxista.dart
// Capa independiente: escucha pendientes / encolar sin reconstruir la pantalla de viaje en curso.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flygo_nuevo/servicios/notification_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';

/// Estado compartido entre el botón del AppBar y el overlay (solo este árbol escucha [notifyListeners]).
class ViajesCercanosTaxistaController extends ChangeNotifier {
  int _pendingCount = 0;
  bool _panelOpen = false;
  String? _encoladoId;

  int get pendingCount => _pendingCount;
  bool get panelOpen => _panelOpen;
  String? get encoladoId => _encoladoId;

  void setPendingCount(int n) {
    if (_pendingCount == n) return;
    _pendingCount = n;
    notifyListeners();
  }

  void togglePanel() {
    _panelOpen = !_panelOpen;
    notifyListeners();
  }

  void hidePanel() {
    if (!_panelOpen) return;
    _panelOpen = false;
    notifyListeners();
  }

  void setEncoladoId(String? id) {
    if (_encoladoId == id) return;
    _encoladoId = id;
    notifyListeners();
  }

  /// Cierra panel y contador local; no borra [encoladoId] (sigue en Firestore / UI del botón ENCOLAR).
  void resetListeningUi() {
    _pendingCount = 0;
    _panelOpen = false;
    notifyListeners();
  }
}

/// [escuchaActiva]: true solo en estados donde aplica buscar pendientes (p. ej. a bordo / en curso).
/// El padre actualiza el [ValueNotifier] sin setState.
class ViajesCercanosTaxistaLayer extends StatefulWidget {
  const ViajesCercanosTaxistaLayer({
    super.key,
    required this.controller,
    required this.escuchaActiva,
    this.taxistaUbicacion,
  });

  final ViajesCercanosTaxistaController controller;
  final ValueNotifier<bool> escuchaActiva;

  /// Posición actual del taxista; si viene informada, la lista se ordena por distancia al punto de recogida.
  final ValueNotifier<(double, double)?>? taxistaUbicacion;

  @override
  State<ViajesCercanosTaxistaLayer> createState() => _ViajesCercanosTaxistaLayerState();
}

class _ViajesCercanosTaxistaLayerState extends State<ViajesCercanosTaxistaLayer> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _rawDocs = [];
  /// Total de pendientes en el último snapshot (tras ordenar), puede ser mayor que [_docs].
  int _pendientesTotales = 0;
  final Set<String> _prevCercanosIds = <String>{};
  bool _cercanosPrimeraEmision = true;

  static const int _kQueryLimit = 40;
  static const int _kMostrarMax = 12;

  @override
  void initState() {
    super.initState();
    widget.escuchaActiva.addListener(_onEscuchaChanged);
    widget.taxistaUbicacion?.addListener(_onTaxistaPosChanged);
    _syncSubscription(widget.escuchaActiva.value);
  }

  @override
  void didUpdateWidget(covariant ViajesCercanosTaxistaLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.escuchaActiva != widget.escuchaActiva) {
      oldWidget.escuchaActiva.removeListener(_onEscuchaChanged);
      widget.escuchaActiva.addListener(_onEscuchaChanged);
      _syncSubscription(widget.escuchaActiva.value);
    }
    if (!identical(oldWidget.taxistaUbicacion, widget.taxistaUbicacion)) {
      oldWidget.taxistaUbicacion?.removeListener(_onTaxistaPosChanged);
      widget.taxistaUbicacion?.addListener(_onTaxistaPosChanged);
      _applySortAndSetState();
    }
  }

  void _onTaxistaPosChanged() {
    _applySortAndSetState();
  }

  void _onEscuchaChanged() {
    _syncSubscription(widget.escuchaActiva.value);
  }

  void _syncSubscription(bool activo) {
    if (activo) {
      _startSub();
    } else {
      _stopSub();
      if (mounted) {
        setState(() {
          _docs = [];
          _rawDocs = [];
          _pendientesTotales = 0;
        });
      }
      widget.controller.resetListeningUi();
    }
  }

  double _distanciaMetrosPickup(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    (double, double) taxista,
  ) {
    final Map<String, dynamic> m = doc.data();
    final double? la = (m['latCliente'] is num) ? (m['latCliente'] as num).toDouble() : null;
    final double? lo = (m['lonCliente'] is num) ? (m['lonCliente'] as num).toDouble() : null;
    if (la == null || lo == null) return double.infinity;
    if (!la.isFinite || !lo.isFinite) return double.infinity;
    return Geolocator.distanceBetween(taxista.$1, taxista.$2, la, lo);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _ordenarPorCercania(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    (double, double)? taxista,
  ) {
    if (taxista == null) return List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> copy =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    copy.sort((QueryDocumentSnapshot<Map<String, dynamic>> a, QueryDocumentSnapshot<Map<String, dynamic>> b) {
      return _distanciaMetrosPickup(a, taxista).compareTo(_distanciaMetrosPickup(b, taxista));
    });
    return copy;
  }

  void _applySortAndSetState() {
    if (!mounted) return;
    final (double, double)? t = widget.taxistaUbicacion?.value;
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> sorted = _ordenarPorCercania(_rawDocs, t);
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> top =
        sorted.take(_kMostrarMax).toList(growable: false);
    setState(() {
      _docs = top;
      _pendientesTotales = sorted.length;
    });
    widget.controller.setPendingCount(sorted.length);
  }

  void _startSub() {
    if (_sub != null) return;
    _cercanosPrimeraEmision = true;
    _prevCercanosIds.clear();
    _rawDocs = [];
    _sub = FirebaseFirestore.instance
        .collection('viajes')
        .where('estado', isEqualTo: 'pendiente')
        .where('completado', isEqualTo: false)
        .limit(_kQueryLimit)
        .snapshots()
        .listen((QuerySnapshot<Map<String, dynamic>> snapshot) {
      if (!mounted) return;
      final Set<String> nowIds = snapshot.docs.map((QueryDocumentSnapshot<Map<String, dynamic>> d) => d.id).toSet();
      _rawDocs = snapshot.docs.toList();

      if (_cercanosPrimeraEmision) {
        _cercanosPrimeraEmision = false;
        _prevCercanosIds
          ..clear()
          ..addAll(nowIds);
        _applySortAndSetState();
        return;
      }

      for (final String id in nowIds.difference(_prevCercanosIds)) {
        final QueryDocumentSnapshot<Map<String, dynamic>> doc =
            snapshot.docs.firstWhere((QueryDocumentSnapshot<Map<String, dynamic>> d) => d.id == id);
        final Map<String, dynamic> data = doc.data();
        unawaited(NotificationService.I.notifyNuevoViaje(
          viajeId: id,
          titulo: 'Nuevo viaje pendiente',
          cuerpo: '${(data['origen'] ?? 'Origen')} → ${(data['destino'] ?? 'Destino')}',
        ));
      }

      _prevCercanosIds
        ..clear()
        ..addAll(nowIds);
      _applySortAndSetState();
    }, onError: (Object error, StackTrace stackTrace) {
      // Importante: no dejar que errores de esta escucha rompan la UI principal
      // de "Viaje en curso" (se mostraba ErrorWidget global en la parte superior).
      if (!mounted) return;
      _stopSub();
      setState(() {
        _docs = [];
        _rawDocs = [];
        _pendientesTotales = 0;
      });
      widget.controller.resetListeningUi();
    });
  }

  void _stopSub() {
    _sub?.cancel();
    _sub = null;
    _cercanosPrimeraEmision = true;
    _prevCercanosIds.clear();
    _rawDocs = [];
    _pendientesTotales = 0;
  }

  @override
  void dispose() {
    widget.escuchaActiva.removeListener(_onEscuchaChanged);
    widget.taxistaUbicacion?.removeListener(_onTaxistaPosChanged);
    _stopSub();
    super.dispose();
  }

  Future<void> _encolar(String viajeId) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await ViajesRepo.reservarComoSiguiente(viajeId: viajeId, uidTaxista: uid);
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set(
        {
          'viajeEncoladoId': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      widget.controller.setEncoladoId(viajeId);
      widget.controller.hidePanel();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '✅ Próximo viaje reservado. Al terminar el actual pasarás directo a la recogida.',
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.orange),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo reservar: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.panelOpen || _docs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 20,
      right: 16,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(20),
        color: Colors.black87,
        child: Container(
          width: 300,
          constraints: const BoxConstraints(maxHeight: 400),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.taxi_alert, color: Colors.greenAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Reservar siguiente',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            widget.taxistaUbicacion?.value != null
                                ? 'Ordenados por cercanía al pickup · se activan al terminar el actual'
                                : 'Activa GPS para ordenar por distancia',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    if (_pendientesTotales > _kMostrarMax) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message:
                            'Hay más pendientes en la consulta; aquí ves los $_kMostrarMax más cercanos (hasta $_kQueryLimit en la búsqueda).',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.45)),
                          ),
                          child: Text(
                            '+${_pendientesTotales - _kMostrarMax}',
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _docs.length,
                  itemBuilder: (BuildContext context, int index) {
                    final QueryDocumentSnapshot<Map<String, dynamic>> doc = _docs[index];
                    final Map<String, dynamic> data = doc.data();
                    final Object? origen = data['origen'] ?? 'Origen';
                    final Object? destino = data['destino'] ?? 'Destino';
                    final dynamic precioRaw = data['precio'];
                    final double precioNum = precioRaw is num
                        ? precioRaw.toDouble()
                        : (double.tryParse('${precioRaw ?? 0}') ?? 0.0);
                    final String precio = FormatosMoneda.rd(precioNum);
                    final (double, double)? t = widget.taxistaUbicacion?.value;
                    String? distTxt;
                    if (t != null) {
                      final double m = _distanciaMetrosPickup(doc, t);
                      if (m.isFinite) {
                        distTxt = m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
                      }
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$origen',
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '→ $destino',
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  precio,
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (distTxt != null)
                                  Text(
                                    'A recogida: $distTxt',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.45),
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ListenableBuilder(
                            listenable: widget.controller,
                            builder: (BuildContext context, Widget? _) {
                              final bool encolado = widget.controller.encoladoId == doc.id;
                              return ElevatedButton(
                                onPressed: () => _encolar(doc.id),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.greenAccent,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  minimumSize: const Size(70, 32),
                                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                child: encolado ? const Text('✓ LISTO') : const Text('SIGUIENTE'),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (_pendientesTotales > _docs.length)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Text(
                    '+${_pendientesTotales - _docs.length} más no listados · consulta hasta $_kQueryLimit',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10),
                  ),
                ),
              TextButton(
                onPressed: () => widget.controller.hidePanel(),
                child: const Text('Ocultar', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón de AppBar: solo reconstruye este icono cuando cambia el controller o la escucha.
class ViajesCercanosTaxistaAppBarAction extends StatelessWidget {
  const ViajesCercanosTaxistaAppBarAction({
    super.key,
    required this.controller,
    required this.escuchaActiva,
  });

  final ViajesCercanosTaxistaController controller;
  final ValueNotifier<bool> escuchaActiva;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: escuchaActiva,
      builder: (BuildContext context, bool activo, Widget? _) {
        if (!activo) return const SizedBox.shrink();
        return ListenableBuilder(
          listenable: controller,
          builder: (BuildContext context, Widget? __) {
            return IconButton(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.taxi_alert, color: Colors.greenAccent),
                  if (controller.pendingCount > 0 && controller.panelOpen)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                        child: Text(
                          '${controller.pendingCount}',
                          style: const TextStyle(color: Colors.white, fontSize: 8),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              onPressed: () {
                if (controller.pendingCount == 0 && !controller.panelOpen) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No hay viajes pendientes cercanos en este momento.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                controller.togglePanel();
              },
            );
          },
        );
      },
    );
  }
}
