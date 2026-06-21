// ignore_for_file: avoid_print, prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';
import 'package:flygo_nuevo/utils/trip_publish_windows.dart';
import 'package:flygo_nuevo/servicios/notification_service.dart';
import 'package:flygo_nuevo/widgets/saldo_ganancias_chip.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';
import 'package:flygo_nuevo/servicios/disponibilidad_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/navegacion/taxista_finanzas_nav.dart';
import 'package:flygo_nuevo/servicios/ubicacion_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/bola_pueblo_disponible_tab.dart';
import 'package:flygo_nuevo/servicios/bola_pueblo_repo.dart';
import 'package:flygo_nuevo/pantallas/taxista/detalle_viaje.dart';
import 'package:flygo_nuevo/widgets/cliente_perfil_conductor_chip.dart';
import 'package:flygo_nuevo/widgets/empty_trips_widget.dart';
import 'package:flygo_nuevo/pantallas/taxista/pool_turismo_taxista.dart';
import 'package:flygo_nuevo/widgets/rai_linear_loading_body.dart';
import 'package:flygo_nuevo/widgets/rai_pool_offline_hint.dart';
import 'package:flygo_nuevo/navegacion/taxista_operacion_nav.dart';
import 'package:flygo_nuevo/servicios/taxista_operacion_gate.dart';
import 'package:flygo_nuevo/pantallas/taxista/completar_vehiculo_taxista.dart';

class _Item {
  final Viaje v;
  final DateTime fecha;
  final DateTime acceptAfter;
  final bool esAhora;

  /// Km desde el taxista al punto de recogida; `null` si no hay coords → al final del listado.
  final double? distanciaKmPickup;
  _Item(this.v, this.fecha, this.acceptAfter, this.esAhora,
      this.distanciaKmPickup);
}

class _OfertaPoolPendiente {
  const _OfertaPoolPendiente({
    required this.id,
    required this.data,
    required this.titulo,
    required this.cuerpo,
  });

  final String id;
  final Map<String, dynamic>? data;
  final String titulo;
  final String cuerpo;
}

extension _PoolTaxistaTheme on BuildContext {
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
    Color panelBg,
    Color panelBorder,
  }) get _poolTaxistaPal {
    final t = Theme.of(this);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;
    if (isDark) {
      final accent = Colors.greenAccent;
      return (
        scaffoldBg: cs.surface,
        textPrimary: cs.onSurface,
        textSecondary: cs.onSurfaceVariant,
        textMuted: cs.onSurfaceVariant,
        textFaint: cs.onSurfaceVariant.withValues(alpha: 0.72),
        accent: accent,
        cardBg: cs.surfaceContainerHighest.withValues(alpha: 0.42),
        cardBorder: accent.withValues(alpha: 0.45),
        chipBg: cs.surfaceContainerLow,
        chipBorder: cs.outlineVariant,
        chipIcon: Colors.greenAccent,
        panelBg: cs.surfaceContainerLow.withValues(alpha: 0.95),
        panelBorder: cs.outlineVariant.withValues(alpha: 0.65),
      );
    }
    // Modo claro: alto contraste tipo inDrive (fondo suave, cards blancas, texto oscuro).
    return (
      scaffoldBg: const Color(0xFFF2F4F7),
      textPrimary: const Color(0xFF101828),
      textSecondary: const Color(0xFF344054),
      textMuted: const Color(0xFF475467),
      textFaint: const Color(0xFF667085),
      accent: const Color(0xFF059669),
      cardBg: Colors.white,
      cardBorder: const Color(0xFFD0D5DD),
      chipBg: const Color(0xFFF9FAFB),
      chipBorder: const Color(0xFFE4E7EC),
      chipIcon: const Color(0xFF047857),
      panelBg: Colors.white,
      panelBorder: const Color(0xFFE4E7EC),
    );
  }
}

/// Carga del listado del pool: barra lineal de borde a borde (mismo patrón que pestaña BOLA / carga inicial).
class _PoolEntradaLoading extends StatelessWidget {
  const _PoolEntradaLoading();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RaiLinearLoadingBody(
      backgroundColor: cs.surface,
      barColor: isDark ? Colors.greenAccent : const Color(0xFF16A34A),
    );
  }
}

class ViajeDisponible extends StatefulWidget {
  const ViajeDisponible({super.key});
  @override
  State<ViajeDisponible> createState() => _ViajeDisponibleState();
}

