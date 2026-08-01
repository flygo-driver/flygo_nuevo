// lib/pantallas/taxista/detalle_viaje.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../widgets/mapa_tiempo_real.dart';
import '../../widgets/rai_viaje_en_curso_ui.dart';
import '../../design_system/rai_ds_colors.dart';
import '../../widgets/navegacion_waze_maps_sheet.dart';
import '../../widgets/cliente_perfil_conductor_chip.dart';
import '../../pantallas/comun/bola_pueblo_actions.dart';
import '../../utils/formatos_moneda.dart';
import '../../servicios/asignacion_turismo_repo.dart';
import '../../servicios/viajes_repo.dart';
import '../../servicios/ubicacion_taxista.dart';
import '../../servicios/roles_service.dart';
import '../../servicios/pagos_taxista_repo.dart';
import '../../servicios/taxista_operacion_gate.dart';
import '../../navegacion/taxista_operacion_nav.dart';
import '../../utils/viaje_pool_taxista_gate.dart';
import '../../servicios/navegacion_externa_launcher.dart';
import '../../servicios/navigation_service.dart';
import '../../servicios/active_trip_service.dart';

class DetalleViaje extends StatefulWidget {
  final String viajeId;
  const DetalleViaje({super.key, required this.viajeId});

  @override
  State<DetalleViaje> createState() => _DetalleViajeState();
}

class _DetalleViajeState extends State<DetalleViaje> {
  bool _procesando = false;
  bool _mapaExpandido = false;

  final DraggableScrollableController _detalleNavSheetCtrl =
      DraggableScrollableController();
  static const double _kDetalleNavSheetMin = 0.14;
  static const double _kDetalleNavSheetInitial = 0.42;

