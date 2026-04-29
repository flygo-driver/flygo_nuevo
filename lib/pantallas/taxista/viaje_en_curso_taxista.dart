// lib/pantallas/taxista/viaje_en_curso_taxista.dart

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flygo_nuevo/data/pago_data.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/pantallas/chat/chat_screen.dart';
import 'package:flygo_nuevo/servicios/directions_service.dart';
import 'package:flygo_nuevo/servicios/error_reporting.dart';
import 'package:flygo_nuevo/servicios/error_auth_es.dart';
import 'package:flygo_nuevo/servicios/taxista_cola_post_completar.dart';
import 'package:flygo_nuevo/servicios/navegacion_externa_launcher.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart'; // 🔥 ESTA LÍNEA
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/telefono_viaje.dart';
import 'package:flygo_nuevo/shell/taxista_shell.dart';
import 'package:flygo_nuevo/widgets/cliente_perfil_conductor_chip.dart';
import 'package:flygo_nuevo/widgets/mapa_tiempo_real.dart';
import 'package:flygo_nuevo/widgets/cola_siguiente_viaje_banner.dart';
import 'package:flygo_nuevo/widgets/navegacion_waze_maps_sheet.dart';
import 'package:flygo_nuevo/widgets/viajes_cercanos_taxista.dart';

const bool kLog = true;
void logDbg(String msg) {
  if (kLog) debugPrint('[VIAJE_TX] $msg');
}

const bool _diagTripFlow =
    bool.fromEnvironment('TRIP_FLOW_DIAG', defaultValue: false);
void _diag(String msg) {
  if (_diagTripFlow) debugPrint('[TRIP_FLOW][en_curso] $msg');
}

/// Solo en debug/profile: ignorar distancias muy pequeñas (mismo dispositivo).
const double kDebugMinDistance = 0.01; // ~10 m
const double kFinalizarRadioMetros =
    250; // Produccion: finalizar solo cerca del destino

class ViajeEnCursoTaxista extends StatefulWidget {
  const ViajeEnCursoTaxista({super.key});
  @override
  State<ViajeEnCursoTaxista> createState() => _ViajeEnCursoTaxistaState();
}

// ... resto del código igual