class _ViajeDisponibleState extends State<ViajeDisponible>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const String _kDebtNotifLastTsKey = 'debt_notif_last_ts_v1';
  static const Duration _debtNotifCooldown = Duration(hours: 12);
  static const bool _diagTripFlow =
      bool.fromEnvironment('TRIP_FLOW_DIAG', defaultValue: false);
  void _diag(String msg) {
    if (_diagTripFlow) debugPrint('[TRIP_FLOW][disponible] $msg');
  }

  final Set<String> _aceptandoIds = <String>{};
  final Set<String> _vistosParaTimbre = <String>{};
  /// Viajes que ya no están en el pool (p. ej. otro taxista los tomó): ocultar al instante.
  final Set<String> _ocultosPoolLocal = <String>{};

  StreamSubscription<fs.QuerySnapshot<Map<String, dynamic>>>? _subTimbreAhora;
  StreamSubscription<fs.QuerySnapshot<Map<String, dynamic>>>? _subTimbreProg;
  StreamSubscription<fs.QuerySnapshot<Map<String, dynamic>>>? _subTimbreBola;

  /// Pestañas BOLA / AHORA / PROGRAMADOS (índices 0 / 1 / 2).
  late TabController _tabPool;

  /// Último snapshot de las queries de timbre (para sonar al cambiar de pestaña).
  fs.QuerySnapshot<Map<String, dynamic>>? _snapTimbreAhora;
  fs.QuerySnapshot<Map<String, dynamic>>? _snapTimbreProg;
  fs.QuerySnapshot<Map<String, dynamic>>? _snapTimbreBola;

  // Listener estable para viaje activo (evita parpadeos por queries amplias).
  StreamSubscription<fs.DocumentSnapshot<Map<String, dynamic>>>?
      _activeUserListener;
  StreamSubscription<fs.DocumentSnapshot<Map<String, dynamic>>>?
      _activeTripListener;
  String? _activeTripListeningId;
  bool _navegandoAViajeActivo = false;
  Timer? _timer;
  bool _debtNotifInFlight = false;

  bool _usarFallbackSinIndiceAhora = false;
  bool _usarFallbackSinIndiceProg = false;

  /// Modo pool según registro (`motor` vs carro). Se actualiza con el doc del usuario.
  String _poolModoConductor = TaxistaPoolModoConductor.vehiculo;

  bool _ignorarPrimeraEmisionTimbreAhora = true;
  bool _ignorarPrimeraEmisionTimbreProg = true;
  bool _ignorarPrimeraEmisionTimbreBola = true;
  bool _entradaInicialProcesada = false;
  bool _appEnForeground = true;
  bool _flushTimbreReentradaPendiente = false;

  static const List<String> _kEstadosPend = <String>[
    EstadosViaje.pendiente,
    'buscando',
    'disponible',
    'pendiente_pago',
    'pendientePago',
    'pendiente_admin',
    'pendienteAdmin',
  ];

  // 🔥 CACHÉ DE UBICACIÓN
  Position? _ubicacionCache;
  bool _ubicacionActualizacionIniciada = false;
  DateTime? _ultimaPersistenciaUbicacion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabPool = TabController(length: 3, vsync: this);
    _tabPool.addListener(_onPoolTabChanged);

    FirebaseAuth.instance.currentUser?.getIdToken(true);

    // 🔥 NUEVO: Escuchar si ya tiene un viaje activo
    _checkExistingActiveTrip();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapViajeActivoDesdeRepo());
    });

    Future.microtask(() => NotificationService.I.ensureInited());
    Future.microtask(() async {
      await _bootstrapPoolModoConductor();
      await _probarIndices();
      _arrancarTimbres();
      if (mounted) setState(() {});
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) await _flushTimbreOfertasParaTab(_tabPool.index);
    });

    // 🔥 Cargar ubicación guardada inmediatamente
    _cargarUbicacionCache();

    _timer = Timer.periodic(const Duration(minutes: 30), (t) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await DisponibilidadService.verificar(uid);
      }
    });
  }

  Future<void> _bootstrapViajeActivoDesdeRepo() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !mounted || _navegandoAViajeActivo) return;
    print('[VIAJE_ACTIVO] viaje_disponible bootstrap ViajesRepo');
    try {
      final snap = await ViajesRepo.getViajeActivoParaUsuario(uid);
      if (snap == null || !snap.exists || !mounted) return;
      final d = snap.data() ?? <String, dynamic>{};
      if (!_esViajeActivoReal(d, uid)) return;
      if (ViajePoolTaxistaGate.debeUsarFlujoBolaPuebloEnLugarDeViajeEnCurso(d)) return;
      _navegandoAViajeActivo = true;
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (!mounted) {
        _navegandoAViajeActivo = false;
        return;
      }
      await _redirectToActiveTrip();
    } catch (e) {
      print('[VIAJE_ACTIVO] viaje_disponible bootstrap error: $e');
      if (mounted) _navegandoAViajeActivo = false;
    }
  }

  bool _esViajeActivoReal(Map<String, dynamic> data, String uid) {
    final String uidTaxista =
        (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString();
    if (uidTaxista != uid) return false;

    final String estado =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());
    final bool estadoActivo = estado == EstadosViaje.aceptado ||
        estado == EstadosViaje.enCaminoPickup ||
        estado == EstadosViaje.aBordo ||
        estado == EstadosViaje.enCurso;
    final bool activo = data['activo'] == true;
    return estadoActivo && activo;
  }

  // Verificar si ya tiene viaje activo y redirigir sin falsos positivos.
  Future<void> _checkExistingActiveTrip() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _diag('init active-trip listener uid=$uid');

    final userRef =
        fs.FirebaseFirestore.instance.collection('usuarios').doc(uid);
    _activeUserListener = userRef.snapshots().listen((uSnap) async {
      if (!mounted) return;
      final uData = uSnap.data() ?? <String, dynamic>{};
      final String viajeActivoId =
          (uData['viajeActivoId'] ?? '').toString().trim();

      if (viajeActivoId.isEmpty) {
        _diag('user.viajeActivoId empty -> stay in disponible');
        await _activeTripListener?.cancel();
        _activeTripListener = null;
        _activeTripListeningId = null;
        return;
      }

      if (_activeTripListeningId == viajeActivoId &&
          _activeTripListener != null) {
        return;
      }

      await _activeTripListener?.cancel();
      _activeTripListeningId = viajeActivoId;
      _activeTripListener = fs.FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeActivoId)
          .snapshots()
          .listen((vSnap) async {
        if (!mounted) return;
        if (!vSnap.exists) {
          _diag('viajeActivoId=$viajeActivoId missing doc -> cleanup user ref');
          try {
            await userRef.set(
              {
                'viajeActivoId': '',
                'updatedAt': fs.FieldValue.serverTimestamp(),
                'actualizadoEn': fs.FieldValue.serverTimestamp(),
              },
              fs.SetOptions(merge: true),
            );
          } catch (_) {}
          return;
        }
        final data = vSnap.data() ?? <String, dynamic>{};
        if (!_esViajeActivoReal(data, uid)) return;
        // Bola espejo: mismo viaje que acordás en bolas_pueblo — no sustituir por ViajeEnCursoTaxista.
        if (ViajePoolTaxistaGate.debeUsarFlujoBolaPuebloEnLugarDeViajeEnCurso(data)) return;
        if (_navegandoAViajeActivo) return;
        _diag('active trip confirmed id=$viajeActivoId -> redirect en_curso');
        _navegandoAViajeActivo = true;
        await Future.delayed(const Duration(milliseconds: 450));
        if (!mounted) return;
        await _redirectToActiveTrip();
      });
    });
  }

  /// No redirige a ViajeEnCurso si el activo es espejo Bola ([bolas_pueblo] manda el flujo).
  /// Al volver de Waze/Maps u otra app: reevaluar `viajeActivoId` y volver al flujo en curso.
  Future<void> _reconciliarViajeActivoAlResume() async {
    print('[VIAJE_ACTIVO] viaje_disponible resumed → reconciliar viaje activo');
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
      if (!_esViajeActivoReal(data, uid)) return;
      if (ViajePoolTaxistaGate.debeUsarFlujoBolaPuebloEnLugarDeViajeEnCurso(data)) return;
      _navegandoAViajeActivo = false;
      await _redirectToActiveTrip();
    } catch (e, st) {
      print('[VIAJE_ACTIVO] viaje_disponible resume reconcile error $e $st');
    }
  }

  Future<void> _redirectToActiveTrip({NavigatorState? preNav}) async {
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
            return;
          }
        }
      } catch (_) {}
    }
    await NavigationService.clearAndGoViajeEnCursoTaxista(preNav: nav);
  }

  @override
  void dispose() {
    _activeUserListener?.cancel();
    _activeTripListener?.cancel();
    _tabPool.removeListener(_onPoolTabChanged);
    _tabPool.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _subTimbreAhora?.cancel();
    _subTimbreProg?.cancel();
    _subTimbreBola?.cancel();
    _timer?.cancel();
    NotificationService.I.stopTimbre();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` sigue siendo app visible (p. ej. panel de notificaciones); no cortar timbre ahí.
    _appEnForeground = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (state == AppLifecycleState.resumed) {
      _arrancarTimbres();
      unawaited(_reconciliarViajeActivoAlResume());
      unawaited(Future<void>.delayed(const Duration(milliseconds: 700), () async {
        if (!mounted) return;
        await _flushTimbreOfertasParaTab(_tabPool.index);
      }));
      if (mounted) setState(() {});
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(NotificationService.I.stopTimbre());
    }
  }

  void _onPoolTabChanged() {
    if (_tabPool.indexIsChanging || !mounted) return;
    unawaited(_flushTimbreOfertasParaTab(_tabPool.index));
  }

  /// Al entrar a una pestaña: un timbre si hay ofertas no vistas acumuladas.
  Future<void> _flushTimbreOfertasParaTab(int tabIndex) async {
    if (!_appEnForeground) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (!await _taxistaDisponibleParaTimbre(myUid)) return;

    final pendientes = _idsOfertasNoVistasEnTab(tabIndex, myUid);
    if (pendientes.isEmpty) return;

    await NotificationService.I.playPoolOfferSoundInApp();
    for (final item in pendientes) {
      _vistosParaTimbre.add(item.id);
      await _notificarOfertaEnBandejaSiAplica(
        id: item.id,
        data: item.data,
        titulo: item.titulo,
        cuerpo: item.cuerpo,
      );
    }
  }

  /// Tras reconectar listeners (volver de background): sonar ofertas no vistas.
  Future<void> _flushTimbreOfertasAlReentrarPool(String myUid) async {
    if (!_appEnForeground) return;
    if (!await _taxistaDisponibleParaTimbre(myUid)) return;

    final pendientes = <_OfertaPoolPendiente>[
      ..._idsOfertasNoVistasEnTab(0, myUid),
      ..._idsOfertasNoVistasEnTab(1, myUid),
      ..._idsOfertasNoVistasEnTab(2, myUid),
    ];
    if (pendientes.isEmpty) return;

    await NotificationService.I.playPoolOfferSoundInApp();
    for (final item in pendientes) {
      _vistosParaTimbre.add(item.id);
      await _notificarOfertaEnBandejaSiAplica(
        id: item.id,
        data: item.data,
        titulo: item.titulo,
        cuerpo: item.cuerpo,
      );
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

  /// Primera carga del pool: revisa BOLA + AHORA + PROGRAMADOS (modo motor/vehículo).
  Future<void> _intentarEntradaInicialPool() async {
    if (_entradaInicialProcesada || !_appEnForeground) return;
    // Bola puede tardar o venir vacío; basta AHORA + PROGRAMADOS para desbloquear timbre.
    if (_ignorarPrimeraEmisionTimbreAhora || _ignorarPrimeraEmisionTimbreProg) {
      return;
    }
    await _procesarEntradaInicialPool();
  }

  Future<void> _procesarEntradaInicialPool() async {
    if (_entradaInicialProcesada || !_appEnForeground) return;
    _entradaInicialProcesada = true;

    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final pendientes = <_OfertaPoolPendiente>[
      ..._idsOfertasNoVistasEnTab(0, myUid),
      ..._idsOfertasNoVistasEnTab(1, myUid),
      ..._idsOfertasNoVistasEnTab(2, myUid),
    ];

    if (pendientes.isNotEmpty &&
        await _taxistaDisponibleParaTimbre(myUid)) {
      await NotificationService.I.playPoolOfferSoundInApp();
    }

    for (final item in pendientes) {
      _vistosParaTimbre.add(item.id);
      if (await _taxistaDisponibleParaTimbre(myUid)) {
        await _notificarOfertaEnBandejaSiAplica(
          id: item.id,
          data: item.data,
          titulo: item.titulo,
          cuerpo: item.cuerpo,
        );
      }
    }
  }

  Future<void> _procesarNuevasOfertasEnTabActivo(
    int tabIndex,
    String myUid,
    List<_OfertaPoolPendiente> nuevas,
  ) async {
    if (!_entradaInicialProcesada || !_appEnForeground) return;
    if (nuevas.isEmpty) return;
    if (!await _taxistaDisponibleParaTimbre(myUid)) return;

    final List<_OfertaPoolPendiente> fresh = nuevas
        .where((item) => !_vistosParaTimbre.contains(item.id))
        .toList();
    if (fresh.isEmpty) return;

    await NotificationService.I.playPoolOfferSoundInApp();

    for (final item in fresh) {
      _vistosParaTimbre.add(item.id);
      await NotificationService.I.vibratePoolOfferInApp();
      await _notificarOfertaEnBandejaSiAplica(
        id: item.id,
        data: item.data,
        titulo: item.titulo,
        cuerpo: item.cuerpo,
      );
    }
  }

  Future<void> _notificarOfertaEnBandejaSiAplica({
    required String id,
    required Map<String, dynamic>? data,
    required String titulo,
    required String cuerpo,
  }) async {
    if (data == null) {
      await NotificationService.I.notifyNuevoViaje(
        viajeId: id,
        titulo: titulo,
        cuerpo: cuerpo,
        skipSound: true,
      );
      return;
    }
    if (!_viajeTienePrecioReal(data)) return;
    await NotificationService.I.notifyNuevoViaje(
      viajeId: id,
      titulo: titulo,
      cuerpo: cuerpo,
      skipSound: true,
    );
  }

  List<_OfertaPoolPendiente> _idsOfertasNoVistasEnTab(
    int tabIndex,
    String myUid,
  ) {
    switch (tabIndex) {
      case 0:
        return _idsOfertasNoVistasBola(myUid);
      case 1:
        return _idsOfertasNoVistasAhora(myUid);
      case 2:
        return _idsOfertasNoVistasProg(myUid);
      default:
        return const <_OfertaPoolPendiente>[];
    }
  }

  List<_OfertaPoolPendiente> _idsOfertasNoVistasAhora(String myUid) {
    final snap = _snapTimbreAhora;
    if (snap == null) return const <_OfertaPoolPendiente>[];
    final out = <_OfertaPoolPendiente>[];
    for (final d in snap.docs) {
      final data = d.data();
      if (!_pasaFiltroAhoraLocal(data)) continue;
      if (!_timbreMeInteresaViaje(data, myUid)) continue;
      if (!_esAhoraDesdeData(data)) continue;
      final id = _timbreClaveViaje(d.id, data, myUid);
      if (_vistosParaTimbre.contains(id)) continue;
      out.add(
        _OfertaPoolPendiente(
          id: id,
          data: data,
          titulo: 'Nuevo viaje disponible',
          cuerpo:
              '${(data['origen'] ?? 'Origen')} → ${(data['destino'] ?? 'Destino')}',
        ),
      );
    }
    return out;
  }

  List<_OfertaPoolPendiente> _idsOfertasNoVistasProg(String myUid) {
    final snap = _snapTimbreProg;
    if (snap == null) return const <_OfertaPoolPendiente>[];
    final out = <_OfertaPoolPendiente>[];
    for (final d in snap.docs) {
      final data = d.data();
      if (!_pasaFiltroProgLocal(data)) continue;
      if (!_timbreMeInteresaViaje(data, myUid)) continue;
      if (_esAhoraDesdeData(data)) continue;
      final id = _timbreClaveViaje(d.id, data, myUid);
      if (_vistosParaTimbre.contains(id)) continue;
      out.add(
        _OfertaPoolPendiente(
          id: id,
          data: data,
          titulo: 'Viaje programado disponible',
          cuerpo:
              '${(data['origen'] ?? 'Origen')} → ${(data['destino'] ?? 'Destino')}',
        ),
      );
    }
    return out;
  }

  List<_OfertaPoolPendiente> _idsOfertasNoVistasBola(String myUid) {
    final snap = _snapTimbreBola;
    if (snap == null || myUid.isEmpty) return const <_OfertaPoolPendiente>[];
    final out = <_OfertaPoolPendiente>[];
    for (final d in snap.docs) {
      final m = d.data();
      if (!_bolaDisparaTimbre(m, myUid)) continue;
      final key = 'bola_${d.id}';
      if (_vistosParaTimbre.contains(key)) continue;
      final origen = (m['origen'] ?? '').toString();
      final destino = (m['destino'] ?? '').toString();
      out.add(
        _OfertaPoolPendiente(
          id: key,
          data: null,
          titulo: 'Nueva Bola Ahorro',
          cuerpo: '$origen → $destino',
        ),
      );
    }
    return out;
  }

  /// Timbre de pool solo si el conductor está en «Disponible» (Cuenta).
  Future<bool> _taxistaDisponibleParaTimbre(String myUid) async {
    if (myUid.isEmpty) return false;
    return RolesService.getDisponibilidad(myUid);
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

  Future<void> _revalidarViajeVisibleEnPool({
    required String viajeId,
    required String myUid,
    required String poolModoConductor,
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
      if (!_disponibleParaMi(
        snap.data() ?? <String, dynamic>{},
        myUid,
        poolModoConductor: poolModoConductor,
      )) {
        _ocultarViajeDelPoolLocal(viajeId);
      }
    } catch (_) {}
  }

  Future<void> _guardarUbicacionCache(Position pos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ultima_lat', pos.latitude);
    await prefs.setDouble('ultima_lon', pos.longitude);
    await prefs.setDouble(
        'ultima_timestamp', pos.timestamp.millisecondsSinceEpoch.toDouble());
  }

  // 🔥 CARGAR ÚLTIMA UBICACIÓN GUARDADA
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

  fs.Query<Map<String, dynamic>> _qPoolAhora() {
    return _qFallbackBase();
  }

  fs.Query<Map<String, dynamic>> _qPoolProgramados() {
    return _qFallbackBase();
  }

  fs.Query<Map<String, dynamic>> _qFallbackBase() {
    // Fallback compatible con reglas endurecidas del pool taxista.
    return fs.FirebaseFirestore.instance
        .collection('viajes')
        .where('estado', whereIn: _kEstadosPend)
        .where('uidTaxista', isEqualTo: '');
  }

  Future<void> _bootstrapPoolModoConductor() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await fs.FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();
      final modo =
          ViajePoolTaxistaGate.poolModoConductorDesdeUsuario(snap.data());
      if (mounted && modo != _poolModoConductor) {
        _poolModoConductor = modo;
      }
    } catch (_) {}
  }

  Future<void> _probarIndices() async {
    try {
      await _qPoolAhora()
          .limit(1)
          .get(const fs.GetOptions(source: fs.Source.server));
      _usarFallbackSinIndiceAhora = false;
    } on fs.FirebaseException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      _usarFallbackSinIndiceAhora =
          e.code == 'failed-precondition' || msg.contains('index');
    } catch (_) {
      _usarFallbackSinIndiceAhora = false;
    }

    try {
      await _qPoolProgramados()
          .limit(1)
          .get(const fs.GetOptions(source: fs.Source.server));
      _usarFallbackSinIndiceProg = false;
    } on fs.FirebaseException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      _usarFallbackSinIndiceProg =
          e.code == 'failed-precondition' || msg.contains('index');
    } catch (_) {
      _usarFallbackSinIndiceProg = false;
    }

    if (!mounted) return;
    setState(() {});
  }

  void _arrancarTimbres() {
    _subTimbreAhora?.cancel();
    _subTimbreProg?.cancel();
    _subTimbreBola?.cancel();

    _ignorarPrimeraEmisionTimbreAhora = true;
    _ignorarPrimeraEmisionTimbreProg = true;
    _ignorarPrimeraEmisionTimbreBola = true;
    _flushTimbreReentradaPendiente = _entradaInicialProcesada;

    final fs.Query<Map<String, dynamic>> qA =
        _usarFallbackSinIndiceAhora ? _qFallbackBase() : _qPoolAhora();
    final fs.Query<Map<String, dynamic>> qP =
        _usarFallbackSinIndiceProg ? _qFallbackBase() : _qPoolProgramados();

    // Mismos límites que los streams de la lista (AHORA 120, PROGRAMADOS 200).
    // Con 60/80 el timbre no veía viajes que sí aparecían en pantalla.
    _subTimbreAhora = qA.limit(120).snapshots().listen((snap) async {
      if (!_appEnForeground) return;
      _snapTimbreAhora = snap;
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
      await _procesarNuevasOfertasEnTabActivo(1, myUid, nuevas);
    });

    _subTimbreProg = qP.limit(200).snapshots().listen((snap) async {
      if (!_appEnForeground) return;
      _snapTimbreProg = snap;
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
      await _procesarNuevasOfertasEnTabActivo(2, myUid, nuevas);
    });

    _subTimbreBola = BolaPuebloRepo.streamTablero().listen((snap) async {
      if (!_appEnForeground) return;
      _snapTimbreBola = snap;
      final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (myUid.isEmpty) return;

      if (_ignorarPrimeraEmisionTimbreBola) {
        _ignorarPrimeraEmisionTimbreBola = false;
        if (!_entradaInicialProcesada) {
          unawaited(_intentarEntradaInicialPool());
        }
        return;
      }

      final nuevas = _idsOfertasNoVistasBola(myUid);
      await _procesarNuevasOfertasEnTabActivo(0, myUid, nuevas);
    });
  }

  Future<void> _notificarBloqueoPagoSiAplica(String uidTaxista) async {
    if (_debtNotifInFlight) return;
    _debtNotifInFlight = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      final int lastMs = prefs.getInt(_kDebtNotifLastTsKey) ?? 0;
      final bool enCooldown =
          (nowMs - lastMs) < _debtNotifCooldown.inMilliseconds;
      if (enCooldown) return;

      await NotificationService.I.notifyNuevoViaje(
        viajeId: 'comision_efectivo_$uidTaxista',
        titulo: 'Recarga pendiente',
        cuerpo: PagosTaxistaRepo.mensajeRecargaTomarViajes,
      );
      await prefs.setInt(_kDebtNotifLastTsKey, nowMs);
    } catch (_) {
      // Sin crash en UI si falla notificación.
    } finally {
      _debtNotifInFlight = false;
    }
  }

  bool _disponibleParaMi(
    Map<String, dynamic> data,
    String myUid, {
    String? poolModoConductor,
  }) {
    return ViajePoolTaxistaGate.viajeTomableEnPool(
      data,
      myUid,
      poolModoConductor: poolModoConductor ?? _poolModoConductor,
    );
  }

  bool _timbreViajeNoIgnorado(Map<String, dynamic> data, String myUid) {
    final ign = data['ignoradosPor'];
    if (ign is List && ign.contains(myUid)) return false;
    return true;
  }

  /// Viaje espejo Bola en negociación: no es “tomable” con un toque pero sí entra al pool en tiempo real.
  bool _esViajeEspejoBolaEnVentana(Map<String, dynamic> data, String myUid) {
    final pid =
        (data['bolaPuebloId'] ?? data['bolaId'] ?? '').toString().trim();
    if (pid.isEmpty || data['bolaNegociacionAbierta'] != true) return false;
    if ((data['uidTaxista'] ?? '').toString().isNotEmpty) return false;
    final estadoNorm =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());
    final estadoRaw = (data['estado'] ?? '').toString().trim();
    if (!ViajePoolTaxistaGate.estadoPermiteClaimPool(estadoRaw, estadoNorm)) {
      return false;
    }
    if (ViajePoolTaxistaGate.reservaVigenteBloquea(data)) return false;
    return ViajePoolTaxistaGate.ventanaPublicacionYAceptacionOk(data);
  }

  /// Timbre de pool: viaje tomable **o** espejo Bola visible (misma ventana publicación/aceptación).
  bool _timbreMeInteresaViaje(
    Map<String, dynamic> data,
    String myUid, {
    String? poolModoConductor,
  }) {
    if (!_timbreViajeNoIgnorado(data, myUid)) return false;
    final modo = poolModoConductor ?? _poolModoConductor;
    if (ViajePoolTaxistaGate.viajeTomableEnPool(
      data,
      myUid,
      poolModoConductor: modo,
    )) {
      return true;
    }
    return _esViajeEspejoBolaEnVentana(data, myUid);
  }

  /// Misma clave que el tablero `bola_{id}` para no doblar timbre si llega espejo + publicación.
  String _timbreClaveViaje(
      String docId, Map<String, dynamic> data, String myUid) {
    if (_esViajeEspejoBolaEnVentana(data, myUid)) {
      final p =
          (data['bolaPuebloId'] ?? data['bolaId'] ?? '').toString().trim();
      if (p.isNotEmpty) return 'bola_$p';
    }
    return docId;
  }

  /// Nueva publicación en tablero Bola (abierta y no es la mía).
  bool _bolaDisparaTimbre(Map<String, dynamic> m, String myUid) {
    final estado = (m['estado'] ?? '').toString();
    if (estado != 'abierta') return false;
    final owner = (m['createdByUid'] ?? '').toString();
    if (owner.isNotEmpty && owner == myUid) return false;
    return true;
  }

  /// Pool “real”: ya hay tarifa (>0). Usado para la notificación en bandeja; el timbre in-app suena antes si hace falta.
  bool _viajeTienePrecioReal(Map<String, dynamic> data) {
    final dynamic pc = data['precio_cents'];
    if (pc is int && pc > 0) return true;
    if (pc is num && pc > 0) return true;
    double n(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      final s = v.toString().trim().replaceAll(',', '.');
      return double.tryParse(s) ?? 0;
    }

    final double pr = n(data['precio']);
    final double pf = n(data['precioFinal'] ?? data['total']);
    return pr > 0.009 || pf > 0.009;
  }

  bool _pasaFiltroAhoraLocal(Map<String, dynamic> d) {
    final String estadoNorm =
        EstadosViaje.normalizar((d['estado'] ?? '').toString());
    final String estadoRaw = (d['estado'] ?? '').toString().trim();
    final String estadoLower = estadoRaw.toLowerCase();
    final bool estadoPendiente = estadoNorm == EstadosViaje.pendiente ||
        estadoNorm == EstadosViaje.pendientePago ||
        estadoLower == 'buscando' ||
        estadoLower == 'disponible' ||
        estadoLower == 'pendiente_admin' ||
        estadoRaw == 'pendienteAdmin';
    if (!estadoPendiente) return false;

    final DateTime fecha = _fechaDe(d);
    final bool esAhora =
        (d['esAhora'] is bool) ? (d['esAhora'] as bool) : _calcEsAhora(fecha);
    DateTime? pub, acc;

    final publishAt = d['publishAt'];
    if (publishAt is fs.Timestamp) pub = publishAt.toDate();
    if (publishAt is DateTime) pub = publishAt;

    final rawA = d['acceptAfter'];
    if (rawA is fs.Timestamp) acc = rawA.toDate();
    if (rawA is DateTime) acc = rawA;

    final now = DateTime.now();

    // Fallback tolerante: si publishAt falta, no bloqueamos.
    final bool publishOk = (pub == null) || !now.isBefore(pub);
    final bool acceptOk = (acc == null) || !now.isBefore(acc);
    return esAhora && publishOk && acceptOk;
  }

  bool _pasaFiltroProgLocal(Map<String, dynamic> d) {
    final String estadoNorm =
        EstadosViaje.normalizar((d['estado'] ?? '').toString());
    final String estadoRaw = (d['estado'] ?? '').toString().trim();
    final String estadoLower = estadoRaw.toLowerCase();
    final bool estadoPendiente = estadoNorm == EstadosViaje.pendiente ||
        estadoNorm == EstadosViaje.pendientePago ||
        estadoLower == 'buscando' ||
        estadoLower == 'disponible' ||
        estadoLower == 'pendiente_admin' ||
        estadoRaw == 'pendienteAdmin';
    if (!estadoPendiente) return false;

    final DateTime fecha = _fechaDe(d);
    final bool esAhora =
        (d['esAhora'] is bool) ? (d['esAhora'] as bool) : _calcEsAhora(fecha);
    if (esAhora) return false;

    DateTime? pub, acc;

    final rawP = d['publishAt'];
    if (rawP is fs.Timestamp) pub = rawP.toDate();
    if (rawP is DateTime) pub = rawP;

    final rawA = d['acceptAfter'];
    if (rawA is fs.Timestamp) acc = rawA.toDate();
    if (rawA is DateTime) acc = rawA;

    final now = DateTime.now();

    // Fallback tolerante: si publishAt falta, no bloqueamos.
    final bool publishOk = (pub == null) || !now.isBefore(pub);
    final bool acceptOk = (acc == null) || !now.isBefore(acc);
    return publishOk && acceptOk;
  }

  Future<void> _aceptarViaje(
    Viaje v, {
    required bool disponible,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    final taxista = FirebaseAuth.instance.currentUser;

    if (taxista == null) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Debes iniciar sesión.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    try {
      final usr = await fs.FirebaseFirestore.instance
          .collection('usuarios')
          .doc(taxista.uid)
          .get();
      final uData = usr.data() ?? {};
      if (!mounted) return;
      final bool bloqueadoPerfil =
          await TaxistaOperacionNav.bloquearClaimSiPerfilIncompleto(
        context,
        uData: uData,
        poolModoConductor: _poolModoConductor,
      );
      if (bloqueadoPerfil) return;
    } catch (_) {}
    if (!disponible) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Activa tu disponibilidad para aceptar.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }
    if (_aceptandoIds.contains(v.id)) return;

    if (mounted) {
      setState(() => _aceptandoIds.add(v.id));
    }
    NavigatorState? rootNav;
    if (mounted) {
      rootNav = NavigationService.navigatorKey.currentState;
      rootNav ??= Navigator.of(context, rootNavigator: true);
    }
    ActiveTripService.bloquearShellTaxistaTrasAceptar(const Duration(minutes: 3));
    _navegandoAViajeActivo = true;
    var navegoAViajeEnCurso = false;

    try {
      await ViajesRepo.ensureTaxistaLibre(taxista.uid);
      await ViajesRepo.ensureSiguienteCoherente(taxista.uid);

      final res = await ViajesRepo.claimTripWithReason(
        viajeId: v.id,
        uidTaxista: taxista.uid,
        nombreTaxista: taxista.displayName ?? taxista.email ?? 'taxista',
        telefono: '',
        placa: '',
      );
      if (kDebugMode) debugPrint('[claimTripWithReason] $res');

      if (res == 'ok') {
        await NotificationService.I.stopTimbre();
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

        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('✅ Viaje aceptado. Redirigiendo...'),
              backgroundColor: Colors.green,
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
            const SnackBar(
              content: Text('Tienes un viaje activo. Redirigiendo...'),
              backgroundColor: Colors.orangeAccent,
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
        );
        if (yaAsignado) {
          await NotificationService.I.stopTimbre();
          if (mounted) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('✅ Viaje tomado. Abriendo viaje en curso...'),
                backgroundColor: Colors.green,
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
      }

      if (_claimIndicaViajeYaNoDisponible(res)) {
        _ocultarViajeDelPoolLocal(v.id);
      }

      if (!mounted) return;
      await TaxistaOperacionNav.guiarTrasFalloClaim(
        context,
        res: res,
        poolModoConductor: _poolModoConductor,
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ No se pudo aceptar: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (!navegoAViajeEnCurso) {
        ActiveTripService.cancelarMantenimientoOverlayViaje();
        _navegandoAViajeActivo = false;
      }
      if (mounted) {
        setState(() => _aceptandoIds.remove(v.id));
      }
    }
  }

  Future<bool> _confirmarAsignacionYRedirigir({
    required String viajeId,
    required String uidTaxista,
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
        final NavigatorState? preNav =
            NavigationService.navigatorKey.currentState;
        await NavigationService.irAViajeEnCursoTaxistaTrasAceptar(
          viajeId: viajeId,
          uidTaxista: uidTaxista,
          preNav: preNav,
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
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

  /// Misma regla que la lista (AHORA vs PROGRAMADOS).
  bool _esAhoraDesdeData(Map<String, dynamic> data) {
    final fecha = _fechaDe(data);
    return (data['esAhora'] is bool)
        ? (data['esAhora'] as bool)
        : _calcEsAhora(fecha);
  }

  String _shortPlace(String s) {
    var out = s.trim();
    if (out.isEmpty) return out;

    final reps = <RegExp, String>{
      RegExp(
        r'aeropuerto.*(las\s*a(m|́)e?ricas|sdq)',
        caseSensitive: false,
      ): 'AILA',
      RegExp(r'\b(sdq)\b', caseSensitive: false): 'AILA',
      RegExp(r'aeropuerto.*cibao', caseSensitive: false): 'Aeropuerto Cibao',
      RegExp(r'aeropuerto.*punta\s*cana|puj', caseSensitive: false):
          'Aeropuerto Punta Cana',
      RegExp(r'\bsto\.?\s*dgo\.?\b', caseSensitive: false): 'Santo Domingo',
      RegExp(r'distrito\s*nacional', caseSensitive: false): 'Santo Domingo',
      RegExp(
        r'rep(ú|u)blica\s*dominicana|dominican\s*republic|\brd\b',
        caseSensitive: false,
      ): '',
    };
    reps.forEach((re, sub) {
      out = out.replaceAll(re, sub).trim();
    });

    final firstSeg = out.split(',').first.trim();
    if (firstSeg.isNotEmpty && firstSeg.length <= 28) out = firstSeg;

    out = out.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    if (out.length > 28) {
      out = '${out.substring(0, 27).trimRight()}…';
    }
    return out;
  }

  String _getTextoDisponibilidad(DateTime acceptAfter, bool esAhora) {
    if (esAhora) return 'Disponible ahora';
    final ahora = DateTime.now();
    final minutosFaltantes = acceptAfter.difference(ahora).inMinutes;
    if (minutosFaltantes > 0) {
      return 'Disponible en $minutosFaltantes min';
    } else {
      return '✅ Disponible ahora';
    }
  }

  Widget _clienteAvatar(BuildContext context, String uidCliente) {
    final pal = context._poolTaxistaPal;
    final fallback = CircleAvatar(
      radius: 20,
      backgroundColor: pal.chipBg,
      child: Icon(Icons.person, color: pal.textSecondary, size: 20),
    );

    if (uidCliente.trim().isEmpty) return fallback;

    return StreamBuilder<fs.DocumentSnapshot<Map<String, dynamic>>>(
      stream: fs.FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uidCliente)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) return fallback;
        final data = snap.data!.data() ?? <String, dynamic>{};
        final String foto =
            (data['fotoUrl'] ?? data['photoURL'] ?? '').toString().trim();
        if (foto.isEmpty) return fallback;
        return CircleAvatar(
          radius: 20,
          backgroundColor: pal.chipBg,
          backgroundImage: NetworkImage(foto),
          onBackgroundImageError: (_, __) {},
        );
      },
    );
  }

  /// Solo el nombre (sin avatar); el avatar va aparte para no competir en ancho con badges de programado.
  Widget _clienteNombreSolo(BuildContext context, String uidCliente) {
    final pal = context._poolTaxistaPal;
    final style = TextStyle(
      color: pal.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w700,
    );
    final String uid = uidCliente.trim();
    if (uid.isEmpty) {
      return Text(
        'Cliente',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return StreamBuilder<fs.DocumentSnapshot<Map<String, dynamic>>>(
      stream: fs.FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? <String, dynamic>{};
        final String nombreRaw =
            (data['nombre'] ?? data['displayName'] ?? 'Cliente')
                .toString()
                .trim();
        final String nombre =
            nombreRaw.isEmpty ? 'Cliente' : nombreRaw.split(' ').first;
        return Text(
          nombre,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }

  Color _getColorDisponibilidad(BuildContext context, DateTime acceptAfter, bool esAhora) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (esAhora) {
      return isDark ? Colors.greenAccent : const Color(0xFF047857);
    }
    final ahora = DateTime.now();
    final minutosFaltantes = acceptAfter.difference(ahora).inMinutes;
    if (minutosFaltantes > 0) {
      return isDark ? Colors.orangeAccent : const Color(0xFFC2410C);
    }
    return isDark ? Colors.greenAccent : const Color(0xFF047857);
  }

  Widget _badgeModo(
    BuildContext context, {
    required bool esAhora,
    required DateTime fecha,
    required bool estaLiberado,
    required DateTime acceptAfter,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final icon = esAhora ? Icons.flash_on : Icons.schedule;
    final color = _getColorDisponibilidad(context, acceptAfter, esAhora);

    String txt;
    if (esAhora) {
      txt = 'Ahora';
    } else if (!estaLiberado) {
      txt = 'Se libera ${DateFormat('HH:mm').format(acceptAfter)}';
    } else {
      txt = 'Programado ${DateFormat('HH:mm').format(fecha)}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.10),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.7 : 0.55),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            txt,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipInfo(
    BuildContext context,
    IconData icon,
    String text, {
    Color? color,
  }) {
    final pal = context._poolTaxistaPal;
    final chipColor = color ?? pal.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: pal.chipBg,
        border: Border.all(color: pal.chipBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? pal.chipIcon),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: chipColor, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildPoolVehiculoIncompletoPlaceholder(BuildContext context) {
    final pal = context._poolTaxistaPal;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_car_outlined, size: 56, color: pal.accent),
            const SizedBox(height: 16),
            Text(
              'Completa tu vehículo',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: pal.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Placa, modelo, año, color y foto. Luego podrás ver y aceptar viajes aquí. '
              'Mientras tanto puedes usar Cuenta y Mis pagos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: pal.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => CompletarVehiculoTaxista(
                      onCompletado: () => Navigator.pop(context),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.edit_road),
              label: const Text('Completar vehículo'),
            ),
          ],
        ),
      ),
    );
  }

  /// Solo cuando el conductor está en «No disponible» (sin card estática de pool).
  Widget _bannerNoDisponiblePool({
    required bool disponible,
    required bool disponibilidadCargando,
  }) {
    if (disponibilidadCargando || disponible) {
      return const SizedBox.shrink();
    }
    final pal = context._poolTaxistaPal;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 152, 0, 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color.fromRGBO(255, 152, 0, 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.pause_circle_outline, color: pal.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No disponible — actívalo en Cuenta para recibir viajes del pool.',
              style: TextStyle(
                color: pal.textSecondary,
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Cabecera del pool (scrollable): saldo y avisos operativos.
  Widget _buildPoolScrollHeader({
    required String uidTaxista,
    required bool bloqueadoPago,
    required bool deudaSemanal,
    required bool disponible,
    required bool disponibilidadCargando,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SaldoRecargaPoolBanner(uidTaxista: uidTaxista),
        const RaiPoolOfflineHint(),
        if (bloqueadoPago)
          _bannerBloqueoSemanal()
        else if (deudaSemanal)
          _bannerRecordatorioPagoSemanal(),
        if (!bloqueadoPago)
          _bannerNoDisponiblePool(
            disponible: disponible,
            disponibilidadCargando: disponibilidadCargando,
          ),
      ],
    );
  }

  /// Deuda semanal sin tope de comisión: el taxista sigue operando; recordatorio en Mis pagos.
  Widget _bannerRecordatorioPagoSemanal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 193, 7, 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color.fromRGBO(255, 193, 7, 0.7)),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month, color: Colors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tienes un pago semanal pendiente: revísalo en Mis pagos y salda el monto de la semana. '
              'Mientras tanto puedes seguir tomando viajes y usando el pool.',
              style: TextStyle(
                color: isDark ? Colors.white70 : const Color(0xFF374151),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerBloqueoSemanal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(244, 67, 54, 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color.fromRGBO(244, 67, 54, 0.7)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              PagosTaxistaRepo.mensajeRecargaBannerLista,
              style: TextStyle(
                color: isDark ? Colors.white70 : const Color(0xFF374151),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Cuando hay bloqueo operativo, la lista queda vacía: mostramos siempre las mismas
  /// rutas que en [BloqueadoPorPagos] (Mis pagos + guía con banco) para que sea coherente
  /// con lo que el admin desbloquea al aprobar.
  Widget _panelBloqueoConOpcionesPago({
    required bool deudaSemanal,
    required bool deudaComision,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark ? Colors.white70 : const Color(0xFF4B5563);
    final textMuted = isDark ? Colors.white54 : const Color(0xFF6B7280);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () => TaxistaFinanzasNav.abrirMisPagos(
              context,
              scrollToRecargaSection: true,
            ),
            icon: const Icon(Icons.payment_rounded),
            label: const Text('Ir a Mis pagos'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => TaxistaFinanzasNav.abrirBloqueadoPagos(context),
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('Cuenta bancaria y pasos'),
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark ? Colors.white : const Color(0xFF111827),
              side: BorderSide(
                  color: isDark ? Colors.white38 : const Color(0xFFD1D5DB)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            PagosTaxistaRepo.mensajeRecargaListaVacia,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textSecondary,
              fontSize: 15,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white24 : const Color(0xFFE5E7EB),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Opciones según tu caso',
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF111827),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                if (deudaSemanal)
                  _bulletOpcionPago(
                    icon: Icons.calendar_month_outlined,
                    titulo: 'Pago semanal',
                    texto:
                        'En Mis pagos verás el monto de la semana. Transfiere, sube el comprobante (URL) y espera verificación del admin.',
                    textMuted: textMuted,
                    isDark: isDark,
                  ),
                if (deudaSemanal && deudaComision) const SizedBox(height: 12),
                if (deudaComision)
                  _bulletOpcionPago(
                    icon: Icons.savings_outlined,
                    titulo: 'Recarga comisión (efectivo)',
                    texto:
                        'En Mis pagos, recarga prepago: monto, foto del depósito. Al aprobar el admin, el monto '
                        'paga primero la comisión legacy pendiente (si hay) y el resto suma al prepago; '
                        'necesitás al menos RD\$${PagosTaxistaRepo.minSaldoPrepagoComisionRd.toStringAsFixed(0)} '
                        'disponible para comisión tras el 1.er viaje en efectivo.',
                    textMuted: textMuted,
                    isDark: isDark,
                  ),
                if (!deudaSemanal && !deudaComision)
                  Text(
                    'Abre Mis pagos para ver el detalle de lo pendiente.',
                    style:
                        TextStyle(color: textMuted, fontSize: 13, height: 1.35),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Cuando el administrador apruebe tu pago o recarga, el acceso se restablece solo: podrás ver viajes de nuevo sin reinstalar la app.',
            textAlign: TextAlign.center,
            style: TextStyle(color: textMuted, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _bulletOpcionPago({
    required IconData icon,
    required String titulo,
    required String texto,
    required Color textMuted,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: Colors.greenAccent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF111827),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                texto,
                style: TextStyle(color: textMuted, fontSize: 13, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bannerFallback(bool usarFallback) {
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
        'Sincronizando índice del pool (2–10 min). '
        'Mientras tanto filtramos en el dispositivo.',
        style: TextStyle(color: cs.onPrimaryContainer, fontSize: 12),
      ),
    );
  }

  Color _getColorForTipoServicio(BuildContext context, String tipoServicio) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (tipoServicio) {
      case 'motor':
        return isDark ? Colors.orange : const Color(0xFFEA580C);
      case 'turismo':
        return isDark ? Colors.purple : const Color(0xFF7C3AED);
      case 'bola_ahorro':
        return isDark ? const Color(0xFFFF8F00) : const Color(0xFFD97706);
      case 'normal':
      default:
        return isDark ? Colors.greenAccent : const Color(0xFF047857);
    }
  }

  IconData _getIconForTipoServicio(String tipoServicio) {
    switch (tipoServicio) {
      case 'motor':
        return Icons.motorcycle;
      case 'turismo':
        return Icons.beach_access;
      case 'bola_ahorro':
        return Icons.savings_outlined;
      case 'normal':
      default:
        return Icons.directions_car;
    }
  }

  String _getLabelForTipoServicio(String tipoServicio) {
    switch (tipoServicio) {
      case 'motor':
        return '🛵 MOTOR 🛵';
      case 'turismo':
        return '🏝️ TURISMO 🏝️';
      case 'bola_ahorro':
        return '💚 BOLA AHORRO';
      case 'normal':
      default:
        return '🚗 NORMAL';
    }
  }

  Widget _buildParadasWidget(BuildContext context, Viaje v) {
    if (v.waypoints == null || v.waypoints!.isEmpty) {
      return const SizedBox.shrink();
    }

    final pal = context._poolTaxistaPal;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: pal.chipBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: pal.chipBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📍 Paradas intermedias:',
            style: TextStyle(
              color: pal.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          ...v.waypoints!.asMap().entries.map((entry) {
            final int index = entry.key + 1;
            final Map<String, dynamic> waypoint = entry.value;
            final String label =
                waypoint['label']?.toString() ?? 'Parada $index';
            return Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.flag_circle,
                      size: 14, color: Colors.orangeAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$index. $label',
                      style: TextStyle(
                        color: pal.textSecondary,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildLista({
    required Stream<fs.QuerySnapshot<Map<String, dynamic>>> stream,
    required bool disponible,

    /// Evita mostrar «No disponible» mientras aún no llega el primer snapshot de `usuarios`.
    required bool disponibilidadCargando,
    required String myUid,
    required bool Function(Map<String, dynamic>) filtroLocalSiFallback,
    required bool ordenarAscEnMemoria,
    required bool usandoFallback,
    required bool esTabAhora,
    required double latTaxista,
    required double lonTaxista,
    required String poolModoConductor,
    bool nestedScrollChild = false,
  }) {
    final scrollPhysics = nestedScrollChild
        ? const ClampingScrollPhysics()
        : null;
    final scrollPrimary = !nestedScrollChild;

    Widget poolTabFill(Widget child) => SizedBox.expand(child: child);

    return StreamBuilder<fs.QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return poolTabFill(const _PoolEntradaLoading());
        }
        if (snapshot.hasError) {
          final errorMsg = snapshot.error.toString().toLowerCase();
          _diag(
              'stream error tab=${esTabAhora ? "ahora" : "prog"} fallback=${esTabAhora ? _usarFallbackSinIndiceAhora : _usarFallbackSinIndiceProg} msg=$errorMsg');
          // Si es error de índice, no mostramos error duro; forzamos fallback local.
          if (errorMsg.contains('index') ||
              errorMsg.contains('failed-precondition')) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                if (esTabAhora) {
                  _usarFallbackSinIndiceAhora = true;
                } else {
                  _usarFallbackSinIndiceProg = true;
                }
              });
              _arrancarTimbres();
            });
            return poolTabFill(const _PoolEntradaLoading());
          }
          // Evita falso "sin internet" cuando hay datos pero falló la query principal.
          // Si ya estamos en fallback y falla, mostramos vacío profesional en vez de error agresivo.
          final bool enFallback = esTabAhora
              ? _usarFallbackSinIndiceAhora
              : _usarFallbackSinIndiceProg;
          if (!enFallback) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                if (esTabAhora) {
                  _usarFallbackSinIndiceAhora = true;
                } else {
                  _usarFallbackSinIndiceProg = true;
                }
              });
              _arrancarTimbres();
            });
            return poolTabFill(const _PoolEntradaLoading());
          }
          return poolTabFill(
            EmptyTripsWidget(
              esTabAhora: esTabAhora,
              poolModoConductor: poolModoConductor,
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return poolTabFill(
            EmptyTripsWidget(
              esTabAhora: esTabAhora,
              poolModoConductor: poolModoConductor,
            ),
          );
        }

        final docs = snapshot.data!.docs.toList();
        final items = <_Item>[];

        if (!esTabAhora) {
          debugPrint('[POOL][PROGRAMADOS] docs=${docs.length}');
        } else {
          debugPrint('[POOL][AHORA] docs=${docs.length}');
        }

        for (final d in docs) {
          final data = d.data();

          if (_ocultosPoolLocal.contains(d.id)) continue;
          if (!filtroLocalSiFallback(data)) continue;
          if (!_disponibleParaMi(
            data,
            myUid,
            poolModoConductor: poolModoConductor,
          )) {
            continue;
          }

          final v = Viaje.fromMap(d.id, Map<String, dynamic>.from(data));

          final fecha = _fechaDe(data);
          final acceptAfter = _acceptAfterDe(data, fecha);

          final bool esAhoraDoc = (data['esAhora'] is bool)
              ? (data['esAhora'] as bool)
              : _calcEsAhora(fecha);

          if (esTabAhora && !esAhoraDoc) continue;
          if (!esTabAhora && esAhoraDoc) continue;

          final bool tieneCoordsCliente =
              v.latCliente.abs() > 0.000001 || v.lonCliente.abs() > 0.000001;
          final double? distanciaKmPickup = tieneCoordsCliente
              ? Geolocator.distanceBetween(
                    latTaxista,
                    lonTaxista,
                    v.latCliente,
                    v.lonCliente,
                  ) /
                  1000
              : null;

          // Producción: no bloquear visibilidad por distancia.
          // La distancia se muestra como dato informativo para decidir.

          items
              .add(_Item(v, fecha, acceptAfter, esAhoraDoc, distanciaKmPickup));
        }

        if (items.isEmpty) {
          debugPrint(
            '[POOL][${esTabAhora ? "AHORA" : "PROGRAMADOS"}] vacio tras filtros docs=${docs.length}',
          );
          _diag(
              'items empty tab=${esTabAhora ? "ahora" : "prog"} docs=${docs.length}');
          return poolTabFill(
            EmptyTripsWidget(
              esTabAhora: esTabAhora,
              poolModoConductor: poolModoConductor,
            ),
          );
        }
        _diag(
            'items ready tab=${esTabAhora ? "ahora" : "prog"} count=${items.length}');

        items.sort((a, b) {
          if (ordenarAscEnMemoria) {
            return a.fecha.compareTo(b.fecha);
          }
          final ad = a.distanciaKmPickup;
          final bd = b.distanciaKmPickup;
          if (ad != null && bd != null) {
            final c = ad.compareTo(bd);
            if (c != 0) return c;
          } else if (ad != null && bd == null) {
            return -1;
          } else if (ad == null && bd != null) {
            return 1;
          }
          return a.fecha.compareTo(b.fecha);
        });

        return ListView.separated(
          primary: scrollPrimary,
          physics: scrollPhysics,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (context, index) {
            final pal = context._poolTaxistaPal;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final it = items[index];
            final v = it.v;
            final fecha = it.fecha;
            final acceptAfter = it.acceptAfter;
            final esAhora = it.esAhora;
            final distanciaKmPickup = it.distanciaKmPickup;
            final aceptando = _aceptandoIds.contains(v.id);

            final bool puedeAceptar =
                esAhora || !DateTime.now().isBefore(acceptAfter);
            final String textoDisponibilidad =
                _getTextoDisponibilidad(acceptAfter, esAhora);
            final Color colorDisponibilidad =
                _getColorDisponibilidad(context, acceptAfter, esAhora);

            final bool estaLiberado =
                esAhora || !DateTime.now().isBefore(acceptAfter);

            final distanciaRecorrido = () {
              final extra = v.extras?['cotizacionDesglose'];
              if (extra is Map) {
                final km = extra['distanciaKm'] ?? extra['distanciaMedidaKm'];
                if (km is num && km > 0) return km.toDouble();
              }
              return DistanciaService.calcularDistancia(
                v.latCliente,
                v.lonCliente,
                v.latDestino,
                v.lonDestino,
              );
            }();

            final precioTotal = v.precio;

            final String uidPoolCliente =
                v.uidCliente.isNotEmpty ? v.uidCliente : v.clienteId;

            final Color servicioColor =
                _getColorForTipoServicio(context, v.tipoServicio);
            final IconData servicioIcon =
                _getIconForTipoServicio(v.tipoServicio);
            final String servicioLabel =
                _getLabelForTipoServicio(v.tipoServicio);

            final bool destacarCercano = esTabAhora &&
                index == 0 &&
                distanciaKmPickup != null &&
                distanciaKmPickup <= 40.0;
            final Color bordeCard = v.waypoints != null && v.waypoints!.isNotEmpty
                ? Colors.red.withValues(alpha: 0.7)
                : destacarCercano
                    ? pal.accent.withValues(alpha: 0.95)
                    : v.tipoServicio == 'motor'
                        ? Colors.orange.withValues(alpha: 0.5)
                        : pal.cardBorder;
            final double anchoBordeCard =
                v.waypoints != null && v.waypoints!.isNotEmpty
                    ? 3
                    : (destacarCercano ? 3 : 2);

            return Card(
              color: pal.cardBg,
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: bordeCard,
                  width: anchoBordeCard,
                ),
              ),
              elevation: isDark ? (destacarCercano ? 10 : 4) : (destacarCercano ? 3 : 1),
              shadowColor: isDark ? Colors.black : Colors.black26,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: _clienteAvatar(context, uidPoolCliente),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _clienteNombreSolo(context, uidPoolCliente),
                                  if (uidPoolCliente.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    ClientePerfilConductorChip(
                                      uidCliente: uidPoolCliente,
                                      compacto: true,
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      if (destacarCercano)
                                        Chip(
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          labelPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 8),
                                          backgroundColor: pal.accent
                                              .withValues(alpha: isDark ? 0.18 : 0.12),
                                          side: BorderSide(
                                              color: pal.accent.withValues(
                                                  alpha: isDark ? 1 : 0.65)),
                                          label: Text(
                                            '📍 Más cercano',
                                            style: TextStyle(
                                              color: isDark
                                                  ? Colors.greenAccent
                                                  : pal.accent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      _badgeModo(
                                        context,
                                        esAhora: esAhora,
                                        fecha: fecha,
                                        estaLiberado: estaLiberado,
                                        acceptAfter: acceptAfter,
                                      ),
                                      _CountdownChip(
                                        fecha: esAhora
                                            ? fecha
                                            : (estaLiberado
                                                ? fecha
                                                : acceptAfter),
                                        label: esAhora
                                            ? 'sale'
                                            : (estaLiberado
                                                ? 'sale'
                                                : 'se libera'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Tooltip(
                          message: '${v.origen} → ${v.destino}',
                          waitDuration: const Duration(milliseconds: 500),
                          child: Text(
                            "${_shortPlace(v.origen)} → ${_shortPlace(v.destino)}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: pal.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: servicioColor.withValues(alpha: isDark ? 0.2 : 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: servicioColor.withValues(
                                alpha: isDark ? 1 : 0.45,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(servicioIcon,
                                  size: 14, color: servicioColor),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  servicioLabel,
                                  maxLines: 3,
                                  softWrap: true,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: servicioColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('EEE d MMM, HH:mm', 'es').format(fecha),
                      style: TextStyle(
                        color: pal.textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    _buildParadasWidget(context, v),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chipInfo(
                          context,
                          Icons.near_me,
                          distanciaKmPickup != null
                              ? 'A ${distanciaKmPickup.toStringAsFixed(1)} km'
                              : 'Cercanía: sin ubicación de recogida',
                        ),
                        _chipInfo(
                          context,
                          Icons.straighten,
                          "Recorrido: ${FormatosMoneda.km(distanciaRecorrido)}",
                        ),
                        if (v.extras != null &&
                            v.extras!['cotizacionDesglose'] is Map &&
                            (v.extras!['cotizacionDesglose']
                                    as Map)['esLargaDistancia'] ==
                                true)
                          _chipInfo(
                            context,
                            Icons.route,
                            'Larga distancia',
                            color: Colors.deepOrangeAccent,
                          ),
                        _chipInfo(context, Icons.credit_card, v.metodoPago),
                        if (!esAhora)
                          _chipInfo(
                            context,
                            Icons.event,
                            DateFormat('dd/MM HH:mm').format(fecha),
                          ),
                        if (v.tipoVehiculo.isNotEmpty &&
                            v.tipoServicio != 'motor')
                          _chipInfo(context, Icons.local_taxi, v.tipoVehiculo),
                        if (v.extras != null && v.extras!['pasajeros'] != null)
                          _chipInfo(
                            context,
                            Icons.people,
                            '${v.extras!['pasajeros']} pasajero${v.extras!['pasajeros'] != 1 ? 's' : ''}',
                          ),
                        if (!esAhora)
                          _chipInfo(
                            context,
                            Icons.timer,
                            textoDisponibilidad,
                            color: colorDisponibilidad,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Total",
                                style: TextStyle(
                                  color: pal.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                FormatosMoneda.rd(precioTotal),
                                style: TextStyle(
                                  fontSize: 28,
                                  color: servicioColor,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
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
                                MaterialPageRoute(
                                  builder: (_) => DetalleViaje(viajeId: v.id),
                                ),
                              );
                              if (!mounted) return;
                              await _revalidarViajeVisibleEnPool(
                                viajeId: v.id,
                                myUid: myUid,
                                poolModoConductor: poolModoConductor,
                              );
                            },
                            icon:
                                Icon(Icons.info_outline, color: servicioColor),
                            label: Text('Ver detalles',
                                style: TextStyle(color: servicioColor)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: servicioColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (aceptando ||
                                    disponibilidadCargando ||
                                    !disponible ||
                                    !puedeAceptar)
                                ? null
                                : () =>
                                    _aceptarViaje(v, disponible: disponible),
                            icon: (aceptando || disponibilidadCargando)
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.check_circle,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                            label: Text(
                              aceptando
                                  ? "Aceptando..."
                                  : (!disponible
                                      ? "No disponible"
                                      : (!esAhora && !puedeAceptar
                                          ? "En ${acceptAfter.difference(DateTime.now()).inMinutes} min"
                                          : "Aceptar")),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: const Color(0xFF16A34A),
                              disabledBackgroundColor: isDark
                                  ? Colors.white24
                                  : const Color(0xFFE5E7EB),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
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

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;

    if (u == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: const RaiAppBar(
          title: 'Viajes Disponibles',
        ),
        body: const Center(
          child: Text(
            'Inicia sesión',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    // Evita arrancar la actualización de ubicación en cada rebuild.
    if (!_ubicacionActualizacionIniciada) {
      UbicacionTaxista.iniciarActualizacion();
      _ubicacionActualizacionIniciada = true;
    }

    return StreamBuilder<Position>(
      stream: UbicacionTaxista.obtenerStreamUbicacion().timeout(
        const Duration(seconds: 15),
        onTimeout: (EventSink<Position> sink) {
          sink.add(Position(
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
          ));
        },
      ),
      builder: (context, ubicacionSnapshot) {
        // 🔥 MOSTRAR INMEDIATAMENTE CON CACHÉ MIENTRAS LLEGA LA REAL
        if (ubicacionSnapshot.connectionState == ConnectionState.waiting) {
          // Para producción (tipo Uber/indriver): no bloqueamos la entrada
          // al pool esperando GPS; usamos caché si existe o una posición
          // por defecto hasta llegar la real.
          if (_ubicacionCache != null) {
            return _buildContenidoPrincipal(context, _ubicacionCache!, u);
          }
          final Position posicionPorDefecto = Position(
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
          return _buildContenidoPrincipal(context, posicionPorDefecto, u);
        }

        if (ubicacionSnapshot.hasError) {
          if (_ubicacionCache != null) {
            return _buildContenidoPrincipal(context, _ubicacionCache!, u);
          }
          final Position posicionPorDefecto = Position(
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
          return _buildContenidoPrincipal(context, posicionPorDefecto, u);
        }

        final pos = ubicacionSnapshot.data;

        if (pos == null) {
          if (_ubicacionCache != null) {
            return _buildContenidoPrincipal(context, _ubicacionCache!, u);
          }
          final Position posicionPorDefecto = Position(
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
          return _buildContenidoPrincipal(context, posicionPorDefecto, u);
        }

        // 🔥 GUARDAR UBICACIÓN EN CACHÉ
        // Evita escribir en SharedPreferences con demasiada frecuencia.
        final now = DateTime.now();
        if (_ultimaPersistenciaUbicacion == null ||
            now.difference(_ultimaPersistenciaUbicacion!) >
                const Duration(seconds: 30)) {
          _ultimaPersistenciaUbicacion = now;
          _guardarUbicacionCache(pos);
        }

        return _buildContenidoPrincipal(context, pos, u);
      },
    );
  }

  Widget _buildContenidoPrincipal(BuildContext context, Position pos, User u) {
    final pal = context._poolTaxistaPal;
    final cs = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final accesibilidad = media.textScaler.clamp(
      minScaleFactor: 1.08,
      maxScaleFactor: 1.18,
    );

    final streamAhora = _usarFallbackSinIndiceAhora
        ? _qFallbackBase().snapshots()
        : _qPoolAhora().limit(120).snapshots();

    final streamProg = _usarFallbackSinIndiceProg
        ? _qFallbackBase().snapshots()
        : _qPoolProgramados().limit(200).snapshots();

    return MediaQuery(
      data: media.copyWith(textScaler: accesibilidad),
      child: Scaffold(
        backgroundColor: pal.scaffoldBg,
        appBar: RaiAppBar(
          title: 'RAI Driver',
          actions: [
            _PoolTurismoAppBarAction(uid: u.uid),
            const SaldoGananciasChip(),
          ],
          bottom: TabBar(
            controller: _tabPool,
            indicatorColor: pal.accent,
            labelColor: pal.accent,
            unselectedLabelColor: pal.textMuted,
            dividerColor: cs.outlineVariant.withValues(alpha: 0.45),
            tabs: const [
              Tab(text: 'BOLA'),
              Tab(text: 'AHORA'),
              Tab(text: 'PROGRAMADOS'),
            ],
          ),
        ),
        body: StreamBuilder<bool>(
            stream: RolesService.streamDisponibilidad(u.uid),
            builder: (context, dispSnap) {
              final disponibilidadCargando =
                  dispSnap.connectionState == ConnectionState.waiting &&
                      !dispSnap.hasData;
              final disponible = dispSnap.data ?? false;
              return StreamBuilder<fs.DocumentSnapshot<Map<String, dynamic>>>(
                stream: fs.FirebaseFirestore.instance
                    .collection('usuarios')
                    .doc(u.uid)
                    .snapshots(),
                builder: (context, usrSnap) {
                  if (usrSnap.connectionState == ConnectionState.waiting &&
                      !usrSnap.hasData) {
                    return RaiLinearLoadingBody(backgroundColor: pal.scaffoldBg);
                  }
                  final Map<String, dynamic>? uData = usrSnap.data?.data();
                  if (uData != null && !taxistaVehiculoPerfilCompleto(uData)) {
                    return _buildPoolVehiculoIncompletoPlaceholder(context);
                  }
                  final String poolModo =
                      ViajePoolTaxistaGate.poolModoConductorDesdeUsuario(uData);
                  if (poolModo != _poolModoConductor) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() => _poolModoConductor = poolModo);
                      _arrancarTimbres();
                    });
                  }
                  final Object debtKey = Object.hash(
                    uData?['tienePagoPendiente'] == true,
                    (uData?['updatedAt'] ?? '').toString(),
                  );
                  return FutureBuilder<List<bool>>(
                    key: ValueKey<Object>(debtKey),
                    future: Future.wait<bool>([
                      PagosTaxistaRepo.tieneBloqueoSemanal(u.uid),
                      PagosTaxistaRepo.tieneBloqueoComisionEfectivo(u.uid),
                    ]),
                    builder: (context, pagoSnap) {
                      final vals = pagoSnap.data;
                      final bool deudaSemanal =
                          vals != null && vals.isNotEmpty && vals[0];
                      final bool deudaComision =
                          vals != null && vals.length > 1 && vals[1];
                      final bool bloqueoPorBanderaUsuario =
                          uData?['tienePagoPendiente'] == true;
                      // `deudaComision` = billetera (prepago/legacy). `tienePagoPendiente` incluye también
                      // deuda pool ≥ umbral (misma regla que Cloud Functions).
                      final bool bloqueadoPago =
                          deudaComision || bloqueoPorBanderaUsuario;
                      if (bloqueadoPago) {
                        Future.microtask(
                            () => _notificarBloqueoPagoSiAplica(u.uid));
                      }
                      if (bloqueadoPago) {
                        return Column(
                          children: [
                            _buildPoolScrollHeader(
                              uidTaxista: u.uid,
                              bloqueadoPago: true,
                              deudaSemanal: deudaSemanal,
                              disponible: disponible,
                              disponibilidadCargando: disponibilidadCargando,
                            ),
                            _bannerFallback(
                              _usarFallbackSinIndiceAhora ||
                                  _usarFallbackSinIndiceProg,
                            ),
                            Expanded(
                              child: _panelBloqueoConOpcionesPago(
                                deudaSemanal: deudaSemanal,
                                deudaComision: deudaComision,
                              ),
                            ),
                          ],
                        );
                      }
                      final bool usarFallbackIndice =
                          _usarFallbackSinIndiceAhora ||
                              _usarFallbackSinIndiceProg;
                      return Column(
                        children: [
                          _buildPoolScrollHeader(
                            uidTaxista: u.uid,
                            bloqueadoPago: false,
                            deudaSemanal: deudaSemanal,
                            disponible: disponible,
                            disponibilidadCargando:
                                disponibilidadCargando,
                          ),
                          _bannerFallback(usarFallbackIndice),
                          Expanded(
                            child: TabBarView(
                              controller: _tabPool,
                              children: [
                                BolaPuebloDisponibleTab(
                                  user: u,
                                  disponible: disponible,
                                  disponibilidadCargando:
                                      disponibilidadCargando,
                                ),
                                _buildLista(
                                  stream: streamAhora,
                                  disponible: disponible,
                                  disponibilidadCargando:
                                      disponibilidadCargando,
                                  myUid: u.uid,
                                  filtroLocalSiFallback:
                                      _pasaFiltroAhoraLocal,
                                  ordenarAscEnMemoria: false,
                                  usandoFallback:
                                      _usarFallbackSinIndiceAhora,
                                  esTabAhora: true,
                                  latTaxista: pos.latitude,
                                  lonTaxista: pos.longitude,
                                  poolModoConductor: poolModo,
                                ),
                                _buildLista(
                                  stream: streamProg,
                                  disponible: disponible,
                                  disponibilidadCargando:
                                      disponibilidadCargando,
                                  myUid: u.uid,
                                  filtroLocalSiFallback:
                                      _pasaFiltroProgLocal,
                                  ordenarAscEnMemoria: true,
                                  usandoFallback:
                                      _usarFallbackSinIndiceProg,
                                  esTabAhora: false,
                                  latTaxista: pos.latitude,
                                  lonTaxista: pos.longitude,
                                  poolModoConductor: poolModo,
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
}

/// Saldo prepago: una línea por defecto; tap para desplegar el detalle completo.
class _SaldoRecargaPoolBanner extends StatefulWidget {
  const _SaldoRecargaPoolBanner({required this.uidTaxista});

  final String uidTaxista;

  @override
  State<_SaldoRecargaPoolBanner> createState() =>
      _SaldoRecargaPoolBannerState();
}

class _SaldoRecargaPoolBannerState extends State<_SaldoRecargaPoolBanner> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final minSaldo = PagosTaxistaRepo.minSaldoPrepagoComisionRd;
    return StreamBuilder<fs.DocumentSnapshot<Map<String, dynamic>>>(
      stream: fs.FirebaseFirestore.instance
          .collection('billeteras_taxista')
          .doc(widget.uidTaxista)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final saldo = PagosTaxistaRepo.saldoPrepagoComisionDesdeBilletera(data);
        final disponible =
            PagosTaxistaRepo.saldoDisponiblePrepagoComisionDesdeBilletera(data);
        final pendLegacy =
            PagosTaxistaRepo.comisionPendienteDesdeBilletera(data);
        final legacyTope = PagosTaxistaRepo.bloqueoPorComisionLegacyTope(data);
        final bloqueado =
            PagosTaxistaRepo.bloqueoOperativoPorComisionEfectivo(data);
        final ultimaComisionCents = data?['ultimaComisionCents'];
        final ultimaComisionRd = (ultimaComisionCents is num)
            ? (ultimaComisionCents.toDouble() / 100.0)
            : 0.0;
        final viajesEstimados = ultimaComisionRd > 0
            ? (disponible / ultimaComisionRd).floor().clamp(0, 9999)
            : null;
        final faltante = (minSaldo - disponible).clamp(0.0, double.infinity);

        final resumen = bloqueado
            ? 'Recarga bloqueada · disp. ${FormatosMoneda.rd(disponible)}'
            : 'Prepago ${FormatosMoneda.rd(saldo)} · disp. ${FormatosMoneda.rd(disponible)}';

        final detalle = bloqueado
            ? (legacyTope
                ? 'Recarga BLOQUEADA: comisión legacy ${FormatosMoneda.rd(pendLegacy)} (tope RD\$${PagosTaxistaRepo.umbralComisionLegacyBloqueoRd.toStringAsFixed(0)}). '
                    'Prepago bruto: ${FormatosMoneda.rd(saldo)}; disponible p. comisión: ${FormatosMoneda.rd(disponible)}.'
                : 'Recarga BLOQUEADA. Disponible p. comisión: ${FormatosMoneda.rd(disponible)} '
                    '(mín. RD\$${minSaldo.toStringAsFixed(0)}). Te faltan ${FormatosMoneda.rd(faltante)}. '
                    'Legacy pendiente: ${FormatosMoneda.rd(pendLegacy)}.')
            : 'Saldo recarga: ${FormatosMoneda.rd(saldo)} (disponible p. comisión: ${FormatosMoneda.rd(disponible)}). '
                '${viajesEstimados == null ? '' : 'Estimado: ~$viajesEstimados viajes como el último antes del mínimo. '}'
                'Legacy pendiente: ${FormatosMoneda.rd(pendLegacy)}.';

        final textColor = isDark
            ? Colors.white.withValues(alpha: 0.88)
            : const Color(0xFF1E3A8A);
        final iconColor =
            bloqueado ? Colors.redAccent : const Color(0xFF2563EB);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _expandido = !_expandido),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: bloqueado
                    ? (isDark
                        ? const Color.fromRGBO(244, 67, 54, 0.15)
                        : const Color.fromRGBO(254, 226, 226, 1))
                    : (isDark
                        ? const Color.fromRGBO(33, 150, 243, 0.12)
                        : const Color(0xFFEFF6FF)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: bloqueado
                      ? (isDark
                          ? const Color.fromRGBO(244, 67, 54, 0.65)
                          : const Color(0xFFF87171))
                      : (isDark
                          ? const Color.fromRGBO(33, 150, 243, 0.55)
                          : const Color(0xFFBFDBFE)),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    bloqueado
                        ? Icons.warning_amber_rounded
                        : Icons.account_balance_wallet_outlined,
                    color: iconColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _expandido ? detalle : resumen,
                          style: TextStyle(
                            color: textColor,
                            fontSize: _expandido ? 12 : 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expandido
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: textColor.withValues(alpha: 0.55),
                    size: 20,
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

/// Pool turístico en la barra superior (solo choferes aprobados).
class _PoolTurismoAppBarAction extends StatelessWidget {
  const _PoolTurismoAppBarAction({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return StreamBuilder<fs.DocumentSnapshot<Map<String, dynamic>>>(
      stream: fs.FirebaseFirestore.instance
          .collection('choferes_turismo')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data();
        final estado = (d?['estado'] ?? '').toString().trim().toLowerCase();
        final ok = estado == 'aprobado' || estado == 'activo';
        if (!ok) return const SizedBox.shrink();
        final color = isDark ? Colors.purple.shade200 : const Color(0xFF7E22CE);
        return Padding(
          padding: const EdgeInsets.only(right: 2),
          child: IconButton(
            tooltip: 'Pool turístico',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PoolTurismoTaxista(),
                ),
              );
            },
            icon: Icon(Icons.tour_rounded, color: color),
            style: IconButton.styleFrom(
              backgroundColor: color.withValues(alpha: isDark ? 0.18 : 0.12),
              foregroundColor: color,
              minimumSize: const Size(40, 40),
              padding: EdgeInsets.zero,
            ),
          ),
        );
      },
    );
  }
}

class _CountdownChip extends StatelessWidget {
  final DateTime fecha;
  final String label;
  const _CountdownChip({required this.fecha, this.label = 'sale'});

  String _fmt(Duration d) {
    if (d.inSeconds <= 0) return 'ahora';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h <= 0) return 'en ${m}m';
    return 'en ${h}h ${m.toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color chipColor =
        isDark ? const Color(0xFF67E8F9) : const Color(0xFF0E7490);
    return StreamBuilder<DateTime>(
      stream: Stream<DateTime>.periodic(
        const Duration(seconds: 30),
        (_) => DateTime.now(),
      ),
      initialData: DateTime.now(),
      builder: (context, snap) {
        final now = snap.data ?? DateTime.now();
        final txt = _fmt(fecha.difference(now));

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: chipColor.withValues(alpha: isDark ? 0.12 : 0.10),
            border: Border.all(
              color: chipColor.withValues(alpha: isDark ? 0.7 : 0.45),
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timer, size: 14, color: chipColor),
              const SizedBox(width: 6),
              Text(
                '$label $txt',
                style: TextStyle(
                  color: chipColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
