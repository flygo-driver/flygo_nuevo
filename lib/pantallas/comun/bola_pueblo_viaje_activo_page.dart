// Pantalla dedicada: mapa + pasos de viaje (acordada / en curso) sin el tablero completo.
// Reutiliza los mismos widgets que la tarjeta del tablero; no cambia reglas ni repositorio.

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_actions.dart';
import 'package:flygo_nuevo/pantallas/comun/factura_bola_pueblo.dart';
import 'package:flygo_nuevo/servicios/bola_nav_coordination_guard.dart';
import 'package:flygo_nuevo/servicios/bola_pueblo_repo.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/utilidades/constante.dart' show etiquetaBolaAhorroUi;
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';
import 'package:flygo_nuevo/widgets/bola_post_factura_reopen_guard.dart';
import 'package:flygo_nuevo/widgets/mapa_tiempo_real.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';

/// Modo viaje Bola: navegación y pasos a pantalla completa (cliente o taxista asignado).
class BolaPuebloViajeActivoPage extends StatelessWidget {
  const BolaPuebloViajeActivoPage({super.key, required this.bolaId});

  final String bolaId;

  static double? _coordNum(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v is num) return v.toDouble();
    return null;
  }

  static LatLng? _taxistaLatLngDesdeUsuario(Map<String, dynamic> m) {
    final dynamic a = m['location'];
    final dynamic b = m['ubicacion'];
    final dynamic c = m['ultimaUbicacion'];
    GeoPoint? gp;
    if (a is GeoPoint) gp = a;
    if (gp == null && b is GeoPoint) gp = b;
    if (gp == null && c is GeoPoint) gp = c;
    if (gp != null) return LatLng(gp.latitude, gp.longitude);

    final dynamic latRaw = m['lat'] ?? m['latTaxista'];
    final dynamic lonRaw = m['lon'] ?? m['lng'] ?? m['lonTaxista'];
    final double? lat = (latRaw is num) ? latRaw.toDouble() : null;
    final double? lon = (lonRaw is num) ? lonRaw.toDouble() : null;
    if (lat == null || lon == null) return null;
    return LatLng(lat, lon);
  }

  static String _fmtHoraFecha(Timestamp ts) {
    final d = ts.toDate();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm $hh:$mi';
  }

  static String _actorPago(String uid, String uidTaxista, String uidCliente) {
    if (uid == uidTaxista) return 'conductor';
    if (uid == uidCliente) return 'pasajero';
    return 'usuario';
  }

  static bool _cuentaBancariaCompleta(
    String banco,
    String cuenta,
    String titular,
  ) {
    return banco.isNotEmpty && cuenta.isNotEmpty && titular.isNotEmpty;
  }

  static Widget _filaCopiar({
    required BuildContext context,
    required String etiqueta,
    required String valor,
    required Color fg,
    required Color fgMuted,
  }) {
    if (valor.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  style: TextStyle(
                    color: fgMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: TextStyle(
                    color: fg,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copiar',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: valor));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$etiqueta copiado'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            icon: Icon(Icons.copy_rounded, size: 20, color: cs.primary),
          ),
        ],
      ),
    );
  }

  static double _distKm(LatLng a, LatLng b) {
    const double r = 6371.0;
    final double dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final double dLon = (b.longitude - a.longitude) * math.pi / 180.0;
    final double la1 = a.latitude * math.pi / 180.0;
    final double la2 = b.latitude * math.pi / 180.0;
    final double h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return r * c;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(etiquetaBolaAhorroUi)),
        body: const Center(child: Text('Iniciá sesión')),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('bolas_pueblo')
          .doc(bolaId)
          .snapshots(),
      builder: (context, bolaSnap) {
        final c = BolaPuebloColors.of(context);
        if (bolaSnap.connectionState == ConnectionState.waiting &&
            !bolaSnap.hasData) {
          return Scaffold(
            backgroundColor: c.bgDeep,
            appBar: AppBar(
              backgroundColor: c.appBarScrim,
              title: const Text('Cargando…'),
            ),
            body: const Center(
                child:
                    CircularProgressIndicator(color: BolaPuebloTheme.accent)),
          );
        }
        if (!bolaSnap.hasData || !(bolaSnap.data?.exists ?? false)) {
          return Scaffold(
            backgroundColor: c.bgDeep,
            appBar: AppBar(
              backgroundColor: c.appBarScrim,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Volver al tablero',
                onPressed: () =>
                    NavigationService.popOrGoBolaTablero(context),
              ),
              title: Text(etiquetaBolaAhorroUi),
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Publicación no encontrada',
                      style: TextStyle(color: c.onMuted)),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () =>
                        NavigationService.popOrGoBolaTablero(context),
                    child: const Text('Volver al tablero'),
                  ),
                ],
              ),
            ),
          );
        }

        final data = bolaSnap.data!.data() ?? {};
        final estado = (data['estado'] ?? '').toString();
        final uidTaxista = (data['uidTaxista'] ?? '').toString();
        final uidCliente = (data['uidCliente'] ?? '').toString();
        final bool partActivo =
            uidTaxista == user.uid || uidCliente == user.uid;

        if (!partActivo || (estado != 'acordada' && estado != 'en_curso')) {
          if (partActivo && estado == 'finalizada') {
            return BolaViajeTerminalPage(
              bolaId: bolaId,
              uid: user.uid,
              uidTaxista: uidTaxista,
              terminal: BolaViajeTerminal.finalizada,
            );
          }
          if (partActivo && estado == 'cancelada') {
            return BolaViajeTerminalPage(
              bolaId: bolaId,
              uid: user.uid,
              uidTaxista: uidTaxista,
              terminal: BolaViajeTerminal.cancelada,
              mensajeCancelacion:
                  BolaPuebloRepo.mensajeCancelacionParaParticipante(
                data,
                user.uid,
              ),
            );
          }
          if (partActivo && estado == 'abierta') {
            return _BolaRedirigirAlTablero(
              mensaje:
                  'Negociá tarifa en el tablero. Cuando acuerdes, entrás a Mi viaje en curso.',
            );
          }
          final bool aunAbierta = estado == 'abierta';
          return Scaffold(
            backgroundColor: c.bgDeep,
            appBar: AppBar(
              backgroundColor: c.appBarScrim,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Volver al tablero',
                onPressed: () =>
                    NavigationService.popOrGoBolaTablero(context),
              ),
              title: Text(etiquetaBolaAhorroUi),
            ),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      aunAbierta
                          ? 'Tu publicación está en el tablero. Cuando acuerdes tarifa con un conductor o pasajero, podrás seguir el viaje aquí.'
                          : 'Esta bola ya no está en modo viaje para vos, o aún no hay acuerdo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.onMuted, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () =>
                          NavigationService.popOrGoBolaTablero(context),
                      child: const Text('Volver al tablero'),
                    ),
                  ],
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
          builder: (context, usrSnap) {
            final ud = usrSnap.data?.data() ?? const <String, dynamic>{};
            final rol = (ud['rol'] ?? 'cliente').toString();
            final esTaxistaRol = rol == 'taxista' || rol == 'driver';
            final soyTaxistaAsignado = uidTaxista == user.uid;
            final soyClienteAsignado = uidCliente == user.uid;

            final origen = (data['origen'] ?? '').toString();
            final destino = (data['destino'] ?? '').toString();
            final tipo = (data['tipo'] ?? '').toString();
            final oLa = _coordNum(data, 'origenLat');
            final oLo = _coordNum(data, 'origenLon');
            final dLa = _coordNum(data, 'destinoLat');
            final dLo = _coordNum(data, 'destinoLon');
            LatLng? oo;
            LatLng? dd;
            List<LatLng>? poly;
            if (oLa != null && oLo != null && dLa != null && dLo != null) {
              oo = LatLng(oLa, oLo);
              dd = LatLng(dLa, dLo);
              poly = [oo, dd];
            }

            final fg = c.onSurface;
            final fgMuted = c.onMuted;
            final pickupConfirmadoTaxista =
                data['pickupConfirmadoTaxista'] == true;
            final codigoBola =
                (data['codigoVerificacionBola'] ?? '').toString();
            final codigoGeneradoEn = data['codigoGeneradoEn'];
            final bool confTax = data['confirmacionTaxistaFinal'] == true;
            final bool confCli = data['confirmacionClienteFinal'] == true;
            final bool codigoVerificado = data['codigoVerificado'] == true;
            final comisionRd = ((data['comisionRd'] ?? 0) as num).toDouble();
            final netoChofer =
                ((data['gananciaNetaChoferRd'] ?? 0) as num).toDouble();
            final String metodoPago =
                (data['metodoPago'] ?? 'efectivo').toString().toLowerCase();
            final String metodoPagoBy =
                (data['metodoPagoUpdatedBy'] ?? '').toString();
            final Timestamp? metodoPagoAt =
                data['metodoPagoUpdatedAt'] is Timestamp
                    ? data['metodoPagoUpdatedAt'] as Timestamp
                    : null;
            final montoAcordadoRd =
                ((data['montoAcordadoRd'] ?? 0) as num).toDouble();
            final monto = ((data['montoSugeridoRd'] ?? 0) as num).toDouble();
            final owner = (data['createdByNombre'] ?? 'Usuario').toString();
            final fecha = BolaPuebloFormat.fmtTs(data['fechaSalida']);
            final nota = (data['nota'] ?? '').toString();
            final distanciaKm = ((data['distanciaKm'] ?? 0) as num).toDouble();
            final pasajeros =
                ((data['pasajeros'] ?? 1) as num).toInt().clamp(1, 8);
            final String viajeEspejoId =
                (data['viajeEspejoId'] ?? '').toString().trim();
            final bool mostrarTaxistaEnMapa = soyClienteAsignado &&
                uidTaxista.isNotEmpty &&
                (estado == 'acordada' || estado == 'en_curso');
            final bool mapaEstiloCalleBlanca =
                soyClienteAsignado && mostrarTaxistaEnMapa;
            final double bottomPad =
                BolaPuebloUi.listScrollPaddingInsideSafeArea(
              context,
              left: 18,
              top: 16,
              right: 18,
            ).bottom;

            return _BolaEspejoPoolAutoNavListener(
              bolaId: bolaId,
              viajeEspejoId: viajeEspejoId,
              esClienteAsignado: soyClienteAsignado,
              esTaxistaAsignado: soyTaxistaAsignado,
              child: Scaffold(
              backgroundColor: c.bgDeep,
              appBar: AppBar(
                backgroundColor: c.appBarScrim,
                elevation: 0,
                foregroundColor: c.onSurface,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: c.onSurface),
                  tooltip: 'Volver al tablero',
                  onPressed: () =>
                      NavigationService.popOrGoBolaTablero(context),
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Viaje · $etiquetaBolaAhorroUi',
                      style: BolaPuebloUi.screenTitleBola(context),
                    ),
                    Text(
                      estado == 'en_curso'
                          ? 'En curso'
                          : 'Acordado — seguí los pasos',
                      style: TextStyle(
                          color: c.onMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              body: SafeArea(
                top: false,
                bottom: true,
                child: Column(
                  children: [
                  Expanded(
                    flex: 38,
                    child: !mostrarTaxistaEnMapa
                        ? MapaTiempoReal(
                            esCliente: !esTaxistaRol,
                            esTaxista: esTaxistaRol,
                            origen: oo,
                            destino: dd,
                            origenNombre: origen.isEmpty ? null : origen,
                            destinoNombre: destino.isEmpty ? null : destino,
                            mostrarOrigen: oo != null,
                            mostrarDestino: dd != null,
                            mostrarTaxista: false,
                            polylinePreviewPoints: poly,
                            estiloCalleAnchaBlanca: mapaEstiloCalleBlanca,
                          )
                        : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            stream: FirebaseFirestore.instance
                                .collection('usuarios')
                                .doc(uidTaxista)
                                .snapshots(),
                            builder: (context, txSnap) {
                              final Map<String, dynamic> txData =
                                  txSnap.data?.data() ??
                                      const <String, dynamic>{};
                              final LatLng? txPos =
                                  _taxistaLatLngDesdeUsuario(txData);
                              List<LatLng>? trackPreview = poly;
                              if (txPos != null && oo != null && estado == 'acordada') {
                                trackPreview = <LatLng>[txPos, oo];
                              } else if (txPos != null &&
                                  dd != null &&
                                  estado == 'en_curso') {
                                trackPreview = <LatLng>[txPos, dd];
                              }
                              return MapaTiempoReal(
                                esCliente: !esTaxistaRol,
                                esTaxista: esTaxistaRol,
                                origen: oo,
                                destino: dd,
                                origenNombre: origen.isEmpty ? null : origen,
                                destinoNombre: destino.isEmpty ? null : destino,
                                mostrarOrigen: oo != null,
                                mostrarDestino: dd != null,
                                mostrarTaxista: txPos != null,
                                ubicacionTaxista: txPos,
                                polylinePreviewPoints: trackPreview,
                                estiloCalleAnchaBlanca: mapaEstiloCalleBlanca,
                              );
                            },
                          ),
                  ),
                  Expanded(
                    flex: 62,
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: c.surface.withValues(alpha: 0.98),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(22)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: c.isDark ? 0.35 : 0.08),
                            blurRadius: 18,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(22)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Container(
                              height: 4,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: <Color>[
                                    BolaPuebloTheme.accent,
                                    BolaPuebloTheme.accentSecondary,
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView(
                                padding:
                                    EdgeInsets.fromLTRB(18, 16, 18, bottomPad),
                                children: [
                                  BolaPuebloUi.routeBlock(context,
                                      origen: origen, destino: destino),
                                  if (soyClienteAsignado &&
                                      uidTaxista.isNotEmpty &&
                                      (estado == 'acordada' ||
                                          estado == 'en_curso')) ...[
                                    const SizedBox(height: 10),
                                    StreamBuilder<
                                        DocumentSnapshot<
                                            Map<String, dynamic>>>(
                                      stream: FirebaseFirestore.instance
                                          .collection('usuarios')
                                          .doc(uidTaxista)
                                          .snapshots(),
                                      builder: (context, txSnap) {
                                        final txData = txSnap.data?.data() ??
                                            const <String, dynamic>{};
                                        final txPos =
                                            _taxistaLatLngDesdeUsuario(txData);
                                        final enVivo = txPos != null;
                                        final LatLng? target = estado == 'acordada'
                                            ? oo
                                            : (estado == 'en_curso' ? dd : null);
                                        final double? km = (enVivo && target != null)
                                            ? _distKm(txPos, target)
                                            : null;
                                        final int? minAprox = (km != null)
                                            ? math.max(1, (km / 0.42).round())
                                            : null;
                                        final Color etaColor = km == null
                                            ? fgMuted
                                            : (km <= 1.0
                                                ? const Color(0xFF2E7D32)
                                                : (km <= 3.0
                                                    ? const Color(0xFFF9A825)
                                                    : const Color(0xFFC62828)));
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                          decoration: BoxDecoration(
                                            color:
                                                fgMuted.withValues(alpha: 0.07),
                                            borderRadius: BorderRadius.circular(
                                                BolaPuebloUi.radiusSmall),
                                            border: Border.all(
                                              color: c.outlineSoft
                                                  .withValues(alpha: 0.4),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                enVivo
                                                    ? Icons.radio_button_checked
                                                    : Icons.history_toggle_off,
                                                color: enVivo
                                                    ? BolaPuebloTheme.accent
                                                    : fgMuted,
                                                size: 16,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  enVivo
                                                      ? (estado == 'acordada'
                                                          ? 'Taxi en camino (seguimiento en tiempo real)'
                                                          : 'Taxi en ruta al destino (tiempo real)')
                                                      : 'Esperando señal del taxi en tiempo real…',
                                                  style: TextStyle(
                                                    color: fgMuted,
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              if (km != null) ...[
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: etaColor.withValues(
                                                        alpha: 0.14),
                                                    borderRadius:
                                                        BorderRadius.circular(999),
                                                  ),
                                                  child: Text(
                                                    '${km.toStringAsFixed(1)} km · $minAprox min',
                                                    style: TextStyle(
                                                      color: etaColor,
                                                      fontSize: 11.5,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  if (estado == 'acordada' ||
                                      estado == 'en_curso') ...[
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: fgMuted.withValues(alpha: 0.07),
                                        borderRadius: BorderRadius.circular(
                                            BolaPuebloUi.radiusSmall),
                                        border: Border.all(
                                            color: c.outlineSoft
                                                .withValues(alpha: 0.4)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Forma de pago del viaje',
                                            style: TextStyle(
                                              color: fgMuted,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.85,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Elegí efectivo o transferencia desde el inicio; '
                                            'ambos lo ven igual. Podés cambiarlo hasta que el viaje termine.',
                                            style: TextStyle(
                                              color: fgMuted,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              height: 1.35,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          if (soyTaxistaAsignado)
                                            Text(
                                              'Total RD\$${(montoAcordadoRd > 0 ? montoAcordadoRd : monto).toStringAsFixed(2)} · '
                                              'Tu neto RD\$${netoChofer.toStringAsFixed(2)} · Comisión RAI RD\$${comisionRd.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                color: fg,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                height: 1.35,
                                              ),
                                            )
                                          else
                                            Text(
                                              'Monto a pagar RD\$${(montoAcordadoRd > 0 ? montoAcordadoRd : monto).toStringAsFixed(2)}',
                                              style: TextStyle(
                                                color: fg,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                height: 1.25,
                                              ),
                                            ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              ChoiceChip(
                                                label:
                                                    const Text('Efectivo'),
                                                selected:
                                                    MetodoPagoViaje.esEfectivo(
                                                        metodoPago),
                                                onSelected: (_) async {
                                                  try {
                                                    await BolaPuebloRepo
                                                        .actualizarMetodoPagoBola(
                                                      bolaId: bolaId,
                                                      uidActor: user.uid,
                                                      metodoPago: 'efectivo',
                                                    );
                                                  } catch (e) {
                                                    if (!context.mounted) return;
                                                    ScaffoldMessenger.of(context)
                                                        .showSnackBar(
                                                      BolaPuebloTheme.snack(
                                                          context, '$e',
                                                          error: true),
                                                    );
                                                  }
                                                },
                                              ),
                                              ChoiceChip(
                                                label: const Text(
                                                    'Transferencia'),
                                                selected:
                                                    MetodoPagoViaje
                                                        .esTransferencia(
                                                            metodoPago),
                                                onSelected: (_) async {
                                                  try {
                                                    await BolaPuebloRepo
                                                        .actualizarMetodoPagoBola(
                                                      bolaId: bolaId,
                                                      uidActor: user.uid,
                                                      metodoPago:
                                                          'transferencia',
                                                    );
                                                  } catch (e) {
                                                    if (!context.mounted) return;
                                                    ScaffoldMessenger.of(context)
                                                        .showSnackBar(
                                                      BolaPuebloTheme.snack(
                                                          context, '$e',
                                                          error: true),
                                                    );
                                                  }
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: fgMuted.withValues(
                                                  alpha: 0.06),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: c.outlineSoft
                                                    .withValues(alpha: 0.35),
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  MetodoPagoViaje
                                                          .esTransferencia(
                                                              metodoPago)
                                                      ? 'Transferencia al conductor'
                                                      : 'Pago en efectivo',
                                                  style: TextStyle(
                                                    color: fg,
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  MetodoPagoViaje
                                                          .esTransferencia(
                                                              metodoPago)
                                                      ? 'Al cerrar el viaje, enviás el dinero '
                                                          'del acuerdo a la cuenta que el conductor tiene '
                                                          'registrada en RAI (abajo). La comisión RAI se '
                                                          'descuenta del lado del conductor según las reglas de la app.'
                                                      : 'Al llegar al destino, pagás en efectivo '
                                                          'al conductor el monto acordado '
                                                          '(RD\$${(montoAcordadoRd > 0 ? montoAcordadoRd : monto).toStringAsFixed(2)}). '
                                                          'La comisión RAI la gestiona el conductor con su saldo/prepago.',
                                                  style: TextStyle(
                                                    color: fgMuted,
                                                    fontSize: 12,
                                                    height: 1.35,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (MetodoPagoViaje.esTransferencia(
                                                  metodoPago) &&
                                              soyTaxistaAsignado) ...[
                                            const SizedBox(height: 10),
                                            Builder(
                                              builder: (ctx) {
                                                final banco =
                                                    (ud['banco'] ?? '')
                                                        .toString()
                                                        .trim();
                                                final cuenta =
                                                    (ud['numeroCuenta'] ?? '')
                                                        .toString()
                                                        .trim();
                                                final titular =
                                                    (ud['titularCuenta'] ??
                                                            ud['titular'] ??
                                                            '')
                                                        .toString()
                                                        .trim();
                                                final ok =
                                                    _cuentaBancariaCompleta(
                                                  banco,
                                                  cuenta,
                                                  titular,
                                                );
                                                return Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      ok
                                                          ? 'Tu cuenta registrada en RAI (la ve el pasajero)'
                                                          : 'Completá tu cuenta en Perfil → datos bancarios',
                                                      style: TextStyle(
                                                        color: ok
                                                            ? fgMuted
                                                            : Colors
                                                                .amber.shade800,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    if (ok) ...[
                                                      _filaCopiar(
                                                        context: ctx,
                                                        etiqueta: 'Banco',
                                                        valor: banco,
                                                        fg: fg,
                                                        fgMuted: fgMuted,
                                                      ),
                                                      _filaCopiar(
                                                        context: ctx,
                                                        etiqueta: 'Titular',
                                                        valor: titular,
                                                        fg: fg,
                                                        fgMuted: fgMuted,
                                                      ),
                                                      _filaCopiar(
                                                        context: ctx,
                                                        etiqueta:
                                                            'Número de cuenta',
                                                        valor: cuenta,
                                                        fg: fg,
                                                        fgMuted: fgMuted,
                                                      ),
                                                    ],
                                                  ],
                                                );
                                              },
                                            ),
                                          ],
                                          if (MetodoPagoViaje.esTransferencia(
                                                  metodoPago) &&
                                              soyClienteAsignado &&
                                              uidTaxista.isNotEmpty)
                                            StreamBuilder<
                                                DocumentSnapshot<
                                                    Map<String, dynamic>>>(
                                              stream: FirebaseFirestore
                                                  .instance
                                                  .collection('usuarios')
                                                  .doc(uidTaxista)
                                                  .snapshots(),
                                              builder: (ctx, txSnap) {
                                                final td = txSnap.data
                                                        ?.data() ??
                                                    const <String,
                                                        dynamic>{};
                                                final banco =
                                                    (td['banco'] ?? '')
                                                        .toString()
                                                        .trim();
                                                final cuenta =
                                                    (td['numeroCuenta'] ?? '')
                                                        .toString()
                                                        .trim();
                                                final titular =
                                                    (td['titularCuenta'] ??
                                                            td['titular'] ??
                                                            '')
                                                        .toString()
                                                        .trim();
                                                final ok =
                                                    _cuentaBancariaCompleta(
                                                  banco,
                                                  cuenta,
                                                  titular,
                                                );
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 10),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'Cuenta del conductor en RAI',
                                                        style: TextStyle(
                                                          color: fg,
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight
                                                                  .w800,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                          height: 6),
                                                      if (!ok)
                                                        Text(
                                                          'El conductor aún no tiene completa la cuenta en el perfil. '
                                                          'Coordiná por chat o WhatsApp y pedile que cargue banco, '
                                                          'titular y número en la app.',
                                                          style: TextStyle(
                                                            color: Colors
                                                                .amber
                                                                .shade800,
                                                            fontSize: 12,
                                                            height: 1.35,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600,
                                                          ),
                                                        )
                                                      else ...[
                                                        _filaCopiar(
                                                          context: ctx,
                                                          etiqueta: 'Banco',
                                                          valor: banco,
                                                          fg: fg,
                                                          fgMuted: fgMuted,
                                                        ),
                                                        _filaCopiar(
                                                          context: ctx,
                                                          etiqueta: 'Titular',
                                                          valor: titular,
                                                          fg: fg,
                                                          fgMuted: fgMuted,
                                                        ),
                                                        _filaCopiar(
                                                          context: ctx,
                                                          etiqueta:
                                                              'Número de cuenta',
                                                          valor: cuenta,
                                                          fg: fg,
                                                          fgMuted: fgMuted,
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          if (metodoPagoAt != null) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              'Último cambio: ${_fmtHoraFecha(metodoPagoAt)}'
                                              '${metodoPagoBy.isNotEmpty ? ' · ${_actorPago(metodoPagoBy, uidTaxista, uidCliente)}' : ''}',
                                              style: TextStyle(
                                                color: fgMuted.withValues(
                                                    alpha: 0.9),
                                                fontSize: 11.5,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  if (soyTaxistaAsignado &&
                                      estado == 'acordada') ...[
                                    BolaTaxistaAcordadaFlow(
                                      docId: bolaId,
                                      user: user,
                                      origen: origen,
                                      destino: destino,
                                      pickupConfirmadoServidor:
                                          pickupConfirmadoTaxista,
                                      uidPasajero: uidCliente,
                                      tipoPublicacion: tipo,
                                      origenLat: oLa,
                                      origenLon: oLo,
                                      destinoLat: dLa,
                                      destinoLon: dLo,
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  if (soyClienteAsignado &&
                                      estado == 'acordada') ...[
                                    BolaPuebloClienteMapsAcordada(
                                      origen: origen,
                                      tipo: tipo,
                                      origenLat: oLa,
                                      origenLon: oLo,
                                    ),
                                    const SizedBox(height: 16),
                                    BolaClienteAcordadaCapas(
                                      bolaId: bolaId,
                                      uidConductor: uidTaxista,
                                      codigoBola: codigoBola,
                                      codigoGeneradoEn: codigoGeneradoEn,
                                      codigoVerificado: codigoVerificado,
                                      pickupConfirmadoTaxista:
                                          pickupConfirmadoTaxista,
                                      user: user,
                                      fg: fg,
                                      fgMuted: fgMuted,
                                      esClienteVaHaciaConductor:
                                          tipo == 'oferta',
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  if (partActivo &&
                                      estado == 'acordada' &&
                                      BolaPuebloRepo.puedeCancelarAcuerdo(
                                          data)) ...[
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              Colors.red.shade700,
                                          side: BorderSide(
                                            color: Colors.red
                                                .withValues(alpha: 0.45),
                                          ),
                                        ),
                                        onPressed: () => BolaPuebloDialogs
                                            .confirmarCancelarAcuerdoBola(
                                          context: context,
                                          bolaId: bolaId,
                                          uid: user.uid,
                                        ),
                                        icon: const Icon(Icons.cancel_outlined,
                                            size: 20),
                                        label:
                                            const Text('Cancelar acuerdo'),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  if (estado == 'en_curso' && partActivo) ...[
                                    BolaPuebloDialogs
                                        .bannerSinCancelacionEnCurso(context),
                                    const SizedBox(height: 12),
                                    BolaEnCursoDestinoAcciones(
                                      bolaId: bolaId,
                                      viajeEspejoId: viajeEspejoId,
                                      soyTaxistaAsignado: soyTaxistaAsignado,
                                      soyClienteAsignado: soyClienteAsignado,
                                      user: user,
                                      uidTaxista: uidTaxista,
                                      uidCliente: uidCliente,
                                      destino: destino,
                                      origen: origen,
                                      destinoLat: dLa,
                                      destinoLon: dLo,
                                      origenLat: oLa,
                                      origenLon: oLo,
                                      confTax: confTax,
                                      confCli: confCli,
                                      codigoVerificado: codigoVerificado,
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  Theme(
                                    data: Theme.of(context).copyWith(
                                        dividerColor: Colors.transparent),
                                    child: ExpansionTile(
                                      tilePadding: EdgeInsets.zero,
                                      initiallyExpanded: false,
                                      title: Text(
                                        'Detalles del viaje',
                                        style: TextStyle(
                                            color: fg,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800),
                                      ),
                                      subtitle: Text(
                                        '$owner · $fecha',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: fgMuted, fontSize: 12),
                                      ),
                                      children: [
                                        BolaPuebloUi.metaRow(
                                          context,
                                          icon: Icons.people_outline_rounded,
                                          text: pasajeros == 1
                                              ? '1 pasajero'
                                              : '$pasajeros pasajeros',
                                        ),
                                        BolaPuebloUi.metaRow(context,
                                            icon: Icons.schedule_rounded,
                                            text: 'Salida: $fecha'),
                                        if (distanciaKm > 0)
                                          BolaPuebloUi.metaRow(
                                            context,
                                            icon: Icons.straighten_rounded,
                                            text:
                                                'Distancia estimada: ${distanciaKm.toStringAsFixed(1)} km',
                                          ),
                                        if (nota.trim().isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          BolaPuebloUi.sectionLabel(
                                              context, 'Nota'),
                                          Text(nota,
                                              style: TextStyle(
                                                  color: fgMuted,
                                                  fontSize: 13,
                                                  height: 1.4)),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
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
      },
    );
  }
}

/// Tras acordar tarifa: abre automáticamente la pantalla estándar de viaje en curso.
class _BolaEspejoPoolAutoNavListener extends StatefulWidget {
  const _BolaEspejoPoolAutoNavListener({
    required this.bolaId,
    required this.viajeEspejoId,
    required this.esClienteAsignado,
    required this.esTaxistaAsignado,
    required this.child,
  });

  final String bolaId;
  final String viajeEspejoId;
  final bool esClienteAsignado;
  final bool esTaxistaAsignado;
  final Widget child;

  @override
  State<_BolaEspejoPoolAutoNavListener> createState() =>
      _BolaEspejoPoolAutoNavListenerState();
}

class _BolaEspejoPoolAutoNavListenerState
    extends State<_BolaEspejoPoolAutoNavListener> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _espejoSub;
  String? _escuchandoViajeId;
  bool _navegacionMapaPoolEnCurso = false;

  @override
  void initState() {
    super.initState();
    _sincronizarListenerEspejo();
  }

  @override
  void didUpdateWidget(covariant _BolaEspejoPoolAutoNavListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viajeEspejoId != widget.viajeEspejoId ||
        oldWidget.esClienteAsignado != widget.esClienteAsignado ||
        oldWidget.esTaxistaAsignado != widget.esTaxistaAsignado ||
        oldWidget.bolaId != widget.bolaId) {
      _sincronizarListenerEspejo();
    }
  }

  void _sincronizarListenerEspejo() {
    final String vid = widget.viajeEspejoId.trim();
    final bool participante =
        widget.esClienteAsignado || widget.esTaxistaAsignado;
    if (!participante || vid.isEmpty || _navegacionMapaPoolEnCurso) {
      _espejoSub?.cancel();
      _espejoSub = null;
      _escuchandoViajeId = null;
      return;
    }
    if (_escuchandoViajeId == vid && _espejoSub != null) return;
    _espejoSub?.cancel();
    _escuchandoViajeId = vid;
    _espejoSub = FirebaseFirestore.instance
        .collection('viajes')
        .doc(vid)
        .snapshots()
        .listen(_onEspejoPoolSnap, onError: (_) {});
  }

  void _onEspejoPoolSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (_navegacionMapaPoolEnCurso || !mounted) return;
    if (!widget.esClienteAsignado && !widget.esTaxistaAsignado) return;
    if (!snap.exists) return;
    final Map<String, dynamic> vd = snap.data() ?? <String, dynamic>{};
    if (ViajePoolTaxistaGate.debeUsarFlujoBolaPuebloEnLugarDeViajeEnCurso(vd)) {
      return;
    }
    _navegacionMapaPoolEnCurso = true;
    _espejoSub?.cancel();
    _espejoSub = null;
    _escuchandoViajeId = null;
    final NavigatorState? preNav =
        NavigationService.navigatorKey.currentState;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _navegacionMapaPoolEnCurso = false;
        return;
      }
      unawaited(() async {
        try {
          await BolaPuebloDialogs.abrirViajeEnCursoOperativoBola(
            bolaId: widget.bolaId,
            esTaxista: widget.esTaxistaAsignado,
            preNav: preNav,
          );
        } finally {
          if (mounted) _navegacionMapaPoolEnCurso = false;
        }
      }());
    });
  }

  @override
  void dispose() {
    _espejoSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum BolaViajeTerminal { finalizada, cancelada }

/// Tras cerrar la bola: factura (si finalizada) y salida coherente al shell.
class BolaViajeTerminalPage extends StatefulWidget {
  const BolaViajeTerminalPage({
    super.key,
    required this.bolaId,
    required this.uid,
    required this.uidTaxista,
    required this.terminal,
    this.mensajeCancelacion,
  });

  final String bolaId;
  final String uid;
  final String uidTaxista;
  final BolaViajeTerminal terminal;
  final String? mensajeCancelacion;

  @override
  State<BolaViajeTerminalPage> createState() => _BolaViajeTerminalPageState();
}

class _BolaViajeTerminalPageState extends State<BolaViajeTerminalPage> {
  bool _autoComprobanteOfrecido = false;

  @override
  void initState() {
    super.initState();
    if (widget.terminal == BolaViajeTerminal.cancelada) {
      BolaNavCoordinationGuard.markCancelHandled(widget.bolaId);
    }
    if (widget.terminal == BolaViajeTerminal.finalizada) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_abrirComprobante(automatico: true));
      });
    }
  }

  String get _role =>
      widget.uid.trim() == widget.uidTaxista.trim() ? 'taxista' : 'cliente';

  /// [automatico]: una sola vez al llegar (evita choque con el listener).
  /// Manual («Ver comprobante»): siempre abre la factura.
  Future<void> _abrirComprobante({required bool automatico}) async {
    if (!mounted) return;

    if (automatico) {
      if (_autoComprobanteOfrecido) return;
      if (BolaPostFacturaReopenGuard.shouldSuppressListenerPush(
        widget.bolaId,
        role: _role,
      )) {
        return;
      }
      _autoComprobanteOfrecido = true;
      BolaPostFacturaReopenGuard.markOpened(widget.bolaId, role: _role);
    }

    try {
      await FacturaBolaPueblo.mostrar(
        context,
        bolaId: widget.bolaId,
        role: _role,
      );
      await BolaPostFacturaReopenGuard.markCompleted(
        bolaId: widget.bolaId,
        role: _role,
        uid: widget.uid,
      );
    } catch (_) {
      if (automatico && mounted) {
        _autoComprobanteOfrecido = false;
      }
    }
  }

  Future<void> _salir() async {
    if (!mounted) return;
    await NavigationService.salirModoViajeBola(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = BolaPuebloColors.of(context);
    final bool finalizada =
        widget.terminal == BolaViajeTerminal.finalizada;

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: AppBar(
        backgroundColor: c.appBarScrim,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Salir',
          onPressed: () => unawaited(_salir()),
        ),
        title: Text(etiquetaBolaAhorroUi),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                finalizada ? Icons.check_circle_outline_rounded : Icons.cancel_outlined,
                size: 56,
                color: finalizada
                    ? BolaPuebloTheme.accent
                    : Colors.red.shade300,
              ),
              const SizedBox(height: 20),
              Text(
                finalizada
                    ? 'Viaje finalizado'
                    : 'Este acuerdo fue cancelado',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                finalizada
                    ? (_role == 'taxista'
                        ? 'La bola quedó cerrada. Revisá tu comprobante y volvé a recibir viajes.'
                        : 'La bola quedó cerrada. Podés ver tu comprobante abajo.')
                    : (widget.mensajeCancelacion ??
                        'Este acuerdo fue cancelado. Ya no hay traslado activo.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.onMuted, height: 1.45),
              ),
              const SizedBox(height: 28),
              if (finalizada) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: BolaPuebloUi.filledPrimary,
                    onPressed: () =>
                        unawaited(_abrirComprobante(automatico: false)),
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: const Text('Ver comprobante'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: BolaPuebloUi.outlineAccent(context),
                  onPressed: () => unawaited(_salir()),
                  icon: const Icon(Icons.home_rounded),
                  label: Text(
                    _role == 'taxista'
                        ? 'Volver a Mi trabajo'
                        : 'Volver al inicio',
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

/// Pantalla puente: redirige al tablero (negociación abierta, no viaje operativo).
class _BolaRedirigirAlTablero extends StatefulWidget {
  const _BolaRedirigirAlTablero({required this.mensaje});

  final String mensaje;

  @override
  State<_BolaRedirigirAlTablero> createState() =>
      _BolaRedirigirAlTableroState();
}

class _BolaRedirigirAlTableroState extends State<_BolaRedirigirAlTablero> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(NavigationService.clearAndGoBolaTablero());
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = BolaPuebloColors.of(context);
    return Scaffold(
      backgroundColor: c.bgDeep,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: BolaPuebloTheme.accent),
              const SizedBox(height: 16),
              Text(
                widget.mensaje,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.onMuted, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
