// ignore_for_file: avoid_print, prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/pantallas/taxista/detalle_viaje.dart';
import 'package:flygo_nuevo/servicios/asignacion_turismo_repo.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/servicios/notification_service.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';
import 'package:flygo_nuevo/servicios/ubicacion_taxista.dart';
import 'package:flygo_nuevo/navegacion/taxista_operacion_nav.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/servicios/taxista_operacion_gate.dart';
import 'package:flygo_nuevo/navegacion/taxista_finanzas_nav.dart';
import 'package:flygo_nuevo/servicios/gps_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';
import 'package:flygo_nuevo/servicios/error_reporting.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/hora_am_pm.dart';
import 'package:flygo_nuevo/utils/trip_publish_windows.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/widgets/auto_trip_router.dart';
import 'package:flygo_nuevo/widgets/empty_trips_widget.dart';
import 'package:flygo_nuevo/widgets/error_professional.dart';
import 'package:flygo_nuevo/widgets/loading_professional.dart';
import 'package:flygo_nuevo/widgets/saldo_ganancias_chip.dart';

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

class _OfertaTurismoPendiente {
  const _OfertaTurismoPendiente({
    required this.id,
    required this.data,
    required this.titulo,
    required this.cuerpo,
  });

  final String id;
  final Map<String, dynamic> data;
  final String titulo;
  final String cuerpo;
}

/// Viajes turísticos con `canalAsignacion == turismo_pool` (liberados por ADM). Solo choferes aprobados.
class PoolTurismoTaxista extends StatefulWidget {
  const PoolTurismoTaxista({super.key});

  @override
  State<PoolTurismoTaxista> createState() => _PoolTurismoTaxistaState();
}