class _ViajeEnCursoTaxistaState extends State<ViajeEnCursoTaxista>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  GoogleMapController? _map;

  /// Tarjeta de acciones/navegación: arrastrable; por defecto ~40% para dejar mapa visible.
  final DraggableScrollableController _viajeNavSheetCtrl =
      DraggableScrollableController();

  static const double _kViajeNavSheetMin = 0.14;
  static const double _kViajeNavSheetInitialMitad = 0.5;

  // ===== GPS =====
  StreamSubscription<Position>? _gpsSub;
  String? _gpsParaViajeId;
  bool _gpsActivo = false;

  // ===== Acciones =====
  bool _actionBusy = false;

  // ===== Remoción / cancelación remota =====
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _cancelSub;
  bool _procesandoRemocion = false;

  // ===== Controlador para código de verificación =====
  final TextEditingController _codigoCtrl = TextEditingController();

  // ===== Polylines para rutas =====
  final Set<Polyline> _polylines = <Polyline>{};
  Timer? _routeDebounce;

  // ===== Viajes cercanos / cola: aislado en [ViajesCercanosTaxistaLayer] (no setState aquí) =====
  final ViajesCercanosTaxistaController _viajesCercanosCtl =
      ViajesCercanosTaxistaController();
  final ValueNotifier<bool> _viajesCercanosEscucha = ValueNotifier<bool>(false);
  final ValueNotifier<(double, double)?> _taxistaPosCola =
      ValueNotifier<(double, double)?>(null);

  // 🚀 Variables para detección de cercanía del cliente
  bool _clienteCerca = false;
  bool _navegacionIniciada = false;
  bool _selectorNavegacionAbierto = false;
  /// Evita ver la tarjeta del viaje y el modal Waze/Maps apilados a la vez.
  bool _viajeSheetOcultoPorModalNav = false;
  static const double DISTANCIA_CERCANIA_KM = 0.1;

  // Cache del viaje actual
  Viaje? _cachedViaje;
  bool _isUpdatingLocation = false;

  // ===== Stream principal (deduplicado: el taxista escribe GPS en el mismo doc → sin esto, cada ping reconstruye toda la pantalla) =====
  Stream<Viaje?> _stream() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return const Stream<Viaje?>.empty();
    return ViajesRepo.streamViajeEnCursoPorTaxista(u.uid)
        .distinct(_mismoViajeParaUiTaxista);
  }

  static bool _mismoViajeParaUiTaxista(Viaje? a, Viaje? b) =>
      _firmaViajeUiTaxista(a) == _firmaViajeUiTaxista(b);

  static String _firmaViajeUiTaxista(Viaje? v) {
    if (v == null) return '';
    final est = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado ? EstadosViaje.aceptado : EstadosViaje.pendiente)),
    );
    String r6(double x) => (x.isFinite) ? x.toStringAsFixed(6) : 'x';
    final int wp = v.waypoints?.length ?? 0;
    // No incluir latTaxista/lonTaxista: este taxista escribe el GPS en el mismo doc y cada
    // actualización dispararía StreamBuilder + Column completa. La posición se mantiene en
    // _cachedViaje vía copyWith en el listener GPS.
    // Cliente/destino con 6 decimales para ver movimiento en tiempo real en el mapa.
    return '${v.id}|$est|${r6(v.latCliente)}|${r6(v.lonCliente)}|${r6(v.latDestino)}|${r6(v.lonDestino)}|'
        '${v.codigoVerificado}|${v.uidTaxista}|${v.completado}|$wp';
  }

  /// Solo campos que afectan polilíneas hacia el cliente o destino.
  static String _firmaRutaMapaTaxista(Viaje v) {
    String r6(double x) => (x.isFinite) ? x.toStringAsFixed(6) : 'x';
    final est = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado ? EstadosViaje.aceptado : EstadosViaje.pendiente)),
    );
    return '$est|${r6(v.latCliente)}|${r6(v.lonCliente)}|${r6(v.latDestino)}|${r6(v.lonDestino)}|${v.codigoVerificado}';
  }

  // ===== Utilidades =====
  bool _coordsValid(double lat, double lon) =>
      lat.isFinite &&
      lon.isFinite &&
      !(lat == 0 && lon == 0) &&
      lat >= -90 &&
      lat <= 90 &&
      lon >= -180 &&
      lon <= 180;

  String _cleanPhone(String raw) => telefonoNormalizarDigitos(raw);

  String _digitsOnlyCode(String? s) => (s ?? '').replaceAll(RegExp(r'\D'), '');

  bool _codigoEsperadoValido(String? codigo) =>
      _digitsOnlyCode(codigo).length == 6;

  void _tripFlowSnack(String msg, {Color backgroundColor = Colors.orange}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  double? _waypointLat(Map<String, dynamic> w) {
    final x = w['lat'];
    if (x is num) return x.toDouble();
    return double.tryParse('$x');
  }

  double? _waypointLon(Map<String, dynamic> w) {
    final x = w['lon'];
    if (x is num) return x.toDouble();
    return double.tryParse('$x');
  }

  String _uidClienteDe(Viaje v) {
    final a = (v.clienteId).toString().trim();
    if (a.isNotEmpty) return a;
    final b = (v.uidCliente).toString().trim();
    return b;
  }

  void _verificarCercaniaCliente(double latTaxista, double lonTaxista,
      double latCliente, double lonCliente) {
    if (!_coordsValid(latTaxista, lonTaxista) ||
        !_coordsValid(latCliente, lonCliente)) {
      return;
    }

    final distancia =
        _calcularDistanciaKm(latTaxista, lonTaxista, latCliente, lonCliente);
    final bool ahoraCerca = distancia <= DISTANCIA_CERCANIA_KM;

    // Modo desarrollo: ignorar distancias muy pequeñas (mismo dispositivo)
    if (kDebugMode && distancia < kDebugMinDistance) {
      logDbg(
          '⚠️ Modo desarrollo: ignorando distancia muy pequeña (${(distancia * 1000).toStringAsFixed(0)}m)');
      return;
    }

    if (ahoraCerca != _clienteCerca && mounted && !_isUpdatingLocation) {
      _isUpdatingLocation = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _clienteCerca = ahoraCerca;
          });
          _isUpdatingLocation = false;

          if (ahoraCerca) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.white),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '🚕 ¡Has llegado! El cliente está cerca. Presiona "Cliente a bordo" para continuar.',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 5),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          }
        } else {
          _isUpdatingLocation = false;
        }
      });
      logDbg(
          '🎯 Cambio de cercanía: $ahoraCerca, distancia: ${(distancia * 1000).toStringAsFixed(0)}m');
    }
  }

  double _calcularDistanciaKm(
      double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371.0;
    final double dLat = (lat2 - lat1) * pi / 180.0;
    final double dLon = (lon2 - lon1) * pi / 180.0;
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) *
            cos(lat2 * pi / 180.0) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  // ===== GPS control =====
  Future<void> _startGpsFor(String viajeId) async {
    logDbg('_startGpsFor($viajeId)');
    if (_gpsParaViajeId == viajeId && _gpsSub != null) return;
    await _gpsSub?.cancel();
    _gpsParaViajeId = viajeId;

    final ref = FirebaseFirestore.instance.collection('viajes').doc(viajeId);
    final LocationSettings gpsSettings =
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            ? AndroidSettings(
                accuracy: LocationAccuracy.bestForNavigation,
                distanceFilter: 8,
                intervalDuration: const Duration(seconds: 2),
              )
            : const LocationSettings(
                accuracy: LocationAccuracy.bestForNavigation,
                distanceFilter: 8,
              );
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: gpsSettings,
    ).listen((p) async {
      try {
        await ref.update({
          'latTaxista': p.latitude,
          'lonTaxista': p.longitude,
          'driverLat': p.latitude,
          'driverLon': p.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        });
        logDbg('📍 Ubicación enviada: ${p.latitude}, ${p.longitude}');
        _taxistaPosCola.value = (p.latitude, p.longitude);

        if (mounted && _cachedViaje != null && _cachedViaje!.id == viajeId) {
          _cachedViaje = _cachedViaje!
              .copyWith(latTaxista: p.latitude, lonTaxista: p.longitude);
        }

        if (mounted &&
            _cachedViaje != null &&
            _coordsValid(_cachedViaje!.latCliente, _cachedViaje!.lonCliente)) {
          _verificarCercaniaCliente(p.latitude, p.longitude,
              _cachedViaje!.latCliente, _cachedViaje!.lonCliente);
          _scheduleDrawRoute();
        }
      } catch (e) {
        logDbg('Error actualizando Firestore: $e');
      }
    });
  }

  void _stopGps() {
    _gpsSub?.cancel();
    _gpsSub = null;
    _gpsActivo = false;
    _gpsParaViajeId = null;
    logDbg('🛑 GPS detenido');
  }

  Future<bool> _asegurarGps(String viajeId) async {
    logDbg('_asegurarGps($viajeId) - _gpsActivo: $_gpsActivo');

    if (_gpsActivo && _gpsParaViajeId == viajeId) {
      logDbg('✅ GPS ya activo');
      return true;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (!mounted) return false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Permiso de ubicación requerido para navegar')),
          );
        }
      });
      logDbg('❌ Permiso denegado');
      return false;
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      if (!mounted) return false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Activa el GPS del teléfono')),
          );
        }
      });
      logDbg('❌ GPS apagado');
      return false;
    }

    await _startGpsFor(viajeId);
    _gpsActivo = true;
    logDbg('✅ GPS activado correctamente');
    return true;
  }

  // ===== RUTAS =====
  void _scheduleDrawRoute() {
    _routeDebounce?.cancel();
    _routeDebounce =
        Timer(const Duration(milliseconds: 500), () => _drawRoutes());
  }

  Future<void> _drawRoutes() async {
    if (!mounted || _cachedViaje == null) return;

    final v = _cachedViaje!;

    final estadoBase = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado ? EstadosViaje.aceptado : EstadosViaje.pendiente)),
    );

    final oldPolylines = Set<Polyline>.from(_polylines);
    _polylines.clear();

    if ((EstadosViaje.esAceptado(estadoBase) ||
            EstadosViaje.esEnCaminoPickup(estadoBase)) &&
        _coordsValid(v.latTaxista, v.lonTaxista) &&
        _coordsValid(v.latCliente, v.lonCliente)) {
      await _drawRoute(
        LatLng(v.latTaxista, v.lonTaxista),
        LatLng(v.latCliente, v.lonCliente),
        id: 'to_cliente',
        color: const Color(0xFF00E5FF),
        width: 6,
      );
    }

    final bool rutaAlDestino = EstadosViaje.esEnCurso(estadoBase) ||
        (EstadosViaje.esAbordo(estadoBase) && v.codigoVerificado);
    if (rutaAlDestino &&
        _coordsValid(v.latCliente, v.lonCliente) &&
        _coordsValid(v.latDestino, v.lonDestino)) {
      await _drawRoute(
        LatLng(v.latCliente, v.lonCliente),
        LatLng(v.latDestino, v.lonDestino),
        id: 'to_destino',
        color: const Color(0xFF49F18B),
      );
    }

    if (mounted && !_polylinesEquals(oldPolylines, _polylines)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  bool _polylinesEquals(Set<Polyline> a, Set<Polyline> b) {
    if (a.length != b.length) return false;
    final aIds = a.map((p) => p.polylineId.value).toSet();
    final bIds = b.map((p) => p.polylineId.value).toSet();
    return aIds.containsAll(bIds) && bIds.containsAll(aIds);
  }

  Future<void> _drawRoute(
    LatLng a,
    LatLng b, {
    required String id,
    required Color color,
    int width = 5,
  }) async {
    try {
      final result = await DirectionsService.drivingDistanceKm(
        originLat: a.latitude,
        originLon: a.longitude,
        destLat: b.latitude,
        destLon: b.longitude,
        withTraffic: true,
        region: 'do',
      );

      List<LatLng> points = [];
      if (result != null && result.path != null && result.path!.isNotEmpty) {
        points = result.path!;
      }

      _polylines.add(
        Polyline(
          polylineId: PolylineId(id),
          points: points.isNotEmpty ? points : [a, b],
          width: width,
          color: color,
          geodesic: true,
        ),
      );
    } catch (e) {
      _polylines.add(
        Polyline(
          polylineId: PolylineId(id),
          points: [a, b],
          width: width,
          color: color,
          geodesic: true,
        ),
      );
    }
  }

  void _colapsarTarjetaViajePorMapa() {
    if (!_viajeNavSheetCtrl.isAttached) return;
    _viajeNavSheetCtrl.animateTo(
      _kViajeNavSheetMin,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _expandirTarjetaViajeTrasMapa() {
    if (!_viajeNavSheetCtrl.isAttached) return;
    _viajeNavSheetCtrl.animateTo(
      _kViajeNavSheetInitialMitad,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// Evita dos “tarjetas” a la vez: la hoja Waze/Maps encima de la del viaje.
  void _plegarTarjetaViajeAntesNavSheet() {
    if (!_viajeNavSheetCtrl.isAttached) return;
    _viajeNavSheetCtrl.jumpTo(_kViajeNavSheetMin);
  }

  void _restaurarTarjetaViajeTrasNavSheet() {
    if (!mounted) return;
    if (!_viajeNavSheetCtrl.isAttached) return;
    _viajeNavSheetCtrl.animateTo(
      _kViajeNavSheetInitialMitad,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _cancelSub?.cancel();
    _map?.dispose();
    _viajeNavSheetCtrl.dispose();
    _stopGps();
    _codigoCtrl.dispose();
    _routeDebounce?.cancel();
    _viajesCercanosEscucha.dispose();
    _viajesCercanosCtl.dispose();
    _taxistaPosCola.dispose();
    super.dispose();
  }

  // ===================== Acciones Principales =====================

  Future<void> _iniciarNavegacionPickup(Viaje v) async {
    if (_actionBusy) return;
    _actionBusy = true;

    try {
      // Si el backend ya está en `en_camino_pickup`, el botón no debe fallar.
      // Esto evita que `marcarEnCaminoPickup()` intente una transición inválida
      // (de `en_camino_pickup` a `en_camino_pickup`) y dispare el snackbar genérico.
      final estadoN = EstadosViaje.normalizar(v.estado);
      final bool yaEnCaminoPickup = estadoN == EstadosViaje.enCaminoPickup;
      if (estadoN == EstadosViaje.cancelado ||
          estadoN == EstadosViaje.completado) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('El viaje ya no está disponible.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        });
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _navegacionIniciada = true);
      });

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (!yaEnCaminoPickup) {
        if (uid != null) {
          try {
            await ViajesRepo.marcarEnCaminoPickup(
              viajeId: v.id,
              uidTaxista: uid,
            );
          } catch (e) {
            // Robustez: si el backend ya está en `en_camino_pickup`,
            // `marcarEnCaminoPickup` puede lanzar "Estado inválido".
            // No bloqueamos la navegación por esto.
            final msg = e.toString().toLowerCase();
            if (msg.contains('estado inválido') ||
                msg.contains('estado invalido') ||
                msg.contains('estado inválido para en_camino_pickup') ||
                msg.contains('estado invalido para en_camino_pickup')) {
              // Continuar: la navegación puede abrirse igual.
            } else {
              rethrow;
            }
          }
        }
      }

      final gpsOk = await _asegurarGps(v.id);
      if (!gpsOk && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _navegacionIniciada = false);
        });
        _actionBusy = false;
        return;
      }

      final tieneCoords = _coordsValid(v.latCliente, v.lonCliente);

      /// Si el sheet se cierra sin elegir app (gesto, barrier, etc.), no dejar
      /// `_navegacionIniciada` en true: desbloquea de nuevo «Navegar» y abordo coherente.
      var eligioAppExterna = false;

      if (mounted) {
        setState(() => _viajeSheetOcultoPorModalNav = true);
        _plegarTarjetaViajeAntesNavSheet();
        try {
          await showNavegacionWazeMapsSheet(
            context,
            title: 'Abrir navegación',
            addressLine: 'Punto de recogida: ${v.origen}',
            tieneCoords: tieneCoords,
            gpsCoordinatesLine: tieneCoords
                ? 'GPS: ${NavegacionExternaLauncher.fmtCoord(v.latCliente)}, ${NavegacionExternaLauncher.fmtCoord(v.lonCliente)}'
                : null,
            showSinGpsBanner: !tieneCoords,
            footerHint:
                'Elige Waze o Maps; al llegar, vuelve a RAI para marcar abordo y el código.',
            onWaze: () {
              eligioAppExterna = true;
              if (tieneCoords) {
                unawaited(NavegacionExternaLauncher.abrirWazeDestino(
                    v.latCliente, v.lonCliente));
              } else {
                unawaited(
                    NavegacionExternaLauncher.abrirWazeBusqueda(v.origen));
              }
            },
            onMaps: () {
              eligioAppExterna = true;
              if (tieneCoords) {
                unawaited(NavegacionExternaLauncher.abrirGoogleMapsDestino(
                    v.latCliente, v.lonCliente));
              } else {
                unawaited(NavegacionExternaLauncher.abrirGoogleMapsDireccion(
                    v.origen));
              }
            },
            onCancel: () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _navegacionIniciada = false);
              });
            },
          );
        } finally {
          if (mounted) {
            setState(() => _viajeSheetOcultoPorModalNav = false);
            _restaurarTarjetaViajeTrasNavSheet();
          }
        }
      }

      if (mounted && !eligioAppExterna) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _navegacionIniciada = false);
        });
      }

      if (mounted && _navegacionIniciada) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.navigation, color: Colors.white),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Navegación hacia el cliente lista. Al llegar, en RAI: «Cliente a bordo» y luego el código.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.blue,
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            );
          }
        });
      }
    } catch (e) {
      logDbg('Error iniciando navegación: $e');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _navegacionIniciada = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al iniciar navegación: ${errorAuthEs(e)}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
    } finally {
      _actionBusy = false;
    }
  }

  Future<void> _marcarClienteAbordo(Viaje v) async {
    if (_actionBusy) return;
    _actionBusy = true;

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        throw Exception('Usuario no autenticado');
      }

      // Micro-harden: al usar el repo garantizamos la transición válida + limpieza
      // defensiva (evita estados "fantasma" en cola/activos del taxista),
      // manteniendo luego los campos extra que la UI depende (`clienteAbordo*`).
      final estadoN = EstadosViaje.normalizar(v.estado);
      final bool yaEnAboard = estadoN == EstadosViaje.aBordo;
      if (!yaEnAboard) {
        try {
          await ViajesRepo.marcarClienteAbordo(viajeId: v.id, uidTaxista: uid);
        } catch (e, st) {
          // Si hubo carrera de estado (backend ya cambió a `a_bordo`),
          // igual dejamos consistentes los campos de UI abajo.
          await ErrorReporting.reportError(
            e,
            stack: st,
            context: '_marcarClienteAbordo: repo.marcarClienteAbordo',
          );
        }
      }

      await FirebaseFirestore.instance.collection('viajes').doc(v.id).update({
        'estado': EstadosViaje.aBordo,
        'clienteAbordo': true,
        'clienteAbordoEn': FieldValue.serverTimestamp(),
        // Importante: el flujo de UI para "Viaje en curso" depende del flag `activo==true`.
        // Al alternar cuentas (un solo teléfono) la pantalla se recarga y usa el stream del repo.
        // Si no se activa aquí, el viaje puede aparecer como "no tienes viaje en curso".
        'activo': true,
        'pickupConfirmadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Text('✅ Cliente marcado como a bordo'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      });

      // Recargar viaje
      final snapshot =
          await FirebaseFirestore.instance.collection('viajes').doc(v.id).get();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && snapshot.exists) {
          final viajeActualizado = Viaje.fromMap(v.id, snapshot.data()!);
          setState(() {
            _cachedViaje = viajeActualizado;
            _navegacionIniciada = false;
            _clienteCerca = false;
          });
        }
      });
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: ${errorAuthEs(e)}'),
                backgroundColor: Colors.red),
          );
        }
      });
    } finally {
      _actionBusy = false;
    }
  }

  Future<void> _verificarCodigo(String viajeId, String codigoCorrecto) async {
    if (_actionBusy) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final esperado = _digitsOnlyCode(codigoCorrecto);
    final ingresado = _digitsOnlyCode(_codigoCtrl.text);
    if (esperado.length != 6) {
      _tripFlowSnack(
        'Este viaje no tiene código de 6 dígitos en el sistema. '
        'Pide al cliente que abra su viaje y confirme el PIN; si sigue igual, contacta soporte.',
      );
      return;
    }
    if (ingresado.length != 6) {
      _tripFlowSnack('Ingresa los 6 dígitos que te dicta el cliente.',
          backgroundColor: Colors.redAccent);
      return;
    }
    if (ingresado != esperado) {
      _tripFlowSnack('Código incorrecto. Vuelve a pedírselo al cliente.',
          backgroundColor: Colors.redAccent);
      return;
    }

    _actionBusy = true;
    _codigoCtrl.clear();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _actionBusy = false;
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .update({
        'codigoVerificado': true,
        'viajeIniciadoEn': FieldValue.serverTimestamp(),
      });

      try {
        await ViajesRepo.iniciarViaje(viajeId: viajeId, uidTaxista: uid);
      } catch (eInicio) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Código verificado. ${errorAuthEs(eInicio)}'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 6),
              ),
            );
          }
        });
        return;
      }

      _tripFlowSnack('Código correcto. Iniciando ruta hacia el destino…',
          backgroundColor: Colors.green);

      if (!mounted) {
        return;
      }

      final viajeSnap = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .get();

      if (!mounted) {
        _actionBusy = false;
        return;
      }

      final data = viajeSnap.data();
      if (data != null) {
        if (mounted && _cachedViaje?.id == viajeId) {
          setState(() {
            _cachedViaje = Viaje.fromMap(viajeId, data);
          });
          _scheduleDrawRoute();
        }
        final latDestino = (data['latDestino'] ?? 0).toDouble();
        final lonDestino = (data['lonDestino'] ?? 0).toDouble();
        final destinoTexto = data['destino']?.toString() ?? 'destino';

        if (_coordsValid(latDestino, lonDestino)) {
          if (mounted) {
            _tripFlowSnack('Abre navegación hacia: $destinoTexto',
                backgroundColor: Colors.blueGrey);
          }
          await _selectorNavegacionDestino(latDestino, lonDestino);
        } else if (mounted) {
          _tripFlowSnack(
              'Código verificado. Usa la dirección de destino en el mapa si no hay GPS.',
              backgroundColor: Colors.orange);
        }
      }
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error al iniciar: $e'),
                backgroundColor: Colors.red),
          );
        }
      });
    } finally {
      _actionBusy = false;
    }
  }

  Future<void> _finalizarViaje(Viaje v) async {
    if (_actionBusy) return;
    _actionBusy = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _actionBusy = false;
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final String estadoLocal = EstadosViaje.normalizar(v.estado);

    // Hardening UX/produccion: finalizar solo cuando el viaje este en curso.
    // Si la UI va atrasada por latencia, validamos tambien contra Firestore.
    if (!EstadosViaje.esEnCurso(estadoLocal)) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('viajes')
            .doc(v.id)
            .get();
        final data = snap.data() ?? const <String, dynamic>{};
        final String estadoRemoto =
            EstadosViaje.normalizar((data['estado'] ?? '').toString());
        if (!EstadosViaje.esEnCurso(estadoRemoto)) {
          if (mounted) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Para finalizar, primero inicia el viaje hacia el destino.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          _actionBusy = false;
          return;
        }
      } catch (_) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo validar el estado del viaje. Intenta nuevamente.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        _actionBusy = false;
        return;
      }
    }

    // Produccion real: solo permitir finalizar cuando el taxista este cerca del destino.
    if (_coordsValid(v.latDestino, v.lonDestino)) {
      double? latTx;
      double? lonTx;

      if (_coordsValid(v.latTaxista, v.lonTaxista)) {
        latTx = v.latTaxista;
        lonTx = v.lonTaxista;
      } else if (_cachedViaje != null &&
          _coordsValid(_cachedViaje!.latTaxista, _cachedViaje!.lonTaxista)) {
        latTx = _cachedViaje!.latTaxista;
        lonTx = _cachedViaje!.lonTaxista;
      } else {
        try {
          final pos = await Geolocator.getCurrentPosition();
          latTx = pos.latitude;
          lonTx = pos.longitude;
        } catch (_) {
          latTx = null;
          lonTx = null;
        }
      }

      if (latTx == null || lonTx == null || !_coordsValid(latTx, lonTx)) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo validar tu ubicacion. Activa GPS y acercate al destino para finalizar.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        _actionBusy = false;
        return;
      }

      final distanciaM = Geolocator.distanceBetween(
        latTx,
        lonTx,
        v.latDestino,
        v.lonDestino,
      );
      if (distanciaM > kFinalizarRadioMetros) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Aun no llegas al destino. Te faltan ${(distanciaM / 1000).toStringAsFixed(2)} km para finalizar.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        _actionBusy = false;
        return;
      }
    }

    if (!mounted) {
      _actionBusy = false;
      return;
    }

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.black,
            title: const Text('Finalizar viaje',
                style: TextStyle(color: Colors.white)),
            content: const Text(
                '¿Confirmas que el viaje terminó correctamente?',
                style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('No',
                      style: TextStyle(color: Colors.white70))),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Sí, finalizar')),
            ],
          ),
        ) ??
        false;

    if (!ok) {
      _actionBusy = false;
      return;
    }

    try {
      await ViajesRepo.completarViajePorTaxista(viajeId: v.id, uidTaxista: uid);

      // ────────────────────────────────────────────────────────────────
      // Pagos / facturación:
      // No silenciamos errores. Si falla registrar el pago, el viaje ya
      // está completado, pero mostramos mensaje + reintento.
      // ────────────────────────────────────────────────────────────────
      double total = v.precio;
      double comision = v.precio * 0.20;
      double ganancia = v.precio - comision;
      String metodo = v.metodoPago.toString().toLowerCase().trim();
      final String uidTxDefault = v.uidTaxista.isNotEmpty ? v.uidTaxista : uid;

      bool retryingPago = false;
      Future<void> retryPago() async {
        final uidTx = uidTxDefault;
        if (uidTx.isEmpty) throw Exception('uidTaxista vacío (pago)');

        if (metodo == 'efectivo') {
          await PagoData.registrarComisionCash(
            viajeId: v.id,
            taxistaId: uidTx,
            comision: comision,
          );
        } else {
          await PagoData.registrarTransferenciaCliente(
            viajeId: v.id,
            uidTaxista: uidTx,
            montoFinalDop: total,
            comision: comision,
            gananciaTaxista: ganancia,
          );
        }
      }

      try {
        final doc = await FirebaseFirestore.instance
            .collection('viajes')
            .doc(v.id)
            .get();
        final data = doc.data() ?? {};
        double _toDouble(dynamic x) =>
            x is num ? x.toDouble() : (double.tryParse('$x') ?? 0.0);

        total = _toDouble(data['precioFinal'] ?? data['precio'] ?? v.precio);

        final cc = data['comision_cents'];
        if (cc is num && cc > 0) {
          comision = cc.toDouble() / 100.0;
        } else {
          final comisionCampo =
              _toDouble(data['comision'] ?? data['comisionFlyGo']);
          comision = comisionCampo > 0 ? comisionCampo : (total * 0.20);
        }

        final gc = data['ganancia_cents'];
        if (gc is num && gc > 0) {
          ganancia = gc.toDouble() / 100.0;
        } else {
          final gananciaCampo = _toDouble(data['gananciaTaxista']);
          ganancia = gananciaCampo > 0 ? gananciaCampo : (total - comision);
        }

        metodo = (data['metodoPago'] ?? v.metodoPago ?? 'Efectivo')
            .toString()
            .toLowerCase()
            .trim();

        await retryPago();
      } catch (e, st) {
        await ErrorReporting.reportError(
          e,
          stack: st,
          context: '_finalizarViaje: registrar pago',
        );

        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: const Text(
                'Viaje completado, pero no se pudo registrar el pago. Reintenta',
              ),
              backgroundColor: Colors.orangeAccent,
              duration: const Duration(seconds: 6),
              action: SnackBarAction(
                label: 'Reintentar',
                onPressed: () {
                  if (retryingPago || !context.mounted) return;
                  retryingPago = true;
                  () async {
                    try {
                      await retryPago();
                      if (!context.mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('✅ Pago registrado correctamente'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } catch (e2, st2) {
                      await ErrorReporting.reportError(
                        e2,
                        stack: st2,
                        context: '_finalizarViaje: reintento pago',
                      );
                      if (!context.mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'No se pudo registrar el pago. Intenta más tarde.',
                          ),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                    } finally {
                      retryingPago = false;
                    }
                  }();
                },
              ),
            ),
          );
        }
      }

      _stopGps();

      if (!mounted) return;
      await TaxistaColaPostCompletar.navegarTrasCompletar(
        context: context,
        uidTaxista: uid,
      );
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          messenger
              .showSnackBar(SnackBar(content: Text('❌ ${errorAuthEs(e)}')));
        }
      });
    } finally {
      _actionBusy = false;
    }
  }

  Future<void> _cancelarPorTaxista(Viaje v) async {
    if (_actionBusy) return;
    _actionBusy = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _actionBusy = false;
      return;
    }

    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);

    final String estado = EstadosViaje.normalizar(v.estado);
    final bool cancelable = estado == EstadosViaje.aceptado ||
        estado == EstadosViaje.enCaminoPickup;
    if (!cancelable) {
      _actionBusy = false;
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Solo puedes cancelar antes de que el cliente esté a bordo.',
            ),
          ),
        );
      }
      return;
    }

    final confirmar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.black,
            title: const Text('Cancelar viaje',
                style: TextStyle(color: Colors.white)),
            content: const Text(
              'Solo puedes cancelar antes de que el cliente esté a bordo o el viaje esté en ruta. '
              'Si cancelas ahora, el pedido vuelve al pool y el cliente es notificado.\n\n'
              'Las cancelaciones frecuentes o sin causa pueden revisarse. '
              '¿Confirmas que deseas cancelar en este punto del servicio?',
              style: TextStyle(color: Colors.white70, height: 1.35),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:
                    const Text('No', style: TextStyle(color: Colors.white70)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sí, cancelar'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmar) {
      _actionBusy = false;
      return;
    }

    try {
      await ViajesRepo.cancelarPorTaxista(
        viajeId: v.id,
        uidTaxista: uid,
      );
      _stopGps();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                '🚨 Viaje cancelado y limpiado. Ya estás disponible.',
              ),
            ),
          );

          navigator.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const TaxistaShell()),
            (route) => false,
          );
        }
      });
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          messenger
              .showSnackBar(SnackBar(content: Text('❌ ${errorAuthEs(e)}')));
        }
      });
    } finally {
      _actionBusy = false;
    }
  }

  // ===== Ver información del cliente =====
  Future<void> _verInfoCliente({required String uidCliente}) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(uidCliente)
                  .snapshots(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: Colors.greenAccent));
                }

                final u = snap.data?.data() ?? {};
                final nombre = (u['nombre'] ?? '—').toString().trim();
                final telefono = (u['telefono'] ?? '—').toString().trim();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                        child: Container(
                            width: 46,
                            height: 5,
                            decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(3)))),
                    const SizedBox(height: 16),
                    const Text('Información del Cliente',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.person,
                                  color: Colors.greenAccent, size: 24),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Nombre',
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12)),
                                    Text(nombre,
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 18)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Icon(Icons.phone,
                                  color: Colors.greenAccent, size: 24),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Teléfono',
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12)),
                                    Text(telefono,
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 18)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Cerrar'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ===== Contactar cliente =====
  Future<void> _contactarCliente(
      {required String uidCliente, required String viajeId}) async {
    if (!mounted) return;
    final ColorScheme sheetScheme = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        final ColorScheme cs = Theme.of(sheetCtx).colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.40,
          maxChildSize: 0.95,
          builder: (ctx, controller) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(sheetCtx).viewPadding.bottom + 16),
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('usuarios')
                    .doc(uidCliente)
                    .snapshots(),
                builder: (ctx2, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: CircularProgressIndicator(color: cs.primary),
                      ),
                    );
                  }

                  final u = snap.data?.data() ?? {};
                  final nombre = (u['nombre'] ?? '—').toString().trim();

                  String telClienteLimpio() =>
                      _cleanPhone(telefonoCrudoDesdeMapa(u));

                  return ListView(
                    controller: controller,
                    children: [
                      Center(
                        child: Container(
                          width: 46,
                          height: 5,
                          decoration: BoxDecoration(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Contactar cliente',
                        style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        nombre.isEmpty ? 'Cliente' : nombre,
                        style:
                            TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () async {
                          final String tel = telClienteLimpio();
                          if (tel.isEmpty) {
                            ScaffoldMessenger.of(sheetCtx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Número del cliente no disponible aún. Usa el chat o espera unos segundos.',
                                ),
                              ),
                            );
                            return;
                          }
                          await telefonoLaunchUri(telefonoUriLlamada(tel));
                        },
                        icon: Icon(Icons.call, color: cs.onPrimary),
                        label: const Text('Llamar'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          final String tel = telClienteLimpio();
                          if (tel.isEmpty) {
                            ScaffoldMessenger.of(sheetCtx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Número del cliente no disponible aún. Usa el chat o espera unos segundos.',
                                ),
                              ),
                            );
                            return;
                          }
                          const String waMsg = 'Hola, soy tu taxista de RAI.';
                          if (await telefonoLaunchUri(
                            telefonoUriWhatsAppApp(tel, waMsg),
                          )) {
                            return;
                          }
                          await telefonoLaunchUri(
                            telefonoUriWhatsAppWeb(tel, waMsg),
                          );
                        },
                        icon:
                            Icon(Icons.chat_bubble_outline, color: cs.primary),
                        label: const Text('WhatsApp'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          Future.microtask(() {
                            if (!mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  otroUid: uidCliente,
                                  otroNombre:
                                      nombre.isEmpty ? 'Cliente' : nombre,
                                  viajeId: viajeId,
                                ),
                              ),
                            );
                          });
                        },
                        icon: Icon(Icons.chat_outlined, color: cs.primary),
                        label: const Text('Chat en la app'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          side: BorderSide(color: cs.outline),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        child:
                            Text('Cerrar', style: TextStyle(color: cs.primary)),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _selectorNavegacionDestino(double lat, double lon) async {
    if (!mounted) return;
    if (_selectorNavegacionAbierto) return;
    _selectorNavegacionAbierto = true;
    try {
      if (mounted) setState(() => _viajeSheetOcultoPorModalNav = true);
      _plegarTarjetaViajeAntesNavSheet();
      try {
        await showNavegacionWazeMapsSheet(
          context,
          title: 'Abrir navegación',
          tieneCoords: true,
          gpsCoordinatesLine:
              'GPS: ${NavegacionExternaLauncher.fmtCoord(lat)}, ${NavegacionExternaLauncher.fmtCoord(lon)}',
          footerHint: 'Elige Waze o Google Maps para ir al destino del viaje.',
          onWaze: () {
            unawaited(NavegacionExternaLauncher.abrirWazeDestino(lat, lon));
          },
          onMaps: () {
            unawaited(
                NavegacionExternaLauncher.abrirGoogleMapsDestino(lat, lon));
          },
        );
      } finally {
        if (mounted) {
          setState(() => _viajeSheetOcultoPorModalNav = false);
          _restaurarTarjetaViajeTrasNavSheet();
        }
      }
    } finally {
      _selectorNavegacionAbierto = false;
    }
  }

  String _s(Object? x) => x?.toString() ?? '';
  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.only(right: 8, bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      );

  Widget _servicioBadge(Viaje v) {
    Color color;
    IconData icon;
    String label;

    switch (v.tipoServicio) {
      case 'motor':
        color = Colors.orange;
        icon = Icons.two_wheeler;
        label = '🛵 MOTOR';
        break;
      case 'turismo':
        color = Colors.purple;
        icon = Icons.beach_access;
        label = '🏝️ TURISMO';
        break;
      default:
        color = Colors.greenAccent;
        icon = Icons.directions_car;
        label = '🚗 NORMAL';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildWaypoints(Viaje v, {required bool enRuta}) {
    if (v.waypoints == null || v.waypoints!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📍 Paradas intermedias:',
            style: TextStyle(
                color: Colors.orangeAccent, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...v.waypoints!.asMap().entries.map((entry) {
            final index = entry.key + 1;
            final waypoint = entry.value;
            final label = waypoint['label']?.toString() ?? 'Parada $index';
            final lat = _waypointLat(waypoint);
            final lon = _waypointLon(waypoint);
            final navOk =
                enRuta && lat != null && lon != null && _coordsValid(lat, lon);
            final wLat = lat;
            final wLon = lon;
            return Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.flag_circle,
                      size: 16, color: Colors.orangeAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$index. $label',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  if (navOk && wLat != null && wLon != null)
                    IconButton(
                      tooltip: 'Navegar a esta parada',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: () => _selectorNavegacionDestino(wLat, wLon),
                      icon: const Icon(Icons.navigation,
                          size: 20, color: Colors.greenAccent),
                    ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildExtras(Viaje v) {
    if (v.extras == null || v.extras!.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<Widget> chips = [];
    if (v.extras!['pasajeros'] != null) {
      chips.add(_chip(
          '👥 ${v.extras!['pasajeros']} pasajero${v.extras!['pasajeros'] != 1 ? 's' : ''}'));
    }
    if (v.extras!['peaje'] != null) {
      chips.add(_chip('💰 Peaje: ${FormatosMoneda.rd(v.extras!['peaje'])}'));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        children: chips,
      ),
    );
  }

  Widget _tarjetaVehiculoVisibleAlCliente(Viaje v) {
    final taxistaId = (v.uidTaxista).toString().trim();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: taxistaId.isEmpty
          ? const Stream.empty()
          : FirebaseFirestore.instance
              .collection('usuarios')
              .doc(taxistaId)
              .snapshots(),
      builder: (context, snap) {
        final tx = (snap.hasData && snap.data!.exists)
            ? (snap.data!.data() ?? const {})
            : const {};

        final tipo = _s(v.tipoVehiculo).trim().isNotEmpty
            ? _s(v.tipoVehiculo).trim()
            : _s(tx['tipoVehiculo']).trim();
        final marca = _s((v as dynamic).marca).trim().isNotEmpty
            ? _s((v as dynamic).marca).trim()
            : _s(tx['marca']).trim().isNotEmpty
                ? _s(tx['marca']).trim()
                : _s(tx['vehiculoMarca']).trim();
        final modelo = _s((v as dynamic).modelo).trim().isNotEmpty
            ? _s((v as dynamic).modelo).trim()
            : _s(tx['modelo']).trim().isNotEmpty
                ? _s(tx['modelo']).trim()
                : _s(tx['vehiculoModelo']).trim();
        final color = _s((v as dynamic).color).trim().isNotEmpty
            ? _s((v as dynamic).color).trim()
            : _s(tx['color']).trim().isNotEmpty
                ? _s(tx['color']).trim()
                : _s(tx['vehiculoColor']).trim();
        final placa = _s((v as dynamic).placa).trim().isNotEmpty
            ? _s((v as dynamic).placa).trim()
            : _s(tx['placa']).trim();

        final linea = [
          if (tipo.isNotEmpty) tipo,
          if (marca.isNotEmpty) marca,
          if (modelo.isNotEmpty) modelo,
        ].join(' · ');

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tu vehículo (visible al cliente)',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(linea.isEmpty ? '—' : linea,
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Wrap(children: [
                if (color.isNotEmpty) _chip('Color: $color'),
                if (placa.isNotEmpty) _chip('Placa: $placa'),
              ]),
            ],
          ),
        );
      },
    );
  }

  String _labelEstado(String e) {
    final s = EstadosViaje.normalizar(e);
    if (s == EstadosViaje.pendiente) return 'Pendiente';
    if (s == EstadosViaje.aceptado) return 'Aceptado';
    if (s == EstadosViaje.enCaminoPickup) return 'Ir a buscar cliente';
    if (s == EstadosViaje.aBordo) return 'Cliente a bordo';
    if (s == EstadosViaje.enCurso) return 'En curso';
    if (s == EstadosViaje.completado) return 'Completado';
    if (s == EstadosViaje.cancelado) return 'Cancelado';
    return e;
  }

  int _etapaActualViaje(String estadoBase) {
    if (EstadosViaje.esCompletado(estadoBase)) return 4;
    if (EstadosViaje.esEnCurso(estadoBase)) return 3;
    if (EstadosViaje.esAbordo(estadoBase)) return 2;
    if (EstadosViaje.esEnCaminoPickup(estadoBase) ||
        EstadosViaje.esAceptado(estadoBase)) {
      return 1;
    }
    return 0;
  }

  Widget _progresoOperativoViaje(String estadoBase) {
    final int etapa = _etapaActualViaje(estadoBase);
    const labels = <String>[
      'Aceptado',
      'Pickup',
      'A bordo',
      'En ruta',
      'Finalizado',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Progreso del viaje',
          style: TextStyle(
              color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 7,
            value: (etapa + 1) / labels.length,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List<Widget>.generate(labels.length, (i) {
            final bool done = i <= etapa;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: done
                    ? Colors.greenAccent.withValues(alpha: 0.18)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: done
                      ? Colors.greenAccent.withValues(alpha: 0.6)
                      : Colors.white24,
                ),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  color: done ? Colors.greenAccent : Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  static String _formatDurationHMS(Duration d) {
    if (d.isNegative) return '00:00';
    final int h = d.inHours;
    final int m = d.inMinutes.remainder(60);
    final int s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildDuracionEnRuta(Viaje v, String estadoBase) {
    if (!EstadosViaje.esEnCurso(estadoBase)) return const SizedBox.shrink();
    final DateTime? start = v.inicioRutaDesde;
    if (start == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: StreamBuilder<DateTime>(
        stream:
            Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
        builder: (BuildContext context, _) {
          final Duration elapsed = DateTime.now().difference(start);
          return Row(
            children: [
              const Icon(Icons.schedule, color: Colors.blueAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tiempo en ruta: ${_formatDurationHMS(elapsed)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _escucharCancelacionRemota(String viajeId) {
    _cancelSub?.cancel();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);

    _cancelSub = FirebaseFirestore.instance
        .collection('viajes')
        .doc(viajeId)
        .snapshots()
        .listen((ds) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        _diag('remote snapshot id=$viajeId exists=${ds.exists}');

        if (!ds.exists) {
          if (_procesandoRemocion) return;
          _procesandoRemocion = true;
          final bool ausenciaConfirmada = await _confirmarAusenciaReal(
            viajeId: viajeId,
            uidTaxista: uid,
          );
          _diag('absence check id=$viajeId confirmed=$ausenciaConfirmada');
          _procesandoRemocion = false;
          if (!ausenciaConfirmada) return;
          _stopGps();
          messenger.showSnackBar(
              const SnackBar(content: Text('El viaje ya no está disponible.')));
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const TaxistaShell()),
            (route) => false,
          );
          return;
        }

        final d = ds.data();
        if (d == null) return;

        final est = (d['estado'] ?? '').toString();
        final estN = EstadosViaje.normalizar(est);
        final taxistaId = (d['taxistaId'] ?? d['uidTaxista'] ?? '').toString();
        final bool teRemovieron =
            uid.isNotEmpty && (taxistaId.isEmpty || taxistaId != uid);
        _diag(
            'state id=$viajeId estado=$estN taxistaDoc=$taxistaId me=$uid teRemovieron=$teRemovieron');

        if (estN == EstadosViaje.cancelado || teRemovieron) {
          // Evita flicker por estados transitorios/reconciliaciones rápidas.
          if (_procesandoRemocion) return;
          _procesandoRemocion = true;
          final String? motivoConfirmado = await _confirmarRemocionReal(
            viajeId: viajeId,
            uidTaxista: uid,
            snapshotActual: d,
          );
          _diag('removal check id=$viajeId result=$motivoConfirmado');
          _procesandoRemocion = false;
          if (motivoConfirmado == null) return;

          _stopGps();
          if (uid.isNotEmpty) {
            try {
              await FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(uid)
                  .set({
                'viajeActivoId': '',
                'updatedAt': FieldValue.serverTimestamp(),
                'actualizadoEn': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            } catch (e, st) {
              await ErrorReporting.reportError(
                e,
                stack: st,
                context:
                    'viaje_en_curso_taxista: reset viajeActivoId (removido)',
              );
            }
          }
          final bool esRemocion = motivoConfirmado == 'removido' ||
              (motivoConfirmado != 'cancelado' && teRemovieron);
          messenger.showSnackBar(
            SnackBar(
              content: Text(esRemocion
                  ? 'Fuiste removido del viaje.'
                  : 'El cliente canceló el viaje.'),
            ),
          );
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const TaxistaShell()),
            (route) => false,
          );
        }
        // Posición del viaje: ya la cubre StreamBuilder + stream deduplicado; evitar setState duplicado aquí.
      });
    }, onError: (e, st) {
      ErrorReporting.reportError(
        e,
        stack: st,
        context: 'viaje_en_curso_taxista: stream listener onError',
      );
    });
  }

  Future<String?> _confirmarRemocionReal({
    required String viajeId,
    required String uidTaxista,
    required Map<String, dynamic> snapshotActual,
  }) async {
    final String estadoNow =
        EstadosViaje.normalizar((snapshotActual['estado'] ?? '').toString());
    final String taxistaNow =
        (snapshotActual['taxistaId'] ?? snapshotActual['uidTaxista'] ?? '')
            .toString();

    if (estadoNow == EstadosViaje.cancelado) {
      _diag('confirmRemocion fast-cancel id=$viajeId');
      return 'cancelado';
    }
    if (uidTaxista.isEmpty) return null;

    // Si aún me pertenece, claramente no está removido.
    if (taxistaNow == uidTaxista) return null;

    try {
      // Pequeño debounce para permitir reconciliaciones rápidas del backend.
      await Future.delayed(const Duration(milliseconds: 700));
      final doc = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .get();
      if (!doc.exists) {
        _diag('confirmRemocion doc-missing id=$viajeId');
        return 'removido';
      }
      final data = doc.data() ?? const <String, dynamic>{};
      final String estado =
          EstadosViaje.normalizar((data['estado'] ?? '').toString());
      final String taxista =
          (data['taxistaId'] ?? data['uidTaxista'] ?? '').toString();

      if (estado == EstadosViaje.cancelado) {
        _diag('confirmRemocion server-cancel id=$viajeId');
        return 'cancelado';
      }
      // Solo confirmamos remoción cuando el viaje sigue sin pertenecerme.
      if (taxista.isEmpty || taxista != uidTaxista) {
        _diag(
            'confirmRemocion server-removed id=$viajeId taxista=$taxista me=$uidTaxista');
        return 'removido';
      }
      return null;
    } catch (_) {
      // Si falla verificación remota, no mostramos mensaje agresivo por seguridad UX.
      return null;
    }
  }

  Future<bool> _confirmarAusenciaReal({
    required String viajeId,
    required String uidTaxista,
  }) async {
    try {
      await Future.delayed(const Duration(milliseconds: 700));
      final doc = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .get();
      if (!doc.exists) return true;
      final data = doc.data() ?? const <String, dynamic>{};
      final String estado =
          EstadosViaje.normalizar((data['estado'] ?? '').toString());
      final String taxista =
          (data['taxistaId'] ?? data['uidTaxista'] ?? '').toString();
      if (estado == EstadosViaje.cancelado) return true;
      return taxista.isEmpty ||
          (uidTaxista.isNotEmpty && taxista != uidTaxista);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final formato = DateFormat('dd/MM/yyyy - HH:mm');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Mi viaje en curso',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          ViajesCercanosTaxistaAppBarAction(
            controller: _viajesCercanosCtl,
            escuchaActiva: _viajesCercanosEscucha,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: StreamBuilder<Viaje?>(
              stream: _stream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: Colors.greenAccent));
                }

                if (snap.hasError) {
                  if (_cachedViaje != null) {
                    final v = _cachedViaje!;
                    final fecha = formato.format(v.fechaHora);
                    final total = FormatosMoneda.rd(v.precio);
                    final estadoBase = EstadosViaje.normalizar(
                      v.estado.isNotEmpty
                          ? v.estado
                          : (v.completado
                              ? EstadosViaje.completado
                              : (v.aceptado
                                  ? EstadosViaje.aceptado
                                  : EstadosViaje.pendiente)),
                    );
                    return Column(
                      children: [
                        Expanded(
                          flex: 3,
                          child: RepaintBoundary(
                            child: MapaTiempoReal(
                              key: const ValueKey<String>('mapa-cache-viaje'),
                              esTaxista: true,
                              esCliente: false,
                              onUserInteractWithMap:
                                  _colapsarTarjetaViajePorMapa,
                              onUserMapGestureEnd:
                                  _expandirTarjetaViajeTrasMapa,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('🧭 ${v.origen} → ${v.destino}',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                Text('🕓 Fecha: $fecha',
                                    style: const TextStyle(
                                        fontSize: 16, color: Colors.white70)),
                                const SizedBox(height: 8),
                                Text('💰 Total: $total',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        color: Colors.greenAccent)),
                                const SizedBox(height: 8),
                                Text('📍 Estado: ${_labelEstado(estadoBase)}',
                                    style: const TextStyle(
                                        fontSize: 16, color: Colors.white70)),
                                const SizedBox(height: 12),
                                const Text(
                                  'Reconectando viaje en tiempo real...',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return const Center(
                      child:
                          CircularProgressIndicator(color: Colors.greenAccent));
                }

                final v = snap.data;

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final bool escucharPendientes = v != null &&
                      (() {
                        final String est = EstadosViaje.normalizar(
                          v.estado.isNotEmpty
                              ? v.estado
                              : (v.completado
                                  ? EstadosViaje.completado
                                  : (v.aceptado
                                      ? EstadosViaje.aceptado
                                      : EstadosViaje.pendiente)),
                        );
                        // Desde aceptado / en camino al pickup hasta a bordo / en curso: puede reservar el siguiente.
                        return EstadosViaje.esActivo(est);
                      })();
                  if (_viajesCercanosEscucha.value != escucharPendientes) {
                    _viajesCercanosEscucha.value = escucharPendientes;
                    if (!escucharPendientes) {
                      _viajesCercanosCtl.resetListeningUi();
                    }
                  }
                });

                if (v == null) {
                  _cachedViaje = null;
                  _stopGps();
                  return Column(
                    children: [
                      Expanded(
                        flex: 3,
                        child: RepaintBoundary(
                          child: MapaTiempoReal(
                            key: const ValueKey<String>('mapa-sin-viaje'),
                            esTaxista: true,
                            esCliente: false,
                            onUserInteractWithMap: _colapsarTarjetaViajePorMapa,
                            onUserMapGestureEnd: _expandirTarjetaViajeTrasMapa,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.taxi_alert,
                                  color: Colors.greenAccent,
                                  size: 60,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'No tienes viaje en curso',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Puedes buscar viajes disponibles\nen el botón verde',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context, rootNavigator: true)
                                        .push(
                                      MaterialPageRoute(
                                          builder: (_) => const TaxistaShell()),
                                    );
                                  },
                                  icon: const Icon(Icons.search),
                                  label: const Text('Buscar viajes'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.greenAccent,
                                    foregroundColor: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                // Actualizar cache
                if (_cachedViaje?.id != v.id) {
                  _cachedViaje = v;
                  _escucharCancelacionRemota(v.id);

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _asegurarGps(v.id).then((_) {
                      if (mounted) {
                        _scheduleDrawRoute();
                      }
                    });
                  });
                } else {
                  final String prevSig = _cachedViaje != null
                      ? _firmaRutaMapaTaxista(_cachedViaje!)
                      : '';
                  _cachedViaje = v;
                  final String newSig = _firmaRutaMapaTaxista(v);
                  if (prevSig != newSig && mounted) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _scheduleDrawRoute();
                    });
                  }
                }

                final fecha = formato.format(v.fechaHora);
                final total = FormatosMoneda.rd(v.precio);

                final estadoBase = EstadosViaje.normalizar(
                  v.estado.isNotEmpty
                      ? v.estado
                      : (v.completado
                          ? EstadosViaje.completado
                          : (v.aceptado
                              ? EstadosViaje.aceptado
                              : EstadosViaje.pendiente)),
                );

                if (estadoBase == EstadosViaje.cancelado) {
                  final cancelNavigator =
                      Navigator.of(context, rootNavigator: true);

                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    _stopGps();
                    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                    if (uid.isNotEmpty) {
                      try {
                        await FirebaseFirestore.instance
                            .collection('usuarios')
                            .doc(uid)
                            .set({
                          'viajeActivoId': '',
                          'updatedAt': FieldValue.serverTimestamp(),
                          'actualizadoEn': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                      } catch (e, st) {
                        await ErrorReporting.reportError(
                          e,
                          stack: st,
                          context:
                              'viaje_en_curso_taxista: set viajeActivoId (cancelado)',
                        );
                      }
                    }
                    if (mounted) {
                      cancelNavigator.pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const TaxistaShell()),
                        (route) => false,
                      );
                    }
                  });
                  return const SizedBox.shrink();
                }

                final mostrarOrigen = EstadosViaje.esAceptado(estadoBase) ||
                    EstadosViaje.esEnCaminoPickup(estadoBase) ||
                    EstadosViaje.esAbordo(estadoBase);

                final mostrarDestino = EstadosViaje.esEnCurso(estadoBase) ||
                    (EstadosViaje.esAbordo(estadoBase) && v.codigoVerificado);

                final LatLng? puntoOrigen =
                    _coordsValid(v.latCliente, v.lonCliente)
                        ? LatLng(v.latCliente, v.lonCliente)
                        : null;

                final LatLng? puntoDestino =
                    _coordsValid(v.latDestino, v.lonDestino)
                        ? LatLng(v.latDestino, v.lonDestino)
                        : null;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: MapaTiempoReal(
                          key: ValueKey<String>('mapa-${v.id}'),
                          origen: puntoOrigen,
                          origenNombre: v.origen,
                          destino: puntoDestino,
                          destinoNombre: v.destino,
                          mostrarOrigen: mostrarOrigen,
                          mostrarDestino: mostrarDestino,
                          esTaxista: true,
                          esCliente: false,
                          mostrarTaxista: false,
                          ubicacionTaxista:
                              _coordsValid(v.latTaxista, v.lonTaxista)
                                  ? LatLng(v.latTaxista, v.lonTaxista)
                                  : null,
                          overlayPolylines: _polylines,
                          onUserInteractWithMap: _colapsarTarjetaViajePorMapa,
                          onUserMapGestureEnd: _expandirTarjetaViajeTrasMapa,
                        ),
                      ),
                    ),
                    Transform.translate(
                      offset: _viajeSheetOcultoPorModalNav
                          ? Offset(
                              0,
                              MediaQuery.sizeOf(context).height + 80,
                            )
                          : Offset.zero,
                      child: DraggableScrollableSheet(
                        controller: _viajeNavSheetCtrl,
                        initialChildSize: _kViajeNavSheetInitialMitad,
                        minChildSize: _kViajeNavSheetMin,
                        maxChildSize: 0.92,
                        snap: true,
                        snapSizes: const <double>[
                          0.14,
                          0.40,
                          _kViajeNavSheetInitialMitad,
                          0.62,
                          0.92,
                        ],
                        builder: (context, scrollController) {
                        return Container(
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(20)),
                            border: Border(
                                top: BorderSide(color: Color(0x22FFFFFF))),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 16,
                                offset: Offset(0, -4),
                              ),
                            ],
                          ),
                          child: ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            children: [
                              Center(
                                child: Container(
                                  width: 40,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: Colors.white24,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (FirebaseAuth.instance.currentUser?.uid !=
                                  null)
                                ColaSiguienteViajeBannerTaxista(
                                  uidTaxista:
                                      FirebaseAuth.instance.currentUser!.uid,
                                ),
                              if (FirebaseAuth.instance.currentUser?.uid !=
                                  null)
                                const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.grey[900],
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '🧭 ${v.origen} → ${v.destino}',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        _servicioBadge(v),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '🕓 Fecha: $fecha',
                                      style: const TextStyle(
                                          fontSize: 16, color: Colors.white70),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '💰 Total: $total',
                                      style: const TextStyle(
                                          fontSize: 18,
                                          color: Colors.greenAccent),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '📍 Estado: ${_labelEstado(estadoBase)}',
                                      style: const TextStyle(
                                          fontSize: 16, color: Colors.white70),
                                    ),
                                    const SizedBox(height: 10),
                                    _progresoOperativoViaje(estadoBase),
                                    _buildDuracionEnRuta(v, estadoBase),
                                    _buildWaypoints(v,
                                        enRuta:
                                            EstadosViaje.esEnCurso(estadoBase)),
                                    _buildExtras(v),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              _tarjetaVehiculoVisibleAlCliente(v),
                              const SizedBox(height: 16),
                              _actionBar(v, estadoBase),
                              const SizedBox(height: 8),
                              _botonRescate(v.id),
                            ],
                          ),
                        );
                      },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          ViajesCercanosTaxistaLayer(
            controller: _viajesCercanosCtl,
            escuchaActiva: _viajesCercanosEscucha,
            taxistaUbicacion: _taxistaPosCola,
          ),
        ],
      ),
    );
  }

  // ==================== BARRA DE ACCIONES ====================

  Widget _actionBar(Viaje v, String estadoBase) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _getActionButtons(v, estadoBase),
      ),
    );
  }

  List<Widget> _getActionButtons(Viaje v, String estadoBase) {
    final uidCli = _uidClienteDe(v);

    if (EstadosViaje.esAceptado(estadoBase) ||
        EstadosViaje.esEnCaminoPickup(estadoBase)) {
      final bool puedeMarcarAbordo = _navegacionIniciada || _clienteCerca;

      return [
        const SizedBox(height: 12),
        const Text(
          'Paso 1: ve al cliente · Paso 2: confirma abordo · Paso 3: código que te dicta · Paso 4: navegas al destino',
          style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[850],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '📍 Punto de recogida del cliente',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                v.origen,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (uidCli.isNotEmpty) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ClientePerfilConductorChip(
                    uidCliente: uidCli,
                  ),
                ),
              ],
              if (_clienteCerca) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.green, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '✅ ¡Estás muy cerca del cliente! Ya puedes marcarlo como a bordo.',
                          style: TextStyle(
                              color: Colors.green, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed:
                _navegacionIniciada ? null : () => _iniciarNavegacionPickup(v),
            icon: Icon(
                _navegacionIniciada ? Icons.check_circle : Icons.navigation,
                size: 24),
            label: Text(
              _navegacionIniciada
                  ? 'YA ABRIÓ NAVEGACIÓN — VE HACIA EL CLIENTE'
                  : 'NAVEGAR HACIA EL CLIENTE',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navegacionIniciada ? Colors.green : Colors.blue,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        if (_navegacionIniciada) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Abriste Maps/Waze hacia el cliente. Al llegar y subir al pasajero, usa «Cliente a bordo» y luego el código.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!_navegacionIniciada && !_clienteCerca) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.touch_app, color: Colors.orange, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Toca «Navegar hacia el cliente» para abrir Waze/Maps al punto de recogida, o acércate (~100 m) para habilitar abordo.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!_navegacionIniciada && _clienteCerca) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '✅ ¡Excelente! Estás en el punto de recogida. Ya puedes marcar "Cliente a bordo".',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (puedeMarcarAbordo) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _marcarClienteAbordo(v),
              icon: const Icon(Icons.person_add, size: 24),
              label: const Text(
                'CLIENTE A BORDO (paso 2)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Divider(color: Colors.white24),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: uidCli.isEmpty
                    ? null
                    : () => _verInfoCliente(uidCliente: uidCli),
                icon: const Icon(Icons.person, size: 18),
                label: const Text('Ver cliente'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: uidCli.isEmpty
                    ? null
                    : () =>
                        _contactarCliente(uidCliente: uidCli, viajeId: v.id),
                icon: const Icon(Icons.chat, size: 18),
                label: const Text('Contactar'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _cancelarPorTaxista(v),
            icon: const Icon(Icons.cancel_outlined, size: 20),
            label: const Text('Cancelar viaje', style: TextStyle(fontSize: 15)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ];
    }

    if (EstadosViaje.esAbordo(estadoBase)) {
      if (!_codigoEsperadoValido(v.codigoVerificacion)) {
        return [
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.55)),
            ),
            child: const Text(
              'Este viaje no tiene un código de verificación válido en el sistema. '
              'Contacta soporte o cancela para que el cliente pueda solicitar un viaje nuevo.',
              style: TextStyle(color: Colors.white70, height: 1.35),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _btnSecundario(
                icon: const Icon(Icons.person, size: 20),
                label: const Text('Ver cliente'),
                onPressed: uidCli.isEmpty
                    ? null
                    : () => _verInfoCliente(uidCliente: uidCli),
              ),
              const SizedBox(width: 12),
              _btnSecundario(
                icon: const Icon(Icons.chat, size: 20),
                label: const Text('Contactar'),
                onPressed: uidCli.isEmpty
                    ? null
                    : () =>
                        _contactarCliente(uidCliente: uidCli, viajeId: v.id),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
          const SizedBox(height: 12),
          const Text(
            'Cancelación bloqueada: el cliente ya está a bordo.',
            style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
          ),
        ];
      }

      if (v.codigoVerificado) {
        return [
          const SizedBox(height: 12),
          const Text(
            'Código verificado',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'El código ya quedó verificado. Continúa para pasar a «en ruta» y abrir navegación al destino.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 16),
          _btnPrimario(
            icon: const Icon(Icons.play_arrow, size: 24),
            label: const Text('INICIAR RUTA AL DESTINO',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            onPressed: () async {
              if (_actionBusy || _selectorNavegacionAbierto) return;
              _actionBusy = true;
              final uidTax = FirebaseAuth.instance.currentUser?.uid;
              if (uidTax == null) {
                _actionBusy = false;
                return;
              }
              try {
                try {
                  await ViajesRepo.iniciarViaje(
                      viajeId: v.id, uidTaxista: uidTax);
                } catch (e, st) {
                  await ErrorReporting.reportError(
                    e,
                    stack: st,
                    context: 'viaje_en_curso_taxista: iniciarViaje (continuar)',
                  );
                }
                final okGps = await _asegurarGps(v.id);
                if (!okGps) return;
                if (!mounted) return;
                await _selectorNavegacionDestino(v.latDestino, v.lonDestino);
              } finally {
                _actionBusy = false;
              }
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _btnSecundario(
                icon: const Icon(Icons.person, size: 20),
                label: const Text('Ver cliente'),
                onPressed: uidCli.isEmpty
                    ? null
                    : () => _verInfoCliente(uidCliente: uidCli),
              ),
              const SizedBox(width: 12),
              _btnSecundario(
                icon: const Icon(Icons.chat, size: 20),
                label: const Text('Contactar'),
                onPressed: uidCli.isEmpty
                    ? null
                    : () =>
                        _contactarCliente(uidCliente: uidCli, viajeId: v.id),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
          const SizedBox(height: 12),
          const Text(
            'Cancelación bloqueada: el cliente ya está a bordo.',
            style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
          ),
        ];
      }

      return [
        const SizedBox(height: 12),
        const Text(
          'Paso 3 — Código con el cliente',
          style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'El mismo PIN de 6 dígitos que el cliente ve en su pantalla. '
          'Al verificarlo, el viaje pasa a ruta y se puede abrir navegación al destino.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              TextField(
                controller: _codigoCtrl,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                onSubmitted: (_) =>
                    _verificarCodigo(v.id, v.codigoVerificacion ?? ''),
                decoration: InputDecoration(
                  hintText: '000000',
                  hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 32,
                      letterSpacing: 8),
                  filled: true,
                  fillColor: Colors.grey[900],
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide.none,
                  ),
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
              _btnPrimario(
                icon: const Icon(Icons.verified, size: 24),
                label: const Text('VERIFICAR E INICIAR RUTA',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                onPressed: _actionBusy
                    ? null
                    : () => _verificarCodigo(v.id, v.codigoVerificacion ?? ''),
                backgroundColor: Colors.orange,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _btnSecundario(
              icon: const Icon(Icons.person, size: 20),
              label: const Text('Ver cliente'),
              onPressed: uidCli.isEmpty
                  ? null
                  : () => _verInfoCliente(uidCliente: uidCli),
            ),
            const SizedBox(width: 12),
            _btnSecundario(
              icon: const Icon(Icons.chat, size: 20),
              label: const Text('Contactar'),
              onPressed: uidCli.isEmpty
                  ? null
                  : () => _contactarCliente(uidCliente: uidCli, viajeId: v.id),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
        const SizedBox(height: 12),
        _btnPeligro(
          icon: const Icon(Icons.cancel_outlined, size: 20),
          label: const Text('Salir a disponibilidad',
              style: TextStyle(fontSize: 15)),
          onPressed: () => _cancelarPorTaxista(v),
        ),
      ];
    }

    if (EstadosViaje.esEnCurso(estadoBase)) {
      return [
        const SizedBox(height: 12),
        const Text(
          'En camino al destino',
          style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          v.destino,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 16),
        _btnPrimario(
          icon: const Icon(Icons.navigation, size: 24),
          label: const Text('NAVEGAR AL DESTINO',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          onPressed: () async {
            final okGps = await _asegurarGps(v.id);
            if (!okGps) return;
            await _selectorNavegacionDestino(v.latDestino, v.lonDestino);
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _btnSecundario(
              icon: const Icon(Icons.person, size: 20),
              label: const Text('Ver cliente'),
              onPressed: uidCli.isEmpty
                  ? null
                  : () => _verInfoCliente(uidCliente: uidCli),
            ),
            const SizedBox(width: 12),
            _btnSecundario(
              icon: const Icon(Icons.chat, size: 20),
              label: const Text('Contactar'),
              onPressed: uidCli.isEmpty
                  ? null
                  : () => _contactarCliente(uidCliente: uidCli, viajeId: v.id),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
        const SizedBox(height: 12),
        _btnPrimario(
          icon: const Icon(Icons.check_circle, size: 24),
          label: const Text('FINALIZAR VIAJE',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          onPressed: () => _finalizarViaje(v),
          backgroundColor: Colors.blueAccent,
        ),
      ];
    }

    return [
      const Center(
        child: Text(
          'Estado del viaje no reconocido',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    ];
  }

  // ==================== ESTILOS DE BOTONES ====================

  Widget _btnPrimario({
    required Widget icon,
    required Widget label,
    required VoidCallback? onPressed,
    Color? backgroundColor,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: label,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? Colors.greenAccent,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 56),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _btnSecundario({
    required Widget icon,
    required Widget label,
    required VoidCallback? onPressed,
  }) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: label,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
          foregroundColor: Colors.white,
          minimumSize: const Size(1, 48),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _btnPeligro({
    required Widget icon,
    required Widget label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: label,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
          foregroundColor: Colors.redAccent,
          minimumSize: const Size(double.infinity, 48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _botonRescate(String viajeId) {
    return TextButton.icon(
      onPressed: () async {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        _stopGps();
        if (uid.isNotEmpty) {
          try {
            await FirebaseFirestore.instance
                .collection('usuarios')
                .doc(uid)
                .set({
              'viajeActivoId': '',
              'updatedAt': FieldValue.serverTimestamp(),
              'actualizadoEn': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } catch (e, st) {
            await ErrorReporting.reportError(
              e,
              stack: st,
              context: 'viaje_en_curso_taxista: set viajeActivoId (rescate)',
            );
          }
        }
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const TaxistaShell()),
            (route) => false,
          );
        }
      },
      icon: const Icon(Icons.exit_to_app, color: Colors.white70),
      label: const Text('Salir a disponibles (rescate)',
          style: TextStyle(color: Colors.white70)),
    );
  }
}
