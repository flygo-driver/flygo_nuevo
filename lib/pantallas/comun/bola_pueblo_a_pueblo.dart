import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flygo_nuevo/pantallas/cliente/bola_conductores_en_ruta_cliente.dart';
import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_actions.dart';
import 'package:flygo_nuevo/servicios/bola_pueblo_repo.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/utilidades/constante.dart' show etiquetaBolaAhorroUi;
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/navegacion/taxista_finanzas_nav.dart';
import 'package:flygo_nuevo/widgets/mapa_tiempo_real.dart';
import 'package:flygo_nuevo/widgets/rai_header_logo.dart';

class BolaPuebloAPuebloPage extends StatefulWidget {
  const BolaPuebloAPuebloPage({super.key});

  @override
  State<BolaPuebloAPuebloPage> createState() => _BolaPuebloAPuebloPageState();
}

class _BolaPuebloAPuebloPageState extends State<BolaPuebloAPuebloPage> {
  bool _guardando = false;

  final DraggableScrollableController _bolaBoardSheetCtrl =
      DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await BolaPuebloRepo.reconciliarSesionBolaAtascada();
      if (mounted) setState(() {});
    });
  }

  static const double _bolaSheetMinFrac = 0.22;
  static const double _bolaSheetMidFrac = 0.46;

  Future<void> _collapseBolaBoardSheet() async {
    if (!_bolaBoardSheetCtrl.isAttached) return;
    try {
      if (_bolaBoardSheetCtrl.size <= _bolaSheetMinFrac + 0.03) return;
      await _bolaBoardSheetCtrl.animateTo(
        _bolaSheetMinFrac,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  void _volverAtrasDesdeTablero({required bool esTaxista}) {
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    unawaited(
      NavigationService.salirModoViajeBola(
        context,
        esTaxista: esTaxista,
      ),
    );
  }

  Future<void> _restoreBolaBoardSheetToMid() async {
    if (!_bolaBoardSheetCtrl.isAttached) return;
    try {
      final current = _bolaBoardSheetCtrl.size;
      // Si ya está cerca de mitad o por encima, no forzar animación.
      if (current >= _bolaSheetMidFrac - 0.02) return;
      await _bolaBoardSheetCtrl.animateTo(
        _bolaSheetMidFrac,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  LatLng? _rutaOrigen;
  LatLng? _rutaDestino;
  List<LatLng>? _rutaPolyline;
  String _rutaOrigenNombre = '';
  String _rutaDestinoNombre = '';

  void _limpiarRutaMapa() {
    setState(() {
      _rutaOrigen = null;
      _rutaDestino = null;
      _rutaPolyline = null;
      _rutaOrigenNombre = '';
      _rutaDestinoNombre = '';
    });
  }

  void _abrirModoViajeBola(String bolaId) {
    unawaited(
      BolaPuebloDialogs.abrirModoViajeBolaPorId(
        context: context,
        bolaId: bolaId,
      ),
    );
  }

  @override
  void dispose() {
    _bolaBoardSheetCtrl.dispose();
    super.dispose();
  }

  static double? _coordNum(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v is num) return v.toDouble();
    return null;
  }

  Widget _tarjetaBolaDesdeDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> d, {
    required User user,
    required String nombre,
    required String rol,
  }) {
    final m = d.data();
    final oLa = _coordNum(m, 'origenLat');
    final oLo = _coordNum(m, 'origenLon');
    final dLa = _coordNum(m, 'destinoLat');
    final dLo = _coordNum(m, 'destinoLon');
    final origenTxt = (m['origen'] ?? '').toString();
    final destinoTxt = (m['destino'] ?? '').toString();
    if (oLa != null && oLo != null && dLa != null && dLo != null) {
      final oo = LatLng(oLa, oLo);
      final dd = LatLng(dLa, dLo);
      return BolaPuebloPublicacionCard(
        docId: d.id,
        data: m,
        user: user,
        nombre: nombre,
        rol: rol,
        onVerRutaEnMapa: () {
          setState(() {
            _rutaOrigen = oo;
            _rutaDestino = dd;
            _rutaPolyline = [oo, dd];
            _rutaOrigenNombre = origenTxt;
            _rutaDestinoNombre = destinoTxt;
          });
        },
        onAbrirModoViaje: _abrirModoViajeBola,
      );
    }
    return BolaPuebloPublicacionCard(
      docId: d.id,
      data: m,
      user: user,
      nombre: nombre,
      rol: rol,
      onAbrirModoViaje: _abrirModoViajeBola,
    );
  }

  Widget _bolaSeccionListaCliente(
    BolaPuebloColors col, {
    required String titulo,
    EdgeInsets padding = const EdgeInsets.fromLTRB(16, 14, 16, 6),
  }) {
    return Padding(
      padding: padding,
      child: BolaPuebloUi.sectionTitle(context, titulo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final cs = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: cs.surface,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Debes iniciar sesión',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.72),
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .snapshots(),
      builder: (context, userSnap) {
        final ud = userSnap.data?.data() ?? const <String, dynamic>{};
        final rol = (ud['rol'] ?? 'cliente').toString();
        final nombre = (ud['nombre'] ?? 'Usuario').toString();
        final bool esTaxista = rol == 'taxista' || rol == 'driver';
        final col = BolaPuebloColors.of(context);

        Widget appBarTitleRow() {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const RaiHeaderLogo(height: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  etiquetaBolaAhorroUi,
                  style: BolaPuebloUi.screenTitleBola(context),
                ),
              ),
            ],
          );
        }

        Widget mapaYTablero() {
          return Scaffold(
            backgroundColor: col.bgDeep,
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: col.appBarScrim,
              elevation: 0,
              foregroundColor: col.onSurface,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: col.onSurface),
                tooltip: 'Volver',
                onPressed: () => _volverAtrasDesdeTablero(esTaxista: esTaxista),
              ),
              actions: [
                if (_rutaPolyline != null)
                  IconButton(
                    tooltip: 'Quitar ruta del mapa',
                    icon: const Icon(Icons.layers_clear_rounded),
                    onPressed: _limpiarRutaMapa,
                  ),
                IconButton(
                  tooltip: esTaxista
                      ? 'Volver a recibir viajes'
                      : 'Volver al inicio',
                  icon: Icon(Icons.home_rounded, color: col.onSurface),
                  onPressed: () => unawaited(
                    esTaxista
                        ? NavigationService.salirVistaBolaTaxista(context)
                        : NavigationService.salirVistaBolaCliente(context),
                  ),
                ),
              ],
              title: appBarTitleRow(),
            ),
            body: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: MapaTiempoReal(
                    esCliente: !esTaxista,
                    esTaxista: esTaxista,
                    origen: _rutaOrigen,
                    destino: _rutaDestino,
                    origenNombre:
                        _rutaOrigenNombre.isEmpty ? null : _rutaOrigenNombre,
                    destinoNombre:
                        _rutaDestinoNombre.isEmpty ? null : _rutaDestinoNombre,
                    mostrarOrigen: _rutaOrigen != null,
                    mostrarDestino: _rutaDestino != null,
                    mostrarTaxista: false,
                    polylinePreviewPoints: _rutaPolyline,
                    onUserInteractWithMap: () =>
                        unawaited(_collapseBolaBoardSheet()),
                    onUserMapGestureEnd: () =>
                        unawaited(_restoreBolaBoardSheetToMid()),
                  ),
                ),
                DraggableScrollableSheet(
                  controller: _bolaBoardSheetCtrl,
                  initialChildSize: 0.4,
                  minChildSize: _bolaSheetMinFrac,
                  maxChildSize: 0.92,
                  builder: (context, scrollController) {
                    return Container(
                      decoration: BoxDecoration(
                        color: col.surface.withValues(alpha: 0.98),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(BolaPuebloUi.radiusSheet),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: col.isDark
                                ? Colors.black54
                                : Colors.black.withValues(alpha: 0.12),
                            blurRadius: 24,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: StreamBuilder<
                              QuerySnapshot<Map<String, dynamic>>>(
                        stream: BolaPuebloRepo.streamTablero(),
                        builder: (context, snap) {
                          final bottomPad = BolaPuebloUi.safeBottomInset(context);
                          final docsAll = snap.data?.docs ?? const [];
                          final Map<String, String>? bolaActivaCliente =
                              esTaxista || snap.data == null
                                  ? null
                                  : BolaPuebloRepo
                                      .bolaActivaClienteDesdeTablero(
                                      snap.data!,
                                      user.uid,
                                    );
                          final Map<String, String>? bolaActivaTaxista =
                              !esTaxista || snap.data == null
                                  ? null
                                  : BolaPuebloRepo
                                      .bolaActivaTaxistaDesdeTablero(
                                      snap.data!,
                                      user.uid,
                                    );
                          final docs = docsAll.where((d) {
                            return BolaPuebloRepo.visibleEnTableroParaUsuario(
                              d.data(),
                              user.uid,
                              bolaId: d.id,
                              rol: rol,
                            );
                          }).toList();
                          final bool taxistaPubAbierta = esTaxista &&
                              docsAll.any((d) {
                                final m = d.data();
                                return (m['createdByUid'] ?? '').toString() ==
                                        user.uid &&
                                    (m['estado'] ?? '').toString() == 'abierta';
                              });

                          final List<Widget> head = [
                            const SizedBox(height: 8),
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: col.dragHandle,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                              child: BolaPuebloUi.boardHeader(
                                context,
                                subtitle: esTaxista
                                    ? (bolaActivaTaxista != null
                                        ? 'Tenés un viaje activo.'
                                        : 'Publicá tu ruta o respondé pedidos.')
                                    : bolaActivaCliente != null
                                        ? 'Tenés un viaje activo.'
                                        : 'Elegí conductor o pedí el tuyo.',
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (!esTaxista)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    BolaClientePedirPedidoPanel(
                                      bolaActiva: bolaActivaCliente,
                                      uid: user.uid,
                                      rol: rol,
                                      nombre: nombre,
                                      guardando: _guardando,
                                      onBusy: (b) =>
                                          setState(() => _guardando = b),
                                      onContinuarBola: _abrirModoViajeBola,
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: BolaPuebloUi.secondaryTile(
                                            context: context,
                                            label: 'Conductores',
                                            icon: Icons.local_taxi_rounded,
                                            onPressed: () =>
                                                NavigationService.push(
                                              const BolaConductoresEnRutaClientePage(),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            if (esTaxista)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: BolaPuebloUi.bigAction(
                                  context: context,
                                  label: 'Voy para…',
                                  icon: Icons.route_rounded,
                                  onPressed: _guardando
                                      ? null
                                      : () => BolaPuebloDialogs.crearPublicacion(
                                            context: context,
                                            uid: user.uid,
                                            rol: rol,
                                            nombre: nombre,
                                            tipo: 'oferta',
                                            onBusy: (b) =>
                                                setState(() => _guardando = b),
                                          ),
                                ),
                              ),
                            if (taxistaPubAbierta)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        BolaPuebloUi.statusChip(
                                          context,
                                          label: 'Tu ruta en el tablero',
                                          color: BolaPuebloTheme.accent,
                                        ),
                                      ],
                                    ),
                                    const BolaBoardVolverInicioButton(
                                      esTaxista: true,
                                      compact: true,
                                      faseViaje: 'abierta',
                                    ),
                                  ],
                                ),
                              ),
                            if (esTaxista && bolaActivaTaxista != null)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: BolaClientePedirPedidoPanel(
                                  bolaActiva: bolaActivaTaxista,
                                  uid: user.uid,
                                  rol: rol,
                                  nombre: nombre,
                                  guardando: _guardando,
                                  onBusy: (b) =>
                                      setState(() => _guardando = b),
                                  onContinuarBola: _abrirModoViajeBola,
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'TABLERO EN VIVO',
                                  style: TextStyle(
                                    color: col.onMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ),
                            ),
                          ];

                          if (snap.connectionState == ConnectionState.waiting) {
                            return ListView(
                              controller: scrollController,
                              padding: EdgeInsets.only(bottom: bottomPad),
                              children: [
                                ...head,
                                const SizedBox(height: 48),
                                const Center(
                                  child: CircularProgressIndicator(
                                      color: BolaPuebloTheme.accent),
                                ),
                              ],
                            );
                          }

                          if (docs.isEmpty) {
                            final emptyMsg = esTaxista
                                ? 'Publicá «Voy para» o esperá pedidos.'
                                : bolaActivaCliente != null
                                    ? 'Tu viaje activo está abajo.'
                                    : 'Aún no hay publicaciones. Tocá «Pedir bola».';
                            return ListView(
                              controller: scrollController,
                              padding: EdgeInsets.only(bottom: bottomPad),
                              children: [
                                ...head,
                                BolaPuebloUi.emptyBoard(
                                  context,
                                  message: emptyMsg,
                                  icon: esTaxista
                                      ? Icons.local_taxi_outlined
                                      : Icons.edit_calendar_outlined,
                                ),
                              ],
                            );
                          }

                          if (esTaxista) {
                            return ListView.builder(
                              controller: scrollController,
                              padding: EdgeInsets.fromLTRB(
                                  16, 0, 16, bottomPad),
                              itemCount: head.length + docs.length,
                              itemBuilder: (context, i) {
                                if (i < head.length) return head[i];
                                final d = docs[i - head.length];
                                return _tarjetaBolaDesdeDoc(
                                  d,
                                  user: user,
                                  nombre: nombre,
                                  rol: rol,
                                );
                              },
                            );
                          }

                          final docsOferta =
                              <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                          final docsPedidos =
                              <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                          for (final d in docs) {
                            final t = (d.data()['tipo'] ?? '').toString();
                            if (t == 'oferta') {
                              docsOferta.add(d);
                            } else {
                              docsPedidos.add(d);
                            }
                          }
                          final hCond = docsOferta.isNotEmpty ? 1 : 0;
                          final hPed =
                              docsPedidos.isNotEmpty && docsOferta.isNotEmpty
                                  ? 1
                                  : 0;
                          final itemCount = head.length +
                              hCond +
                              docsOferta.length +
                              hPed +
                              docsPedidos.length;

                          return ListView.builder(
                            controller: scrollController,
                            padding:
                                EdgeInsets.fromLTRB(16, 0, 16, bottomPad),
                            itemCount: itemCount,
                            itemBuilder: (context, i) {
                              if (i < head.length) return head[i];
                              var j = i - head.length;
                              if (hCond > 0) {
                                if (j == 0) {
                                  return _bolaSeccionListaCliente(
                                    col,
                                    titulo: 'Conductores',
                                  );
                                }
                                j--;
                              }
                              if (j < docsOferta.length) {
                                return _tarjetaBolaDesdeDoc(
                                  docsOferta[j],
                                  user: user,
                                  nombre: nombre,
                                  rol: rol,
                                );
                              }
                              j -= docsOferta.length;
                              if (hPed > 0) {
                                if (j == 0) {
                                  return _bolaSeccionListaCliente(
                                    col,
                                    titulo: 'Otros pasajeros',
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 18, 16, 6),
                                  );
                                }
                                j--;
                              }
                              return _tarjetaBolaDesdeDoc(
                                docsPedidos[j],
                                user: user,
                                nombre: nombre,
                                rol: rol,
                              );
                            },
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        }

        if (!esTaxista) {
          return mapaYTablero();
        }

        Widget loadingTaxistaGate() {
          return Scaffold(
            backgroundColor: col.bgDeep,
            appBar: AppBar(
              backgroundColor: col.appBarScrim,
              elevation: 0,
              foregroundColor: col.onSurface,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: col.onSurface),
                tooltip: 'Volver',
                onPressed: () => _volverAtrasDesdeTablero(esTaxista: esTaxista),
              ),
              title: appBarTitleRow(),
            ),
            body: const Center(
              child: CircularProgressIndicator(color: BolaPuebloTheme.accent),
            ),
          );
        }

        /// Misma regla que [ViajesRepo.claimTripWithReason]: usuario + billetera.
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('usuarios')
              .doc(user.uid)
              .snapshots(),
          builder: (context, uSnap) {
            if (uSnap.connectionState == ConnectionState.waiting &&
                !uSnap.hasData) {
              return loadingTaxistaGate();
            }
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('billeteras_taxista')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, billSnap) {
                if (billSnap.connectionState == ConnectionState.waiting &&
                    !billSnap.hasData) {
                  return loadingTaxistaGate();
                }
                final uData = uSnap.data?.data();
                final bData = billSnap.data?.data();
                final bloqueado =
                    !PagosTaxistaRepo.taxistaSinBloqueoPrepagoOperativo(
                        uData, bData);
                if (!bloqueado) {
                  return mapaYTablero();
                }

                return Scaffold(
                  backgroundColor: col.bgDeep,
                  extendBodyBehindAppBar: false,
                  appBar: AppBar(
                    backgroundColor: col.appBarScrim,
                    elevation: 0,
                    foregroundColor: col.onSurface,
                    leading: IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: col.onSurface),
                      tooltip: 'Volver',
                      onPressed: () => _volverAtrasDesdeTablero(esTaxista: esTaxista),
                    ),
                    title: appBarTitleRow(),
                  ),
                  body: SafeArea(
                    child: SingleChildScrollView(
                      padding: BolaPuebloUi.listScrollPadding(
                        context,
                        left: 20,
                        top: 12,
                        right: 20,
                        base: 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 44,
                            color: col.onMuted,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'No puedes participar en Bola Ahorro: tu saldo prepago de comisión '
                            'en efectivo es insuficiente o tienes pagos / bloqueos pendientes en cuenta. '
                            'Es la misma regla que el pool de viajes.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: col.onMuted,
                              fontSize: 15,
                              height: 1.45,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Recarga y regulariza en Mis pagos para volver a ofertar o tomar viajes.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: col.onMuted.withValues(alpha: 0.92),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: () => TaxistaFinanzasNav.abrirMisPagos(
                              context,
                              scrollToRecargaSection: true,
                            ),
                            icon: const Icon(Icons.payment_rounded),
                            label: const Text('Ir a Mis pagos'),
                            style: FilledButton.styleFrom(
                              backgroundColor: BolaPuebloTheme.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () =>
                                TaxistaFinanzasNav.abrirBloqueadoPagos(context),
                            icon: const Icon(Icons.account_balance_outlined),
                            label: const Text('Cuenta bancaria y pasos'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: col.onSurface,
                              side: BorderSide(color: col.outlineSoft),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