class _PoolTurismoTaxistaState extends State<PoolTurismoTaxista>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final Set<String> _aceptandoIds = <String>{};
  final Set<String> _vistosParaTimbre = <String>{};
  final Set<String> _ocultosPoolLocal = <String>{};

  StreamSubscription<fs.QuerySnapshot<Map<String, dynamic>>>? _subTimbreAhora;
  StreamSubscription<fs.QuerySnapshot<Map<String, dynamic>>>? _subTimbreProg;
  fs.QuerySnapshot<Map<String, dynamic>>? _snapTimbreAhora;
  fs.QuerySnapshot<Map<String, dynamic>>? _snapTimbreProg;

  Stream<fs.QuerySnapshot<Map<String, dynamic>>>? _streamPoolAhora;
  Stream<fs.QuerySnapshot<Map<String, dynamic>>>? _streamPoolProg;
  bool _streamPoolAhoraFallback = false;
  bool _streamPoolProgFallback = false;

  late TabController _tabPool;
  bool _ignorarPrimeraEmisionTimbreAhora = true;
  bool _ignorarPrimeraEmisionTimbreProg = true;
  bool _entradaInicialProcesada = false;
  bool _appEnForeground = true;
  bool _flushTimbreReentradaPendiente = false;

  StreamSubscription<fs.QuerySnapshot<Map<String, dynamic>>>?
      _activeTripListener;

  bool _usarFallbackSinIndiceAhora = false;
  bool _usarFallbackSinIndiceProg = false;
  Timer? _reintentoIndiceTimer;

  static const List<String> _kEstadosPend = <String>[
    EstadosViaje.pendiente,
    'pendiente_pago',
    'pendientePago',
    'pendiente_admin',
  ];

  static const double _radioBusquedaKm = 50.0;

  Position? _ubicacionCache;
  bool _navegandoAViajeActivo = false;
  bool? _gpsServicioActivo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabPool = TabController(length: 2, vsync: this);
    _tabPool.addListener(_onPoolTabChanged);
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    _checkExistingActiveTrip();
    Future.microtask(() async {
      await NotificationService.I.ensureInited();
      await _probarIndices();
      _arrancarTimbres();
      if (mounted) setState(() {});
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) await _flushTimbreOfertasParaTab(_tabPool.index);
    });
    _cargarUbicacionCache();
    unawaited(_refrescarEstadoGps());
  }

  void _onPoolTabChanged() {
    if (_tabPool.indexIsChanging || !mounted) return;
    unawaited(_flushTimbreOfertasParaTab(_tabPool.index));
  }

  Future<void> _refrescarEstadoGps() async {
    final snap = await GpsService.readServiceAndPermissionStabilizedNoRequest();
    if (!mounted) return;
    setState(() => _gpsServicioActivo = snap.serviceEnabled);
  }

  Future<void> _reconciliarViajeActivoAlResume() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !mounted) return;
    try {
      final uDoc = await fs.FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();
      final vid = (uDoc.data()?['viajeActivoId'] ?? '').toString().trim();
      if (vid.isEmpty) return;
      final vSnap = await fs.FirebaseFirestore.instance
          .collection('viajes')
          .doc(vid)
          .get();
      if (!vSnap.exists || !mounted) return;
      final data = vSnap.data() ?? <String, dynamic>{};
      if (data['completado'] == true) return;
      final estado = (data['estado'] ?? '').toString();
      if (estado == 'cancelado' || estado == 'completado') return;
      if ((data['uidTaxista'] ?? '').toString() != uid) return;
      if (ViajePoolTaxistaGate.debeUsarFlujoBolaPuebloEnLugarDeViajeEnCurso(data)) {
        return;
      }
      _navegandoAViajeActivo = false;
      _redirectToActiveTrip();
    } catch (e, st) {
      print('[TURISMO_POOL] resume reconcile error $e $st');
    }
  }

  Widget _pantallaUbicacionRequerida() {
    final p = context._poolTurismoPal;
    return Scaffold(
      backgroundColor: p.scaffoldBg,
      appBar: _poolAppBar(context),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_off_rounded, size: 56, color: p.textSecondary),
              const SizedBox(height: 16),
              Text(
                'Activa el GPS para ver viajes turísticos cerca de ti',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Sin ubicación real no podemos mostrar el pool con precisión. '
                'Actívalo y vuelve a esta pantalla.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textSecondary, height: 1.45),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () async {
                  await Geolocator.openLocationSettings();
                },
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Abrir ajustes de ubicación'),
              ),
              if (_ubicacionCache != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    setState(() => _gpsServicioActivo = true);
                  },
                  child: const Text('Usar última ubicación conocida'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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

  Future<void> _redirectToActiveTrip({NavigatorState? preNav}) async {
    if (!mounted || _navegandoAViajeActivo) return;
    _navegandoAViajeActivo = true;
    NavigatorState? nav = preNav ?? NavigationService.navigatorKey.currentState;
    if (nav == null) {
      if (!mounted) return;
      nav = Navigator.of(context, rootNavigator: true);
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final uidDoc = await fs.FirebaseFirestore.instance
            .collection('usuarios')
            .doc(uid)
            .get();
        final vid = (uidDoc.data()?['viajeActivoId'] ?? '').toString().trim();
        if (vid.isNotEmpty) {
          final vs = await fs.FirebaseFirestore.instance
              .collection('viajes')
              .doc(vid)
              .get();
          final d = vs.data();
          if (d != null &&
              ViajePoolTaxistaGate.debeUsarFlujoBolaPuebloEnLugarDeViajeEnCurso(
                  d)) {
            _navegandoAViajeActivo = false;
            return;
          }
        }
      } catch (_) {}
    }
    await NavigationService.clearAndGoViajeEnCursoTaxista(preNav: nav);
  }

  /// Si el claim falló por permisos pero el viaje ya quedó asignado en servidor.
  Future<bool> _confirmarAsignacionYRedirigir({
    required String viajeId,
    required String uidTaxista,
    NavigatorState? preNav,
  }) async {
    try {
      final snap = await fs.FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .get(const fs.GetOptions(source: fs.Source.server));
      if (!snap.exists) return false;
      final d = snap.data() ?? <String, dynamic>{};
      final String uidTx = (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString();
      final String estado = (d['estado'] ?? '').toString();
      final bool activo = d['activo'] == true;
      final bool estadoActivo = estado == 'aceptado' ||
          estado == 'en_camino_pickup' ||
          estado == 'enCaminoPickup' ||
          estado == 'a_bordo' ||
          estado == 'aBordo' ||
          estado == 'en_curso' ||
          estado == 'enCurso';
      if (uidTx == uidTaxista && (activo || estadoActivo)) {
        await fs.FirebaseFirestore.instance
            .collection('usuarios')
            .doc(uidTaxista)
            .set({
          'viajeActivoId': viajeId,
          'updatedAt': fs.FieldValue.serverTimestamp(),
          'actualizadoEn': fs.FieldValue.serverTimestamp(),
        }, fs.SetOptions(merge: true));
        _navegandoAViajeActivo = true;
        ActiveTripService.bloquearShellTaxistaTrasAceptar(const Duration(minutes: 3));
        final NavigatorState? nav = preNav ??
            NavigationService.navigatorKey.currentState ??
            (mounted ? Navigator.of(context, rootNavigator: true) : null);
        await NavigationService.irAViajeEnCursoTaxistaTrasAceptar(
          viajeId: viajeId,
          uidTaxista: uidTaxista,
          preNav: nav,
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _reintentoIndiceTimer?.cancel();
    _subTimbreAhora?.cancel();
    _subTimbreProg?.cancel();
    _tabPool.removeListener(_onPoolTabChanged);
    _tabPool.dispose();
    _activeTripListener?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _programarReintentoIndicesSiFalta() {
    if (!_usarFallbackSinIndiceAhora && !_usarFallbackSinIndiceProg) {
      _reintentoIndiceTimer?.cancel();
      _reintentoIndiceTimer = null;
      return;
    }
    _reintentoIndiceTimer ??= Timer.periodic(const Duration(minutes: 2), (_) {
      if (!mounted) return;
      unawaited(_probarIndices());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appEnForeground = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_refrescarEstadoGps());
      unawaited(_reconciliarViajeActivoAlResume());
      _arrancarTimbres();
      if (_usarFallbackSinIndiceAhora || _usarFallbackSinIndiceProg) {
        unawaited(_probarIndices());
      }
      unawaited(Future<void>.delayed(const Duration(milliseconds: 700), () async {
        if (!mounted) return;
        await _flushTimbreOfertasParaTab(_tabPool.index);
      }));
      setState(() {});
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(NotificationService.I.stopTimbre());
    }
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
    _programarReintentoIndicesSiFalta();
    _arrancarTimbres();
  }

  void _asegurarStreamsPoolUi() {
    if (_streamPoolAhora == null ||
        _streamPoolAhoraFallback != _usarFallbackSinIndiceAhora) {
      _streamPoolAhoraFallback = _usarFallbackSinIndiceAhora;
      final fs.Query<Map<String, dynamic>> q = _usarFallbackSinIndiceAhora
          ? _qFallbackBase()
          : _qTurismoPoolAhora();
      _streamPoolAhora = q.limit(120).snapshots();
    }
    if (_streamPoolProg == null ||
        _streamPoolProgFallback != _usarFallbackSinIndiceProg) {
      _streamPoolProgFallback = _usarFallbackSinIndiceProg;
      final fs.Query<Map<String, dynamic>> q = _usarFallbackSinIndiceProg
          ? _qFallbackBase()
          : _qTurismoPoolProgramados();
      _streamPoolProg = q.limit(200).snapshots();
    }
  }

  void _refrescarListaPoolUi() {
    if (!mounted) return;
    setState(() {});
  }

  void _arrancarTimbres() {
    _asegurarStreamsPoolUi();
    _subTimbreAhora?.cancel();
    _subTimbreProg?.cancel();
    _ignorarPrimeraEmisionTimbreAhora = true;
    _ignorarPrimeraEmisionTimbreProg = true;
    _flushTimbreReentradaPendiente = _entradaInicialProcesada;

    final qA = _usarFallbackSinIndiceAhora ? _qFallbackBase() : _qTurismoPoolAhora();
    final qP =
        _usarFallbackSinIndiceProg ? _qFallbackBase() : _qTurismoPoolProgramados();

    _subTimbreAhora = qA.limit(120).snapshots().listen((snap) async {
      _snapTimbreAhora = snap;
      _refrescarListaPoolUi();
      if (!_appEnForeground) return;
      final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

      if (_ignorarPrimeraEmisionTimbreAhora) {
        _ignorarPrimeraEmisionTimbreAhora = false;
        if (_entradaInicialProcesada) {
          unawaited(_maybeFlushTrasReconexionTimbre(myUid));
        } else {
          unawaited(_intentarEntradaInicialPool());
        }
        return;
      }

      final nuevas = _idsOfertasNoVistasAhora(myUid);
      await _procesarNuevasOfertasEnTabActivo(0, myUid, nuevas);
    });

    _subTimbreProg = qP.limit(200).snapshots().listen((snap) async {
      _snapTimbreProg = snap;
      _refrescarListaPoolUi();
      if (!_appEnForeground) return;
      final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

      if (_ignorarPrimeraEmisionTimbreProg) {
        _ignorarPrimeraEmisionTimbreProg = false;
        if (_entradaInicialProcesada) {
          unawaited(_maybeFlushTrasReconexionTimbre(myUid));
        } else {
          unawaited(_intentarEntradaInicialPool());
        }
        return;
      }

      final nuevas = _idsOfertasNoVistasProg(myUid);
      await _procesarNuevasOfertasEnTabActivo(1, myUid, nuevas);
    });
  }

  bool _timbreViajeNoIgnorado(Map<String, dynamic> data, String myUid) {
    final ign = data['ignoradosPor'];
    if (ign is List && ign.contains(myUid)) return false;
    return true;
  }

  bool _timbreMeInteresaTurismoPool(Map<String, dynamic> data, String myUid) {
    if (!_timbreViajeNoIgnorado(data, myUid)) return false;
    return ViajePoolTaxistaGate.esTurismoPoolTomable(data);
  }

  bool _viajeTienePrecioReal(Map<String, dynamic> data) {
    final dynamic pc = data['precio_cents'];
    if (pc is int && pc > 0) return true;
    if (pc is num && pc > 0) return true;
    double n(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().trim().replaceAll(',', '.')) ?? 0;
    }

    return n(data['precio']) > 0.009 || n(data['precioFinal'] ?? data['total']) > 0.009;
  }

  Future<void> _flushTimbreOfertasParaTab(int tabIndex) async {
    if (!_appEnForeground) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (myUid.isNotEmpty && !await RolesService.getDisponibilidad(myUid)) {
      return;
    }
    final pendientes = _idsOfertasNoVistasEnTab(tabIndex, myUid);
    if (pendientes.isEmpty) return;

    await NotificationService.I.playPoolOfferSoundInApp();
    for (final item in pendientes) {
      _vistosParaTimbre.add(item.id);
      if (_viajeTienePrecioReal(item.data)) {
        await NotificationService.I.notifyNuevoViaje(
          viajeId: item.id,
          titulo: item.titulo,
          cuerpo: item.cuerpo,
          skipSound: true,
        );
      }
    }
  }

  Future<void> _flushTimbreOfertasAlReentrarPool(String myUid) async {
    if (!_appEnForeground) return;
    if (myUid.isNotEmpty && !await RolesService.getDisponibilidad(myUid)) {
      return;
    }
    final pendientes =
        _idsOfertasNoVistasEnTab(_tabPool.index, myUid);
    if (pendientes.isEmpty) return;

    await NotificationService.I.playPoolOfferSoundInApp();
    for (final item in pendientes) {
      _vistosParaTimbre.add(item.id);
      if (_viajeTienePrecioReal(item.data)) {
        await NotificationService.I.notifyNuevoViaje(
          viajeId: item.id,
          titulo: item.titulo,
          cuerpo: item.cuerpo,
          skipSound: true,
        );
      }
    }
  }

  Future<void> _maybeFlushTrasReconexionTimbre(String myUid) async {
    if (!_flushTimbreReentradaPendiente) return;
    if (_ignorarPrimeraEmisionTimbreAhora || _ignorarPrimeraEmisionTimbreProg) {
      return;
    }
    _flushTimbreReentradaPendiente = false;
    await _flushTimbreOfertasAlReentrarPool(myUid);
  }

  Future<void> _intentarEntradaInicialPool() async {
    if (_entradaInicialProcesada || !_appEnForeground) return;
    if (_ignorarPrimeraEmisionTimbreAhora || _ignorarPrimeraEmisionTimbreProg) {
      return;
    }
    await _procesarEntradaInicialPool();
  }

  Future<void> _procesarEntradaInicialPool() async {
    if (_entradaInicialProcesada || !_appEnForeground) return;
    _entradaInicialProcesada = true;

    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final pendientes =
        _idsOfertasNoVistasEnTab(_tabPool.index, myUid);

    final bool disponible = myUid.isEmpty ||
        await RolesService.getDisponibilidad(myUid);

    if (pendientes.isNotEmpty && disponible) {
      await NotificationService.I.playPoolOfferSoundInApp();
    }

    for (final item in pendientes) {
      _vistosParaTimbre.add(item.id);
      if (_viajeTienePrecioReal(item.data)) {
        await NotificationService.I.notifyNuevoViaje(
          viajeId: item.id,
          titulo: item.titulo,
          cuerpo: item.cuerpo,
          skipSound: true,
        );
      }
    }
  }

  Future<void> _procesarNuevasOfertasEnTabActivo(
    int tabIndex,
    String myUid,
    List<_OfertaTurismoPendiente> nuevas,
  ) async {
    if (!_entradaInicialProcesada || !_appEnForeground) return;
    if (_tabPool.index != tabIndex) return;
    if (nuevas.isEmpty) return;
    if (myUid.isNotEmpty && !await RolesService.getDisponibilidad(myUid)) {
      return;
    }

    final List<_OfertaTurismoPendiente> fresh = nuevas
        .where((item) => !_vistosParaTimbre.contains(item.id))
        .toList();
    if (fresh.isEmpty) return;

    await NotificationService.I.playPoolOfferSoundInApp();

    for (final item in fresh) {
      _vistosParaTimbre.add(item.id);
      await NotificationService.I.vibratePoolOfferInApp();
      if (_viajeTienePrecioReal(item.data)) {
        await NotificationService.I.notifyNuevoViaje(
          viajeId: item.id,
          titulo: item.titulo,
          cuerpo: item.cuerpo,
          skipSound: true,
        );
      }
    }
  }

  List<_OfertaTurismoPendiente> _idsOfertasNoVistasEnTab(
    int tabIndex,
    String myUid,
  ) {
    if (tabIndex == 0) return _idsOfertasNoVistasAhora(myUid);
    if (tabIndex == 1) return _idsOfertasNoVistasProg(myUid);
    return const <_OfertaTurismoPendiente>[];
  }

  List<_OfertaTurismoPendiente> _idsOfertasNoVistasAhora(String myUid) {
    final snap = _snapTimbreAhora;
    if (snap == null) return const <_OfertaTurismoPendiente>[];
    final out = <_OfertaTurismoPendiente>[];
    for (final d in snap.docs) {
      final data = d.data();
      if (!_pasaFiltroAhoraLocalPool(data)) continue;
      if (!_timbreMeInteresaTurismoPool(data, myUid)) continue;
      if (_vistosParaTimbre.contains(d.id)) continue;
      out.add(
        _OfertaTurismoPendiente(
          id: d.id,
          data: data,
          titulo: 'Nuevo viaje turístico',
          cuerpo:
              '${(data['origen'] ?? 'Origen')} → ${(data['destino'] ?? 'Destino')}',
        ),
      );
    }
    return out;
  }

  List<_OfertaTurismoPendiente> _idsOfertasNoVistasProg(String myUid) {
    final snap = _snapTimbreProg;
    if (snap == null) return const <_OfertaTurismoPendiente>[];
    final out = <_OfertaTurismoPendiente>[];
    for (final d in snap.docs) {
      final data = d.data();
      if (!_pasaFiltroProgLocalPool(data)) continue;
      if (!_timbreMeInteresaTurismoPool(data, myUid)) continue;
      if (_vistosParaTimbre.contains(d.id)) continue;
      out.add(
        _OfertaTurismoPendiente(
          id: d.id,
          data: data,
          titulo: 'Viaje turístico programado',
          cuerpo:
              '${(data['origen'] ?? 'Origen')} → ${(data['destino'] ?? 'Destino')}',
        ),
      );
    }
    return out;
  }

  bool _disponibleParaMiPool(Map<String, dynamic> data, String myUid) {
    if (!_timbreViajeNoIgnorado(data, myUid)) return false;
    return ViajePoolTaxistaGate.esTurismoPoolTomable(data);
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
    if (!ViajePoolTaxistaGate.esTurismoPoolTomable(d)) return false;

    final bool publishOk = (pub == null) || !now.isBefore(pub);
    final bool acceptOk = (acc == null) || !now.isBefore(acc);
    return esAhora && publishOk && acceptOk;
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
    if (!ViajePoolTaxistaGate.esTurismoPoolTomable(d)) return false;

    final bool publishOk = (pub == null) || !now.isBefore(pub);
    final bool acceptOk = (acc == null) || !now.isBefore(acc);
    return publishOk && acceptOk;
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
    return fecha.subtract(
      const Duration(minutes: TripPublishWindows.poolLeadMinutesProgramado),
    );
  }

  bool _calcEsAhora(DateTime fecha) => TripPublishWindows.esAhoraPorFechaPickup(
        fecha,
        DateTime.now(),
      );

  String _mensajeClaimFallidoPoolTurismo(String res) {
    if (res == 'chofer-turismo-no-aprobado') {
      return AsignacionTurismoRepo.mensajeNoAutorizadoPoolTurismo;
    }
    if (res.startsWith('Este viaje pidió') ||
        res.startsWith('Este viaje requiere')) {
      return res;
    }
    if (res == 'vehiculo-turismo-no-compatible') {
      return AsignacionTurismoRepo.mensajeVehiculoNoCompatiblePoolTurismo;
    }
    return taxistaMensajeClaimFallido(res);
  }

  bool _claimIndicaViajeYaNoDisponible(String res) {
    switch (res) {
      case 'ya-asignado':
      case 'estado-no-pendiente':
      case 'no-existe':
      case 'reservado-otro':
        return true;
      default:
        return false;
    }
  }

  void _ocultarViajeDelPoolLocal(String viajeId) {
    if (viajeId.isEmpty) return;
    final changed = _ocultosPoolLocal.add(viajeId);
    _vistosParaTimbre.add(viajeId);
    if (changed && mounted) setState(() {});
  }

  Future<void> _revalidarViajeVisibleEnPoolTurismo({
    required String viajeId,
    required String myUid,
  }) async {
    try {
      final snap = await fs.FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .get(const fs.GetOptions(source: fs.Source.server));
      if (!snap.exists) {
        _ocultarViajeDelPoolLocal(viajeId);
        return;
      }
      if (!_disponibleParaMiPool(snap.data() ?? <String, dynamic>{}, myUid)) {
        _ocultarViajeDelPoolLocal(viajeId);
      }
    } catch (_) {}
  }

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
    NavigatorState? rootNav;
    if (mounted) {
      rootNav = NavigationService.navigatorKey.currentState;
      rootNav ??= Navigator.of(context, rootNavigator: true);
    }
    ActiveTripService.bloquearShellTaxistaTrasAceptar(const Duration(minutes: 3));
    _navegandoAViajeActivo = true;
    var navegoAViajeEnCurso = false;

    try {
      final usrSnap = await fs.FirebaseFirestore.instance
          .collection('usuarios')
          .doc(taxista.uid)
          .get();
      final uData = usrSnap.data() ?? <String, dynamic>{};
      if (!mounted) return;
      if (await TaxistaOperacionNav.bloquearClaimSiPerfilIncompleto(
        context,
        uData: uData,
      )) {
        return;
      }

      final prep = await AsignacionTurismoRepo.prepararClaimPoolTurismo(
        uidChofer: taxista.uid,
        viajeId: v.id,
        rawViaje: raw,
      );
      if (!prep.ok) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(prep.mensaje),
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

      if (res == 'ok') {
        await NotificationService.I.stopTimbre();
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
        // No borrar siguienteViajeId: claim ya preserva cola corporativa.

        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content:
                  const Text('✅ Viaje turístico aceptado. Redirigiendo...'),
              backgroundColor: cs.primary,
            ),
          );
        }
        navegoAViajeEnCurso = true;
        await NavigationService.irAViajeEnCursoTaxistaTrasAceptar(
          viajeId: v.id,
          uidTaxista: taxista.uid,
          preNav: rootNav,
        );
        return;
      }

      if (res == 'taxista-ocupado') {
        await NotificationService.I.stopTimbre();
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: const Text('Tienes un viaje activo. Redirigiendo...'),
              backgroundColor: cs.tertiaryContainer,
            ),
          );
        }
        navegoAViajeEnCurso = true;
        await NavigationService.irAViajeEnCursoTaxistaTrasAceptar(
          viajeId: v.id,
          uidTaxista: taxista.uid,
          preNav: rootNav,
        );
        return;
      }

      if (res.startsWith('permiso:')) {
        final bool yaAsignado = await _confirmarAsignacionYRedirigir(
          viajeId: v.id,
          uidTaxista: taxista.uid,
          preNav: rootNav,
        );
        if (yaAsignado) {
          await NotificationService.I.stopTimbre();
          await ViajesRepo.sincronizarChoferTurismoTrasAceptarDesdePool(
            uidChofer: taxista.uid,
            viajeId: v.id,
          );
          if (mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: const Text(
                  '✅ Viaje turístico tomado. Abriendo viaje en curso...',
                ),
                backgroundColor: cs.primary,
              ),
            );
          }
          navegoAViajeEnCurso = true;
          return;
        }
      }

      if (!mounted) return;

      if (res == 'chofer-turismo-no-aprobado') {
        messenger.showSnackBar(
          SnackBar(
            content: Text(_mensajeClaimFallidoPoolTurismo(res)),
            backgroundColor: cs.error,
          ),
        );
        return;
      }

      if (_claimIndicaViajeYaNoDisponible(res)) {
        _ocultarViajeDelPoolLocal(v.id);
      }

      await TaxistaOperacionNav.guiarTrasFalloClaim(context, res: res);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ No se pudo aceptar: $e'),
          backgroundColor: cs.error,
        ),
      );
    } finally {
      if (!navegoAViajeEnCurso) {
        ActiveTripService.cancelarMantenimientoOverlayViaje();
        _navegandoAViajeActivo = false;
      }
      if (mounted) setState(() => _aceptandoIds.remove(v.id));
    }
  }

  PreferredSizeWidget _poolAppBar(
    BuildContext context, {
    TabBar? bottom,
    List<Widget>? actions,
  }) {
    final cs = Theme.of(context).colorScheme;
    final canPop = Navigator.canPop(context);
    return AppBar(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      surfaceTintColor: cs.surfaceTint,
      elevation: 0,
      scrolledUnderElevation: 1,
      leading: canPop
          ? IconButton(
              icon: Icon(Icons.arrow_back, color: cs.onSurface),
              onPressed: () => Navigator.maybePop(context),
            )
          : const SizedBox(width: 48),
      automaticallyImplyLeading: false,
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
        'Sincronizando índice del pool turístico (2–10 min). '
        'Mientras tanto filtramos en el dispositivo.',
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
    fs.QuerySnapshot<Map<String, dynamic>>? preferSnapshot,
    required bool disponible,
    required String myUid,
    required bool Function(Map<String, dynamic>) filtroLocalSiFallback,
    required bool usandoFallback,
    required bool esTabAhora,
    required double latTaxista,
    required double lonTaxista,
    Map<String, dynamic>? choferData,
  }) {
    return StreamBuilder<fs.QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final fs.QuerySnapshot<Map<String, dynamic>>? qs =
            preferSnapshot ?? snapshot.data;
        if (qs == null) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingProfessional();
          }
        }
        if (snapshot.hasError && qs == null) {
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
        if (qs == null || qs.docs.isEmpty) {
          return EmptyTripsWidget(esTabAhora: esTabAhora);
        }

        final docs = qs.docs.toList();
        final items = <_ItemPoolTurismo>[];

        for (final d in docs) {
          final data = d.data();

          if (_ocultosPoolLocal.contains(d.id)) continue;
          if (usandoFallback && !filtroLocalSiFallback(data)) continue;
          if (!_disponibleParaMiPool(data, myUid)) continue;

          if (choferData != null && choferData.isNotEmpty) {
            final evalPool =
                AsignacionTurismoRepo.evaluarVehiculoTurismoParaViaje(
              choferData: choferData,
              rawViaje: data,
            );
            if (!evalPool.ok) continue;
          }

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

            final puedeAceptar =
                esAhora || !DateTime.now().isBefore(acceptAfter);
            final subtipo = AsignacionTurismoRepo.subtipoTurismoRequeridoDesdeViaje(raw);
            final subtipoLabel =
                AsignacionTurismoRepo.labelTipoVehiculoTurismo(subtipo);
            final pax = _pasajerosDesde(v);
            ResultadoEvalVehiculoTurismo? evalVeh;
            if (choferData != null && choferData.isNotEmpty) {
              evalVeh = AsignacionTurismoRepo.evaluarVehiculoTurismoParaViaje(
                choferData: choferData,
                rawViaje: raw,
              );
            }
            final bool vehiculoCompatible = evalVeh?.ok ?? true;
            final String? avisoVehiculo =
                evalVeh != null && !evalVeh.ok ? evalVeh.mensaje : null;

            final distanciaKm = DistanciaService.calcularDistancia(
              v.latCliente,
              v.lonCliente,
              v.latDestino,
              v.lonDestino,
            );
            final precioTotal = v.precio;
            final ganancia = (v.gananciaTaxista > 0)
                ? v.gananciaTaxista
                : PlataformaEconomia.gananciaTaxistaRdDesdeTotal(precioTotal);

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
                      fmtFechaHoraAmPm(fecha, sep: ','),
                      style: TextStyle(color: pal.textFaint, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(context, Icons.directions_car,
                            'Requiere: $subtipoLabel'),
                        if (pax != null)
                          _chip(context, Icons.people, '$pax pasajeros'),
                        _chip(context, Icons.near_me,
                            'A ${distancia.toStringAsFixed(1)} km'),
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
                            'Programado ${fmtDdMmHoraAmPm(fecha)}',
                          ),
                      ],
                    ),
                    if (avisoVehiculo != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .errorContainer
                              .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .error
                                .withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                avisoVehiculo,
                                style: TextStyle(
                                  color: pal.textSecondary,
                                  fontSize: 12.5,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total',
                                style: TextStyle(
                                    color: pal.textMuted, fontSize: 12),
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
                              style:
                                  TextStyle(color: pal.textMuted, fontSize: 12),
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
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => DetalleViaje(viajeId: v.id),
                                ),
                              );
                              if (!mounted) return;
                              await _revalidarViajeVisibleEnPoolTurismo(
                                viajeId: v.id,
                                myUid: myUid,
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
                                    !vehiculoCompatible ||
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
                                : Icon(Icons.check_circle,
                                    color: pal.onAcceptBtn),
                            label: Text(
                              aceptando
                                  ? 'Aceptando...'
                                  : (!vehiculoCompatible
                                      ? 'Vehículo no coincide'
                                      : (!disponible
                                          ? 'No disponible'
                                          : (!esAhora && !puedeAceptar
                                              ? 'Espera liberación'
                                              : 'Aceptar'))),
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
    final double maxW =
        (MediaQuery.sizeOf(context).width - 48).clamp(120.0, 600.0);
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

  Widget _panelBloqueoPoolTurismo() {
    final p = context._poolTurismoPal;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () => TaxistaOperacionNav.guiarTrasRecargaPrepagoOperativa(
              context,
              mensaje: PagosTaxistaRepo.mensajeRecargaBannerLista,
            ),
            icon: const Icon(Icons.payment_rounded),
            label: const Text('Ir a Mis pagos'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => TaxistaFinanzasNav.abrirBloqueadoPagos(context),
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('Cuenta bancaria y pasos'),
          ),
          const SizedBox(height: 20),
          Text(
            PagosTaxistaRepo.mensajeRecargaListaVacia,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 15,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Cuando el administrador apruebe tu recarga, el pool turístico se reactiva solo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textMuted, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildContenidoPrincipal(
    BuildContext context,
    Position pos,
    User u, {
    Map<String, dynamic>? choferData,
  }) {
    _asegurarStreamsPoolUi();
    final streamAhora = _streamPoolAhora!;
    final streamProg = _streamPoolProg!;

    final p = context._poolTurismoPal;

    return TaxistaTripRouter(
      child: Scaffold(
        backgroundColor: p.scaffoldBg,
        appBar: _poolAppBar(
          context,
          actions: const [SaldoGananciasChip()],
          bottom: TabBar(
            controller: _tabPool,
            indicatorColor: p.accent,
            labelColor: p.accent,
            unselectedLabelColor: p.textMuted,
            tabs: const [
              Tab(text: 'AHORA'),
              Tab(text: 'PROGRAMADOS'),
            ],
          ),
        ),
        body: StreamBuilder<fs.DocumentSnapshot<Map<String, dynamic>>>(
          stream: fs.FirebaseFirestore.instance
              .collection('usuarios')
              .doc(u.uid)
              .snapshots(),
          builder: (context, usrSnap) {
            final uData = usrSnap.data?.data();
            return StreamBuilder<fs.DocumentSnapshot<Map<String, dynamic>>>(
              stream: fs.FirebaseFirestore.instance
                  .collection('billeteras_taxista')
                  .doc(u.uid)
                  .snapshots(),
              builder: (context, billeSnap) {
                final bloqueado = !PagosTaxistaRepo.taxistaSinBloqueoPrepagoOperativo(
                  uData,
                  billeSnap.data?.data(),
                );
                return StreamBuilder<bool>(
                  stream: RolesService.streamDisponibilidad(u.uid),
                  builder: (context, dispSnap) {
                    final disponible = dispSnap.data ?? false;
                    return Column(
                      children: [
                        if (!disponible) _bannerNoDisponible(context),
                        if (bloqueado)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(244, 67, 54, 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color.fromRGBO(244, 67, 54, 0.7),
                              ),
                            ),
                            child: Text(
                              PagosTaxistaRepo.mensajeRecargaBannerLista,
                              style: TextStyle(color: p.textSecondary),
                            ),
                          ),
                        _bannerFallback(
                          context,
                          _usarFallbackSinIndiceAhora ||
                              _usarFallbackSinIndiceProg,
                        ),
                        Expanded(
                          child: bloqueado
                              ? _panelBloqueoPoolTurismo()
                              : TabBarView(
                                  controller: _tabPool,
                                  children: [
                                    _buildLista(
                                      stream: streamAhora,
                                      preferSnapshot: _snapTimbreAhora,
                                      disponible: disponible,
                                      myUid: u.uid,
                                      filtroLocalSiFallback:
                                          _pasaFiltroAhoraLocalPool,
                                      usandoFallback:
                                          _usarFallbackSinIndiceAhora,
                                      esTabAhora: true,
                                      latTaxista: pos.latitude,
                                      lonTaxista: pos.longitude,
                                      choferData: choferData,
                                    ),
                                    _buildLista(
                                      stream: streamProg,
                                      preferSnapshot: _snapTimbreProg,
                                      disponible: disponible,
                                      myUid: u.uid,
                                      filtroLocalSiFallback:
                                          _pasaFiltroProgLocalPool,
                                      usandoFallback:
                                          _usarFallbackSinIndiceProg,
                                      esTabAhora: false,
                                      latTaxista: pos.latitude,
                                      lonTaxista: pos.longitude,
                                      choferData: choferData,
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
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
        appBar: _poolAppBar(context),
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
        final aprobado =
            d != null && AsignacionTurismoRepo.choferEstadoOperativo(d['estado']);
        if (!aprobado) {
          return _pantallaNoAprobado();
        }

        unawaited(UbicacionTaxista.habilitarSyncChoferTurismo(u.uid));
        UbicacionTaxista.iniciarActualizacion();

        return StreamBuilder<Position>(
          stream: UbicacionTaxista.obtenerStreamUbicacion().timeout(
            const Duration(seconds: 15),
          ),
          builder: (context, ubicacionSnapshot) {
            if (_gpsServicioActivo == false &&
                _ubicacionCache == null &&
                ubicacionSnapshot.connectionState == ConnectionState.waiting) {
              return _pantallaUbicacionRequerida();
            }

            if (ubicacionSnapshot.connectionState == ConnectionState.waiting &&
                _ubicacionCache != null) {
              return _buildContenidoPrincipal(
                context,
                _ubicacionCache!,
                u,
                choferData: d,
              );
            }

            if (ubicacionSnapshot.connectionState == ConnectionState.waiting) {
              final p = context._poolTurismoPal;
              return Scaffold(
                backgroundColor: p.scaffoldBg,
                appBar: _poolAppBar(context),
                body: const LoadingProfessional(
                  mensajePersonalizado: 'Obteniendo tu ubicación',
                ),
              );
            }

            if (ubicacionSnapshot.hasError) {
              if (_ubicacionCache != null) {
                return _buildContenidoPrincipal(
                  context,
                  _ubicacionCache!,
                  u,
                  choferData: d,
                );
              }
              return _pantallaUbicacionRequerida();
            }

            final pos = ubicacionSnapshot.data;
            if (pos == null) {
              if (_ubicacionCache != null) {
                return _buildContenidoPrincipal(
                  context,
                  _ubicacionCache!,
                  u,
                  choferData: d,
                );
              }
              return _pantallaUbicacionRequerida();
            }

            _guardarUbicacionCache(pos);
            if (mounted && _gpsServicioActivo != true) {
              _gpsServicioActivo = true;
            }
            return _buildContenidoPrincipal(
              context,
              pos,
              u,
              choferData: d,
            );
          },
        );
      },
    );
  }
}
