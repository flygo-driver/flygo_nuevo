// ignore_for_file: avoid_print, prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'dart:async';
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
import 'package:flygo_nuevo/servicios/notification_service.dart';
import 'package:flygo_nuevo/widgets/taxista_drawer.dart';
import 'package:flygo_nuevo/widgets/saldo_ganancias_chip.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';
import 'package:flygo_nuevo/servicios/disponibilidad_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/servicios/ubicacion_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/detalle_viaje.dart';
import 'package:flygo_nuevo/widgets/loading_professional.dart';
import 'package:flygo_nuevo/widgets/empty_trips_widget.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';

class _Item {
  final Viaje v;
  final DateTime fecha;
  final DateTime acceptAfter;
  final bool esAhora;
  final double distancia;
  const _Item(this.v, this.fecha, this.acceptAfter, this.esAhora, this.distancia);
}

class ViajeDisponible extends StatefulWidget {
  const ViajeDisponible({super.key});
  @override
  State<ViajeDisponible> createState() => _ViajeDisponibleState();
}

class _ViajeDisponibleState extends State<ViajeDisponible>
    with WidgetsBindingObserver {
  static const String _kDebtNotifLastTsKey = 'debt_notif_last_ts_v1';
  static const String _kDebtGraceStartTsKey = 'debt_grace_start_ts_v1';
  static const Duration _debtNotifCooldown = Duration(hours: 12);
  static const Duration _debtBlockGrace = Duration(hours: 2);
  static const bool _diagTripFlow =
      bool.fromEnvironment('TRIP_FLOW_DIAG', defaultValue: false);
  void _diag(String msg) {
    if (_diagTripFlow) debugPrint('[TRIP_FLOW][disponible] $msg');
  }

  final Set<String> _aceptandoIds = <String>{};
  final Set<String> _vistosParaTimbre = <String>{};

  StreamSubscription<fs.QuerySnapshot<Map<String, dynamic>>>? _subTimbreAhora;
  StreamSubscription<fs.QuerySnapshot<Map<String, dynamic>>>? _subTimbreProg;
  
  // Listener estable para viaje activo (evita parpadeos por queries amplias).
  StreamSubscription<fs.DocumentSnapshot<Map<String, dynamic>>>? _activeUserListener;
  StreamSubscription<fs.DocumentSnapshot<Map<String, dynamic>>>? _activeTripListener;
  String? _activeTripListeningId;
  bool _navegandoAViajeActivo = false;
  Timer? _timer;
  bool _debtNotifInFlight = false;

  bool _usarFallbackSinIndiceAhora = false;
  bool _usarFallbackSinIndiceProg = false;

  bool _ignorarPrimeraEmisionTimbreAhora = true;
  bool _ignorarPrimeraEmisionTimbreProg = true;
  bool _appEnForeground = true;

  static const List<String> _kEstadosPend = <String>[
    EstadosViaje.pendiente,
    'buscando',
    'disponible',
    'pendiente_pago',
    'pendientePago',
    'pendiente_admin',
    'pendienteAdmin',
  ];

  static const double _radioBusquedaKm = 50.0;

  // 🔥 CACHÉ DE UBICACIÓN
  Position? _ubicacionCache;
  bool _ubicacionActualizacionIniciada = false;
  DateTime? _ultimaPersistenciaUbicacion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    FirebaseAuth.instance.currentUser?.getIdToken(true);
    
    // 🔥 NUEVO: Escuchar si ya tiene un viaje activo
    _checkExistingActiveTrip();

    Future.microtask(() => NotificationService.I.ensureInited());
    Future.microtask(() async {
      await _probarIndices();
      _arrancarTimbres();
      if (mounted) setState(() {});
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

  bool _esViajeActivoReal(Map<String, dynamic> data, String uid) {
    final String uidTaxista = (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString();
    if (uidTaxista != uid) return false;

    final String estado = EstadosViaje.normalizar((data['estado'] ?? '').toString());
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

    final userRef = fs.FirebaseFirestore.instance.collection('usuarios').doc(uid);
    _activeUserListener = userRef.snapshots().listen((uSnap) async {
      if (!mounted) return;
      final uData = uSnap.data() ?? <String, dynamic>{};
      final String viajeActivoId = (uData['viajeActivoId'] ?? '').toString().trim();

      if (viajeActivoId.isEmpty) {
        _diag('user.viajeActivoId empty -> stay in disponible');
        await _activeTripListener?.cancel();
        _activeTripListener = null;
        _activeTripListeningId = null;
        return;
      }

      if (_activeTripListeningId == viajeActivoId && _activeTripListener != null) {
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
        if (_navegandoAViajeActivo) return;
        _diag('active trip confirmed id=$viajeActivoId -> redirect en_curso');
        _navegandoAViajeActivo = true;
        await Future.delayed(const Duration(milliseconds: 450));
        if (!mounted) return;
        _redirectToActiveTrip();
      });
    });
  }

  // 🔥 NUEVO MÉTODO: Redirigir a viaje en curso
  void _redirectToActiveTrip() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ViajeEnCursoTaxista()),
    );
  }

  @override
  void dispose() {
    _activeUserListener?.cancel();
    _activeTripListener?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _subTimbreAhora?.cancel();
    _subTimbreProg?.cancel();
    _timer?.cancel();
    NotificationService.I.stopTimbre();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appEnForeground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      _arrancarTimbres();
      if (mounted) setState(() {});
    } else {
      NotificationService.I.stopTimbre();
    }
  }

  // 🔥 GUARDAR UBICACIÓN EN CACHÉ
  Future<void> _guardarUbicacionCache(Position pos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ultima_lat', pos.latitude);
    await prefs.setDouble('ultima_lon', pos.longitude);
    await prefs.setDouble('ultima_timestamp', pos.timestamp.millisecondsSinceEpoch.toDouble());
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

    _ignorarPrimeraEmisionTimbreAhora = true;
    _ignorarPrimeraEmisionTimbreProg = true;

    final fs.Query<Map<String, dynamic>> qA =
        _usarFallbackSinIndiceAhora ? _qFallbackBase() : _qPoolAhora();
    final fs.Query<Map<String, dynamic>> qP =
        _usarFallbackSinIndiceProg ? _qFallbackBase() : _qPoolProgramados();

    _subTimbreAhora = qA.limit(60).snapshots().listen((snap) async {
      if (!_appEnForeground) return;
      final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

      // Primera emisión: solo marcamos como "vistos" para que nuevos viajes
      // (posteriores) disparen timbre, sin notificar todo lo existente.
      if (_ignorarPrimeraEmisionTimbreAhora) {
        _ignorarPrimeraEmisionTimbreAhora = false;
        for (final d in snap.docs) {
          final data = d.data();
          if (_usarFallbackSinIndiceAhora && !_pasaFiltroAhoraLocal(data)) {
            continue;
          }
          if (!_disponibleParaMi(data, myUid)) continue;
          if (!_esAhoraDesdeData(data)) continue;
          if (!_viajeTienePrecioReal(data)) continue;
          _vistosParaTimbre.add(d.id);
        }
        return;
      }

      for (final d in snap.docs) {
        final data = d.data();
        if (_usarFallbackSinIndiceAhora && !_pasaFiltroAhoraLocal(data)) {
          continue;
        }
        if (!_disponibleParaMi(data, myUid)) continue;
        if (!_esAhoraDesdeData(data)) continue;
        if (!_viajeTienePrecioReal(data)) continue;

        final id = d.id;
        if (_vistosParaTimbre.contains(id)) continue;
        _vistosParaTimbre.add(id);

        await NotificationService.I.playPoolOfferSoundInApp();
        await NotificationService.I.notifyNuevoViaje(
          viajeId: id,
          titulo: 'Nuevo viaje disponible',
          cuerpo:
              '${(data['origen'] ?? 'Origen')} → ${(data['destino'] ?? 'Destino')}',
          skipSound: true,
        );
      }
    });

    _subTimbreProg = qP.limit(80).snapshots().listen((snap) async {
      if (!_appEnForeground) return;
      final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

      // Primera emisión: marcar como "vistos" para que solo nuevos viajes
      // posteriores disparen sonido.
      if (_ignorarPrimeraEmisionTimbreProg) {
        _ignorarPrimeraEmisionTimbreProg = false;
        for (final d in snap.docs) {
          final data = d.data();
          if (_usarFallbackSinIndiceProg && !_pasaFiltroProgLocal(data)) {
            continue;
          }
          if (!_disponibleParaMi(data, myUid)) continue;
          if (_esAhoraDesdeData(data)) continue;
          if (!_viajeTienePrecioReal(data)) continue;
          _vistosParaTimbre.add(d.id);
        }
        return;
      }

      for (final d in snap.docs) {
        final data = d.data();
        if (_usarFallbackSinIndiceProg && !_pasaFiltroProgLocal(data)) {
          continue;
        }
        if (!_disponibleParaMi(data, myUid)) continue;
        if (_esAhoraDesdeData(data)) continue;
        if (!_viajeTienePrecioReal(data)) continue;

        final id = d.id;
        if (_vistosParaTimbre.contains(id)) continue;
        _vistosParaTimbre.add(id);

        await NotificationService.I.playPoolOfferSoundInApp();
        await NotificationService.I.notifyNuevoViaje(
          viajeId: id,
          titulo: 'Viaje programado disponible',
          cuerpo:
              '${(data['origen'] ?? 'Origen')} → ${(data['destino'] ?? 'Destino')}',
          skipSound: true,
        );
      }
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
        viajeId: 'deuda_semanal_$uidTaxista',
        titulo: 'Pago semanal pendiente',
        cuerpo: 'Debes pagar la comisión de RAI para volver a recibir viajes.',
      );
      await prefs.setInt(_kDebtNotifLastTsKey, nowMs);
    } catch (_) {
      // Sin crash en UI si falla notificación.
    } finally {
      _debtNotifInFlight = false;
    }
  }

  Future<bool> _debeBloquearPorDeuda(String uidTaxista, bool bloqueadoPago) async {
    final prefs = await SharedPreferences.getInstance();
    if (!bloqueadoPago) {
      await prefs.remove(_kDebtGraceStartTsKey);
      return false;
    }

    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final int inicioMs = prefs.getInt(_kDebtGraceStartTsKey) ?? 0;

    if (inicioMs <= 0) {
      await prefs.setInt(_kDebtGraceStartTsKey, nowMs);
      return false; // Ventana de gracia recién iniciada.
    }

    return (nowMs - inicioMs) >= _debtBlockGrace.inMilliseconds;
  }

  Future<String> _textoVentanaGracia() async {
    final prefs = await SharedPreferences.getInstance();
    final int inicioMs = prefs.getInt(_kDebtGraceStartTsKey) ?? 0;
    if (inicioMs <= 0) return 'Debes pagar la comisión de RAI.';
    final DateTime inicio = DateTime.fromMillisecondsSinceEpoch(inicioMs);
    final DateTime limite = inicio.add(_debtBlockGrace);
    final Duration restante = limite.difference(DateTime.now());
    if (restante.inSeconds <= 0) {
      return 'Debes pagar la comisión de RAI.';
    }
    final int h = restante.inHours;
    final int m = restante.inMinutes.remainder(60);
    return 'Debes pagar la comisión de RAI. El bloqueo total aplica en ${h}h ${m}m.';
    }

  bool _disponibleParaMi(Map<String, dynamic> data, String myUid) {
    return ViajePoolTaxistaGate.viajeTomableEnPool(data, myUid);
  }

  /// Pool “real”: ya hay tarifa (>0). Evita timbre en borradores; si el precio llega después, sí suena.
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
    final String estadoNorm = EstadosViaje.normalizar((d['estado'] ?? '').toString());
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
    final bool esAhora = (d['esAhora'] is bool)
        ? (d['esAhora'] as bool)
        : _calcEsAhora(fecha);
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
    final String estadoNorm = EstadosViaje.normalizar((d['estado'] ?? '').toString());
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
    final bool esAhora = (d['esAhora'] is bool)
        ? (d['esAhora'] as bool)
        : _calcEsAhora(fecha);
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
      print('🔴 RESULTADO claimTripWithReason: $res');

      if (!mounted) return;

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

        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text('✅ Viaje aceptado. Redirigiendo...'),
            backgroundColor: Colors.green,
          ),
        );
        
        // 🔥 NUEVO: Redirigir a viaje en curso
        _redirectToActiveTrip();
        return;
      }

      if (res == 'taxista-ocupado') {
        await NotificationService.I.stopTimbre();
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Tienes un viaje activo. Redirigiendo...'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        // 🔥 NUEVO: Redirigir a viaje en curso
        _redirectToActiveTrip();
        return;
      }

      if (res.startsWith('permiso:')) {
        final bool yaAsignado = await _confirmarAsignacionYRedirigir(
          viajeId: v.id,
          uidTaxista: taxista.uid,
        );
        if (yaAsignado) {
          await NotificationService.I.stopTimbre();
          if (!mounted) return;
          messenger.showSnackBar(
            const SnackBar(
              content: Text('✅ Viaje tomado. Abriendo viaje en curso...'),
              backgroundColor: Colors.green,
            ),
          );
          return;
        }
      }

      final msg = () {
        switch (res) {
          case 'bloqueado-pago-semanal':
            return 'Debes saldar tu pago semanal para aceptar viajes.';
          case 'no-existe':
            return 'El viaje ya no existe.';
          case 'estado-no-pendiente':
            return 'El viaje ya no está pendiente.';
          case 'ya-asignado':
            return 'Ese viaje ya fue asignado.';
          case 'acceptAfter-futuro':
            return 'Aún no se libera (acceptAfter en el futuro).';
          case 'publish-futuro':
            return 'Aún no se publica (publishAt en el futuro).';
          case 'reservado-otro':
            return 'Reservado por otro taxista.';
          case 'taxista-ocupado':
            return 'Tienes un viaje activo. Finalízalo o cancélalo.';
          default:
            if (res.startsWith('permiso:')) {
              return 'Permisos/reglas Firestore: ${res.split(':').last}';
            }
            return 'No se pudo aceptar: $res';
        }
      }();

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
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
        await fs.FirebaseFirestore.instance.collection('usuarios').doc(uidTaxista).set({
          'viajeActivoId': viajeId,
          'updatedAt': fs.FieldValue.serverTimestamp(),
          'actualizadoEn': fs.FieldValue.serverTimestamp(),
        }, fs.SetOptions(merge: true));
        if (mounted) _redirectToActiveTrip();
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
    return fecha.subtract(const Duration(hours: 2));
  }

  bool _calcEsAhora(DateTime fecha) =>
      !fecha.isAfter(DateTime.now().add(const Duration(minutes: 15)));

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

  Widget _clienteAvatar(String uidCliente) {
    final fallback = CircleAvatar(
      radius: 20,
      backgroundColor: Colors.white12,
      child: const Icon(Icons.person, color: Colors.white70, size: 20),
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
        final String foto = (data['fotoUrl'] ?? data['photoURL'] ?? '')
            .toString()
            .trim();
        if (foto.isEmpty) return fallback;
        return CircleAvatar(
          radius: 20,
          backgroundColor: Colors.white12,
          backgroundImage: NetworkImage(foto),
          onBackgroundImageError: (_, __) {},
        );
      },
    );
  }

  Widget _clienteInfoHeader(String uidCliente) {
    final String uid = uidCliente.trim();
    final Widget avatar = _clienteAvatar(uid);

    if (uid.isEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          const SizedBox(width: 8),
          const Text(
            'Cliente',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return StreamBuilder<fs.DocumentSnapshot<Map<String, dynamic>>>(
      stream: fs.FirebaseFirestore.instance.collection('usuarios').doc(uid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? <String, dynamic>{};
        final String nombreRaw = (data['nombre'] ?? data['displayName'] ?? 'Cliente')
            .toString()
            .trim();
        final String nombre = nombreRaw.isEmpty ? 'Cliente' : nombreRaw.split(' ').first;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            avatar,
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 74),
              child: Text(
                nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Color _getColorDisponibilidad(DateTime acceptAfter, bool esAhora) {
    if (esAhora) return Colors.greenAccent;
    final ahora = DateTime.now();
    final minutosFaltantes = acceptAfter.difference(ahora).inMinutes;
    if (minutosFaltantes > 0) {
      return Colors.orangeAccent;
    } else {
      return Colors.greenAccent;
    }
  }

  Widget _badgeModo({
    required bool esAhora,
    required DateTime fecha,
    required bool estaLiberado,
    required DateTime acceptAfter,
  }) {
    final icon = esAhora ? Icons.flash_on : Icons.schedule;
    final color = esAhora ? Colors.greenAccent : Colors.orangeAccent;

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
        color: Color.fromRGBO(
          esAhora ? 0 : 255,
          esAhora ? 255 : 165,
          0,
          0.12,
        ),
        border: Border.all(
          color: Color.fromRGBO(
            esAhora ? 0 : 255,
            esAhora ? 255 : 165,
            0,
            0.7,
          ),
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipInfo(IconData icon, String text, {Color color = Colors.white70}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.06),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  Widget _bannerNoDisponible() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 152, 0, 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color.fromRGBO(255, 152, 0, 0.5),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.orangeAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Estás en "No disponible". No podrás aceptar viajes hasta activarlo.',
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
              'Tienes pago semanal pendiente. No tendrás viajes disponibles hasta saldarlo.',
              style: TextStyle(
                color: isDark ? Colors.white70 : const Color(0xFF374151),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerFallback(bool usarFallback) {
    if (!usarFallback) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(33, 150, 243, 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color.fromRGBO(33, 150, 243, 0.5),
        ),
      ),
      child: Text(
        'Modo sin índice: filtrando/ordenando en el dispositivo mientras el índice se crea.',
        style: TextStyle(
          color: isDark ? Colors.white70 : const Color(0xFF374151),
        ),
      ),
    );
  }

  Color _getColorForTipoServicio(String tipoServicio) {
    switch (tipoServicio) {
      case 'motor':
        return Colors.orange;
      case 'turismo':
        return Colors.purple;
      case 'normal':
      default:
        return Colors.greenAccent;
    }
  }

  IconData _getIconForTipoServicio(String tipoServicio) {
    switch (tipoServicio) {
      case 'motor':
        return Icons.motorcycle;
      case 'turismo':
        return Icons.beach_access;
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
      case 'normal':
      default:
        return '🚗 NORMAL';
    }
  }

  Widget _buildParadasWidget(Viaje v) {
    if (v.waypoints == null || v.waypoints!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📍 Paradas intermedias:',
            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          ...v.waypoints!.asMap().entries.map((entry) {
            final int index = entry.key + 1;
            final Map<String, dynamic> waypoint = entry.value;
            final String label = waypoint['label']?.toString() ?? 'Parada $index';
            return Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.flag_circle, size: 14, color: Colors.orangeAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$index. $label',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
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
  }) {
    return StreamBuilder<fs.QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingProfessional();
        }
        if (snapshot.hasError) {
          final errorMsg = snapshot.error.toString().toLowerCase();
          _diag('stream error tab=${esTabAhora ? "ahora" : "prog"} fallback=${esTabAhora ? _usarFallbackSinIndiceAhora : _usarFallbackSinIndiceProg} msg=$errorMsg');
          // Si es error de índice, no mostramos error duro; forzamos fallback local.
          if (errorMsg.contains('index') || errorMsg.contains('failed-precondition')) {
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
            return const LoadingProfessional(
              mensajePersonalizado: "Preparando viajes disponibles",
            );
          }
          // Evita falso "sin internet" cuando hay datos pero falló la query principal.
          // Si ya estamos en fallback y falla, mostramos vacío profesional en vez de error agresivo.
          final bool enFallback = esTabAhora ? _usarFallbackSinIndiceAhora : _usarFallbackSinIndiceProg;
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
            return const LoadingProfessional(
              mensajePersonalizado: "Reconectando viajes disponibles",
            );
          }
          return EmptyTripsWidget(esTabAhora: esTabAhora);
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return EmptyTripsWidget(esTabAhora: esTabAhora);
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

          if (usandoFallback && !filtroLocalSiFallback(data)) continue;
          if (!_disponibleParaMi(data, myUid)) continue;

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
          final double distancia = tieneCoordsCliente
              ? Geolocator.distanceBetween(
                    latTaxista,
                    lonTaxista,
                    v.latCliente,
                    v.lonCliente,
                  ) /
                  1000
              : 0.0;

          // Producción: no bloquear visibilidad por distancia.
          // La distancia se muestra como dato informativo para decidir.

          items.add(_Item(v, fecha, acceptAfter, esAhoraDoc, distancia));
        }

        if (items.isEmpty) {
          debugPrint(
            '[POOL][${esTabAhora ? "AHORA" : "PROGRAMADOS"}] vacio tras filtros docs=${docs.length}',
          );
          _diag('items empty tab=${esTabAhora ? "ahora" : "prog"} docs=${docs.length}');
          return EmptyTripsWidget(esTabAhora: esTabAhora);
        }
        _diag('items ready tab=${esTabAhora ? "ahora" : "prog"} count=${items.length}');

        items.sort((a, b) => a.distancia.compareTo(b.distancia));

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (context, index) {
            final it = items[index];
            final v = it.v;
            final fecha = it.fecha;
            final acceptAfter = it.acceptAfter;
            final esAhora = it.esAhora;
            final distancia = it.distancia;
            final aceptando = _aceptandoIds.contains(v.id);

            final bool puedeAceptar = esAhora || !DateTime.now().isBefore(acceptAfter);
            final String textoDisponibilidad = _getTextoDisponibilidad(acceptAfter, esAhora);
            final Color colorDisponibilidad = _getColorDisponibilidad(acceptAfter, esAhora);

            final bool estaLiberado =
                esAhora || !DateTime.now().isBefore(acceptAfter);

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

            final Color servicioColor = _getColorForTipoServicio(v.tipoServicio);
            final IconData servicioIcon = _getIconForTipoServicio(v.tipoServicio);
            final String servicioLabel = _getLabelForTipoServicio(v.tipoServicio);

            return Card(
              color: const Color(0xFF121826),
              margin: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: v.waypoints != null && v.waypoints!.isNotEmpty
                      ? Colors.red.withValues(alpha: 0.7)
                      : v.tipoServicio == 'motor' 
                          ? Colors.orange.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.3),
                  width: v.waypoints != null && v.waypoints!.isNotEmpty ? 3 : 2,
                ),
              ),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _clienteInfoHeader(
                                v.uidCliente.isNotEmpty
                                    ? v.uidCliente
                                    : v.clienteId,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              alignment: WrapAlignment.end,
                              children: [
                                _badgeModo(
                                  esAhora: esAhora,
                                  fecha: fecha,
                                  estaLiberado: estaLiberado,
                                  acceptAfter: acceptAfter,
                                ),
                                _CountdownChip(
                                  fecha: esAhora
                                      ? fecha
                                      : (estaLiberado ? fecha : acceptAfter),
                                  label: esAhora
                                      ? 'sale'
                                      : (estaLiberado ? 'sale' : 'se libera'),
                                ),
                              ],
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
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
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
                            color: servicioColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: servicioColor),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(servicioIcon, size: 14, color: servicioColor),
                              const SizedBox(width: 6),
                              Text(
                                servicioLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: servicioColor,
                                  fontWeight: FontWeight.bold,
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
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    
                    _buildParadasWidget(v),
                    
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chipInfo(
                          Icons.near_me,
                          'A ${distancia.toStringAsFixed(1)} km',
                        ),
                        _chipInfo(
                          Icons.straighten,
                          "Recorrido: ${FormatosMoneda.km(distanciaKm)}",
                        ),
                        _chipInfo(Icons.credit_card, v.metodoPago),
                        if (!esAhora)
                          _chipInfo(
                            Icons.event,
                            DateFormat('dd/MM HH:mm').format(fecha),
                          ),
                        if (v.tipoVehiculo.isNotEmpty && v.tipoServicio != 'motor')
                          _chipInfo(Icons.local_taxi, v.tipoVehiculo),
                        if (v.extras != null && v.extras!['pasajeros'] != null)
                          _chipInfo(
                            Icons.people,
                            '${v.extras!['pasajeros']} pasajero${v.extras!['pasajeros'] != 1 ? 's' : ''}',
                          ),
                        if (!esAhora)
                          _chipInfo(
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
                              const Text(
                                "Total",
                                style: TextStyle(
                                  color: Colors.white70,
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
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DetalleViaje(viajeId: v.id),
                                ),
                              );
                            },
                            icon: Icon(Icons.info_outline, color: servicioColor),
                            label: Text('Ver detalles', style: TextStyle(color: servicioColor)),
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
                                : () => _aceptarViaje(v, disponible: disponible),
                            icon: aceptando
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
                                  : (disponibilidadCargando
                                      ? "Cargando perfil…"
                                      : (!disponible
                                          ? "No disponible"
                                          : (!esAhora && !puedeAceptar
                                              ? "En ${acceptAfter.difference(DateTime.now()).inMinutes} min"
                                              : "Aceptar"))),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: const Color(0xFF16A34A),
                              disabledBackgroundColor: Colors.white24,
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color pageBg = isDark ? const Color(0xFF090B10) : const Color(0xFFE9EEF5);
    final Color appBarBg = const Color(0xFF10141C);
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
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: pageBg,
          drawer: const TaxistaDrawer(),
          appBar: AppBar(
            backgroundColor: appBarBg,
            leading: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                tooltip: 'Menú',
              ),
            ),
            title: const Text(
              'Viajes Disponibles',
              style: TextStyle(
                fontSize: 24,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            centerTitle: true,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: const [SaldoGananciasChip()],
            bottom: const TabBar(
              indicatorColor: Colors.greenAccent,
              tabs: [
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
              return FutureBuilder<bool>(
                future: PagosTaxistaRepo.tieneBloqueoSemanal(u.uid),
                builder: (context, pagoSnap) {
                  final bool bloqueadoPagoRaw = pagoSnap.data ?? false;
                  if (bloqueadoPagoRaw) {
                    Future.microtask(() => _notificarBloqueoPagoSiAplica(u.uid));
                  }
                  return FutureBuilder<bool>(
                    future: _debeBloquearPorDeuda(u.uid, bloqueadoPagoRaw),
                    builder: (context, bloqueoSnap) {
                      final bool bloqueadoPago = bloqueoSnap.data ?? false;
                      return FutureBuilder<String>(
                        future: bloqueadoPagoRaw ? _textoVentanaGracia() : Future.value(''),
                        builder: (context, textoSnap) {
                          final String textoGracia = textoSnap.data ?? '';
                          return Column(
                            children: [
                              if (bloqueadoPago)
                                _bannerBloqueoSemanal()
                              else if (bloqueadoPagoRaw)
                                Container(
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
                                      const Icon(Icons.schedule, color: Colors.amber),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          textoGracia,
                                          style: const TextStyle(color: Colors.white70),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (!bloqueadoPago &&
                                  !bloqueadoPagoRaw &&
                                  !disponibilidadCargando &&
                                  !disponible)
                                _bannerNoDisponible(),
                              if (!bloqueadoPago)
                                _bannerFallback(
                                  _usarFallbackSinIndiceAhora || _usarFallbackSinIndiceProg,
                                ),
                              Expanded(
                                child: bloqueadoPago
                                    ? const Center(
                                        child: Text(
                                          'No hay viajes disponibles por deuda semanal.',
                                          style: TextStyle(color: Colors.white70),
                                        ),
                                      )
                                    : TabBarView(
                                        children: [
                                          _buildLista(
                                            stream: streamAhora,
                                            disponible: disponible,
                                            disponibilidadCargando: disponibilidadCargando,
                                            myUid: u.uid,
                                            filtroLocalSiFallback: _pasaFiltroAhoraLocal,
                                            ordenarAscEnMemoria: false,
                                            usandoFallback: _usarFallbackSinIndiceAhora,
                                            esTabAhora: true,
                                            latTaxista: pos.latitude,
                                            lonTaxista: pos.longitude,
                                          ),
                                          _buildLista(
                                            stream: streamProg,
                                            disponible: disponible,
                                            disponibilidadCargando: disponibilidadCargando,
                                            myUid: u.uid,
                                            filtroLocalSiFallback: _pasaFiltroProgLocal,
                                            ordenarAscEnMemoria: true,
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
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
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
            color: const Color.fromRGBO(0, 255, 255, 0.12),
            border: Border.all(
              color: const Color.fromRGBO(0, 255, 255, 0.7),
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer, size: 14, color: Colors.cyanAccent),
              const SizedBox(width: 6),
              Text(
                '$label $txt',
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}