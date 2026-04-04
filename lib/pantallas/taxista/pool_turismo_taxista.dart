// ignore_for_file: avoid_print, prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/pantallas/taxista/detalle_viaje.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
import 'package:flygo_nuevo/servicios/asignacion_turismo_repo.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';
import 'package:flygo_nuevo/servicios/ubicacion_taxista.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/servicios/error_reporting.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/widgets/auto_trip_router.dart';
import 'package:flygo_nuevo/widgets/empty_trips_widget.dart';
import 'package:flygo_nuevo/widgets/error_professional.dart';
import 'package:flygo_nuevo/widgets/loading_professional.dart';
import 'package:flygo_nuevo/widgets/saldo_ganancias_chip.dart';
import 'package:flygo_nuevo/widgets/taxista_drawer.dart';

extension _PoolTurismoThemeX on BuildContext {
  ({
    Color scaffoldBg,
    Color textPrimary,
    Color textSecondary,
    Color textMuted,
    Color textFaint,
    Color accent,
    Color cardBg,
    Color cardBorder,
    Color chipBg,
    Color chipBorder,
    Color chipIcon,
    Color gainColor,
    Color acceptBtnBg,
    Color onAcceptBtn,
  }) get _poolTurismoPal {
    final t = Theme.of(this);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;
    final accent = cs.tertiary;
    return (
      scaffoldBg: cs.surface,
      textPrimary: cs.onSurface,
      textSecondary: cs.onSurfaceVariant,
      textMuted: cs.onSurfaceVariant,
      textFaint: cs.onSurfaceVariant.withValues(alpha: 0.72),
      accent: accent,
      cardBg: cs.surfaceContainerHighest.withValues(
        alpha: isDark ? 0.42 : 0.78,
      ),
      cardBorder: accent.withValues(alpha: 0.45),
      chipBg: cs.surfaceContainerLow,
      chipBorder: cs.outlineVariant,
      chipIcon: accent,
      gainColor: cs.secondary,
      acceptBtnBg: cs.primary,
      onAcceptBtn: cs.onPrimary,
    );
  }
}

class _ItemPoolTurismo {
  final Viaje v;
  final Map<String, dynamic> raw;
  final DateTime fecha;
  final DateTime acceptAfter;
  final bool esAhora;
  final double distancia;

  const _ItemPoolTurismo(
    this.v,
    this.raw,
    this.fecha,
    this.acceptAfter,
    this.esAhora,
    this.distancia,
  );
}

/// Viajes turísticos con `canalAsignacion == turismo_pool` (liberados por ADM). Solo choferes aprobados.
class PoolTurismoTaxista extends StatefulWidget {
  const PoolTurismoTaxista({super.key});

  @override
  State<PoolTurismoTaxista> createState() => _PoolTurismoTaxistaState();
}