  void _colapsarDetalleSheetPorMapa() {
    if (!_detalleNavSheetCtrl.isAttached) return;
    _detalleNavSheetCtrl.animateTo(
      _kDetalleNavSheetMin,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _expandirDetalleSheetTrasMapa() {
    if (!_detalleNavSheetCtrl.isAttached) return;
    _detalleNavSheetCtrl.animateTo(
      _kDetalleNavSheetInitial,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _detalleNavSheetCtrl.dispose();
    super.dispose();
  }

  /// Una sola consulta de deuda; si no, cada tick del stream del viaje reinicia el Future y el botón falla o parpadea.
  late final Future<bool> _futuroBloqueoOperativo = () {
    final u = FirebaseAuth.instance.currentUser?.uid;
    if (u == null || u.isEmpty) return Future<bool>.value(false);
    return PagosTaxistaRepo.tieneBloqueoOperativo(u);
  }();

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  DateTime _asDate(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _mostrarNavegacionRecogida(
    BuildContext context, {
    required String origen,
    required double latCliente,
    required double lonCliente,
    required bool hayCoords,
  }) {
    showNavegacionWazeMapsSheet(
      context,
      title: 'Ir al punto de recogida',
      addressLine: origen.trim().isEmpty ? null : 'Punto de recogida: $origen',
      tieneCoords: hayCoords,
      gpsCoordinatesLine: hayCoords
          ? 'GPS: ${latCliente.toStringAsFixed(5)}, ${lonCliente.toStringAsFixed(5)}'
          : null,
      showSinGpsBanner: !hayCoords,
      footerHint: 'Elige Waze o Google Maps.',
      onWaze: () {
        if (hayCoords) {
          NavegacionExternaLauncher.abrirWazeDestino(latCliente, lonCliente);
        } else {
          NavegacionExternaLauncher.abrirWazeBusqueda(origen);
        }
      },
      onMaps: () {
        if (hayCoords) {
          NavegacionExternaLauncher.abrirGoogleMapsDestino(
              latCliente, lonCliente);
        } else {
          NavegacionExternaLauncher.abrirGoogleMapsDireccion(origen);
        }
      },
    );
  }

  /// Pool turístico: solo cerrar detalle (el viaje sigue en pool para otros choferes).
  /// Pool taxi/motor: marcar [ignoradosPor] como antes.
  Future<void> _ignorarViaje(
    String viajeId, {
    required bool turismoPoolSoloCerrar,
  }) async {
    if (turismoPoolSoloCerrar) {
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }

    setState(() => _procesando = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No autenticado');

      try {
        await FirebaseFirestore.instance
            .collection('viajes')
            .doc(viajeId)
            .update({
          'ignoradosPor': FieldValue.arrayUnion([user.uid]),
        });
      } on FirebaseException catch (e) {
        final String code = e.code.toLowerCase();
        if (code == 'permission-denied' || code == 'permission_denied') {
          final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
          final resp = await fx
              .httpsCallable('ignorarViajePoolSeguro')
              .call(<String, dynamic>{
            'viajeId': viajeId,
            'idempotencyKey':
                'ignore_${viajeId}_${user.uid}_${DateTime.now().millisecondsSinceEpoch}',
          });
          final map = (resp.data is Map)
              ? Map<String, dynamic>.from(resp.data as Map)
              : <String, dynamic>{};
          if (map['ok'] != true) {
            throw Exception('No se pudo ignorar el viaje (servidor).');
          }
        } else {
          rethrow;
        }
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Viaje ignorado. No volverá a aparecer.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _aceptarViaje(String viajeId) async {
    setState(() => _procesando = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No autenticado');

      if (!await RolesService.getDisponibilidad(user.uid)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Activa tu disponibilidad en el menú (Disponibilidad) para aceptar viajes.',
            ),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        return;
      }
      if (await PagosTaxistaRepo.tieneBloqueoOperativo(user.uid)) {
        if (!mounted) return;
        await TaxistaOperacionNav.guiarTrasRecargaPrepagoOperativa(
          context,
          mensaje: PagosTaxistaRepo.mensajeRecargaTomarViajes,
        );
        return;
      }

      final usrSnap = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();
      final Map<String, dynamic> uData = usrSnap.data() ?? <String, dynamic>{};
      final String poolModo =
          ViajePoolTaxistaGate.poolModoConductorDesdeUsuario(uData);
      if (!mounted) return;
      final bool bloqueadoPerfil =
          await TaxistaOperacionNav.bloquearClaimSiPerfilIncompleto(
        context,
        uData: uData,
        poolModoConductor: poolModo,
      );
      if (bloqueadoPerfil) return;

      final doc = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .get();
      if (!doc.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El viaje ya no existe.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      final Map<String, dynamic> d = doc.data()!;

      final billeSnap = await FirebaseFirestore.instance
          .collection('billeteras_taxista')
          .doc(user.uid)
          .get();
      final String? prepagoRechazo =
          PagosTaxistaRepo.codigoRechazoPrepagoInsuficienteComisionViaje(
        billeData: billeSnap.data(),
        viajeData: d,
      );
      if (prepagoRechazo != null) {
        if (!mounted) return;
        await TaxistaOperacionNav.guiarTrasPrepagoInsuficienteComisionViaje(
          context,
          viajeId: viajeId,
          mensaje: PagosTaxistaRepo.mensajePrepagoInsuficienteComisionViaje(
            viajeData: d,
            billeData: billeSnap.data(),
          ),
        );
        return;
      }

      final String tipoServicio = (d['tipoServicio'] ?? 'normal').toString();
      final String canalAsignacion =
          (d['canalAsignacion'] ?? 'pool').toString();

      if (tipoServicio == 'turismo' && canalAsignacion == 'admin') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Este viaje de turismo lo asigna el equipo administrativo; no puedes aceptarlo desde la app.',
            ),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        return;
      }

      if (tipoServicio == 'turismo' &&
          canalAsignacion == AsignacionTurismoRepo.canalTurismoPool) {
        await ViajesRepo.ensureTaxistaLibre(user.uid);
        await ViajesRepo.ensureSiguienteCoherente(user.uid);

        final ResultadoPrepClaimPoolTurismo prep =
            await AsignacionTurismoRepo.prepararClaimPoolTurismo(
          uidChofer: user.uid,
          viajeId: viajeId,
          rawViaje: Map<String, dynamic>.from(d),
        );
        if (!prep.ok) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(prep.mensaje),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
        final DatosClaimPoolTurismo datos = prep.datos!;

        NavigatorState? rootNav;
        if (mounted) {
          rootNav = NavigationService.navigatorKey.currentState;
          rootNav ??= Navigator.of(context, rootNavigator: true);
        }
        ActiveTripService.bloquearShellTaxistaTrasAceptar(const Duration(minutes: 3));

        final String res = await ViajesRepo.claimTripWithReason(
          viajeId: viajeId,
          uidTaxista: user.uid,
          nombreTaxista: datos.nombreChofer,
          telefono: datos.telefonoChofer,
          placa: datos.placa,
          tipoVehiculo: datos.subtipoTurismo,
        );

        if (res == 'ok') {
          await ViajesRepo.sincronizarChoferTurismoTrasAceptarDesdePool(
            uidChofer: user.uid,
            viajeId: viajeId,
          );
          // No borrar siguienteViajeId: claim ya preserva cola corporativa.
          await UbicacionTaxista.marcarNoDisponible();
          await NavigationService.irAViajeEnCursoTaxistaTrasAceptar(
            viajeId: viajeId,
            uidTaxista: user.uid,
            preNav: rootNav,
          );
          return;
        }

        if (res == 'taxista-ocupado') {
          ActiveTripService.cancelarBloqueoShellTaxista();
          if (mounted) {
            await TaxistaOperacionNav.guiarTrasTaxistaOcupadoEnClaim(
              context,
              uidTaxista: user.uid,
            );
          }
          return;
        }

        if (!mounted) return;

        await TaxistaOperacionNav.guiarTrasFalloClaim(
          context,
          res: res,
          poolModoConductor: poolModo,
        );
        return;
      }

      await ViajesRepo.ensureTaxistaLibre(user.uid);
      await ViajesRepo.ensureSiguienteCoherente(user.uid);

      final res = await ViajesRepo.claimTripWithReason(
        viajeId: viajeId,
        uidTaxista: user.uid,
        nombreTaxista: user.displayName ?? user.email ?? 'taxista',
        telefono: '',
        placa: '',
      );

      if (!mounted) return;

      if (res == 'ok') {
        // No borrar siguienteViajeId: claim ya preserva cola corporativa.
        await UbicacionTaxista.marcarNoDisponible();

        if (!mounted) return;
        await NavigationService.irAViajeEnCursoTaxistaTrasAceptar(
          viajeId: viajeId,
          uidTaxista: user.uid,
        );
      } else if (res == 'taxista-ocupado') {
        if (!mounted) return;
        await TaxistaOperacionNav.guiarTrasTaxistaOcupadoEnClaim(
          context,
          uidTaxista: user.uid,
        );
      } else {
        if (!mounted) return;
        await TaxistaOperacionNav.guiarTrasFalloClaim(
          context,
          res: res,
          poolModoConductor: poolModo,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd/MM/yyyy - HH:mm');
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return Scaffold(
        backgroundColor: RaiViajeEnCursoUi.scaffoldBg,
        appBar: AppBar(
          title: const Text(
            'Detalle del viaje',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          backgroundColor: RaiViajeEnCursoUi.scaffoldBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          centerTitle: true,
        ),
        body: const Center(
          child: Text(
            'Inicia sesión.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: RaiViajeEnCursoUi.scaffoldBg,
      appBar: AppBar(
        title: const Text(
          'Detalle del viaje',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        backgroundColor: RaiViajeEnCursoUi.scaffoldBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: FutureBuilder<bool>(
        future: _futuroBloqueoOperativo,
        builder: (context, debtSnap) {
          final bloqueoDeuda = debtSnap.data ?? false;
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('usuarios')
                .doc(uid)
                .snapshots(),
            builder: (context, userSnap) {
              final userLoading =
                  userSnap.connectionState == ConnectionState.waiting &&
                      !userSnap.hasData;
              final Map<String, dynamic> ud =
                  userSnap.data?.data() ?? const <String, dynamic>{};
              final nombrePerfil = (ud['nombre'] ?? 'Usuario').toString();
              final rolPerfil = (ud['rol'] ?? 'taxista').toString();
              final disponibleUsuario =
                  RolesService.leerDisponibleDesdeUsuarioDoc(
                userSnap.data?.data(),
              );

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('viajes')
                    .doc(widget.viajeId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child:
                          CircularProgressIndicator(color: RaiDsColors.neon),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error: ${snapshot.error}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    );
                  }
                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return const Center(
                      child: Text(
                        'El viaje no existe.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    );
                  }

                  final d = snapshot.data!.data()!;

                  final origen = (d['origen'] ?? '').toString();
                  final destino = (d['destino'] ?? '').toString();
                  final latOrigen = _asDouble(d['latCliente']);
                  final lonOrigen = _asDouble(d['lonCliente']);
                  final latDestino = _asDouble(d['latDestino']);
                  final lonDestino = _asDouble(d['lonDestino']);

                  final precio = _asDouble(d['precio']);
                  final tipoServicio =
                      (d['tipoServicio'] ?? 'normal').toString();
                  final gananciaTax = _asDouble(d['gananciaTaxista']);
                  final ganancia = gananciaTax > 0
                      ? gananciaTax
                      : (tipoServicio == 'bola_ahorro'
                          ? precio * 0.9
                          : precio * 0.8);
                  final fecha = formatoFecha.format(_asDate(d['fechaHora']));
                  final metodoPago = (d['metodoPago'] ?? 'Efectivo').toString();
                  final tipoVehiculo = (d['tipoVehiculo'] ?? '').toString();
                  final marca = (d['marca'] ?? '').toString();
                  final modelo = (d['modelo'] ?? '').toString();
                  final color = (d['color'] ?? '').toString();
                  final placa = (d['placa'] ?? '').toString();
                  final idaYVuelta = (d['idaYVuelta'] ?? false) == true;

                  final String uidClienteViaje =
                      (d['uidCliente'] ?? d['clienteId'] ?? '')
                          .toString()
                          .trim();

                  final bolaPuebloId = (d['bolaPuebloId'] ?? d['bolaId'] ?? '')
                      .toString()
                      .trim();
                  final bool bolaNegociacionAbierta =
                      d['bolaNegociacionAbierta'] == true;

                  final uidTaxistaL = (d['uidTaxista'] ?? '').toString();
                  final sinTaxista = uidTaxistaL.isEmpty;
                  final turismoSoloAdmin =
                      ViajePoolTaxistaGate.esTurismoSoloAdminPendiente(d);
                  final poolModo =
                      ViajePoolTaxistaGate.poolModoConductorDesdeUsuario(ud);
                  final puedeTomarPool =
                      ViajePoolTaxistaGate.viajeTomableEnPool(
                    d,
                    uid,
                    poolModoConductor: poolModo,
                  );
                  final puedeTomarTurismoPool =
                      ViajePoolTaxistaGate.esTurismoPoolTomable(d);
                  final puedeTomar = puedeTomarPool || puedeTomarTurismoPool;

                  final bool accionesAceptarIgnorar =
                      puedeTomar && !turismoSoloAdmin;
                  final bool aceptarHabilitado = accionesAceptarIgnorar &&
                      !_procesando &&
                      disponibleUsuario &&
                      !bloqueoDeuda &&
                      !userLoading;

                  String etiquetaBotonAceptar() {
                    if (_procesando) return 'Procesando...';
                    if (userLoading) return 'Cargando perfil…';
                    if (bloqueoDeuda) return 'Recarga pendiente';
                    if (!disponibleUsuario) return 'No disponible';
                    return 'Aceptar viaje';
                  }

                  String? textoBloqueoAceptar() {
                    if (!accionesAceptarIgnorar || aceptarHabilitado) {
                      return null;
                    }
                    if (userLoading) {
                      return 'Cargando tu perfil…';
                    }
                    if (bloqueoDeuda) {
                      return PagosTaxistaRepo.mensajeRecargaTomarViajes;
                    }
                    if (!disponibleUsuario) {
                      return 'Activa tu disponibilidad en el menú (Disponibilidad) para aceptar este viaje.';
                    }
                    if (!ViajePoolTaxistaGate.viajeCoincideModoConductor(
                      d,
                      poolModo,
                    )) {
                      return poolModo == TaxistaPoolModoConductor.motor
                          ? 'Este viaje es de carro/taxi. Tu perfil es de motores.'
                          : 'Este viaje es de motores. Tu perfil es vehículo.';
                    }
                    return null;
                  }

                  final waypoints = d['waypoints'] as List<dynamic>?;
                  final bool hayOrigenMapa = latOrigen != 0 &&
                      lonOrigen != 0 &&
                      latOrigen.abs() <= 90 &&
                      lonOrigen.abs() <= 180;
                  final bool hayDestinoMapa = latDestino != 0 &&
                      lonDestino != 0 &&
                      latDestino.abs() <= 90 &&
                      lonDestino.abs() <= 180;
                  final List<LatLng> puntosRuta = <LatLng>[];
                  if (hayOrigenMapa) {
                    puntosRuta.add(LatLng(latOrigen, lonOrigen));
                  }
                  if (waypoints != null) {
                    for (final dynamic raw in waypoints) {
                      if (raw is! Map) continue;
                      final w = Map<String, dynamic>.from(raw);
                      final double la = _asDouble(w['lat']);
                      final double lo = _asDouble(w['lon']);
                      if (la != 0 &&
                          lo != 0 &&
                          la.abs() <= 90 &&
                          lo.abs() <= 180) {
                        puntosRuta.add(LatLng(la, lo));
                      }
                    }
                  }
                  if (hayDestinoMapa) {
                    puntosRuta.add(LatLng(latDestino, lonDestino));
                  }

                  final Widget filaToggleMapa = Material(
                    color: RaiViajeEnCursoUi.actionPanelBg,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: () =>
                          setState(() => _mapaExpandido = !_mapaExpandido),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: RaiDsColors.border),
                        ),
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 16),
                        child: Row(
                          children: [
                            Icon(
                              _mapaExpandido
                                  ? Icons.expand_less
                                  : Icons.map_outlined,
                              color: RaiDsColors.neon,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _mapaExpandido
                                    ? 'Ocultar mapa'
                                    : 'Mostrar mapa (toca para desplegar)',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );

                  final List<Widget> detalleCuerpoViaje = <Widget>[
                    if (sinTaxista &&
                        !puedeTomarTurismoPool &&
                        !ViajePoolTaxistaGate.viajeCoincideModoConductor(
                          d,
                          poolModo,
                        ))
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orangeAccent.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Colors.orangeAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                poolModo == TaxistaPoolModoConductor.motor
                                    ? 'Este viaje es de carro/taxi. Tu perfil registrado es de motores.'
                                    : 'Este viaje es de motores. Tu perfil registrado es vehículo.',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: RaiViajeEnCursoUi.panelDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.circle,
                                  color: Colors.blueAccent, size: 12),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Origen: $origen',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                          if (waypoints != null && waypoints.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Divider(color: Colors.white24, height: 1),
                            const SizedBox(height: 8),
                            const Text(
                              '📍 Paradas intermedias:',
                              style: TextStyle(
                                  color: Colors.blueAccent,
                                  fontWeight: FontWeight.bold),
                            ),
                            ...waypoints.asMap().entries.map((entry) {
                              final int i = entry.key + 1;
                              final Map<String, dynamic> w =
                                  entry.value as Map<String, dynamic>;
                              final String label =
                                  w['label']?.toString() ?? 'Parada $i';
                              return Padding(
                                padding:
                                    const EdgeInsets.only(left: 16, top: 6),
                                child: Row(
                                  children: [
                                    const Icon(Icons.flag_circle,
                                        color: Colors.orange, size: 14),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Parada $i: $label',
                                        style: const TextStyle(
                                            color: Colors.white70),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.flag,
                                  color: Colors.greenAccent, size: 12),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Destino: $destino',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                          if (origen.trim().isNotEmpty || hayOrigenMapa) ...[
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _mostrarNavegacionRecogida(
                                  context,
                                  origen: origen,
                                  latCliente: latOrigen,
                                  lonCliente: lonOrigen,
                                  hayCoords: hayOrigenMapa,
                                ),
                                icon: const Icon(Icons.navigation,
                                    color: Colors.greenAccent),
                                label: const Text('Navegar al recogida'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.greenAccent,
                                  side: const BorderSide(
                                      color: Colors.greenAccent),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (uidClienteViaje.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ClientePerfilConductorChip(
                            uidCliente: uidClienteViaje),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        FormatosMoneda.rd(precio),
                        style: const TextStyle(
                          fontSize: 40,
                          color: RaiDsColors.neon,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Ganas: ${FormatosMoneda.rd(ganancia)}',
                        style: const TextStyle(
                          fontSize: 18,
                          color: RaiDsColors.neonSoft,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip('📅 $fecha'),
                        _chip('💳 $metodoPago'),
                        if (tipoServicio != 'normal') _chip('🚗 $tipoServicio'),
                        if (tipoVehiculo.isNotEmpty) _chip('🚘 $tipoVehiculo'),
                        if (marca.isNotEmpty && modelo.isNotEmpty)
                          _chip('$marca $modelo'),
                        if (color.isNotEmpty) _chip('🎨 $color'),
                        if (placa.isNotEmpty) _chip('🔖 $placa'),
                        if (idaYVuelta) _chip('🔄 Ida y vuelta'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (bolaPuebloId.isNotEmpty && bolaNegociacionAbierta) ...[
                      _BolaNegociacionDetallePool(
                        bolaId: bolaPuebloId,
                        uid: uid,
                        nombre: nombrePerfil,
                        rol: rolPerfil,
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (!puedeTomar && !turismoSoloAdmin)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          sinTaxista
                              ? (bolaNegociacionAbierta &&
                                      bolaPuebloId.isNotEmpty
                                  ? 'Precio por Ahorra: el cliente acepta una oferta en el tablero; '
                                      'acá ves el trayecto y podés proponer monto abajo. No uses «Aceptar viaje».'
                                  : 'Este viaje no está disponible para aceptar en este momento.')
                              : 'Este viaje ya tiene chofer asignado o está cerrado.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13),
                        ),
                      )
                    else if (turismoSoloAdmin)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.45),
                          ),
                        ),
                        child: const Text(
                          'Turismo (administración): un administrador asignará el chofer. '
                          'Cuando un viaje pase al pool turístico, podrás tomarlo desde «Pool turístico».',
                          style: TextStyle(color: Colors.white70, height: 1.35),
                        ),
                      )
                    else ...[
                      if (textoBloqueoAceptar() != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            textoBloqueoAceptar()!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 13),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _procesando
                                  ? null
                                  : () => _ignorarViaje(
                                        widget.viajeId,
                                        turismoPoolSoloCerrar:
                                            puedeTomarTurismoPool,
                                      ),
                              icon: _procesando
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.not_interested,
                                      color: Colors.redAccent),
                              label: Text(
                                _procesando
                                    ? 'Procesando...'
                                    : 'No me interesa',
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.redAccent),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: (aceptarHabilitado)
                                  ? () => _aceptarViaje(widget.viajeId)
                                  : null,
                              icon: _procesando
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check_circle,
                                      color: Colors.black),
                              label: Text(
                                etiquetaBotonAceptar(),
                                style: TextStyle(
                                  color: aceptarHabilitado
                                      ? Colors.black
                                      : RaiDsColors.textMuted,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: RaiDsColors.neon,
                                disabledBackgroundColor:
                                    RaiDsColors.neon.withValues(alpha: 0.25),
                                foregroundColor: Colors.black,
                                disabledForegroundColor: RaiDsColors.textMuted,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ];

                  if (!_mapaExpandido) {
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        filaToggleMapa,
                        const SizedBox(height: 16),
                        ...detalleCuerpoViaje,
                      ],
                    );
                  }

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: MapaTiempoReal(
                            key: ValueKey<String>(
                                'detalle_map_${widget.viajeId}'),
                            origen: hayOrigenMapa
                                ? LatLng(latOrigen, lonOrigen)
                                : null,
                            origenNombre: origen,
                            destino: hayDestinoMapa
                                ? LatLng(latDestino, lonDestino)
                                : null,
                            destinoNombre: destino,
                            mostrarOrigen: hayOrigenMapa,
                            mostrarDestino: hayDestinoMapa,
                            esTaxista: true,
                            esCliente: false,
                            polylinePreviewPoints:
                                puntosRuta.length >= 2 ? puntosRuta : null,
                            onUserInteractWithMap: _colapsarDetalleSheetPorMapa,
                            onUserMapGestureEnd: _expandirDetalleSheetTrasMapa,
                          ),
                        ),
                      ),
                      DraggableScrollableSheet(
                        controller: _detalleNavSheetCtrl,
                        minChildSize: _kDetalleNavSheetMin,
                        maxChildSize: 0.94,
                        initialChildSize: _kDetalleNavSheetInitial,
                        snap: true,
                        snapSizes: const <double>[
                          _kDetalleNavSheetMin,
                          0.35,
                          _kDetalleNavSheetInitial,
                          0.65,
                          0.94,
                        ],
                        builder: (sheetCtx, scrollController) {
                          return Container(
                            decoration: RaiViajeEnCursoUi.sheetDecoration(),
                            child: ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              children: <Widget>[
                                Center(
                                  child: Container(
                                    width: 40,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: RaiDsColors.border,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                filaToggleMapa,
                                const SizedBox(height: 12),
                                ...detalleCuerpoViaje,
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: RaiDsColors.cardElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RaiDsColors.border),
      ),
      child: Text(
        text,
        style: const TextStyle(color: RaiDsColors.textMuted, fontSize: 12.5),
      ),
    );
  }
}

/// Panel de ofertas enlazado a `bolas_pueblo` cuando el viaje del pool es espejo de una bola (pedido).
class _BolaNegociacionDetallePool extends StatelessWidget {
  const _BolaNegociacionDetallePool({
    required this.bolaId,
    required this.uid,
    required this.nombre,
    required this.rol,
  });

  final String bolaId;
  final String uid;
  final String nombre;
  final String rol;

  @override
  Widget build(BuildContext context) {
    final bool esTaxista = rol == 'taxista' || rol == 'driver';
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('bolas_pueblo')
          .doc(bolaId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: CircularProgressIndicator(color: RaiDsColors.neon),
            ),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'No se pudo cargar el tablero Bola: ${snap.error}',
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
            ),
          );
        }
        if (!snap.hasData || !snap.data!.exists) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Publicación no encontrada. Abrí Ahorra desde el menú.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          );
        }
        final bd = snap.data!.data() ?? {};
        final estado = (bd['estado'] ?? '').toString();
        final ownerUid = (bd['createdByUid'] ?? '').toString();
        final monto = ((bd['montoSugeridoRd'] ?? 0) as num).toDouble();
        final tarifaBaseBolaRd =
            ((bd['tarifaBaseBolaRd'] ?? monto) as num).toDouble();
        final ofertaMinRd = ((bd['ofertaMinRd'] ?? 0) as num).toDouble();
        final ofertaMaxRd = ((bd['ofertaMaxRd'] ?? 0) as num).toDouble();
        final tarifaNormalRd = ((bd['tarifaNormalRd'] ?? 0) as num).toDouble();
        final double montoSemillaOferta = monto > 0
            ? monto
            : (ofertaMinRd > 0 && ofertaMaxRd >= ofertaMinRd
                ? ((ofertaMinRd + ofertaMaxRd) / 2)
                    .clamp(ofertaMinRd, ofertaMaxRd)
                : (tarifaBaseBolaRd > 0
                    ? tarifaBaseBolaRd
                    : (tarifaNormalRd > 0 ? tarifaNormalRd : monto)));

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: RaiDsColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: RaiDsColors.purple.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (estado == 'abierta' && ownerUid.isNotEmpty && ownerUid != uid)
                BolaPuebloOfertaDescartadaListener(
                  bolaId: bolaId,
                  miUid: uid,
                  activo: true,
                ),
              Row(
                children: [
                  Icon(Icons.savings_outlined,
                      color: RaiDsColors.purple, size: 22),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ahorra (tiempo real)',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                estado == 'abierta'
                    ? 'Las ofertas se guardan en el tablero; el cliente las ve al instante en «Ver ofertas y aceptar».'
                    : 'Estado en tablero: $estado. Los detalles del traslado siguen en Ahorra.',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.35),
              ),
              if (estado == 'abierta' &&
                  esTaxista &&
                  ownerUid.isNotEmpty &&
                  ownerUid != uid) ...[
                const SizedBox(height: 14),
                Text(
                  'Rango: RD\$${ofertaMinRd.toStringAsFixed(0)} – RD\$${ofertaMaxRd.toStringAsFixed(0)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: RaiDsColors.neon,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => BolaPuebloDialogs.enviarOferta(
                    context: context,
                    bolaId: bolaId,
                    uid: uid,
                    nombre: nombre,
                    rol: rol,
                    montoInicial: montoSemillaOferta,
                  ),
                  child: Text(
                    monto > 0
                        ? 'Misma cifra referencia · RD\$${monto.toStringAsFixed(0)}'
                        : 'Enviar propuesta · RD\$${montoSemillaOferta.toStringAsFixed(0)}',
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.tealAccent.shade700,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => BolaPuebloDialogs.enviarOferta(
                    context: context,
                    bolaId: bolaId,
                    uid: uid,
                    nombre: nombre,
                    rol: rol,
                    montoInicial: ofertaMaxRd,
                  ),
                  child: Text(
                      'Tope permitido · RD\$${ofertaMaxRd.toStringAsFixed(0)}'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.greenAccent),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => BolaPuebloDialogs.enviarOferta(
                    context: context,
                    bolaId: bolaId,
                    uid: uid,
                    nombre: nombre,
                    rol: rol,
                    montoInicial: montoSemillaOferta,
                  ),
                  child: const Text('Proponer otro monto'),
                ),
              ] else if (estado == 'abierta' && !esTaxista) ...[
                const SizedBox(height: 10),
                const Text(
                  'Solo conductores envían ofertas en pedidos Bola.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ] else if (estado == 'abierta' && ownerUid == uid) ...[
                const SizedBox(height: 10),
                const Text(
                  'Sos quien publicó: revisá ofertas en la pantalla Ahorra.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
