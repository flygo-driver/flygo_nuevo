// lib/widgets/viajes_cercanos_taxista.dart
// Capa independiente: escucha pendientes / encolar sin reconstruir la pantalla de viaje en curso.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flygo_nuevo/servicios/notification_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/servicios/taxista_operacion_gate.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/formato_distancia_cercania.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/negocio_aliado_viaje_doc.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';
import 'package:flygo_nuevo/widgets/negocio_aliado_taxista_banner.dart';

/// Punto desde el que se mide distancia al pickup del candidato (GPS taxista o destino del viaje activo).
class ColaCercaniaReferencia {
  const ColaCercaniaReferencia({
    required this.lat,
    required this.lon,
    required this.porDestinoViajeActivo,
    this.destinoEtiqueta = '',
  });

  final double lat;
  final double lon;

  /// Si true, [lat]/[lon] es el destino (o parada actual) del viaje en curso, no el GPS.
  final bool porDestinoViajeActivo;

  /// Nombre del destino del viaje actual (solo informativo en UI).
  final String destinoEtiqueta;

  (double, double) get coords => (lat, lon);
}

/// Mejor candidato para encadenar (pickup más cercano al destino del viaje activo).
class ViajesCercanosTopCandidato {
  const ViajesCercanosTopCandidato({
    required this.viajeId,
    required this.origen,
    required this.destino,
    required this.metrosDesdeReferencia,
    required this.etiquetaDistancia,
    required this.precioTexto,
  });

  final String viajeId;
  final String origen;
  final String destino;
  final double metrosDesdeReferencia;
  final String etiquetaDistancia;
  final String precioTexto;

  bool get encadenamientoMuyCercano =>
      metrosDesdeReferencia.isFinite &&
      metrosDesdeReferencia <= _kEncadenarMismoOrigenMetros;

  static const double _kEncadenarMismoOrigenMetros = 1500;
}

/// Estado compartido entre el botón del AppBar y el overlay (solo este árbol escucha [notifyListeners]).
class ViajesCercanosTaxistaController extends ChangeNotifier {
  int _pendingCount = 0;
  bool _panelOpen = false;
  String? _encoladoId;
  ViajesCercanosTopCandidato? _topCandidato;
  bool _sugerenciaEncadenarOculta = false;

  /// Asignado por [ViajesCercanosTaxistaLayer] para encolar desde banner / sugerencia.
  Future<void> Function(String viajeId)? encolarViaje;

  int get pendingCount => _pendingCount;
  bool get panelOpen => _panelOpen;
  String? get encoladoId => _encoladoId;
  ViajesCercanosTopCandidato? get topCandidato => _topCandidato;
  bool get sugerenciaEncadenarOculta => _sugerenciaEncadenarOculta;

  void setPendingCount(int n) {
    if (_pendingCount == n) return;
    _pendingCount = n;
    notifyListeners();
  }

  void togglePanel() {
    _panelOpen = !_panelOpen;
    notifyListeners();
  }

  void openPanel() {
    if (_panelOpen) return;
    _panelOpen = true;
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

  void setTopCandidato(ViajesCercanosTopCandidato? c) {
    if (_topCandidato?.viajeId == c?.viajeId &&
        _topCandidato?.metrosDesdeReferencia == c?.metrosDesdeReferencia) {
      return;
    }
    _topCandidato = c;
    notifyListeners();
  }

  void ocultarSugerenciaEncadenar() {
    if (_sugerenciaEncadenarOculta) return;
    _sugerenciaEncadenarOculta = true;
    notifyListeners();
  }

  void resetSugerenciaEncadenar() {
    if (!_sugerenciaEncadenarOculta) return;
    _sugerenciaEncadenarOculta = false;
    notifyListeners();
  }

  /// Cierra panel y contador local; no borra [encoladoId] (sigue en Firestore / UI del botón ENCOLAR).
  void resetListeningUi() {
    _pendingCount = 0;
    _panelOpen = false;
    _topCandidato = null;
    _sugerenciaEncadenarOculta = false;
    notifyListeners();
  }
}

/// [escuchaActiva]: true mientras el taxista tiene un viaje activo (aceptado…en curso) y puede reservar el siguiente.
/// El padre actualiza el [ValueNotifier] sin setState.
class ViajesCercanosTaxistaLayer extends StatefulWidget {
  const ViajesCercanosTaxistaLayer({
    super.key,
    required this.controller,
    required this.escuchaActiva,
    this.referenciaOrdenCola,
  });