class _PoolTurismoTaxistaState extends State<PoolTurismoTaxista>
    with WidgetsBindingObserver {
  final Set<String> _aceptandoIds = <String>{};

  StreamSubscription<fs.QuerySnapshot<Map<String, dynamic>>>? _activeTripListener;

  bool _usarFallbackSinIndiceAhora = false;
  bool _usarFallbackSinIndiceProg = false;

  static const List<String> _kEstadosPend = <String>[
    EstadosViaje.pendiente,
    'pendiente_pago',
    'pendientePago',
    'pendiente_admin',
  ];

  static const double _radioBusquedaKm = 50.0;

  Position? _ubicacionCache;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    _checkExistingActiveTrip();
    Future.microtask(() async {
      await _probarIndices();
      if (mounted) setState(() {});
    });
    _cargarUbicacionCache();
  }

  Future<void> _checkExistingActiveTrip() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _activeTripListener = fs.FirebaseFirestore.instance
        .collection('viajes')
        .where('uidTaxista', isEqualTo: uid)
        .where('completado', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      if (snapshot.docs.isEmpty) return;
      final estado = snapshot.docs.first.data()['estado'] ?? '';
      if (estado != 'cancelado' && estado != 'completado') {
        _redirectToActiveTrip();
      }
    });
  }

  void _redirectToActiveTrip() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const ViajeEnCursoTaxista()),
    );
  }

  @override
  void dispose() {
    _activeTripListener?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  Future<void> _guardarUbicacionCache(Position pos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ultima_lat', pos.latitude);
    await prefs.setDouble('ultima_lon', pos.longitude);
    await prefs.setDouble(
      'ultima_timestamp',
      pos.timestamp.millisecondsSinceEpoch.toDouble(),
    );
  }

  Future<void> _cargarUbicacionCache() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble('ultima_lat');
    final lon = prefs.getDouble('ultima_lon');
    final ts = prefs.getDouble('ultima_timestamp');

    if (lat != null && lon != null && ts != null) {
      _ubicacionCache = Position(
        latitude: lat,
        longitude: lon,
        timestamp: DateTime.fromMillisecondsSinceEpoch(ts.toInt()),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      if (mounted) setState(() {});
    }
  }

  fs.Query<Map<String, dynamic>> _qTurismoPoolAhora() {
    return fs.FirebaseFirestore.instance
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
  }

  fs.Query<Map<String, dynamic>> _qTurismoPoolProgramados() {
    return fs.FirebaseFirestore.instance
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
  }

  fs.Query<Map<String, dynamic>> _qFallbackBase() {
    return fs.FirebaseFirestore.instance
        .collection('viajes')
        .orderBy('updatedAt', descending: true);
  }

  Future<void> _probarIndices() async {
    try {
      await _qTurismoPoolAhora()
          .limit(1)
          .get(const fs.GetOptions(source: fs.Source.server));
      _usarFallbackSinIndiceAhora = false;
    } on fs.FirebaseException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      _usarFallbackSinIndiceAhora =
          e.code == 'failed-precondition' || msg.contains('index');
    } catch (e, st) {
      _usarFallbackSinIndiceAhora = false;
      await ErrorReporting.reportError(
        e,
        stack: st,
        context: 'pool_turismo_taxista: _probarIndices (ahora)',
      );
    }

    try {
      await _qTurismoPoolProgramados()
          .limit(1)
          .get(const fs.GetOptions(source: fs.Source.server));
      _usarFallbackSinIndiceProg = false;
    } on fs.FirebaseException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      _usarFallbackSinIndiceProg =
          e.code == 'failed-precondition' || msg.contains('index');
    } catch (e, st) {
      _usarFallbackSinIndiceProg = false;
      await ErrorReporting.reportError(
        e,
        stack: st,
        context: 'pool_turismo_taxista: _probarIndices (programados)',
      );
    }

    if (!mounted) return;
    setState(() {});
  }

  bool _disponibleParaMiPool(Map<String, dynamic> data, String myUid) {
    final tipoServicio = (data['tipoServicio'] ?? '').toString();
    final canal = (data['canalAsignacion'] ?? '').toString();

    if (tipoServicio != 'turismo' ||
        canal != AsignacionTurismoRepo.canalTurismoPool) {
      return false;
    }

    if ((data['uidTaxista'] ?? '').toString().isNotEmpty) return false;

    final estado = (data['estado'] ?? '').toString();
    if (!_kEstadosPend.contains(estado)) return false;

    final ignorados =
        (data['ignoradosPor'] as List?)?.cast<String>() ?? const <String>[];
    if (myUid.isNotEmpty && ignorados.contains(myUid)) return false;

    final reservadoPor = (data['reservadoPor'] ?? '').toString();
    final rh = data['reservadoHasta'];
    DateTime? vence;
    if (rh is fs.Timestamp) vence = rh.toDate();
    if (rh is DateTime) vence = rh;

    final bool reservaVigente = reservadoPor.isNotEmpty &&
        (vence == null || vence.isAfter(DateTime.now()));
    if (reservaVigente) return false;

    return true;
  }

  bool _pasaFiltroAhoraLocalPool(Map<String, dynamic> d) {
    final esAhora = (d['esAhora'] == true);
    DateTime? pub, acc;

    final publishAt = d['publishAt'];
    if (publishAt is fs.Timestamp) pub = publishAt.toDate();
    if (publishAt is DateTime) pub = publishAt;

    final rawA = d['acceptAfter'];
    if (rawA is fs.Timestamp) acc = rawA.toDate();
    if (rawA is DateTime) acc = rawA;

    final now = DateTime.now();
    final tipo = (d['tipoServicio'] ?? '').toString();
    final canal = (d['canalAsignacion'] ?? '').toString();

    if (tipo != 'turismo' || canal != AsignacionTurismoRepo.canalTurismoPool) {
      return false;
    }

    return esAhora &&
        pub != null &&
        !now.isBefore(pub) &&
        (acc == null || !now.isBefore(acc));
  }

  bool _pasaFiltroProgLocalPool(Map<String, dynamic> d) {
    final esAhora = (d['esAhora'] == true);
    if (esAhora) return false;

    DateTime? pub, acc;

    final rawP = d['publishAt'];
    if (rawP is fs.Timestamp) pub = rawP.toDate();
    if (rawP is DateTime) pub = rawP;

    final rawA = d['acceptAfter'];
    if (rawA is fs.Timestamp) acc = rawA.toDate();
    if (rawA is DateTime) acc = rawA;

    final now = DateTime.now();
    final tipo = (d['tipoServicio'] ?? '').toString();
    final canal = (d['canalAsignacion'] ?? '').toString();

    if (tipo != 'turismo' || canal != AsignacionTurismoRepo.canalTurismoPool) {
      return false;
    }

    return (pub != null && !now.isBefore(pub)) &&
        (acc == null || !now.isBefore(acc));
  }

  DateTime _fechaDe(Map<String, dynamic> data) {
    final fh = data['fechaHora'];
    if (fh is fs.Timestamp) return fh.toDate();
    if (fh is DateTime) return fh;
    if (fh is String) {
      return DateTime.tryParse(fh) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime _acceptAfterDe(Map<String, dynamic> data, DateTime fecha) {
    final raw = data['acceptAfter'];
    if (raw is fs.Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) {
      final p = DateTime.tryParse(raw);
      if (p != null) return p;
    }
    return fecha.subtract(const Duration(hours: 2));
  }

  bool _calcEsAhora(DateTime fecha) =>
      !fecha.isAfter(DateTime.now().add(const Duration(minutes: 15)));

  Future<void> _aceptarViajeTurismo(
    Viaje v,
    Map<String, dynamic> raw, {
    required bool disponible,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final cs = Theme.of(context).colorScheme;
    final taxista = FirebaseAuth.instance.currentUser;

    if (taxista == null) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Debes iniciar sesión.'),
          backgroundColor: cs.error,
        ),
      );
      return;
    }
    if (!disponible) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Activa tu disponibilidad para aceptar.'),
          backgroundColor: cs.tertiaryContainer,
        ),
      );
      return;
    }
    if (_aceptandoIds.contains(v.id)) return;

    setState(() => _aceptandoIds.add(v.id));

    try {
      final prep = await AsignacionTurismoRepo.prepararClaimPoolTurismo(
        uidChofer: taxista.uid,
        viajeId: v.id,
        rawViaje: raw,
      );
      if (!prep.ok) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(AsignacionTurismoRepo.mensajeNoAutorizadoPoolTurismo),
            backgroundColor: cs.error,
          ),
        );
        return;
      }
      final datos = prep.datos!;

      await ViajesRepo.ensureTaxistaLibre(taxista.uid);
      await ViajesRepo.ensureSiguienteCoherente(taxista.uid);

      final res = await ViajesRepo.claimTripWithReason(
        viajeId: v.id,
        uidTaxista: taxista.uid,
        nombreTaxista: datos.nombreChofer,
        telefono: datos.telefonoChofer,
        placa: datos.placa,
        tipoVehiculo: datos.subtipoTurismo,
      );

      if (!mounted) return;

      if (res == 'ok') {
        await ViajesRepo.sincronizarChoferTurismoTrasAceptarDesdePool(
          uidChofer: taxista.uid,
          viajeId: v.id,
        );
        try {
          await UbicacionTaxista.marcarNoDisponible();
        } catch (e, st) {
          await ErrorReporting.reportError(
            e,
            stack: st,
            context: 'pool_turismo_taxista: marcarNoDisponible post-claim',
          );
        }
        await fs.FirebaseFirestore.instance
            .collection('usuarios')
            .doc(taxista.uid)
            .set(
          {
            'siguienteViajeId': '',
            'updatedAt': fs.FieldValue.serverTimestamp(),
            'actualizadoEn': fs.FieldValue.serverTimestamp(),
          },
          fs.SetOptions(merge: true),
        );

        messenger.showSnackBar(
          SnackBar(
            content: const Text('✅ Viaje turístico aceptado. Redirigiendo...'),
            backgroundColor: cs.primary,
          ),
        );
        _redirectToActiveTrip();
        return;
      }

      if (res == 'taxista-ocupado') {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Tienes un viaje activo. Redirigiendo...'),
            backgroundColor: cs.tertiaryContainer,
          ),
        );
        _redirectToActiveTrip();
        return;
      }

      final msg = switch (res) {
        'no-existe' => 'El viaje ya no existe.',
        'estado-no-pendiente' => 'El viaje ya no está pendiente.',
        'ya-asignado' => 'Ese viaje ya fue asignado.',
        'acceptAfter-futuro' => 'Aún no se libera (acceptAfter en el futuro).',
        'publish-futuro' => 'Aún no se publica (publishAt en el futuro).',
        'reservado-otro' => 'Reservado por otro taxista.',
        _ => res.startsWith('permiso:')
            ? 'Permisos/reglas Firestore: ${res.split(':').last}'
            : 'No se pudo aceptar: $res',
      };

      messenger.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: cs.error),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ No se pudo aceptar: $e'),
          backgroundColor: cs.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _aceptandoIds.remove(v.id));
    }
  }

  PreferredSizeWidget _poolAppBar(
    BuildContext context, {
    TabBar? bottom,
    List<Widget>? actions,
    bool useDrawerMenu = true,
  }) {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      surfaceTintColor: cs.surfaceTint,
      elevation: 0,
      scrolledUnderElevation: 1,
      leading: useDrawerMenu
          ? Builder(
              builder: (ctx) => IconButton(
                icon: Icon(Icons.menu, color: cs.onSurface),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            )
          : null,
      automaticallyImplyLeading: !useDrawerMenu,
      title: Text(
        'Pool turístico',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
      ),
      centerTitle: true,
      iconTheme: IconThemeData(color: cs.onSurface),
      bottom: bottom,
      actions: actions,
    );
  }

  Widget _bannerFallback(BuildContext context, bool usarFallback) {
    if (!usarFallback) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        'Modo sin índice: filtrando en el dispositivo. Crea el índice compuesto si Firestore lo solicita.',
        style: TextStyle(color: cs.onPrimaryContainer, fontSize: 12),
      ),
    );
  }

  Widget _bannerNoDisponible(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.tertiary.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: cs.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Activa disponibilidad para aceptar viajes del pool turístico.',
              style: TextStyle(color: cs.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  int? _pasajerosDesde(Viaje v) {
    final e = v.extras;
    if (e == null) return null;
    final p = e['pasajeros'];
    if (p is int) return p;
    if (p is num) return p.toInt();
    return int.tryParse(p?.toString() ?? '');
  }

  Widget _buildLista({
    required Stream<fs.QuerySnapshot<Map<String, dynamic>>> stream,
    required bool disponible,
    required String myUid,
    required bool Function(Map<String, dynamic>) filtroLocalSiFallback,
    required bool usandoFallback,
    required bool esTabAhora,
    required double latTaxista,
    required double lonTaxista,
  }) {
    return StreamBuilder<fs.QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingProfessional();
        }
        if (snapshot.hasError) {
          final errorMsg = snapshot.error.toString().toLowerCase();
          if (errorMsg.contains('index') ||
              errorMsg.contains('failed-precondition')) {
            return const LoadingProfessional(
              mensajePersonalizado: 'Preparando pool turístico',
            );
          }
          return ErrorProfessionalWidget(
            mensaje: 'Error al cargar viajes',
            onRetry: () => setState(() {}),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return EmptyTripsWidget(esTabAhora: esTabAhora);
        }

        final docs = snapshot.data!.docs.toList();
        final items = <_ItemPoolTurismo>[];

        for (final d in docs) {
          final data = d.data();

          if (usandoFallback && !filtroLocalSiFallback(data)) continue;
          if (!_disponibleParaMiPool(data, myUid)) continue;

          final v = Viaje.fromMap(d.id, Map<String, dynamic>.from(data));

          if (v.tipoServicio != 'turismo' ||
              v.canalAsignacion != AsignacionTurismoRepo.canalTurismoPool) {
            continue;
          }

          final fecha = _fechaDe(data);
          final acceptAfter = _acceptAfterDe(data, fecha);

          final bool esAhoraDoc = (data['esAhora'] is bool)
              ? (data['esAhora'] as bool)
              : _calcEsAhora(fecha);

          if (esTabAhora && !esAhoraDoc) continue;
          if (!esTabAhora && esAhoraDoc) continue;

          final distancia = Geolocator.distanceBetween(
                latTaxista,
                lonTaxista,
                v.latCliente,
                v.lonCliente,
              ) /
              1000;

          if (distancia > _radioBusquedaKm) continue;

          items.add(_ItemPoolTurismo(
            v,
            Map<String, dynamic>.from(data),
            fecha,
            acceptAfter,
            esAhoraDoc,
            distancia,
          ));
        }

        if (items.isEmpty) {
          return EmptyTripsWidget(esTabAhora: esTabAhora);
        }

        items.sort((a, b) => a.distancia.compareTo(b.distancia));

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (context, index) {
            final it = items[index];
            final v = it.v;
            final raw = it.raw;
            final fecha = it.fecha;
            final acceptAfter = it.acceptAfter;
            final esAhora = it.esAhora;
            final distancia = it.distancia;
            final aceptando = _aceptandoIds.contains(v.id);

            final puedeAceptar = esAhora || !DateTime.now().isBefore(acceptAfter);
            final subtipo =
                v.subtipoTurismo.isEmpty ? 'carro' : v.subtipoTurismo;
            final pax = _pasajerosDesde(v);

            final distanciaKm = DistanciaService.calcularDistancia(
              v.latCliente,
              v.lonCliente,
              v.latDestino,
              v.lonDestino,
            );
            final precioTotal = v.precio;
            final ganancia = (v.gananciaTaxista > 0)
                ? v.gananciaTaxista
                : (precioTotal * 0.80);

            final pal = context._poolTurismoPal;

            return Card(
              color: pal.cardBg,
              margin: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: pal.cardBorder,
                  width: 2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tour, color: pal.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${v.origen} → ${v.destino}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: pal.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat('EEE d MMM, HH:mm', 'es').format(fecha),
                      style: TextStyle(color: pal.textFaint, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(context, Icons.directions_car, 'Vehículo: $subtipo'),
                        if (pax != null) _chip(context, Icons.people, '$pax pasajeros'),
                        _chip(context, Icons.near_me, 'A ${distancia.toStringAsFixed(1)} km'),
                        _chip(
                          context,
                          Icons.straighten,
                          'Recorrido: ${FormatosMoneda.km(distanciaKm)}',
                        ),
                        _chip(context, Icons.payment, v.metodoPago),
                        if (!esAhora)
                          _chip(
                            context,
                            Icons.schedule,
                            'Programado ${DateFormat('dd/MM HH:mm').format(fecha)}',
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total',
                                style: TextStyle(color: pal.textMuted, fontSize: 12),
                              ),
                              Text(
                                FormatosMoneda.rd(precioTotal),
                                style: TextStyle(
                                  fontSize: 20,
                                  color: pal.accent,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Ganas',
                              style: TextStyle(color: pal.textMuted, fontSize: 12),
                            ),
                            Text(
                              FormatosMoneda.rd(ganancia),
                              style: TextStyle(
                                fontSize: 17,
                                color: pal.gainColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => DetalleViaje(viajeId: v.id),
                                ),
                              );
                            },
                            icon: Icon(Icons.info_outline, color: pal.accent),
                            label: Text(
                              'Detalles',
                              style: TextStyle(color: pal.accent),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: pal.accent),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (aceptando ||
                                    !disponible ||
                                    (!esAhora && !puedeAceptar))
                                ? null
                                : () => _aceptarViajeTurismo(
                                      v,
                                      raw,
                                      disponible: disponible,
                                    ),
                            icon: aceptando
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: pal.onAcceptBtn,
                                    ),
                                  )
                                : Icon(Icons.check_circle, color: pal.onAcceptBtn),
                            label: Text(
                              aceptando
                                  ? 'Aceptando...'
                                  : (!disponible
                                      ? 'No disponible'
                                      : (!esAhora && !puedeAceptar
                                          ? 'Espera liberación'
                                          : 'Aceptar')),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: pal.onAcceptBtn,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: pal.acceptBtnBg,
                              foregroundColor: pal.onAcceptBtn,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _chip(BuildContext context, IconData icon, String text) {
    final p = context._poolTurismoPal;
    final double maxW = (MediaQuery.sizeOf(context).width - 48).clamp(120.0, 600.0);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: p.chipBg,
          border: Border.all(color: p.chipBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: p.chipIcon),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pantallaNoAprobado() {
    final p = context._poolTurismoPal;
    return Scaffold(
      backgroundColor: p.scaffoldBg,
      drawer: const TaxistaDrawer(),
      appBar: _poolAppBar(context),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            AsignacionTurismoRepo.mensajeNoAutorizadoPoolTurismo,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContenidoPrincipal(
    BuildContext context,
    Position pos,
    User u,
  ) {
    final streamAhora = _usarFallbackSinIndiceAhora
        ? _qFallbackBase().limit(120).snapshots()
        : _qTurismoPoolAhora().limit(120).snapshots();

    final streamProg = _usarFallbackSinIndiceProg
        ? _qFallbackBase().limit(200).snapshots()
        : _qTurismoPoolProgramados().limit(200).snapshots();

    final p = context._poolTurismoPal;

    return TaxistaTripRouter(
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: p.scaffoldBg,
          drawer: const TaxistaDrawer(),
          appBar: _poolAppBar(
            context,
            actions: const [SaldoGananciasChip()],
            bottom: TabBar(
              indicatorColor: p.accent,
              labelColor: p.accent,
              unselectedLabelColor: p.textMuted,
              tabs: const [
                Tab(text: 'AHORA'),
                Tab(text: 'PROGRAMADOS'),
              ],
            ),
          ),
          body: StreamBuilder<bool>(
            stream: RolesService.streamDisponibilidad(u.uid),
            builder: (context, dispSnap) {
              final disponible = dispSnap.data ?? false;
              return Column(
                children: [
                  if (!disponible) _bannerNoDisponible(context),
                  _bannerFallback(
                    context,
                    _usarFallbackSinIndiceAhora || _usarFallbackSinIndiceProg,
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildLista(
                          stream: streamAhora,
                          disponible: disponible,
                          myUid: u.uid,
                          filtroLocalSiFallback: _pasaFiltroAhoraLocalPool,
                          usandoFallback: _usarFallbackSinIndiceAhora,
                          esTabAhora: true,
                          latTaxista: pos.latitude,
                          lonTaxista: pos.longitude,
                        ),
                        _buildLista(
                          stream: streamProg,
                          disponible: disponible,
                          myUid: u.uid,
                          filtroLocalSiFallback: _pasaFiltroProgLocalPool,
                          usandoFallback: _usarFallbackSinIndiceProg,
                          esTabAhora: false,
                          latTaxista: pos.latitude,
                          lonTaxista: pos.longitude,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;

    if (u == null) {
      final p = context._poolTurismoPal;
      return Scaffold(
        backgroundColor: p.scaffoldBg,
        appBar: _poolAppBar(context, useDrawerMenu: false),
        body: Center(
          child: Text(
            'Inicia sesión',
            style: TextStyle(color: p.textSecondary),
          ),
        ),
      );
    }

    return StreamBuilder<fs.DocumentSnapshot<Map<String, dynamic>>>(
      stream: fs.FirebaseFirestore.instance
          .collection('choferes_turismo')
          .doc(u.uid)
          .snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data();
        final aprobado = d != null && d['estado']?.toString() == 'aprobado';
        if (!aprobado) {
          return _pantallaNoAprobado();
        }

        UbicacionTaxista.iniciarActualizacion();

        return StreamBuilder<Position>(
          stream: UbicacionTaxista.obtenerStreamUbicacion().timeout(
            const Duration(seconds: 15),
            onTimeout: (EventSink<Position> sink) {
              sink.add(
                Position(
                  longitude: -69.9312,
                  latitude: 18.4861,
                  timestamp: DateTime.now(),
                  accuracy: 0,
                  altitude: 0,
                  altitudeAccuracy: 0,
                  heading: 0,
                  headingAccuracy: 0,
                  speed: 0,
                  speedAccuracy: 0,
                ),
              );
            },
          ),
          builder: (context, ubicacionSnapshot) {
            if (ubicacionSnapshot.connectionState == ConnectionState.waiting &&
                _ubicacionCache != null) {
              return _buildContenidoPrincipal(context, _ubicacionCache!, u);
            }

            if (ubicacionSnapshot.connectionState == ConnectionState.waiting) {
              final p = context._poolTurismoPal;
              return Scaffold(
                backgroundColor: p.scaffoldBg,
                drawer: const TaxistaDrawer(),
                appBar: _poolAppBar(context),
                body: const LoadingProfessional(
                  mensajePersonalizado: 'Obteniendo tu ubicación',
                ),
              );
            }

            if (ubicacionSnapshot.hasError && _ubicacionCache != null) {
              return _buildContenidoPrincipal(context, _ubicacionCache!, u);
            }

            final pos = ubicacionSnapshot.data;
            if (pos == null) {
              if (_ubicacionCache != null) {
                return _buildContenidoPrincipal(context, _ubicacionCache!, u);
              }
              final def = Position(
                longitude: -69.9312,
                latitude: 18.4861,
                timestamp: DateTime.now(),
                accuracy: 0,
                altitude: 0,
                altitudeAccuracy: 0,
                heading: 0,
                headingAccuracy: 0,
                speed: 0,
                speedAccuracy: 0,
              );
              return _buildContenidoPrincipal(context, def, u);
            }

            _guardarUbicacionCache(pos);
            return _buildContenidoPrincipal(context, pos, u);
          },
        );
      },
    );
  }
}
