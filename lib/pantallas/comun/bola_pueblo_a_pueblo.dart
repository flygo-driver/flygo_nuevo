import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flygo_nuevo/pantallas/cliente/bola_conductores_en_ruta_cliente.dart';
import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_actions.dart';
import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_viaje_activo_page.dart';
import 'package:flygo_nuevo/servicios/bola_pueblo_repo.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/widgets/mapa_tiempo_real.dart';

class BolaPuebloAPuebloPage extends StatefulWidget {
  const BolaPuebloAPuebloPage({super.key});

  @override
  State<BolaPuebloAPuebloPage> createState() => _BolaPuebloAPuebloPageState();
}

class _BolaPuebloAPuebloPageState extends State<BolaPuebloAPuebloPage> {
  bool _guardando = false;

  final DraggableScrollableController _bolaBoardSheetCtrl =
      DraggableScrollableController();

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
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BolaPuebloViajeActivoPage(bolaId: bolaId),
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
    required String subtitulo,
    EdgeInsets padding = const EdgeInsets.fromLTRB(16, 14, 16, 6),
  }) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              color: col.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.35,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitulo,
            style: TextStyle(
              color: col.onMuted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
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
            children: [
              Image.asset(
                'assets/icon/logo_rai_vertical.png',
                height: 32,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.location_city, color: col.onSurface),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Bola Ahorro',
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
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Volver',
                onPressed: () => Navigator.maybePop(context),
              ),
              actions: [
                if (_rutaPolyline != null)
                  IconButton(
                    tooltip: 'Quitar ruta del mapa',
                    icon: const Icon(Icons.layers_clear_rounded),
                    onPressed: _limpiarRutaMapa,
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
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: BolaPuebloRepo.streamTablero(),
                        builder: (context, snap) {
                          final safeBottom =
                              MediaQuery.of(context).padding.bottom;
                          final docsAll = snap.data?.docs ?? const [];
                          final docs = docsAll.where((d) {
                            final m = d.data();
                            final estado = (m['estado'] ?? '').toString();
                            final ownerUid =
                                (m['createdByUid'] ?? '').toString();
                            final uidTx = (m['uidTaxista'] ?? '').toString();
                            final uidCli = (m['uidCliente'] ?? '').toString();
                            if (estado == 'abierta' || estado == 'en_curso') {
                              return true;
                            }
                            if (estado == 'acordada') {
                              return ownerUid == user.uid ||
                                  uidTx == user.uid ||
                                  uidCli == user.uid;
                            }
                            return false;
                          }).toList();

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
                                    ? 'Publicá tu ruta con el botón «Voy para» o respondé a pedidos de pasajeros abajo.'
                                    : 'Abajo ves primero conductores con ruta; después pedidos de otros pasajeros. '
                                        '«Pedir bola» es para cuando vos necesitás el viaje.',
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'El mapa es fijo; esta lista se desplaza para no tapar las tarjetas.',
                                style: TextStyle(
                                  color: col.onMuted,
                                  fontSize: 11.5,
                                  height: 1.35,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (!esTaxista)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: BolaPuebloUi.actionPanel(
                                  context,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      BolaPuebloUi.sectionLabel(
                                          context, 'Para vos (pasajero)'),
                                      Text(
                                        'Los conductores publican «estoy en X, voy para Y» con un precio; '
                                        'negociás en la tarjeta y podés quedar más barato que un viaje normal.',
                                        style: BolaPuebloUi.panelBody(context),
                                      ),
                                      const SizedBox(height: 14),
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF00C853),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 18, vertical: 16),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                BolaPuebloUi.radiusButton),
                                          ),
                                          elevation: 6,
                                          shadowColor: const Color(0xFF00E676)
                                              .withValues(alpha: 0.65),
                                        ).copyWith(
                                          overlayColor: WidgetStatePropertyAll(
                                            Colors.white
                                                .withValues(alpha: 0.08),
                                          ),
                                        ),
                                        onPressed: _guardando
                                            ? null
                                            : () => BolaPuebloDialogs
                                                    .crearPublicacion(
                                                  context: context,
                                                  uid: user.uid,
                                                  rol: rol,
                                                  nombre: nombre,
                                                  tipo: 'pedido',
                                                  onBusy: (b) => setState(
                                                      () => _guardando = b),
                                                ),
                                        icon: const Icon(Icons.add_road_rounded,
                                            size: 22),
                                        label: const Text(
                                          'Pedir bola',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.2,
                                            shadows: [
                                              Shadow(
                                                color: Color(0x5500FF95),
                                                blurRadius: 12,
                                                offset: Offset(0, 0),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      OutlinedButton.icon(
                                        onPressed: () => NavigationService.push(
                                          const BolaConductoresEnRutaClientePage(),
                                        ),
                                        icon: const Icon(
                                            Icons.local_taxi_outlined,
                                            size: 20),
                                        label: const Text(
                                          'Pantalla solo conductores (estoy en → voy para)',
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          backgroundColor:
                                              const Color(0xFF3D5AFE),
                                          side: BorderSide(
                                            color: const Color(0xFF8C9EFF)
                                                .withValues(alpha: 0.95),
                                            width: 1.4,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 14, horizontal: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                BolaPuebloUi.radiusButton),
                                          ),
                                          elevation: 4,
                                          shadowColor: const Color(0xFF536DFE)
                                              .withValues(alpha: 0.45),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (esTaxista)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: BolaPuebloUi.actionPanel(
                                  context,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      BolaPuebloUi.sectionLabel(context,
                                          'Conductor · publicá tu ruta'),
                                      Text(
                                        'Ej.: estoy en La Vega → voy para Santo Domingo (capital). '
                                        'Los pasajeros te ven en la lista y negocian el monto.',
                                        style: BolaPuebloUi.panelBody(context),
                                      ),
                                      const SizedBox(height: 14),
                                      FilledButton.icon(
                                        style:
                                            BolaPuebloUi.filledPrimary.copyWith(
                                          padding: const WidgetStatePropertyAll(
                                            EdgeInsets.symmetric(
                                                horizontal: 20, vertical: 18),
                                          ),
                                        ),
                                        onPressed: _guardando
                                            ? null
                                            : () => BolaPuebloDialogs
                                                    .crearPublicacion(
                                                  context: context,
                                                  uid: user.uid,
                                                  rol: rol,
                                                  nombre: nombre,
                                                  tipo: 'oferta',
                                                  onBusy: (b) => setState(
                                                      () => _guardando = b),
                                                ),
                                        icon: const Icon(Icons.route_rounded,
                                            size: 26),
                                        label: const Text(
                                          'Voy para…',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.touch_app_rounded,
                                            color:
                                                BolaPuebloTheme.accentSecondary,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'También podés ofertar en los pedidos de pasajeros que aparecen abajo. '
                                              'Chat y teléfono se habilitan cuando el precio queda acordado.',
                                              style: BolaPuebloUi.panelBody(
                                                  context),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
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
                              padding: EdgeInsets.only(bottom: 28 + safeBottom),
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
                                ? 'Publicá «Voy para…» o esperá pedidos de pasajeros; las tarjetas aparecen acá.'
                                : 'Cuando un conductor publique ruta u otro pasajero un pedido, lo verás abajo. '
                                    'Usá «Pedir bola» arriba para publicar el tuyo.';
                            return ListView(
                              controller: scrollController,
                              padding: EdgeInsets.only(bottom: 28 + safeBottom),
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
                                  16, 0, 16, 28 + safeBottom),
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
                                EdgeInsets.fromLTRB(16, 0, 16, 28 + safeBottom),
                            itemCount: itemCount,
                            itemBuilder: (context, i) {
                              if (i < head.length) return head[i];
                              var j = i - head.length;
                              if (hCond > 0) {
                                if (j == 0) {
                                  return _bolaSeccionListaCliente(
                                    col,
                                    titulo: 'Conductores · rutas publicadas',
                                    subtitulo:
                                        'Van de un sitio a otro con precio negociable; suele salir más barato que pedir taxi solo.',
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
                                    titulo: 'Pasajeros · pedidos publicados',
                                    subtitulo:
                                        'Otros viajeros buscan conductor; podés ver la ruta. Para tu viaje usá «Pedir bola» arriba.',
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
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Volver',
                onPressed: () => Navigator.maybePop(context),
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
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Volver',
                      onPressed: () => Navigator.maybePop(context),
                    ),
                    title: appBarTitleRow(),
                  ),
                  body: SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                            PagosTaxistaRepo.mensajeRecargaBannerLista,
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
                            'Misma regla que el pool: saldo prepago mínimo / comisión RAI '
                            '(y la bandera de cuenta si aplica). Regularizá en Mis pagos.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: col.onMuted.withValues(alpha: 0.92),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: () =>
                                Navigator.of(context).pushNamed('/mis_pagos'),
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
                            onPressed: () => Navigator.of(context)
                                .pushNamed('/bloqueado_por_pagos'),
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