  final ViajesCercanosTaxistaController controller;
  final ValueNotifier<bool> escuchaActiva;

  /// Punto de referencia para ordenar candidatos (taxista o destino del viaje activo).
  final ValueNotifier<ColaCercaniaReferencia?>? referenciaOrdenCola;

  @override
  State<ViajesCercanosTaxistaLayer> createState() =>
      _ViajesCercanosTaxistaLayerState();
}

class _ViajesCercanosTaxistaLayerState
    extends State<ViajesCercanosTaxistaLayer> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _rawDocs = [];

  /// Total de pendientes en el último snapshot (tras ordenar), puede ser mayor que [_docs].
  int _pendientesTotales = 0;
  final Set<String> _prevCercanosIds = <String>{};
  bool _cercanosPrimeraEmision = true;
  String _poolModoConductor = TaxistaPoolModoConductor.vehiculo;

  static const int _kQueryLimit = 100;
  static const int _kMostrarMax = 15;

  /// Mismos estados que [ViajesRepo.reservarComoSiguiente] admite (sin taxista asignado en documento).
  static const List<String> _kEstadosReservablesSiguiente = <String>[
    EstadosViaje.pendiente,
    EstadosViaje.pendientePago,
    'pendiente_admin',
  ];

  static bool _docSinTaxistaAsignado(Map<String, dynamic> m) {
    final String uid = (m['uidTaxista'] ?? '').toString().trim();
    return uid.isEmpty;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.encolarViaje = _encolar;
    widget.escuchaActiva.addListener(_onEscuchaChanged);
    widget.referenciaOrdenCola?.addListener(_onReferenciaOrdenChanged);
    unawaited(_cargarPoolModoConductor());
    _syncSubscription(widget.escuchaActiva.value);
  }

  Future<void> _cargarPoolModoConductor() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      if (!mounted) return;
      final String modo = ViajePoolTaxistaGate.poolModoConductorDesdeUsuario(
        snap.data(),
      );
      if (_poolModoConductor != modo) {
        setState(() => _poolModoConductor = modo);
        _applySortAndSetState();
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant ViajesCercanosTaxistaLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.escuchaActiva != widget.escuchaActiva) {
      oldWidget.escuchaActiva.removeListener(_onEscuchaChanged);
      widget.escuchaActiva.addListener(_onEscuchaChanged);
      _syncSubscription(widget.escuchaActiva.value);
    }
    if (!identical(oldWidget.referenciaOrdenCola, widget.referenciaOrdenCola)) {
      oldWidget.referenciaOrdenCola?.removeListener(_onReferenciaOrdenChanged);
      widget.referenciaOrdenCola?.addListener(_onReferenciaOrdenChanged);
      _applySortAndSetState();
    }
  }

  void _onReferenciaOrdenChanged() {
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
    (double, double) referencia,
  ) {
    final Map<String, dynamic> m = doc.data();
    final double? la =
        (m['latCliente'] is num) ? (m['latCliente'] as num).toDouble() : null;
    final double? lo =
        (m['lonCliente'] is num) ? (m['lonCliente'] as num).toDouble() : null;
    if (la == null || lo == null) return double.infinity;
    if (!la.isFinite || !lo.isFinite) return double.infinity;
    return Geolocator.distanceBetween(
        referencia.$1, referencia.$2, la, lo);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _ordenarPorCercania(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    ColaCercaniaReferencia? referencia,
  ) {
    if (referencia == null) {
      return List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    }
    final (double, double) coords = referencia.coords;
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> copy =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    copy.sort((QueryDocumentSnapshot<Map<String, dynamic>> a,
        QueryDocumentSnapshot<Map<String, dynamic>> b) {
      return _distanciaMetrosPickup(a, coords)
          .compareTo(_distanciaMetrosPickup(b, coords));
    });
    return copy;
  }

  void _applySortAndSetState() {
    if (!mounted) return;
    final ColaCercaniaReferencia? ref = widget.referenciaOrdenCola?.value;
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> sorted =
        _ordenarPorCercania(_rawDocs, ref);
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> top =
        sorted.take(_kMostrarMax).toList(growable: false);
    setState(() {
      _docs = top;
      _pendientesTotales = sorted.length;
    });
    widget.controller.setPendingCount(sorted.length);
    _publicarTopCandidato(sorted, ref);
  }

  void _publicarTopCandidato(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sorted,
    ColaCercaniaReferencia? ref,
  ) {
    if (sorted.isEmpty || ref == null) {
      widget.controller.setTopCandidato(null);
      return;
    }
    final QueryDocumentSnapshot<Map<String, dynamic>> doc = sorted.first;
    final Map<String, dynamic> data = doc.data();
    final double metros = _distanciaMetrosPickup(doc, ref.coords);
    if (!metros.isFinite) {
      widget.controller.setTopCandidato(null);
      return;
    }
    final dynamic precioRaw = data['precio'];
    final double precioNum = precioRaw is num
        ? precioRaw.toDouble()
        : (double.tryParse('${precioRaw ?? 0}') ?? 0.0);
    final String etiqueta = ref.porDestinoViajeActivo
        ? FormatoDistanciaCercania.pickupCercaDeDestinoActual(
            metros,
            destinoActual: ref.destinoEtiqueta,
          )
        : FormatoDistanciaCercania.pickupCercaDeTuPosicion(metros);
    widget.controller.setTopCandidato(
      ViajesCercanosTopCandidato(
        viajeId: doc.id,
        origen: (data['origen'] ?? 'Origen').toString(),
        destino: (data['destino'] ?? 'Destino').toString(),
        metrosDesdeReferencia: metros,
        etiquetaDistancia: etiqueta,
        precioTexto: FormatosMoneda.rd(precioNum),
      ),
    );
  }

  Future<void> _syncEncoladoDesdeUsuario() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      final String sig =
          (snap.data()?['siguienteViajeId'] ?? '').toString().trim();
      if (!mounted) return;
      widget.controller.setEncoladoId(sig.isEmpty ? null : sig);
    } catch (_) {}
  }

  void _startSub() {
    if (_sub != null) return;
    _cercanosPrimeraEmision = true;
    _prevCercanosIds.clear();
    _rawDocs = [];
    unawaited(_syncEncoladoDesdeUsuario());
    _sub = FirebaseFirestore.instance
        .collection('viajes')
        .where('estado', whereIn: _kEstadosReservablesSiguiente)
        .where('uidTaxista', isEqualTo: '')
        .where('completado', isEqualTo: false)
        .limit(_kQueryLimit)
        .snapshots()
        .listen((QuerySnapshot<Map<String, dynamic>> snapshot) {
      if (!mounted) return;
      final String? uid = FirebaseAuth.instance.currentUser?.uid;
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> filtrados =
          snapshot.docs
              .where((QueryDocumentSnapshot<Map<String, dynamic>> d) {
                final Map<String, dynamic> data = d.data();
                if (!_docSinTaxistaAsignado(data)) return false;
                if (uid == null || uid.isEmpty) return false;
                return ViajePoolTaxistaGate.viajeEncadenableComoSiguiente(
                  data,
                  uid,
                  poolModoConductor: _poolModoConductor,
                );
              })
              .toList(growable: false);
      final Set<String> nowIds = filtrados
          .map((QueryDocumentSnapshot<Map<String, dynamic>> d) => d.id)
          .toSet();
      _rawDocs = filtrados;

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
            filtrados.firstWhere(
                (QueryDocumentSnapshot<Map<String, dynamic>> d) => d.id == id);
        final Map<String, dynamic> data = doc.data();
        final String? uid = FirebaseAuth.instance.currentUser?.uid;
        final String clienteId = ViajesRepo.uidClienteDesdeDocViaje(data);
        if (uid != null && clienteId.isNotEmpty && clienteId == uid) {
          continue;
        }
        unawaited(NotificationService.I.notifyNuevoViaje(
          viajeId: id,
          titulo: 'Nuevo viaje pendiente',
          cuerpo:
              '${(data['origen'] ?? 'Origen')} → ${(data['destino'] ?? 'Destino')}',
        ));
      }

      _prevCercanosIds
        ..clear()
        ..addAll(nowIds);
      _applySortAndSetState();
    }, onError: (Object error, StackTrace stackTrace) {
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
    if (widget.controller.encolarViaje != null) {
      widget.controller.encolarViaje = null;
    }
    widget.escuchaActiva.removeListener(_onEscuchaChanged);
    widget.referenciaOrdenCola?.removeListener(_onReferenciaOrdenChanged);
    _stopSub();
    super.dispose();
  }

  Future<void> _encolar(String viajeId) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (widget.controller.encoladoId != null &&
        widget.controller.encoladoId != viajeId) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            taxistaMensajeReservarSiguienteFallido('ya-tiene-siguiente'),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    try {
      await ViajesRepo.reservarComoSiguiente(viajeId: viajeId, uidTaxista: uid);
      widget.controller.setEncoladoId(viajeId);
      widget.controller.hidePanel();
      widget.controller.ocultarSugerenciaEncadenar();
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
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            taxistaMensajeReservarSiguienteFallido(e.message ?? e.code),
          ),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            taxistaMensajeReservarSiguienteFallido('error'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _tituloPanel(ColaCercaniaReferencia? ref) {
    if (ref?.porDestinoViajeActivo == true) {
      return 'Siguientes cerca de tu destino';
    }
    return 'Viajes cerca de ti';
  }

  String _subtituloOrden(ColaCercaniaReferencia? ref) {
    if (ref == null) {
      return 'Activa GPS para ver pickups ordenados por distancia';
    }
    if (ref.porDestinoViajeActivo) {
      final String dest = ref.destinoEtiqueta.trim();
      if (dest.isNotEmpty) {
        return 'Después de dejar al cliente en $dest · el más conveniente arriba';
      }
      return 'Después de este viaje · pickups ordenados desde tu destino';
    }
    return 'Ordenados por cercanía a tu posición actual';
  }

  Color _accentModo(ColaCercaniaReferencia? ref) {
    if (ref?.porDestinoViajeActivo == true) {
      return const Color(0xFFFFB74D);
    }
    return Colors.greenAccent;
  }

  Future<void> _encolarMasCercano() async {
    if (_docs.isEmpty) return;
    await _encolar(_docs.first.id);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.panelOpen || _docs.isEmpty) {
      return const SizedBox.shrink();
    }

    final ColaCercaniaReferencia? ref = widget.referenciaOrdenCola?.value;
    final Color modoAccent = _accentModo(ref);
    final bool modoDestino = ref?.porDestinoViajeActivo == true;

    return Positioned(
      left: 12,
      right: 12,
      bottom: 16,
      child: Material(
        elevation: 16,
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF0B1220),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 500),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: modoAccent.withValues(alpha: 0.45),
              width: 1.2,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                const Color(0xFF0F1B2D),
                const Color(0xFF0B1220),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                decoration: BoxDecoration(
                  color: modoAccent.withValues(alpha: 0.1),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: modoAccent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            modoDestino
                                ? Icons.fork_right_rounded
                                : Icons.radar_rounded,
                            color: modoAccent,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _tituloPanel(ref),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _subtituloOrden(ref),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.62),
                                  fontSize: 11.5,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_pendientesTotales > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: modoAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: modoAccent.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Text(
                              '$_pendientesTotales',
                              style: TextStyle(
                                color: modoAccent,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        IconButton(
                          onPressed: () => widget.controller.hidePanel(),
                          icon: Icon(Icons.close_rounded,
                              color: Colors.white.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            modoDestino
                                ? Icons.info_outline_rounded
                                : Icons.my_location_rounded,
                            color: modoAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              modoDestino
                                  ? 'No es tu viaje actual. Son candidatos para cuando termines con el cliente de a bordo.'
                                  : 'Viajes pendientes cerca de tu ubicación. Podés reservar uno como siguiente.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 11.5,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_docs.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ListenableBuilder(
                        listenable: widget.controller,
                        builder: (context, _) {
                          final bool yaEncolado =
                              widget.controller.encoladoId != null;
                          return SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed:
                                  yaEncolado ? null : _encolarMasCercano,
                              icon: Icon(
                                yaEncolado
                                    ? Icons.check_circle_rounded
                                    : Icons.playlist_add_check_rounded,
                                size: 18,
                              ),
                              label: Text(
                                yaEncolado
                                    ? 'Ya tenés un siguiente reservado'
                                    : (modoDestino
                                        ? 'Encolar el más cercano a tu destino'
                                        : 'Encolar el más cercano a ti'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: modoAccent,
                                foregroundColor: Colors.black,
                                disabledBackgroundColor:
                                    Colors.white.withValues(alpha: 0.12),
                                disabledForegroundColor:
                                    Colors.white.withValues(alpha: 0.55),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  itemCount: _docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final QueryDocumentSnapshot<Map<String, dynamic>> doc =
                        _docs[index];
                    final Map<String, dynamic> data = doc.data();
                    final Object? origen = data['origen'] ?? 'Origen';
                    final Object? destino = data['destino'] ?? 'Destino';
                    final dynamic precioRaw = data['precio'];
                    final double precioNum = precioRaw is num
                        ? precioRaw.toDouble()
                        : (double.tryParse('${precioRaw ?? 0}') ?? 0.0);
                    final String precio = FormatosMoneda.rd(precioNum);

                    double? metros;
                    String? distLabel;
                    if (ref != null) {
                      metros = _distanciaMetrosPickup(doc, ref.coords);
                      if (metros.isFinite) {
                        distLabel = ref.porDestinoViajeActivo
                            ? FormatoDistanciaCercania.pickupCercaDeDestinoActual(
                                metros,
                                destinoActual: ref.destinoEtiqueta,
                              )
                            : FormatoDistanciaCercania.pickupCercaDeTuPosicion(
                                metros,
                              );
                      }
                    }

                    final int tier = metros != null && metros.isFinite
                        ? FormatoDistanciaCercania.tierCercania(metros)
                        : 0;
                    final bool esTop = index == 0;
                    final Color accent = tier >= 2
                        ? modoAccent
                        : tier >= 1
                            ? modoAccent.withValues(alpha: 0.85)
                            : Colors.white70;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: tier >= 2
                            ? modoAccent.withValues(alpha: 0.1)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: esTop
                              ? accent.withValues(alpha: 0.65)
                              : Colors.white.withValues(alpha: 0.08),
                          width: esTop ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '#${index + 1}',
                              style: TextStyle(
                                color: accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (distLabel != null)
                                  Row(
                                    children: [
                                      if (esTop)
                                        Container(
                                          margin:
                                              const EdgeInsets.only(right: 6),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: modoAccent
                                                .withValues(alpha: 0.22),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            modoDestino
                                                ? 'MEJOR SIGUIENTE'
                                                : 'MÁS CERCANO',
                                            style: TextStyle(
                                              color: modoAccent,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ),
                                      Expanded(
                                        child: Text(
                                          esTop && tier >= 1
                                              ? '⚡ $distLabel'
                                              : distLabel,
                                          style: TextStyle(
                                            color: accent,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  '$origen',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '→ $destino',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.72),
                                    fontSize: 12.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                if (NegocioAliadoViajeDoc.esReferidoQr(data))
                                  NegocioAliadoTaxistaBanner(
                                    viajeData: data,
                                    compacto: true,
                                  ),
                                Text(
                                  precio,
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ListenableBuilder(
                            listenable: widget.controller,
                            builder: (BuildContext context, Widget? _) {
                              final bool encolado =
                                  widget.controller.encoladoId == doc.id;
                              final bool bloqueadoOtro =
                                  widget.controller.encoladoId != null &&
                                      widget.controller.encoladoId != doc.id;
                              return FilledButton(
                                onPressed: bloqueadoOtro
                                    ? null
                                    : () => _encolar(doc.id),
                                style: FilledButton.styleFrom(
                                  backgroundColor: encolado
                                      ? Colors.white24
                                      : modoAccent,
                                  foregroundColor: encolado
                                      ? Colors.white
                                      : Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  encolado ? '✓ LISTO' : 'ENCOLAR',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    '+${_pendientesTotales - _docs.length} más en cola · mostrando los $_kMostrarMax más cercanos',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 10.5,
                    ),
                  ),
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
    this.referenciaOrdenCola,
  });

  final ViajesCercanosTaxistaController controller;
  final ValueNotifier<bool> escuchaActiva;
  final ValueNotifier<ColaCercaniaReferencia?>? referenciaOrdenCola;

  String _tooltip(ColaCercaniaReferencia? ref, int n) {
    if (ref?.porDestinoViajeActivo == true) {
      return n > 0
          ? '$n siguientes cerca de tu destino (no es el viaje actual)'
          : 'Buscar siguientes cerca de donde dejas al cliente';
    }
    return n > 0
        ? '$n viajes cerca de ti para encolar'
        : 'Buscar viajes cerca de ti';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: escuchaActiva,
      builder: (BuildContext context, bool activo, Widget? _) {
        if (!activo) return const SizedBox.shrink();
        if (referenciaOrdenCola == null) {
          return _buildIcon(context, null);
        }
        return ValueListenableBuilder<ColaCercaniaReferencia?>(
          valueListenable: referenciaOrdenCola!,
          builder: (context, ref, __) => _buildIcon(context, ref),
        );
      },
    );
  }

  Widget _buildIcon(BuildContext context, ColaCercaniaReferencia? ref) {
    final bool modoDestino = ref?.porDestinoViajeActivo == true;
    final Color accent =
        modoDestino ? const Color(0xFFFFB74D) : Colors.greenAccent;
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? __) {
        final int n = controller.pendingCount;
        return IconButton(
          tooltip: _tooltip(ref, n),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                modoDestino ? Icons.fork_right_rounded : Icons.radar_rounded,
                color: n > 0 ? accent : Colors.white70,
              ),
              if (n > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      n > 99 ? '99+' : '$n',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          onPressed: () {
            if (controller.pendingCount == 0 && !controller.panelOpen) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    modoDestino
                        ? 'No hay siguientes pendientes cerca de tu destino.'
                        : 'No hay viajes pendientes cerca de ti.',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
              return;
            }
            controller.togglePanel();
          },
        );
      },
    );
  }
}

/// Botón compacto para el panel del viaje en curso (sheet).
class ViajesCercanosTaxistaSheetButton extends StatelessWidget {
  const ViajesCercanosTaxistaSheetButton({
    super.key,
    required this.controller,
    required this.escuchaActiva,
    this.referenciaOrdenCola,
  });

  final ViajesCercanosTaxistaController controller;
  final ValueNotifier<bool> escuchaActiva;
  final ValueNotifier<ColaCercaniaReferencia?>? referenciaOrdenCola;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: escuchaActiva,
      builder: (BuildContext context, bool activo, Widget? _) {
        if (!activo) return const SizedBox.shrink();
        if (referenciaOrdenCola == null) {
          return _buildCard(context, null);
        }
        return ValueListenableBuilder<ColaCercaniaReferencia?>(
          valueListenable: referenciaOrdenCola!,
          builder: (context, ref, __) => _buildCard(context, ref),
        );
      },
    );
  }

  Widget _buildCard(BuildContext context, ColaCercaniaReferencia? ref) {
    final bool modoDestino = ref?.porDestinoViajeActivo == true;
    final Color accent =
        modoDestino ? const Color(0xFFFFB74D) : Colors.greenAccent;
    final String titulo = modoDestino
        ? 'Siguientes cerca de tu destino'
        : 'Viajes cerca de ti';
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? __) {
        final int n = controller.pendingCount;
        final String dest = (ref?.destinoEtiqueta ?? '').trim();
        final ViajesCercanosTopCandidato? top = controller.topCandidato;
        final bool sugerenciaLista = modoDestino &&
            top != null &&
            top.encadenamientoMuyCercano &&
            controller.encoladoId == null;
        return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (n == 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              modoDestino
                                  ? 'Sin siguientes pendientes cerca de donde dejas al cliente.'
                                  : 'Sin viajes pendientes cerca de tu ubicación.',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                        return;
                      }
                      controller.openPanel();
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            accent.withValues(alpha: 0.18),
                            accent.withValues(alpha: 0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            modoDestino
                                ? Icons.fork_right_rounded
                                : Icons.radar_rounded,
                            color: accent,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        titulo,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.white.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'NO ES EL VIAJE ACTUAL',
                                        style: TextStyle(
                                          color:
                                              Colors.white.withValues(alpha: 0.7),
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  sugerenciaLista
                                      ? '¡Hay uno en este mismo lugar! Tocá para encolar en 1 paso.'
                                      : (n > 0
                                          ? (modoDestino
                                              ? (dest.isNotEmpty
                                                  ? '$n candidatos · pickups cerca de $dest'
                                                  : '$n candidatos · ordenados desde tu destino')
                                              : '$n pendientes · más cercanos a tu GPS')
                                          : (modoDestino
                                              ? 'Buscando siguientes cerca de tu destino…'
                                              : 'Buscando pendientes cerca de ti…')),
                                  style: TextStyle(
                                    color: sugerenciaLista
                                        ? const Color(0xFFFFB74D)
                                        : Colors.white.withValues(alpha: 0.65),
                                    fontSize: 11.5,
                                    fontWeight: sugerenciaLista
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (n > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '$n',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          const SizedBox(width: 6),
                          Icon(Icons.chevron_right_rounded,
                              color: Colors.white.withValues(alpha: 0.6)),
                        ],
                      ),
                    ),
                  ),
                );
      },
    );
  }
}

/// Banner flotante al acercarse al destino: un toque encola el mejor siguiente.
class ViajesCercanosTaxistaEncadenarSugerencia extends StatefulWidget {
  const ViajesCercanosTaxistaEncadenarSugerencia({
    super.key,
    required this.controller,
    required this.escuchaActiva,
    required this.referenciaOrdenCola,
    required this.distanciaAlDestinoMetros,
  });

  final ViajesCercanosTaxistaController controller;
  final ValueNotifier<bool> escuchaActiva;
  final ValueNotifier<ColaCercaniaReferencia?> referenciaOrdenCola;
  final ValueNotifier<double?> distanciaAlDestinoMetros;

  static const double kMostrarCercaDestinoMetros = 3000;

  @override
  State<ViajesCercanosTaxistaEncadenarSugerencia> createState() =>
      _ViajesCercanosTaxistaEncadenarSugerenciaState();
}

class _ViajesCercanosTaxistaEncadenarSugerenciaState
    extends State<ViajesCercanosTaxistaEncadenarSugerencia> {
  bool _encolando = false;
  String? _ultimoHapticViajeId;

  bool _debeMostrar({
    required bool escucha,
    required ColaCercaniaReferencia? ref,
    required ViajesCercanosTopCandidato? top,
    required double? distDest,
    required bool oculta,
    required bool panelAbierto,
    required String? encoladoId,
  }) {
    if (!escucha || panelAbierto || oculta || encoladoId != null) return false;
    if (ref?.porDestinoViajeActivo != true || top == null) return false;
    if (top.encadenamientoMuyCercano) return true;
    if (distDest == null || !distDest.isFinite) return false;
    return distDest <= ViajesCercanosTaxistaEncadenarSugerencia.kMostrarCercaDestinoMetros;
  }

  Future<void> _onEncolar(String viajeId) async {
    if (_encolando) return;
    setState(() => _encolando = true);
    try {
      await widget.controller.encolarViaje?.call(viajeId);
    } finally {
      if (mounted) setState(() => _encolando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        widget.controller,
        widget.escuchaActiva,
        widget.referenciaOrdenCola,
        widget.distanciaAlDestinoMetros,
      ]),
      builder: (context, _) {
        final bool escucha = widget.escuchaActiva.value;
        final ColaCercaniaReferencia? ref = widget.referenciaOrdenCola.value;
        final ViajesCercanosTopCandidato? top = widget.controller.topCandidato;
        final double? distDest = widget.distanciaAlDestinoMetros.value;
        final bool visible = _debeMostrar(
          escucha: escucha,
          ref: ref,
          top: top,
          distDest: distDest,
          oculta: widget.controller.sugerenciaEncadenarOculta,
          panelAbierto: widget.controller.panelOpen,
          encoladoId: widget.controller.encoladoId,
        );
        if (!visible || top == null) {
          _ultimoHapticViajeId = null;
          return const SizedBox.shrink();
        }

        if (_ultimoHapticViajeId != top.viajeId) {
          _ultimoHapticViajeId = top.viajeId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            HapticFeedback.mediumImpact();
          });
        }

        final String destLabel = ref?.destinoEtiqueta.trim() ?? '';
        final String titulo = top.encadenamientoMuyCercano
            ? 'Siguiente en este mismo lugar'
            : 'Siguiente cerca de tu destino';
        final String subtitulo = top.encadenamientoMuyCercano
            ? (destLabel.isNotEmpty
                ? 'Pickup a ${top.etiquetaDistancia} de $destLabel · ${top.precioTexto}'
                : 'Pickup a ${top.etiquetaDistancia} · ${top.precioTexto}')
            : '${top.etiquetaDistancia} · ${top.origen} → ${top.destino} · ${top.precioTexto}';

        return Positioned(
          left: 12,
          right: 12,
          bottom: 108,
          child: Material(
            elevation: 18,
            borderRadius: BorderRadius.circular(20),
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0xFF1A1208),
                    Color(0xFF0F0A06),
                  ],
                ),
                border: Border.all(
                  color: const Color(0xFFFFB020).withValues(alpha: 0.65),
                  width: 1.4,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFFFFB020).withValues(alpha: 0.22),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFB020).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.fork_right_rounded,
                            color: Color(0xFFFFB020),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      titulo,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ),
                                  if (top.encadenamientoMuyCercano)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFB020),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'MEJOR SIGUIENTE',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                subtitulo,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontSize: 11.5,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: widget.controller.ocultarSugerenciaEncadenar,
                          icon: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withValues(alpha: 0.55),
                            size: 20,
                          ),
                          tooltip: 'Ocultar sugerencia',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: FilledButton(
                      onPressed: _encolando ? null : () => _onEncolar(top.viajeId),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFB020),
                        foregroundColor: Colors.black,
                        disabledBackgroundColor:
                            Colors.white.withValues(alpha: 0.12),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _encolando
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.black,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(Icons.playlist_add_check_rounded, size: 22),
                                SizedBox(width: 8),
                                Text(
                                  'ENCOLAR SIGUIENTE AQUÍ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
