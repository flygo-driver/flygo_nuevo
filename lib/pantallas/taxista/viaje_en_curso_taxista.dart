// lib/pantallas/taxista/viaje_en_curso_taxista.dart
// ignore_for_file: avoid_print -- [VIAJE_ACTIVO] / [FINALIZAR] / [FINALIZAR_VIAJE]

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/data/pago_data.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/pantallas/chat/chat_screen.dart';
import 'package:flygo_nuevo/servicios/bola_pueblo_firestore_sync.dart';
import 'package:flygo_nuevo/servicios/bola_pueblo_repo.dart';
import 'package:flygo_nuevo/servicios/directions_service.dart';
import 'package:flygo_nuevo/servicios/gps_service.dart';
import 'package:flygo_nuevo/servicios/error_reporting.dart';
import 'package:flygo_nuevo/servicios/error_auth_es.dart';
import 'package:flygo_nuevo/navegacion/post_viaje_taxista_nav.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/navegacion_externa_launcher.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart'; // 🔥 ESTA LÍNEA
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/release_build_flags.dart';
import 'package:flygo_nuevo/utils/precio_viaje_doc.dart';
import 'package:flygo_nuevo/utils/telefono_viaje.dart';
import 'package:flygo_nuevo/utils/ux_log.dart';
import 'package:flygo_nuevo/servicios/viaje_comunicacion_repo.dart';
import 'package:flygo_nuevo/shell/taxista_shell.dart';
import 'package:flygo_nuevo/widgets/cliente_perfil_conductor_chip.dart';
import 'package:flygo_nuevo/widgets/mapa_tiempo_real.dart';
import 'package:flygo_nuevo/widgets/viaje_chat_mensajes_en_vivo.dart';
import 'package:flygo_nuevo/widgets/cola_siguiente_viaje_banner.dart';
import 'package:flygo_nuevo/widgets/navegacion_waze_maps_sheet.dart';
import 'package:flygo_nuevo/widgets/viaje_flujo_orientacion.dart';
import 'package:flygo_nuevo/widgets/viajes_cercanos_taxista.dart';

String _safeFechaViaje(DateTime? dt) {
  try {
    return dt == null ? '—' : DateFormat('dd/MM/yyyy - HH:mm').format(dt);
  } catch (_) {
    return '—';
  }
}

String _safeMoneyViaje(num? n) {
  try {
    final double v = (n ?? 0).toDouble();
    if (!v.isFinite) return FormatosMoneda.rd(0);
    return FormatosMoneda.rd(v);
  } catch (_) {
    return FormatosMoneda.rd(0);
  }
}

/// Tras [finalizarViajeSeguro]: no reintentar escrituras legacy en billetera.
bool _pagoYaAsentadoPorServidor(Map<String, dynamic> data) {
  if (data['comision_cents'] is num && (data['comision_cents'] as num) > 0) {
    return true;
  }
  if (data['facturaSaldoPrepagoComisionRd'] != null) {
    return true;
  }
  final String st =
      EstadosViaje.normalizar((data['estado'] ?? '').toString());
  return data['completado'] == true && st == EstadosViaje.completado;
}

void logDbg(String msg) {
  if (kDebugMode) debugPrint('[VIAJE_TX] $msg');
}

const bool _diagTripFlow =
    bool.fromEnvironment('TRIP_FLOW_DIAG', defaultValue: false);
void _diag(String msg) {
  if (_diagTripFlow) debugPrint('[TRIP_FLOW][en_curso] $msg');
}

/// Solo en debug/profile: ignorar distancias muy pequeñas (mismo dispositivo).
const double kDebugMinDistance = 0.01; // ~10 m

/// Radio máximo para habilitar el botón **Finalizar** (Geolocator vs pin de destino).
const double kFinalizarRadioMetros = 50;

class ViajeEnCursoTaxista extends StatefulWidget {
  const ViajeEnCursoTaxista({super.key});
  @override
  State<ViajeEnCursoTaxista> createState() => _ViajeEnCursoTaxistaState();
}

class _ViajeEnCursoTaxistaState extends State<ViajeEnCursoTaxista>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  /// Pruebas en silla: solo debug/profile con define; nunca en Play Store.
  bool get _flygoSimCasa => ReleaseBuildFlags.simCasaEnabled;

  /// Pruebas en casa / Bola Ahorro: abrir Maps y finalizar sin recorrer distancia real.
  bool _permitePruebaSinRecorrido(Viaje v) =>
      _flygoSimCasa || v.tipoServicio == 'bola_ahorro';

  /// Copy del sheet: Bola solo en viajes bola; SIM CASA en debug sin mezclar productos.
  String _hintPruebaSinRecorrido(
    Viaje v, {
    required bool trasIniciarRuta,
  }) {
    if (v.tipoServicio == 'bola_ahorro') {
      return trasIniciarRuta
          ? 'Bola Ahorro: no hace falta recorrer km. '
              'Tras iniciar ruta podés finalizar directo.'
          : 'Bola Ahorro: abrí mapa o continuá sin mapa; '
              'luego aparece «Finalizar viaje».';
    }
    return trasIniciarRuta
        ? 'Modo prueba (SIM CASA): no hace falta recorrer km. '
            'Tras iniciar ruta podés finalizar directo.'
        : 'Modo prueba (SIM CASA): abrí mapa o continuá sin mapa; '
            'luego aparece «Finalizar viaje».';
  }

  /// GPS en vivo para el doc del viaje; abrir Waze/Maps no lo exige en prueba/Bola.
  Future<bool> _gpsListoParaAbrirNavegacionExterna(Viaje v) async {
    if (_permitePruebaSinRecorrido(v)) return true;
    return _asegurarGps(v.id);
  }

  @override
  bool get wantKeepAlive => true;

  /// Evita leer SharedPreferences en cada frame del stream.
  String? _navPickupPrefsLoadedForId;
  String? _navDestinoPrefsLoadedForId;

  /// Antispam del snackbar al volver de Waze/Maps (resumed).
  DateTime? _lastNavResumeSnackAt;

  GoogleMapController? _map;

  // ===== GPS =====
  StreamSubscription<Position>? _gpsSub;
  String? _gpsParaViajeId;
  bool _gpsActivo = false;

  /// Reintento acotado si el stream de posición falla (p. ej. GPS apagado).
  static const int _kMaxGpsStreamRecoveryIntentos = 3;
  static const Duration _kGpsStreamRecoveryDelay = Duration(seconds: 5);
  int _gpsStreamRecoveryIntentos = 0;
  Timer? _gpsStreamRecoveryTimer;

  // ===== Acciones =====
  bool _actionBusy = false;

  // ===== Remoción / cancelación remota =====
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _cancelSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _bolaCancelSub;
  String? _bolaCancelWatchViajeId;
  bool _procesandoRemocion = false;
  DateTime? _cancelListenerIniciadoEn;

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
  final ValueNotifier<ColaCercaniaReferencia?> _colaReferenciaOrden =
      ValueNotifier<ColaCercaniaReferencia?>(null);

  // 🚀 Variables para detección de cercanía del cliente
  bool _clienteCerca = false;
  bool _navegacionIniciada = false;
  bool _navegacionDestinoIniciada = false;
  bool _selectorNavegacionAbierto = false;
  /// Evita ver la tarjeta del viaje y el modal Waze/Maps apilados a la vez.
  bool _viajeSheetOcultoPorModalNav = false;
  final DraggableScrollableController _viajeSheetCtrl =
      DraggableScrollableController();
  static const double _kViajeSheetMin = 0.14;
  static const double _kViajeSheetInitial = 0.48;
  static const double DISTANCIA_CERCANIA_KM = 0.1;

  // Cache del viaje actual
  Viaje? _cachedViaje;
  bool _isUpdatingLocation = false;

  /// Distancia al pin de destino (último waypoint o destino); solo en `en_curso`.
  double? _distanciaMetrosAlDestino;

  /// Multiparada: cuántos destinos (paradas + final) ya confirmó el taxista.
  int _multiLegCompletadas = 0;
  String? _multiNavViajeId;

  /// Un solo ticker para "tiempo en ruta" (evita recrear Stream.periodic en cada rebuild).
  late final Stream<DateTime> _duracionEnRutaTicker =
      Stream<DateTime>.periodic(
        const Duration(seconds: 1),
        (_) => DateTime.now(),
      ).asBroadcastStream();

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
        '${v.codigoVerificado}|${v.uidTaxista}|${v.completado}|$wp|${v.multiparadaLegCompletadas}|${v.multiparadaCompleta}';
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
    return '$est|${r6(v.latCliente)}|${r6(v.lonCliente)}|${r6(v.latDestino)}|${r6(v.lonDestino)}|'
        '${v.codigoVerificado}|${v.multiparadaLegCompletadas}|${v.multiparadaCompleta}';
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
    for (final k in ['lat', 'latitude', 'latitud']) {
      final x = w[k];
      if (x is num && x.isFinite) return x.toDouble();
      final d = double.tryParse('$x');
      if (d != null && d.isFinite) return d;
    }
    return null;
  }

  double? _waypointLon(Map<String, dynamic> w) {
    for (final k in ['lon', 'lng', 'longitude', 'longitud']) {
      final x = w[k];
      if (x is num && x.isFinite) return x.toDouble();
      final d = double.tryParse('$x');
      if (d != null && d.isFinite) return d;
    }
    return null;
  }

  bool _esMultiparada(Viaje v) {
    final List<Map<String, dynamic>>? wps = v.waypoints;
    if (wps != null && wps.isNotEmpty) return true;
    final dynamic rp = v.extras?['rutaPuntos'];
    if (rp is! List) return false;
    for (final dynamic item in rp) {
      if (item is! Map) continue;
      final String rol = (item['rol'] ?? '').toString().toLowerCase();
      if (rol == 'parada') return true;
    }
    return false;
  }

  List<({double lat, double lon, String label})> _paradasIntermediasDesdeViaje(
    Viaje v,
  ) {
    final List<({double lat, double lon, String label})> out =
        <({double lat, double lon, String label})>[];
    final List<Map<String, dynamic>>? raw = v.waypoints;
    if (raw != null) {
      for (final Map<String, dynamic> m in raw) {
        final double? lat = _waypointLat(m);
        final double? lon = _waypointLon(m);
        if (lat == null || lon == null || !_coordsValid(lat, lon)) continue;
        final String label = (m['label'] ?? '').toString().trim();
        out.add((
          lat: lat,
          lon: lon,
          label: label.isEmpty ? 'Parada ${out.length + 1}' : label,
        ));
      }
    }
    if (out.isNotEmpty) return out;

    final dynamic rp = v.extras?['rutaPuntos'];
    if (rp is List) {
      for (final dynamic item in rp) {
        if (item is! Map) continue;
        final String rol = (item['rol'] ?? '').toString().toLowerCase();
        if (rol == 'origen' || rol == 'destino') continue;
        final double? lat = _waypointLat(Map<String, dynamic>.from(item));
        final double? lon = _waypointLon(Map<String, dynamic>.from(item));
        if (lat == null || lon == null || !_coordsValid(lat, lon)) continue;
        final String label = (item['label'] ?? 'Parada').toString().trim();
        out.add((
          lat: lat,
          lon: lon,
          label: label.isEmpty ? 'Parada ${out.length + 1}' : label,
        ));
      }
    }
    return out;
  }

  List<({double lat, double lon, String label, bool esFinal})>
      _destinosOrdenadosMultiparada(Viaje v) {
    final List<({double lat, double lon, String label, bool esFinal})> out =
        <({double lat, double lon, String label, bool esFinal})>[];
    for (final ({double lat, double lon, String label}) p
        in _paradasIntermediasDesdeViaje(v)) {
      out.add((lat: p.lat, lon: p.lon, label: p.label, esFinal: false));
    }
    if (_coordsValid(v.latDestino, v.lonDestino)) {
      final String dest = v.destino.trim();
      out.add((
        lat: v.latDestino,
        lon: v.lonDestino,
        label: dest.isNotEmpty ? dest : 'Destino final',
        esFinal: true,
      ));
    } else {
      final dynamic rp = v.extras?['rutaPuntos'];
      if (rp is List) {
        for (final dynamic item in rp.reversed) {
          if (item is! Map) continue;
          final Map<String, dynamic> m = Map<String, dynamic>.from(item);
          final String rol = (m['rol'] ?? '').toString().toLowerCase();
          if (rol != 'destino' && rol != 'destino_final') continue;
          final double? lat = _waypointLat(m);
          final double? lon = _waypointLon(m);
          if (lat == null || lon == null || !_coordsValid(lat, lon)) continue;
          final String label = (m['label'] ?? v.destino).toString().trim();
          out.add((
            lat: lat,
            lon: lon,
            label: label.isNotEmpty ? label : 'Destino final',
            esFinal: true,
          ));
          break;
        }
      }
    }
    return out;
  }

  ({double lat, double lon, String label, bool esFinal})? _destinoMultiActual(
      Viaje v) {
    final List<({double lat, double lon, String label, bool esFinal})> legs =
        _destinosOrdenadosMultiparada(v);
    if (_multiLegCompletadas >= legs.length) return null;
    return legs[_multiLegCompletadas];
  }

  bool _multiparadaRutaCompleta(Viaje v) {
    if (!_esMultiparada(v)) return true;
    if (v.multiparadaCompleta) return true;
    final int total = _destinosOrdenadosMultiparada(v).length;
    if (total <= 0) return true;
    return v.multiparadaLegCompletadas >= total ||
        _multiLegCompletadas >= total;
  }

  void _aplicarProgresoMultiparadaDesdeViaje(Viaje v) {
    if (!_esMultiparada(v)) {
      if (_multiLegCompletadas != 0 || _multiNavViajeId != null) {
        _multiLegCompletadas = 0;
        _multiNavViajeId = null;
      }
      return;
    }
    final int total = _destinosOrdenadosMultiparada(v).length;
    final int fromServer = v.multiparadaLegCompletadas.clamp(0, total);
    if (_multiNavViajeId != v.id || _multiLegCompletadas != fromServer) {
      _multiLegCompletadas = fromServer;
      _multiNavViajeId = v.id;
    }
  }

  bool _puedeFinalizarViajeMultiparada(Viaje v) =>
      !_esMultiparada(v) || _multiparadaRutaCompleta(v);

  ({double lat, double lon})? _coordsLegMultiActual(Viaje v) {
    final leg = _destinoMultiActual(v);
    if (leg != null) return (lat: leg.lat, lon: leg.lon);
    return _coordsDestinoParaFinalizar(v);
  }

  Future<Viaje> _asegurarEnCursoParaMultiparada(Viaje v) async {
    final String st = EstadosViaje.normalizar(v.estado);
    if (st == EstadosViaje.enCurso) return v;
    if (st != EstadosViaje.aBordo || !v.codigoVerificado) {
      throw Exception(
        'Iniciá la ruta al destino antes de confirmar paradas.',
      );
    }
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('Sesión inválida');
    }
    await ViajesRepo.iniciarViaje(viajeId: v.id, uidTaxista: uid);
    final DocumentSnapshot<Map<String, dynamic>> snap =
        await FirebaseFirestore.instance.collection('viajes').doc(v.id).get();
    if (!snap.exists) throw Exception('Viaje no encontrado');
    return Viaje.fromMap(v.id, snap.data() ?? <String, dynamic>{});
  }

  Future<void> _abrirMapsLegMultiparada(
    double lat,
    double lon,
    String label,
  ) async {
    await NavegacionExternaLauncher.abrirGoogleMapsDestino(lat, lon);
    _tripFlowSnack(
      'Navegación al pin: $label',
      backgroundColor: Colors.lightBlueAccent,
    );
  }

  Future<void> _navegarDestinoMultiparadaActual(Viaje v) async {
    final leg = _destinoMultiActual(v);
    if (leg == null) return;
    final int total = _destinosOrdenadosMultiparada(v).length;
    final int paso = _multiLegCompletadas + 1;
    final String tipo = leg.esFinal ? 'destino final' : 'parada $paso';
    await _selectorNavegacionDestino(
      leg.lat,
      leg.lon,
      titulo: leg.esFinal ? 'Navegar al destino final' : 'Navegar a la parada',
      addressLine: '${leg.label}\n($paso de $total · $tipo)',
      footerHint:
          'Waze o Maps abren este punto exacto (lat/lon). Al salir, confirma «Llegué — siguiente destino».',
    );
  }

  Future<void> _confirmarLlegadaDestinoMulti(Viaje v) async {
    if (_actionBusy) return;
    final int total = _destinosOrdenadosMultiparada(v).length;
    if (_multiLegCompletadas >= total || v.multiparadaCompleta) return;
    _actionBusy = true;
    try {
      Viaje operativo = await _asegurarEnCursoParaMultiparada(v);
      if (!mounted) return;
      if (mounted) {
        setState(() {
          _aplicarProgresoMultiparadaDesdeViaje(operativo);
          _cachedViaje = operativo;
        });
      }
      final int totalOperativo =
          _destinosOrdenadosMultiparada(operativo).length;
      if (_multiLegCompletadas >= totalOperativo ||
          operativo.multiparadaCompleta) {
        return;
      }
      final (double, double)? ping = _taxistaPosCola.value;
      await ViajesRepo.registrarLegMultiparadaCompletada(
        viajeId: operativo.id,
        latConfirmacion: ping?.$1,
        lonConfirmacion: ping?.$2,
      );
      if (!mounted) return;
      final snap = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(operativo.id)
          .get();
      if (!mounted) return;
      final data = snap.data();
      if (data != null) {
        final Viaje actualizado = Viaje.fromMap(operativo.id, data);
        setState(() {
          _aplicarProgresoMultiparadaDesdeViaje(actualizado);
          _cachedViaje = actualizado;
        });
        _sincronizarReferenciaOrdenCola(actualizado);
        _recalcDistanciaDestino();
        _scheduleDrawRoute();
        final int next = _multiLegCompletadas;
        if (next >= total) {
          _tripFlowSnack(
            'Ruta multiparada completada. Podés finalizar el viaje.',
            backgroundColor: Colors.greenAccent,
          );
        } else {
          final leg = _destinoMultiActual(actualizado);
          if (leg == null) {
            _tripFlowSnack(
              'Parada registrada.',
              backgroundColor: Colors.lightBlueAccent,
            );
          } else {
            _tripFlowSnack(
              'Siguiente destino: ${leg.label}',
              backgroundColor: Colors.lightBlueAccent,
            );
            if (mounted) {
              await _abrirMapsLegMultiparada(leg.lat, leg.lon, leg.label);
            }
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      _tripFlowSnack(
        e.toString().replaceFirst('Exception: ', ''),
        backgroundColor: Colors.redAccent,
      );
    } finally {
      if (mounted) _actionBusy = false;
    }
  }

  Future<void> _abrirGoogleMapsRutaMultiRestante(Viaje v) async {
    final List<({double lat, double lon, String label, bool esFinal})> legs =
        _destinosOrdenadosMultiparada(v);
    if (legs.isEmpty) return;
    final int from = _multiLegCompletadas.clamp(0, legs.length);
    if (from >= legs.length) return;

    double oLat = v.latCliente;
    double oLon = v.lonCliente;
    if (!_coordsValid(oLat, oLon)) {
      final ping = _taxistaPosCola.value;
      if (ping != null) {
        oLat = ping.$1;
        oLon = ping.$2;
      } else if (_coordsValid(v.latTaxista, v.lonTaxista)) {
        oLat = v.latTaxista;
        oLon = v.lonTaxista;
      }
    }
    if (!_coordsValid(oLat, oLon)) {
      _tripFlowSnack('Sin ubicación de origen para la ruta.');
      return;
    }

    final List<({double lat, double lon, String label, bool esFinal})> remaining =
        legs.sublist(from.clamp(0, legs.length));
    if (remaining.isEmpty) return;
    final double dLat = remaining.last.lat;
    final double dLon = remaining.last.lon;
    final List<({double lat, double lon})> paradas =
        <({double lat, double lon})>[];
    if (remaining.length > 1) {
      for (var i = 0; i < remaining.length - 1; i++) {
        paradas.add((lat: remaining[i].lat, lon: remaining[i].lon));
      }
    }

    await showNavegacionWazeMapsSheet(
      context,
      title: 'Ruta con paradas restantes',
      addressLine:
          'Google Maps: ${paradas.length} parada(s) + destino final.',
      tieneCoords: true,
      footerHint:
          'Waze solo admite un destino; usa los botones «Navegar» parada a parada.',
      onWaze: () => unawaited(
        NavegacionExternaLauncher.abrirWazeDestino(dLat, dLon),
      ),
      onMaps: () => unawaited(
        NavegacionExternaLauncher.abrirGoogleMapsRutaConParadas(
          origenLat: oLat,
          origenLon: oLon,
          destinoLat: dLat,
          destinoLon: dLon,
          paradas: paradas,
        ),
      ),
    );
  }

  List<Widget> _bloqueNavegacionMultiparada(Viaje v) {
    final List<({double lat, double lon, String label, bool esFinal})> legs =
        _destinosOrdenadosMultiparada(v);
    if (legs.isEmpty) return const <Widget>[];

    final int total = legs.length;
    final int hechos = _multiLegCompletadas.clamp(0, total);
    final bool completa = hechos >= total;
    final leg = _destinoMultiActual(v);

    return <Widget>[
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              completa
                  ? 'Multiparada: todos los destinos visitados ($total/$total)'
                  : 'Multiparada: destino ${hechos + 1} de $total',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < legs.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      i < hechos
                          ? Icons.check_circle
                          : (i == hechos && !completa
                              ? Icons.radio_button_checked
                              : Icons.circle_outlined),
                      size: 18,
                      color: i < hechos
                          ? Colors.greenAccent
                          : (i == hechos && !completa
                              ? Colors.orangeAccent
                              : Colors.white38),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${i + 1}. ${legs[i].label}${legs[i].esFinal ? ' (final)' : ''}',
                        style: TextStyle(
                          color: i == hechos && !completa
                              ? Colors.white
                              : Colors.white70,
                          fontSize: 13,
                          fontWeight: i == hechos && !completa
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (!completa && leg != null) ...<Widget>[
        _btnPrimario(
          icon: const Icon(Icons.navigation, size: 24),
          label: Text(
            leg.esFinal
                ? 'NAVEGAR AL DESTINO FINAL'
                : 'NAVEGAR A PARADA ${hechos + 1}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          onPressed: (_actionBusy || _selectorNavegacionAbierto)
              ? null
              : () async {
                  if (_actionBusy || _selectorNavegacionAbierto) return;
                  _actionBusy = true;
                  try {
                    await _navegarDestinoMultiparadaActual(v);
                  } finally {
                    if (mounted) _actionBusy = false;
                  }
                },
        ),
        const SizedBox(height: 10),
        Text(
          leg.label,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        _btnPrimario(
          icon: const Icon(Icons.check_circle_outline, size: 24),
          label: Text(
            leg.esFinal
                ? 'LLEGUÉ EN PARADA ${hechos + 1} DE $total · FINAL'
                : 'LLEGUÉ EN PARADA ${hechos + 1} DE $total',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.deepOrange,
          onPressed: _actionBusy
              ? null
              : () => unawaited(_confirmarLlegadaDestinoMulti(v)),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () => unawaited(_abrirGoogleMapsRutaMultiRestante(v)),
          icon: const Icon(Icons.alt_route, size: 24),
          label: const Text(
            'VER RUTA COMPLETA RESTANTE (GOOGLE MAPS)',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1565C0),
            foregroundColor: Colors.white,
            elevation: 3,
            minimumSize: const Size(double.infinity, 54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Muestra todas las paradas encadenadas en un solo mapa.',
          style: TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ],
    ];
  }

  /// Punto de cierre del viaje: destino final del documento (no la última parada intermedia).
  ({double lat, double lon})? _coordsDestinoParaFinalizar(Viaje v) {
    if (_coordsValid(v.latDestino, v.lonDestino)) {
      return (lat: v.latDestino, lon: v.lonDestino);
    }
    final wps = v.waypoints;
    if (wps != null && wps.isNotEmpty) {
      for (var i = wps.length - 1; i >= 0; i--) {
        final lat = _waypointLat(wps[i]);
        final lon = _waypointLon(wps[i]);
        if (lat != null && lon != null && _coordsValid(lat, lon)) {
          return (lat: lat, lon: lon);
        }
      }
    }
    return null;
  }

  /// Punto desde el que ordenar candidatos de cola: destino/parada actual si va con cliente; si no, GPS.
  void _sincronizarReferenciaOrdenCola(Viaje? v) {
    ColaCercaniaReferencia? next;
    if (v != null) {
      final String estadoBase = EstadosViaje.normalizar(
        v.estado.isNotEmpty
            ? v.estado
            : (v.completado
                ? EstadosViaje.completado
                : (v.aceptado ? EstadosViaje.aceptado : EstadosViaje.pendiente)),
      );
      final bool rutaAlDestino = EstadosViaje.esEnCurso(estadoBase) ||
          (EstadosViaje.esAbordo(estadoBase) && v.codigoVerificado);
      if (rutaAlDestino) {
        final ({double lat, double lon})? dest =
            _esMultiparada(v) && !_multiparadaRutaCompleta(v)
                ? _coordsLegMultiActual(v)
                : _coordsDestinoParaFinalizar(v);
        if (dest != null) {
          next = ColaCercaniaReferencia(
            lat: dest.lat,
            lon: dest.lon,
            porDestinoViajeActivo: true,
          );
        }
      }
    }
    if (next == null) {
      final (double, double)? ping = _taxistaPosCola.value;
      if (ping != null && _coordsValid(ping.$1, ping.$2)) {
        next = ColaCercaniaReferencia(
          lat: ping.$1,
          lon: ping.$2,
          porDestinoViajeActivo: false,
        );
      } else if (v != null && _coordsValid(v.latTaxista, v.lonTaxista)) {
        next = ColaCercaniaReferencia(
          lat: v.latTaxista,
          lon: v.lonTaxista,
          porDestinoViajeActivo: false,
        );
      }
    }
    final ColaCercaniaReferencia? prev = _colaReferenciaOrden.value;
    if (prev != null &&
        next != null &&
        prev.lat == next.lat &&
        prev.lon == next.lon &&
        prev.porDestinoViajeActivo == next.porDestinoViajeActivo) {
      return;
    }
    if (prev == null && next == null) return;
    _colaReferenciaOrden.value = next;
  }

  ({double lat, double lon})? _origenRutaEnCursoTaxista(Viaje v) {
    final (double, double)? ping = _taxistaPosCola.value;
    if (ping != null && _coordsValid(ping.$1, ping.$2)) {
      return (lat: ping.$1, lon: ping.$2);
    }
    if (_coordsValid(v.latTaxista, v.lonTaxista)) {
      return (lat: v.latTaxista, lon: v.lonTaxista);
    }
    if (_cachedViaje != null &&
        _coordsValid(_cachedViaje!.latTaxista, _cachedViaje!.lonTaxista)) {
      return (
        lat: _cachedViaje!.latTaxista,
        lon: _cachedViaje!.lonTaxista,
      );
    }
    if (_coordsValid(v.latCliente, v.lonCliente)) {
      return (lat: v.latCliente, lon: v.lonCliente);
    }
    return null;
  }

  /// Mejor distancia al pin de destino: primero el ping **en vivo** del stream (navegación en curso),
  /// luego lecturas puntuales y la posición guardada en el viaje.
  Future<double?> _menorDistanciaMetrosAlDestinoParaFinalizar(
    Viaje v,
    ({double lat, double lon}) destino, {
    (double, double)? pingStreamLatLon,
  }) async {
    final List<({double lat, double lon})> pts = [];

    if (pingStreamLatLon != null) {
      final double a = pingStreamLatLon.$1;
      final double b = pingStreamLatLon.$2;
      if (_coordsValid(a, b)) pts.add((lat: a, lon: b));
    }

    try {
      final Position? last = await Geolocator.getLastKnownPosition();
      if (last != null && _coordsValid(last.latitude, last.longitude)) {
        pts.add((lat: last.latitude, lon: last.longitude));
      }
    } catch (e) {
      uxLog('GPS_FINALIZAR', 'getLastKnownPosition', e);
    }

    for (final LocationAccuracy acc in [
      LocationAccuracy.high,
      LocationAccuracy.medium,
      LocationAccuracy.low,
    ]) {
      try {
        final Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: acc,
        );
        if (_coordsValid(pos.latitude, pos.longitude)) {
          pts.add((lat: pos.latitude, lon: pos.longitude));
        }
      } catch (e) {
        uxLog('GPS_FINALIZAR', 'getCurrentPosition acc=$acc', e);
      }
    }

    if (_coordsValid(v.latTaxista, v.lonTaxista)) {
      pts.add((lat: v.latTaxista, lon: v.lonTaxista));
    }
    if (_cachedViaje != null &&
        _coordsValid(_cachedViaje!.latTaxista, _cachedViaje!.lonTaxista)) {
      pts.add((lat: _cachedViaje!.latTaxista, lon: _cachedViaje!.lonTaxista));
    }

    if (pts.isEmpty) return null;

    double minM = double.infinity;
    for (final ({double lat, double lon}) p in pts) {
      final double d = Geolocator.distanceBetween(
        p.lat,
        p.lon,
        destino.lat,
        destino.lon,
      );
      if (d < minM) minM = d;
    }
    return minM;
  }

  /// Actualiza [_distanciaMetrosAlDestino] desde la posición en vivo (cola GPS).
  void _recalcDistanciaDestino() {
    final v = _cachedViaje;
    if (v == null || !mounted) return;
    final estadoBase = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado ? EstadosViaje.aceptado : EstadosViaje.pendiente)),
    );
    // Misma lógica que la ruta verde al destino: empieza a medir en cuanto el PIN
    // quedó verificado, aunque Firestore tarde un instante en pasar a `en_curso`.
    final bool rutaAlDestino = EstadosViaje.esEnCurso(estadoBase) ||
        (EstadosViaje.esAbordo(estadoBase) && v.codigoVerificado);
    if (!rutaAlDestino) {
      if (_distanciaMetrosAlDestino != null) {
        setState(() => _distanciaMetrosAlDestino = null);
      }
      return;
    }
    final dest = _esMultiparada(v) && !_multiparadaRutaCompleta(v)
        ? _coordsLegMultiActual(v)
        : _coordsDestinoParaFinalizar(v);
    if (dest == null) {
      if (_distanciaMetrosAlDestino != null) {
        setState(() => _distanciaMetrosAlDestino = null);
      }
      return;
    }
    // Ping en vivo del stream; si aún no hay fix, usar posición del doc (Firestore).
    (double, double)? ping = _taxistaPosCola.value;
    if (ping == null && _coordsValid(v.latTaxista, v.lonTaxista)) {
      ping = (v.latTaxista, v.lonTaxista);
    }
    if (ping == null &&
        _cachedViaje != null &&
        _coordsValid(_cachedViaje!.latTaxista, _cachedViaje!.lonTaxista)) {
      ping = (_cachedViaje!.latTaxista, _cachedViaje!.lonTaxista);
    }
    if (ping == null) {
      if (_distanciaMetrosAlDestino != null) {
        setState(() => _distanciaMetrosAlDestino = null);
      }
      return;
    }
    final d = Geolocator.distanceBetween(
      ping.$1,
      ping.$2,
      dest.lat,
      dest.lon,
    );
    final prev = _distanciaMetrosAlDestino;
    if (prev == null || (d - prev).abs() > 3) {
      setState(() => _distanciaMetrosAlDestino = d);
    }
  }

  Future<void> _refrescarViajeDocDesdeFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      print('[VIAJE_ACTIVO] resume refresh skip (sin uid)');
      return;
    }
    String? vid = _cachedViaje?.id;
    if (vid == null || vid.isEmpty) {
      try {
        final us = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(uid)
            .get();
        vid = (us.data()?['viajeActivoId'] ?? '').toString().trim();
      } catch (_) {}
    }
    if (vid == null || vid.isEmpty) {
      print('[VIAJE_ACTIVO] resume refresh skip (sin viajeId)');
      return;
    }
    print('[VIAJE_ACTIVO] resume refresh GET viajes/$vid');
    try {
      final snap =
          await FirebaseFirestore.instance.collection('viajes').doc(vid).get();
      if (!snap.exists || !mounted) return;
      final fresh = Viaje.fromMap(snap.id, snap.data()!);
      setState(() {
        _cachedViaje = fresh.copyWith(
          latTaxista: _cachedViaje?.latTaxista ?? fresh.latTaxista,
          lonTaxista: _cachedViaje?.lonTaxista ?? fresh.lonTaxista,
        );
      });
      _recalcDistanciaDestino();
      print(
          '[VIAJE_ACTIVO] resume refresh OK estado=${fresh.estado} completado=${fresh.completado}');
    } catch (e, st) {
      print('[VIAJE_ACTIVO] resume refresh error $e $st');
    }
  }

  static String _textoDistanciaAlPin(double metros) {
    if (metros < 1000) {
      return '${metros.round()} m';
    }
    return '${(metros / 1000).toStringAsFixed(1)} km';
  }

  /// Diálogo según proximidad: en zona → cierre para factura/pago; fuera/sin GPS → confirmación explícita.
  Future<bool?> _dialogoConfirmarFinalizarViaje(
    BuildContext context, {
    required bool hayPinDestino,
    double? distanciaMetrosMin,
  }) {
    late final String body;

    if (!hayPinDestino) {
      body =
          'No hay coordenadas de destino en este viaje. ¿Confirmás que ya terminó el servicio para emitir la factura al cliente?';
    } else if (distanciaMetrosMin == null) {
      body =
          'No pudimos contrastar tu ubicación con el mapa (GPS). Si ya están en el punto de bajada y el cliente va a pagar o hacer una transferencia, podés finalizar para que vea el monto en la factura.';
    } else if (distanciaMetrosMin <= kFinalizarRadioMetros) {
      body =
          'Tu posición está cerca del destino del viaje (cliente a bordo y en ruta). '
          'Al finalizar, el cliente verá la factura con el monto y podrá pagar o transferir. ¿Finalizamos?';
    } else {
      final String dTxt = _textoDistanciaAlPin(distanciaMetrosMin);
      body =
          'Tu posición aparece a unos $dTxt del punto de destino guardado en el viaje (referencia de GPS, no es una ruta que “te falte” recorrer). '
          'Si ya estás en el lugar de bajada y el pasajero va a pagar o transferir, podés finalizar igual para que salga la factura.';
    }

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text(
          'Finalizar viaje',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          body,
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ahora no', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, finalizar'),
          ),
        ],
      ),
    );
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
  void _programarRecuperacionGpsStream(String viajeId, Object error) {
    logDbg('GPS stream error → recuperación programada: $error');
    unawaited(_gpsSub?.cancel());
    _gpsSub = null;
    _gpsActivo = false;

    if (!mounted) return;
    final Viaje? v = _cachedViaje;
    if (v == null || v.id != viajeId) return;

    final String est = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado ? EstadosViaje.aceptado : EstadosViaje.pendiente)),
    );
    final bool enRuta = EstadosViaje.esEnCurso(est) ||
        (EstadosViaje.esAbordo(est) && v.codigoVerificado);
    if (!enRuta) {
      _gpsStreamRecoveryIntentos = 0;
      return;
    }

    _gpsStreamRecoveryIntentos++;
    if (_gpsStreamRecoveryIntentos > _kMaxGpsStreamRecoveryIntentos) {
      logDbg(
          '🛑 GPS stream: máximo $_kMaxGpsStreamRecoveryIntentos reintentos alcanzado',
      );
      return;
    }

    _gpsStreamRecoveryTimer?.cancel();
    _gpsStreamRecoveryTimer = Timer(_kGpsStreamRecoveryDelay, () {
      _gpsStreamRecoveryTimer = null;
      if (!mounted) return;
      unawaited(() async {
        final bool ok = await _asegurarGps(viajeId);
        if (ok && mounted) {
          _gpsStreamRecoveryIntentos = 0;
        }
      }());
    });
  }

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
    ).listen(
      (p) async {
        try {
          _gpsStreamRecoveryTimer?.cancel();
          _gpsStreamRecoveryTimer = null;
          _gpsStreamRecoveryIntentos = 0;

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
          _sincronizarReferenciaOrdenCola(_cachedViaje);

          if (mounted && _cachedViaje != null && _cachedViaje!.id == viajeId) {
            _cachedViaje = _cachedViaje!
                .copyWith(latTaxista: p.latitude, lonTaxista: p.longitude);
          }
          _recalcDistanciaDestino();

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
      },
      onError: (Object e) => _programarRecuperacionGpsStream(viajeId, e),
      cancelOnError: false,
    );
  }

  void _stopGps() {
    _gpsStreamRecoveryTimer?.cancel();
    _gpsStreamRecoveryTimer = null;
    _gpsStreamRecoveryIntentos = 0;
    _gpsSub?.cancel();
    _gpsSub = null;
    _gpsActivo = false;
    _gpsParaViajeId = null;
    logDbg('🛑 GPS detenido');
  }

  Future<bool> _asegurarGps(
    String viajeId, {
    bool allowPermissionDialog = true,
  }) async {
    logDbg(
      '_asegurarGps($viajeId) allowPermissionDialog=$allowPermissionDialog '
      '_gpsActivo: $_gpsActivo',
    );

    if (_gpsActivo && _gpsParaViajeId == viajeId) {
      logDbg('✅ GPS ya activo');
      return true;
    }

    final ({bool serviceEnabled, LocationPermission permission}) snap =
        // Explícito: solo cuando el taxista inicia GPS del viaje con diálogo permitido.
        // resumed / reanudación usa allowPermissionDialog:false → readNoRequest.
        allowPermissionDialog
            ? await GpsService.checkServiceThenRequestPermissionIfNeeded()
            : await GpsService.readServiceAndPermissionStabilizedNoRequest();
    if (!snap.serviceEnabled) {
      if (!mounted) return false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Activa la ubicación del teléfono (GPS).'),
              action: SnackBarAction(
                label: 'Ubicación',
                onPressed: () => unawaited(GpsService.openLocationSettings()),
              ),
            ),
          );
        }
      });
      logDbg('❌ GPS apagado');
      return false;
    }

    final LocationPermission perm = snap.permission;
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
    if (rutaAlDestino) {
      if (_esMultiparada(v) && !_multiparadaRutaCompleta(v)) {
        final leg = _destinoMultiActual(v);
        final origen = _origenRutaEnCursoTaxista(v);
        if (leg != null &&
            origen != null &&
            _coordsValid(leg.lat, leg.lon)) {
          await _drawRoute(
            LatLng(origen.lat, origen.lon),
            LatLng(leg.lat, leg.lon),
            id: 'to_leg_actual',
            color: const Color(0xFF49F18B),
          );
        }
      } else if (_coordsValid(v.latCliente, v.lonCliente) &&
          _coordsValid(v.latDestino, v.lonDestino)) {
        List<({double lat, double lon})>? vias;
        if (_esMultiparada(v)) {
          vias = <({double lat, double lon})>[];
          for (final leg in _destinosOrdenadosMultiparada(v)) {
            if (!leg.esFinal) {
              vias.add((lat: leg.lat, lon: leg.lon));
            }
          }
          if (vias.isEmpty) vias = null;
        }
        final origen = _origenRutaEnCursoTaxista(v) ??
            (lat: v.latCliente, lon: v.lonCliente);
        await _drawRoute(
          LatLng(origen.lat, origen.lon),
          LatLng(v.latDestino, v.lonDestino),
          id: 'to_destino',
          color: const Color(0xFF49F18B),
          viaIntermediate: vias,
        );
      }
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
    List<({double lat, double lon})>? viaIntermediate,
  }) async {
    try {
      final result = await DirectionsService.drivingDistanceKm(
        originLat: a.latitude,
        originLon: a.longitude,
        destLat: b.latitude,
        destLon: b.longitude,
        waypoints: (viaIntermediate != null && viaIntermediate.isNotEmpty)
            ? viaIntermediate
            : null,
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

  static String _prefKeyNavPickup(String viajeId) => 'vctx_nav_pickup_$viajeId';

  static String _prefKeyNavDestino(String viajeId) => 'vctx_nav_destino_$viajeId';

  Future<void> _persistNavPickupFlag(String viajeId, bool value) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (value) {
        await p.setBool(_prefKeyNavPickup(viajeId), true);
      } else {
        await p.remove(_prefKeyNavPickup(viajeId));
      }
    } catch (e, st) {
      await ErrorReporting.reportError(
        e,
        stack: st,
        context: 'viaje_en_curso_taxista: persist nav pickup',
      );
    }
  }

  Future<void> _persistNavDestinoFlag(String viajeId, bool value) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (value) {
        await p.setBool(_prefKeyNavDestino(viajeId), true);
      } else {
        await p.remove(_prefKeyNavDestino(viajeId));
      }
    } catch (e, st) {
      await ErrorReporting.reportError(
        e,
        stack: st,
        context: 'viaje_en_curso_taxista: persist nav destino',
      );
    }
  }

  Future<void> _loadNavDestinoPrefs(Viaje v, {bool force = false}) async {
    final estadoBase = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado
                  ? EstadosViaje.aceptado
                  : EstadosViaje.pendiente)),
    );
    if (!EstadosViaje.esEnCurso(estadoBase)) {
      _navDestinoPrefsLoadedForId = null;
      if (mounted && _navegacionDestinoIniciada) {
        setState(() => _navegacionDestinoIniciada = false);
      }
      try {
        final p = await SharedPreferences.getInstance();
        if (p.containsKey(_prefKeyNavDestino(v.id))) {
          await p.remove(_prefKeyNavDestino(v.id));
        }
      } catch (_) {}
      return;
    }
    if (!force && _navDestinoPrefsLoadedForId == v.id) return;

    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getBool(_prefKeyNavDestino(v.id)) ?? false;
      _navDestinoPrefsLoadedForId = v.id;
      if (mounted && saved && !_navegacionDestinoIniciada) {
        setState(() => _navegacionDestinoIniciada = true);
      }
    } catch (e, st) {
      await ErrorReporting.reportError(
        e,
        stack: st,
        context: 'viaje_en_curso_taxista: load nav destino prefs',
      );
    }
  }

  void _marcarNavegacionDestinoLista(Viaje v) {
    unawaited(_persistNavDestinoFlag(v.id, true));
    if (mounted) setState(() => _navegacionDestinoIniciada = true);
  }

  /// Tras volver de Waze/Maps o del sistema: restauramos «navegación iniciada» para no bloquear «Cliente a bordo».
  Future<void> _loadNavPickupPrefs(Viaje v, {bool force = false}) async {
    final estadoBase = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado
                  ? EstadosViaje.aceptado
                  : EstadosViaje.pendiente)),
    );
    if (!EstadosViaje.esAceptado(estadoBase)) {
      _navPickupPrefsLoadedForId = null;
      try {
        final p = await SharedPreferences.getInstance();
        if (p.containsKey(_prefKeyNavPickup(v.id))) {
          await p.remove(_prefKeyNavPickup(v.id));
        }
      } catch (e, st) {
        await ErrorReporting.reportError(
          e,
          stack: st,
          context: 'viaje_en_curso_taxista: clear stale nav pickup pref',
        );
      }
      return;
    }
    if (!force && _navPickupPrefsLoadedForId == v.id) return;

    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getBool(_prefKeyNavPickup(v.id)) ?? false;
      _navPickupPrefsLoadedForId = v.id;
      if (mounted && saved) {
        setState(() => _navegacionIniciada = true);
      }
    } catch (e, st) {
      await ErrorReporting.reportError(
        e,
        stack: st,
        context: 'viaje_en_curso_taxista: load nav pickup prefs',
      );
    }
  }

  Future<void> _handleAppResumedTrasNavegacionExterna() async {
    if (!mounted) return;
    final v = _cachedViaje;
    if (v == null) return;
    await _loadNavPickupPrefs(v, force: true);
    await _loadNavDestinoPrefs(v, force: true);
    if (!mounted) return;

    final estadoBase = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado
                  ? EstadosViaje.aceptado
                  : EstadosViaje.pendiente)),
    );
    final bool enPickup = EstadosViaje.esAceptado(estadoBase);
    final bool enRutaDestino = EstadosViaje.esEnCurso(estadoBase);
    if (!enPickup && !enRutaDestino) return;

    final now = DateTime.now();
    if (_lastNavResumeSnackAt != null &&
        now.difference(_lastNavResumeSnackAt!) < const Duration(seconds: 6)) {
      return;
    }

    _lastNavResumeSnackAt = now;
    _expandirViajeSheetTrasMapa();

    if (enPickup) {
      if (!_navegacionIniciada) return;
      _tripFlowSnack(
        _permitePruebaSinRecorrido(v)
            ? 'Volviste a RAI Driver. Siguiente: «Cliente a bordo (paso 2)».'
            : 'Volviste a RAI Driver. Continúa: Cliente a bordo → código → destino.',
        backgroundColor: Colors.blueGrey.shade800,
      );
      return;
    }

    if (!_navegacionDestinoIniciada && _permitePruebaSinRecorrido(v)) {
      _tripFlowSnack(
        'Volviste a RAI Driver. Abrí «Navegar al destino» o tocá «Continuar sin mapa».',
        backgroundColor: Colors.blueGrey.shade800,
      );
      return;
    }

    if (!_navegacionDestinoIniciada) {
      _tripFlowSnack(
        'Volviste a RAI Driver. Abrí «Navegar al destino» y al llegar finalizá el viaje.',
        backgroundColor: Colors.blueGrey.shade800,
      );
      return;
    }

    _tripFlowSnack(
      'Volviste a RAI Driver. Siguiente paso: «Finalizar viaje».',
      backgroundColor: const Color(0xFF2E7D32),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(BolaPuebloRepo.reconciliarSesionBolaAtascada());
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(_verificarViajeTerminadoAlEntrarTaxista()));
  }

  Future<void> _verificarViajeTerminadoAlEntrarTaxista() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !mounted) return;
    print('[VIAJE_ACTIVO] taxista pantalla init: verificar si viaje ya cerró');
    try {
      final us = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();
      final vid = (us.data()?['viajeActivoId'] ?? '').toString().trim();
      if (vid.isEmpty) return;
      final vs =
          await FirebaseFirestore.instance.collection('viajes').doc(vid).get();
      if (!vs.exists || !mounted) return;
      final d = vs.data() ?? <String, dynamic>{};
      final st = EstadosViaje.normalizar((d['estado'] ?? '').toString());
      final done = d['completado'] == true ||
          st == EstadosViaje.completado ||
          st == EstadosViaje.cancelado ||
          st == EstadosViaje.rechazado;
      if (done) {
        print('[VIAJE_ACTIVO] taxista init: viaje terminal → salir de pantalla');
        if (mounted) {
          Navigator.of(context, rootNavigator: true).maybePop();
        }
      }
    } catch (e) {
      print('[VIAJE_ACTIVO] taxista init check error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      print('[VIAJE_ACTIVO] taxista lifecycle resumed');
      // resumed: GPS se reanuda con _asegurarGps(..., allowPermissionDialog:false) → readNoRequest, sin diálogo del SO.
      unawaited(() async {
        await _refrescarViajeDocDesdeFirestore();
        if (!mounted) return;
        await _reanudarGpsSiEnCursoTrasResume();
        if (!mounted) return;
        await _handleAppResumedTrasNavegacionExterna();
      }());
    }
  }

  /// Tras volver de Waze/Maps o del sistema: si el viaje va al destino pero el
  /// stream GPS quedó caído, reintenta [_asegurarGps] una vez (sin bucles).
  Future<void> _reanudarGpsSiEnCursoTrasResume() async {
    final Viaje? v = _cachedViaje;
    if (v == null) return;
    final String estadoBase = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado ? EstadosViaje.aceptado : EstadosViaje.pendiente)),
    );
    if (!EstadosViaje.taxistaReanudaGpsStreamTrasResume(estadoBase,
        codigoVerificado: v.codigoVerificado)) {
      return;
    }
    if (_gpsActivo) return;
    logDbg(
        '[VIAJE_ACTIVO] resume: reintentar GPS (en_curso o a_bordo+PIN) viaje=${v.id} (_gpsActivo=false)',
    );
    await _asegurarGps(v.id, allowPermissionDialog: false);
  }

  void _colapsarViajeSheetPorMapa() {
    if (!_viajeSheetCtrl.isAttached) return;
    _viajeSheetCtrl.animateTo(
      _kViajeSheetMin,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _expandirViajeSheetTrasMapa() {
    if (!_viajeSheetCtrl.isAttached) return;
    _viajeSheetCtrl.animateTo(
      _kViajeSheetInitial,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _viajeSheetDivider([String label = 'Detalles del viaje']) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelSub?.cancel();
    _bolaCancelSub?.cancel();
    _viajeSheetCtrl.dispose();
    _map?.dispose();
    _gpsStreamRecoveryTimer?.cancel();
    _gpsStreamRecoveryTimer = null;
    _stopGps();
    _codigoCtrl.dispose();
    _routeDebounce?.cancel();
    _viajesCercanosEscucha.dispose();
    _viajesCercanosCtl.dispose();
    _taxistaPosCola.dispose();
    _colaReferenciaOrden.dispose();
    super.dispose();
  }

  // ===================== Acciones Principales =====================

  /// Marca `en_camino_pickup` sin bloquear Waze/Maps si Firestore rechaza el write.
  Future<void> _intentarMarcarEnCaminoPickupBestEffort(
    Viaje v,
    String uid,
  ) async {
    try {
      await ViajesRepo.marcarEnCaminoPickup(
        viajeId: v.id,
        uidTaxista: uid,
      );
    } on FirebaseException catch (e, st) {
      await ErrorReporting.reportError(
        e,
        stack: st,
        context: 'viaje_en_curso_taxista: marcarEnCaminoPickup best-effort',
      );
      if (!mounted) return;
      if (e.code == 'permission-denied') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo actualizar el estado en el servidor. '
                'Puedes abrir Waze/Maps igual; si persiste, contacta soporte.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        });
      }
    } catch (e, st) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('estado inválido') ||
          msg.contains('estado invalido') ||
          msg.contains('estado inválido para en_camino_pickup') ||
          msg.contains('estado invalido para en_camino_pickup')) {
        return;
      }
      await ErrorReporting.reportError(
        e,
        stack: st,
        context: 'viaje_en_curso_taxista: marcarEnCaminoPickup best-effort',
      );
    }
  }

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

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (!yaEnCaminoPickup && uid != null) {
        await _intentarMarcarEnCaminoPickupBestEffort(v, uid);
      }

      final gpsOk = await _gpsListoParaAbrirNavegacionExterna(v);
      if (!gpsOk && mounted) {
        unawaited(_persistNavPickupFlag(v.id, false));
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
              unawaited(_persistNavPickupFlag(v.id, false));
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _navegacionIniciada = false);
              });
            },
          );
        } finally {
          if (mounted) {
            setState(() => _viajeSheetOcultoPorModalNav = false);
          }
        }
      }

      if (mounted && eligioAppExterna) {
        unawaited(_persistNavPickupFlag(v.id, true));
        setState(() => _navegacionIniciada = true);
      }

      if (mounted && !eligioAppExterna) {
        unawaited(_persistNavPickupFlag(v.id, false));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _navegacionIniciada = false);
        });
      }

      if (mounted && eligioAppExterna) {
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
      unawaited(_persistNavPickupFlag(v.id, false));
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

      final refViaje = FirebaseFirestore.instance.collection('viajes').doc(v.id);
      final snapAbordo = await refViaje.get();
      final dAbordo = snapAbordo.data() ?? <String, dynamic>{};
      final String codRaw = (dAbordo['codigoVerificacion'] ??
              dAbordo['codigo_verificacion'] ??
              '')
          .toString()
          .replaceAll(RegExp(r'\D'), '');
      final Map<String, dynamic> patchAbordo = {
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
      };
      if (codRaw.length != 6) {
        patchAbordo['codigoVerificacion'] =
            ViajesRepo.codigoVerificacionSeisDigitosDesdeDoc(dAbordo);
        patchAbordo['codigoVerificado'] = false;
      }
      await refViaje.update(patchAbordo);

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
      unawaited(_persistNavPickupFlag(v.id, false));
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
      try {
        await ViajesRepo.iniciarViaje(
          viajeId: viajeId,
          uidTaxista: uid,
          pinVerificacion: ingresado,
        );
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
        if ((data['tipoServicio'] ?? '').toString().trim() == 'bola_ahorro') {
          unawaited(BolaPuebloFirestoreSync.syncBolaEnCursoDesdeViaje(viajeId));
        }
        final viajeActualizado = Viaje.fromMap(viajeId, data);
        _aplicarProgresoMultiparadaDesdeViaje(viajeActualizado);
        if (mounted && _cachedViaje?.id == viajeId) {
          setState(() => _cachedViaje = viajeActualizado);
          _scheduleDrawRoute();
        }

        if (_esMultiparada(viajeActualizado)) {
          _tripFlowSnack(
            'Código correcto. Ruta multiparada: seguí parada a parada.',
            backgroundColor: Colors.green,
          );
          final leg = _destinoMultiActual(viajeActualizado);
          if (leg != null) {
            if (mounted) {
              _tripFlowSnack(
                'Primera parada: ${leg.label}',
                backgroundColor: Colors.blueGrey,
              );
            }
            await _navegarDestinoMultiparadaActual(viajeActualizado);
          } else if (mounted) {
            _tripFlowSnack(
              'Confirmá cada parada con «Llegué — siguiente destino».',
              backgroundColor: Colors.orange,
            );
          }
        } else {
          _tripFlowSnack(
            'Código correcto. Podés abrir «Navegar al destino» o «Finalizar viaje» '
            'cuando corresponda (no hace falta recorrer en prueba).',
            backgroundColor: Colors.green,
          );
          if (mounted) _expandirViajeSheetTrasMapa();
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
      print('[FINALIZAR_VIAJE] _finalizarViaje abort: sin uid');
      _actionBusy = false;
      return;
    }

    print('[FINALIZAR] _finalizarViaje start viajeId=${v.id} uid=$uid');
    final messenger = ScaffoldMessenger.of(context);
    final String estadoLocal = EstadosViaje.normalizar(v.estado);

    if (!_puedeFinalizarViajeMultiparada(v)) {
      final int total = _destinosOrdenadosMultiparada(v).length;
      final int hechos = v.multiparadaLegCompletadas.clamp(0, total);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Viaje multiparada: confirmá las $total paradas/destinos antes de finalizar '
              '($hechos/$total registrados).',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      _actionBusy = false;
      return;
    }

    // Callable acepta `en_curso` o `a_bordo` (PIN verificado sin transición).
    if (!EstadosViaje.taxistaPuedeInvocarFinalizar(estadoLocal)) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('viajes')
            .doc(v.id)
            .get();
        final data = snap.data() ?? const <String, dynamic>{};
        final String estadoRemoto =
            EstadosViaje.normalizar((data['estado'] ?? '').toString());
        if (!EstadosViaje.taxistaPuedeInvocarFinalizar(estadoRemoto)) {
          print(
              '[FINALIZAR_ERROR] estado remoto no finalizable: $estadoRemoto viajeId=${v.id}');
          if (mounted) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Para finalizar, primero tené el cliente a bordo con código verificado '
                  'e iniciá la ruta al destino (o esperá a que la app actualice el estado).',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          _actionBusy = false;
          return;
        }
      } catch (_) {
        print('[FINALIZAR_ERROR] error validando estado remoto viajeId=${v.id}');
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

    if (_permitePruebaSinRecorrido(v)) {
      print(
        '[FLYGO_SIM_CASA] finalizar sin GPS/diálogo/medición viaje=${v.id} '
        'tipo=${v.tipoServicio}',
      );
    } else {
      // Intento de GPS en vivo sin abrir diálogo de permisos (permiso ya concedido).
      await _asegurarGps(v.id, allowPermissionDialog: false);

      // Diálogo informativo; no bloqueamos por distancia.
      final ({double lat, double lon})? pinDestino =
          _coordsDestinoParaFinalizar(v);
      double? distMinM;
      if (pinDestino != null) {
        distMinM = await _menorDistanciaMetrosAlDestinoParaFinalizar(
          v,
          pinDestino,
          pingStreamLatLon: _taxistaPosCola.value,
        );
      }

      if (!mounted) {
        _actionBusy = false;
        return;
      }

      final ok = await _dialogoConfirmarFinalizarViaje(
            context,
            hayPinDestino: pinDestino != null,
            distanciaMetrosMin: distMinM,
          ) ??
          false;

      if (!ok) {
        print('[FINALIZAR_VIAJE] usuario canceló diálogo');
        _actionBusy = false;
        return;
      }
    }

    try {
      // Evita que TaxistaShell quite ViajeEnCurso antes de factura/post-viaje.
      ActiveTripService.mantenerOverlayViajeEnShell(const Duration(minutes: 3));

      print('[FINALIZAR] invocando ViajesRepo.completarViajePorTaxista');
      try {
        try {
          final snapPre = await FirebaseFirestore.instance
              .collection('viajes')
              .doc(v.id)
              .get();
          final dPre = snapPre.data() ?? const <String, dynamic>{};
          final stPre = EstadosViaje.normalizar(
              (dPre['estado'] ?? '').toString());
          final compPre = dPre['completado'] == true;
          print(
            '[FINALIZAR_ERROR] pre-callable viajeId=${v.id} '
            'estadoFirestore=$stPre completado=$compPre '
            'codigoVerificado=${dPre['codigoVerificado'] == true}',
          );
        } catch (e, st) {
          print(
              '[FINALIZAR_ERROR] pre-callable lectura Firestore falló viajeId=${v.id}: $e $st');
        }

        final outcome = await ViajesRepo.completarViajePorTaxista(v.id);
        if (outcome == CompletarViajeTaxistaOutcome.alreadyCompleted &&
            mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Viaje ya finalizado'),
              backgroundColor: Colors.green,
            ),
          );
        }
        if (v.tipoServicio == 'bola_ahorro') {
          if (kDebugMode) {
            print('[BOLA_AHORRO] finalizar callable OK → sync bola viaje=${v.id}');
          }
          unawaited(BolaPuebloFirestoreSync.postCompletarViajeEspejo(v.id));
        }
      } on FirebaseFunctionsException catch (e, st) {
        print(
            '[FINALIZAR_ERROR] FirebaseFunctionsException viajeId=${v.id} '
            '${e.code} ${e.message} $st');
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'No se pudo finalizar el viaje: ${e.message ?? e.code}',
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        ActiveTripService.cancelarMantenimientoOverlayViaje();
        _actionBusy = false;
        return;
      } catch (e, st) {
        print('[FINALIZAR_ERROR] completarViaje viajeId=${v.id} $e $st');
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('No se pudo finalizar el viaje: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        ActiveTripService.cancelarMantenimientoOverlayViaje();
        _actionBusy = false;
        return;
      }

      print('[FINALIZAR] callable OK → post-proceso pago/factura');

      // ────────────────────────────────────────────────────────────────
      // Pagos / facturación:
      // No silenciamos errores. Si falla registrar el pago, el viaje ya
      // está completado, pero mostramos mensaje + reintento.
      // ────────────────────────────────────────────────────────────────
      double total = v.precio;
      double comision = v.precio * PlataformaEconomia.factorComision;
      double ganancia = v.precio - comision;
      String metodo = v.metodoPago.toString().toLowerCase().trim();
      final String uidTxDefault = v.uidTaxista.isNotEmpty ? v.uidTaxista : uid;

      bool retryingPago = false;
      Future<void> retryPago() async {
        final uidTx = uidTxDefault;
        if (uidTx.isEmpty) throw Exception('uidTaxista vacío (pago)');

        if (MetodoPagoViaje.esEfectivo(metodo)) {
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
        double toDoubleLocal(dynamic x) =>
            x is num ? x.toDouble() : (double.tryParse('$x') ?? 0.0);

        total = totalRdDesdeDocViaje(data);
        if (total <= 1e-6) {
          total = v.precio > 0 ? v.precio : v.precioFinal;
        }

        final cc = data['comision_cents'];
        if (cc is num && cc > 0) {
          comision = cc.toDouble() / 100.0;
        } else {
          final comisionCampo =
              toDoubleLocal(data['comision'] ?? data['comisionFlyGo']);
          comision = comisionCampo > 0
              ? comisionCampo
              : (total * PlataformaEconomia.factorComision);
        }

        final gc = data['ganancia_cents'];
        if (gc is num && gc > 0) {
          ganancia = gc.toDouble() / 100.0;
        } else {
          final gananciaCampo = toDoubleLocal(data['gananciaTaxista']);
          ganancia = gananciaCampo > 0 ? gananciaCampo : (total - comision);
        }

        metodo = (data['metodoPago'] ?? v.metodoPago ?? 'Efectivo')
            .toString()
            .toLowerCase()
            .trim();

        if (data['pagoRegistrado'] == true) {
          print('[FINALIZAR] pagoRegistrado=true → omitir PagoData legacy');
        } else if (_pagoYaAsentadoPorServidor(data)) {
          print('[FINALIZAR] comisión ya en servidor → omitir PagoData legacy');
        } else {
          await retryPago();
        }
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

      final Map<String, dynamic>? semillaViaje =
          await FirebaseFirestore.instance
              .collection('viajes')
              .doc(v.id)
              .get()
              .then((DocumentSnapshot<Map<String, dynamic>> s) => s.data());

      print('[FINALIZAR] abriendo factura + post-viaje taxista viajeId=${v.id}');
      await PostViajeTaxistaNav.abrirFacturaYFlujo(
        context: mounted ? context : null,
        viajeId: v.id,
        uidTaxista: uid,
        viajeDataSemilla: semillaViaje,
      );
    } catch (e, st) {
      print('[FINALIZAR] _finalizarViaje catch outer $e $st');
      ActiveTripService.cancelarMantenimientoOverlayViaje();
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
                      if (uidCliente.isNotEmpty &&
                          FirebaseAuth.instance.currentUser?.uid != null) ...[
                        const SizedBox(height: 12),
                        ViajeChatMensajesEnVivo(
                          viajeId: viajeId,
                          miUid: FirebaseAuth.instance.currentUser!.uid,
                          otroUid: uidCliente,
                          otroNombre: nombre.isEmpty ? 'Cliente' : nombre,
                        ),
                      ],
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
                          unawaited(
                            ViajeComunicacionRepo.notificarIntentoComunicacion(
                              viajeId: viajeId,
                              tipo: 'llamada',
                            ),
                          );
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
                          unawaited(
                            ViajeComunicacionRepo.notificarIntentoComunicacion(
                              viajeId: viajeId,
                              tipo: 'whatsapp',
                            ),
                          );
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

  Future<bool> _selectorNavegacionDestino(
    double lat,
    double lon, {
    String titulo = 'Abrir navegación',
    String? addressLine,
    String? footerHint,
    Viaje? viajeParaPersistirDestino,
  }) async {
    if (!mounted) return false;
    if (_selectorNavegacionAbierto) return false;
    _selectorNavegacionAbierto = true;
    var eligioAppExterna = false;
    try {
      if (mounted) setState(() => _viajeSheetOcultoPorModalNav = true);
      try {
        await showNavegacionWazeMapsSheet(
          context,
          title: titulo,
          addressLine: addressLine,
          tieneCoords: true,
          gpsCoordinatesLine:
              'GPS: ${NavegacionExternaLauncher.fmtCoord(lat)}, ${NavegacionExternaLauncher.fmtCoord(lon)}',
          footerHint: footerHint ??
              'Elige Waze o Google Maps. Las coordenadas son el pin exacto del viaje.',
          onWaze: () {
            eligioAppExterna = true;
            unawaited(NavegacionExternaLauncher.abrirWazeDestino(lat, lon));
          },
          onMaps: () {
            eligioAppExterna = true;
            unawaited(
                NavegacionExternaLauncher.abrirGoogleMapsDestino(lat, lon));
          },
        );
      } finally {
        if (mounted) {
          setState(() => _viajeSheetOcultoPorModalNav = false);
        }
      }
    } finally {
      _selectorNavegacionAbierto = false;
    }

    final Viaje? vNav = viajeParaPersistirDestino ?? _cachedViaje;
    if (eligioAppExterna && vNav != null) {
      _marcarNavegacionDestinoLista(vNav);
    }
    return eligioAppExterna;
  }

  String _s(Object? x) => x?.toString() ?? '';

  double? _extraNumero(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw == null) return null;
    return double.tryParse(raw.toString().trim());
  }

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
            final dynamic rawWp = entry.value;
            if (rawWp is! Map) return const SizedBox.shrink();
            final Map<String, dynamic> waypoint =
                Map<String, dynamic>.from(rawWp);
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
                  if (navOk &&
                      wLat != null &&
                      wLon != null &&
                      !_esMultiparada(v))
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
    final dynamic rawPasajeros = v.extras!['pasajeros'];
    if (rawPasajeros != null) {
      final int? pasajeros = rawPasajeros is num
          ? rawPasajeros.round()
          : int.tryParse(rawPasajeros.toString());
      if (pasajeros != null && pasajeros > 0) {
        chips.add(_chip(
            '👥 $pasajeros pasajero${pasajeros != 1 ? 's' : ''}'));
      }
    }
    final double? peaje = _extraNumero(v.extras!['peaje']);
    if (peaje != null && peaje > 0) {
      chips.add(_chip('💰 Peaje: ${FormatosMoneda.rd(peaje)}'));
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

  Widget _estadoProfesionalCard({
    required IconData icon,
    required Color color,
    required String titulo,
    required String detalle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detalle,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _progresoOperativoViaje(String estadoBase) {
    try {
      final int etapa = _etapaActualViaje(estadoBase);
      const labels = <String>[
        'Aceptado',
        'Pickup',
        'A bordo',
        'En ruta',
        'Finalizado',
      ];
      final double progress =
          ((etapa + 1) / labels.length).clamp(0.0, 1.0).toDouble();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Progreso del viaje',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress,
              backgroundColor: Colors.white12,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
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
    } catch (_) {
      return const SizedBox.shrink();
    }
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
    try {
      if (!EstadosViaje.esEnCurso(estadoBase)) return const SizedBox.shrink();
      final DateTime? start = v.inicioRutaDesde;
      if (start == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: StreamBuilder<DateTime>(
          stream: _duracionEnRutaTicker,
          builder: (BuildContext context, AsyncSnapshot<DateTime> snap) {
            if (snap.hasError) return const SizedBox.shrink();
            try {
              final Duration elapsed = DateTime.now().difference(start);
              return Row(
                children: [
                  const Icon(Icons.schedule, color: Colors.blueAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tiempo en ruta: ${_formatDurationHMS(elapsed)}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                  ),
                ],
              );
            } catch (_) {
              return const SizedBox.shrink();
            }
          },
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildDetallesViajePanel(Viaje v, String estadoBase) {
    try {
      final fecha = _safeFechaViaje(v.fechaHora);
      final total = _safeMoneyViaje(v.precio);
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
              style: const TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              '💰 Total: $total',
              style: const TextStyle(fontSize: 18, color: Colors.greenAccent),
            ),
            _DesgloseComisionNeto(precio: v.precio),
            const SizedBox(height: 8),
            Text(
              '📍 Estado: ${_labelEstado(estadoBase)}',
              style: const TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 10),
            _progresoOperativoViaje(estadoBase),
            _buildDuracionEnRuta(v, estadoBase),
            _buildWaypoints(
              v,
              enRuta: EstadosViaje.esEnCurso(estadoBase),
            ),
            _buildExtras(v),
          ],
        ),
      );
    } catch (e, st) {
      unawaited(ErrorReporting.reportError(
        e,
        stack: st,
        context: 'viaje_en_curso_taxista: detalles_panel',
      ));
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
            Text(
              '🧭 ${v.origen} → ${v.destino}',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '📍 Estado: ${_labelEstado(estadoBase)}',
              style: const TextStyle(fontSize: 15, color: Colors.white70),
            ),
          ],
        ),
      );
    }
  }

  void _disposeBolaCancelWatch() {
    _bolaCancelSub?.cancel();
    _bolaCancelSub = null;
    _bolaCancelWatchViajeId = null;
  }

  Future<void> _watchBolaCancelEnViaje(String viajeId) async {
    final String vid = viajeId.trim();
    if (vid.isEmpty) {
      _disposeBolaCancelWatch();
      return;
    }
    if (_bolaCancelWatchViajeId == vid && _bolaCancelSub != null) return;

    _disposeBolaCancelWatch();
    _bolaCancelWatchViajeId = vid;

    try {
      final DocumentSnapshot<Map<String, dynamic>> vSnap =
          await FirebaseFirestore.instance.collection('viajes').doc(vid).get();
      if (!vSnap.exists) return;
      final Map<String, dynamic> vd = vSnap.data() ?? <String, dynamic>{};
      if (!ViajePoolTaxistaGate.esViajeEspejoBolaParaFlujo(vd)) return;

      final String bolaId =
          ViajePoolTaxistaGate.bolaPuebloIdDesdeViajeDoc(vd);
      if (bolaId.isEmpty) return;

      _bolaCancelSub = FirebaseFirestore.instance
          .collection('bolas_pueblo')
          .doc(bolaId)
          .snapshots()
          .listen((DocumentSnapshot<Map<String, dynamic>> snap) {
        if (!mounted) return;
        final Map<String, dynamic>? bolaData = snap.data();
        if ((bolaData?['estado'] ?? '').toString().trim() != 'cancelada') {
          return;
        }
        final String uid =
            (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
        final String canceladaPor =
            (bolaData?['canceladaPor'] ?? '').toString().trim();
        if (canceladaPor.isNotEmpty && canceladaPor == uid) return;
        final String msg = bolaData != null
            ? BolaPuebloRepo.mensajeCancelacionParaParticipante(bolaData, uid)
            : 'El acuerdo Bola Ahorro fue cancelado.';
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          _stopGps();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
          );
          await NavigationService.irAlInicioTaxista(context: context);
        });
      }, onError: (_) {});
    } catch (_) {}
  }

  void _escucharCancelacionRemota(String viajeId) {
    _cancelSub?.cancel();
    _cancelListenerIniciadoEn = DateTime.now();
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
          // Tras aceptar, el primer snapshot puede llegar sin taxista asignado aún.
          final DateTime? desde = _cancelListenerIniciadoEn;
          if (teRemovieron &&
              estN != EstadosViaje.cancelado &&
              desde != null &&
              DateTime.now().difference(desde) <
                  const Duration(seconds: 5)) {
            return;
          }
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

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: _flygoSimCasa
            ? GestureDetector(
                onDoubleTap: () {
                  final v = _cachedViaje;
                  if (v == null || !mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '[SIM CASA] Doble tap en título → finalizar (mismo que el botón)',
                      ),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  unawaited(_finalizarViaje(v));
                },
                child: const Text(
                  'Mi viaje en curso',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : const Text(
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
                    final fecha = _safeFechaViaje(v.fechaHora);
                    final total = _safeMoneyViaje(v.precio);
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
                        const Expanded(
                          flex: 3,
                          child: RepaintBoundary(
                            child: MapaTiempoReal(
                              key: ValueKey<String>('mapa-cache-viaje'),
                              esTaxista: true,
                              esCliente: false,
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
                                // Desglose informativo (solo lectura, no
                                // modifica el cálculo): comisión RAI y neto.
                                _DesgloseComisionNeto(precio: v.precio),
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
                  _sincronizarReferenciaOrdenCola(v);
                });

                if (v == null) {
                  _cachedViaje = null;
                  _navPickupPrefsLoadedForId = null;
                  _distanciaMetrosAlDestino = null;
                  _stopGps();
                  return Column(
                    children: [
                      const Expanded(
                        flex: 3,
                        child: RepaintBoundary(
                          child: MapaTiempoReal(
                            key: ValueKey<String>('mapa-sin-viaje'),
                            esTaxista: true,
                            esCliente: false,
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
                                    ActiveTripService
                                        .cancelarMantenimientoOverlayViaje();
                                    Navigator.of(context, rootNavigator: true)
                                        .pushAndRemoveUntil(
                                      MaterialPageRoute<void>(
                                          builder: (_) => const TaxistaShell()),
                                      (route) => false,
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
                  _navPickupPrefsLoadedForId = null;
                  _navDestinoPrefsLoadedForId = null;
                  _navegacionIniciada = false;
                  _navegacionDestinoIniciada = false;
                  _distanciaMetrosAlDestino = null;
                  _multiLegCompletadas = 0;
                  _multiNavViajeId = null;
                  _cachedViaje = v;
                  _aplicarProgresoMultiparadaDesdeViaje(v);
                  _escucharCancelacionRemota(v.id);
                  unawaited(_watchBolaCancelEnViaje(v.id));

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
                  _aplicarProgresoMultiparadaDesdeViaje(v);
                  final String newSig = _firmaRutaMapaTaxista(v);
                  if (prevSig != newSig && mounted) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _scheduleDrawRoute();
                    });
                  }
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    unawaited(_loadNavPickupPrefs(v));
                    unawaited(_loadNavDestinoPrefs(v));
                  }
                  _recalcDistanciaDestino();
                  _sincronizarReferenciaOrdenCola(v);
                });

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
                    unawaited(_persistNavPickupFlag(v.id, false));
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

                if (_viajeSheetOcultoPorModalNav) {
                  return RepaintBoundary(
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
                    ),
                  );
                }

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
                          onUserInteractWithMap: _colapsarViajeSheetPorMapa,
                          onUserMapGestureEnd: _expandirViajeSheetTrasMapa,
                        ),
                      ),
                    ),
                    if (_mensajeOrientacionFlujo(v, estadoBase)
                        case final String orientacionMapa?)
                      Positioned(
                        top: MediaQuery.paddingOf(context).top + 8,
                        left: 12,
                        right: 12,
                        child: ViajeFlujoOrientacionBanner(
                          mensaje: orientacionMapa,
                        ),
                      ),
                    DraggableScrollableSheet(
                      controller: _viajeSheetCtrl,
                      minChildSize: _kViajeSheetMin,
                      maxChildSize: 1.0,
                      initialChildSize: _kViajeSheetInitial,
                      snap: true,
                      snapSizes: const <double>[
                        _kViajeSheetMin,
                        0.35,
                        _kViajeSheetInitial,
                        0.72,
                        1.0,
                      ],
                      builder: (sheetCtx, scrollController) {
                        final double bottomInset =
                            MediaQuery.viewPaddingOf(sheetCtx).bottom;
                        final String? uid =
                            FirebaseAuth.instance.currentUser?.uid;
                        return DecoratedBox(
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(16)),
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
                            padding: EdgeInsets.fromLTRB(
                              16,
                              8,
                              16,
                              12 + bottomInset,
                            ),
                            children: [
                              const SizedBox(height: 8),
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
                              _actionBar(v, estadoBase),
                              if (v.uidCliente.isNotEmpty && uid != null) ...[
                                const SizedBox(height: 10),
                                ViajeChatMensajesEnVivo(
                                  viajeId: v.id,
                                  miUid: uid,
                                  otroUid: v.uidCliente,
                                  otroNombre: 'Cliente',
                                ),
                              ],
                              _viajeSheetDivider(),
                              if (uid != null)
                                const _ColaSiguienteViajeBannerSeguro(),
                              if (uid != null) const SizedBox(height: 12),
                              _buildDetallesViajePanel(v, estadoBase),
                              const SizedBox(height: 12),
                              _tarjetaVehiculoVisibleAlCliente(v),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          ViajesCercanosTaxistaLayer(
            controller: _viajesCercanosCtl,
            escuchaActiva: _viajesCercanosEscucha,
            referenciaOrdenCola: _colaReferenciaOrden,
          ),
        ],
      ),
    );
  }

  String? _mensajeOrientacionFlujo(Viaje v, String estadoBase) =>
      viajeFlujoOrientacionMensajeTaxista(
        estadoBase: estadoBase,
        navegacionPickupIniciada: _navegacionIniciada,
        navegacionDestinoIniciada: _navegacionDestinoIniciada,
        codigoVerificado: v.codigoVerificado,
        esMultiparada: _esMultiparada(v),
        multiparadaRutaCompleta: _multiparadaRutaCompleta(v),
      );

  // ==================== BARRA DE ACCIONES ====================

  Widget _actionBar(Viaje v, String estadoBase) {
    final String? orientacion = _mensajeOrientacionFlujo(v, estadoBase);
    final String actionStateKey =
        '$estadoBase|${_navegacionIniciada ? 1 : 0}|${_navegacionDestinoIniciada ? 1 : 0}|${_clienteCerca ? 1 : 0}|${v.codigoVerificado ? 1 : 0}|${orientacion ?? ''}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1,
            child: child,
          ),
        ),
        child: Column(
          key: ValueKey<String>(actionStateKey),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (orientacion != null) ...<Widget>[
              ViajeFlujoOrientacionBanner(mensaje: orientacion),
              const SizedBox(height: 12),
            ],
            ..._getActionButtons(v, estadoBase),
          ],
        ),
      ),
    );
  }

  List<Widget> _getActionButtons(Viaje v, String estadoBase) {
    final uidCli = _uidClienteDe(v);

    if (EstadosViaje.esAceptado(estadoBase) ||
        EstadosViaje.esEnCaminoPickup(estadoBase)) {
      return [
        _estadoProfesionalCard(
          icon: Icons.directions_car_filled_rounded,
          color: Colors.lightBlueAccent,
          titulo: 'Paso actual: ir al punto de recogida',
          detalle: _navegacionIniciada
              ? 'Siguiente acción: confirmar "Cliente a bordo" y el código.'
              : 'Primero abre Waze/Maps con «Navegar hacia el cliente».',
        ),
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
                          'Estás cerca del punto de recogida.',
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
        if (taxistaMostrarNavegarPickup(_navegacionIniciada)) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  _actionBusy ? null : () => _iniciarNavegacionPickup(v),
              icon: const Icon(Icons.navigation, size: 24),
              label: const Text(
                'Navegar hacia el cliente',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          if (_permitePruebaSinRecorrido(v)) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  unawaited(_persistNavPickupFlag(v.id, true));
                  setState(() => _navegacionIniciada = true);
                  _tripFlowSnack(
                    'Punto marcado. Siguiente: «Cliente a bordo (paso 2)».',
                    backgroundColor: Colors.teal.shade800,
                  );
                },
                icon: const Icon(Icons.check_circle_outline_rounded, size: 22),
                label: const Text('Llegué al punto (prueba en casa)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.tealAccent,
                  side: BorderSide(
                      color: Colors.tealAccent.withValues(alpha: 0.55)),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ] else if (taxistaMostrarClienteAbordo(_navegacionIniciada)) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _actionBusy ? null : () => _marcarClienteAbordo(v),
              icon: const Icon(Icons.person_add, size: 24),
              label: const Text(
                'Cliente a bordo (paso 2)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
          _estadoProfesionalCard(
            icon: Icons.warning_amber_rounded,
            color: Colors.orangeAccent,
            titulo: 'Paso actual: validar código de inicio',
            detalle:
                'No hay PIN válido en el viaje; contacta soporte antes de continuar.',
          ),
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
          _estadoProfesionalCard(
            icon: Icons.task_alt_rounded,
            color: Colors.greenAccent,
            titulo: 'Paso actual: código verificado',
            detalle:
                'Siguiente acción esperada: abrir navegación al destino y conducir.',
          ),
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
              label: const Text('Iniciar ruta al destino',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
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
                  if (!mounted) return;
                  if (_permitePruebaSinRecorrido(v)) {
                    _tripFlowSnack(
                      'Ruta iniciada. Abrí «Navegar al destino» o finalizá directo en prueba.',
                      backgroundColor: Colors.green.shade800,
                    );
                    _expandirViajeSheetTrasMapa();
                    return;
                  }
                  final okGps = await _gpsListoParaAbrirNavegacionExterna(v);
                  if (!okGps) return;
                  if (!mounted) return;
                  if (_esMultiparada(v)) {
                    await _navegarDestinoMultiparadaActual(v);
                  } else {
                    await _selectorNavegacionDestino(
                      v.latDestino,
                      v.lonDestino,
                      viajeParaPersistirDestino: v,
                    );
                  }
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
        _estadoProfesionalCard(
          icon: Icons.pin_rounded,
          color: Colors.amberAccent,
          titulo: 'Paso actual: solicitar PIN al cliente',
          detalle:
              'Siguiente acción esperada: validar el código para iniciar la ruta.',
        ),
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
      final legMulti = _destinoMultiActual(v);
      final String destinoUi = _esMultiparada(v) && legMulti != null
          ? legMulti.label
          : v.destino;
      return [
        _estadoProfesionalCard(
          icon: Icons.route_rounded,
          color: Colors.lightBlueAccent,
          titulo: _esMultiparada(v)
              ? 'Paso actual: ruta multiparada'
              : 'Paso actual: en ruta al destino',
          detalle: _esMultiparada(v)
              ? 'Navega parada a parada. Al salir de Waze/Maps, toca «Llegué — siguiente destino».'
              : 'Siguiente acción esperada: al llegar, confirmar y finalizar el viaje.',
        ),
        const SizedBox(height: 12),
        Text(
          _esMultiparada(v) ? 'Destino actual' : 'En camino al destino',
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          destinoUi,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          _coordsLegMultiActual(v) == null
              ? 'No hay coordenadas de destino en el viaje: podés finalizar igual para emitir la factura.'
              : _distanciaMetrosAlDestino == null
                  ? 'Distancia al destino: sin señal GPS en este momento (podés finalizar igual).'
                  : 'Distancia al pin actual: ${_textoDistanciaAlPin(_distanciaMetrosAlDestino!)} '
                      '(referencia; podés finalizar cuando corresponda).',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.62),
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 16),
        if (_esMultiparada(v)) ..._bloqueNavegacionMultiparada(v),
        if (!_esMultiparada(v) || _multiparadaRutaCompleta(v)) ...[
          if (!_navegacionDestinoIniciada) ...[
            _btnPrimario(
              icon: const Icon(Icons.navigation, size: 24),
              label: const Text('Navegar al destino',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              onPressed: () async {
                final okGps = await _gpsListoParaAbrirNavegacionExterna(v);
                if (!okGps) return;
                await _selectorNavegacionDestino(
                  v.latDestino,
                  v.lonDestino,
                  viajeParaPersistirDestino: v,
                );
              },
            ),
            if (_permitePruebaSinRecorrido(v)) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    _marcarNavegacionDestinoLista(v);
                    _expandirViajeSheetTrasMapa();
                    _tripFlowSnack(
                      'Listo. Siguiente paso: «Finalizar viaje».',
                      backgroundColor: const Color(0xFF2E7D32),
                    );
                  },
                  icon: const Icon(Icons.skip_next_rounded, size: 22),
                  label: const Text('Continuar sin mapa (prueba en casa)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.tealAccent,
                    side: BorderSide(
                        color: Colors.tealAccent.withValues(alpha: 0.55)),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ],
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
        // Botón opcional para que el taxista confirme la transferencia él mismo
        // (sin esperar al admin). Solo visible si el método es transferencia y
        // el cliente ya subió el comprobante. No reemplaza al admin: la
        // validación admin sigue funcionando como respaldo.
        _ConfirmarTransferenciaTaxistaButton(
          viajeId: v.id,
          metodoPagoFallback: v.metodoPago,
        ),
        if (_permitePruebaSinRecorrido(v) && !_navegacionDestinoIniciada) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _hintPruebaSinRecorrido(v, trasIniciarRuta: false),
              style: TextStyle(
                color: Colors.deepOrangeAccent.withValues(alpha: 0.95),
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ),
        ],
        if (_esMultiparada(v) && !_multiparadaRutaCompleta(v)) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.45)),
            ),
            child: Text(
              'Multiparada: faltan destinos por confirmar '
              '(${_multiLegCompletadas.clamp(0, _destinosOrdenadosMultiparada(v).length)}/'
              '${_destinosOrdenadosMultiparada(v).length}). '
              'Usá «Llegué — siguiente destino» en cada parada.',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (taxistaMostrarFinalizarViaje(
          navegacionDestinoIniciada: _navegacionDestinoIniciada,
          esMultiparada: _esMultiparada(v),
          multiparadaRutaCompleta: _multiparadaRutaCompleta(v),
        )) ...[
          _btnFinalizarViaje(
            onPressed: (_actionBusy || !_puedeFinalizarViajeMultiparada(v))
                ? null
                : () => _finalizarViaje(v),
            label: _labelFinalizarViaje(v),
          ),
        ],
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

  String _labelFinalizarViaje(Viaje v) =>
      v.tipoServicio == 'bola_ahorro' ? 'Finalizar bola' : 'Finalizar viaje';

  Widget _btnFinalizarViaje({
    required VoidCallback? onPressed,
    String label = 'Finalizar viaje',
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.flag_rounded, size: 26),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.15,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade700,
          disabledForegroundColor: Colors.white54,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

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

}

/// Botón "Confirmar pago recibido" que aparece SOLO cuando:
///   * el método de pago del viaje es transferencia,
///   * el cliente ya subió el comprobante (`comprobanteTransferenciaUrl`),
///   * la transferencia aún no fue confirmada (`transferenciaConfirmada != true`).
///
/// El botón llama a la callable [ViajesRepo.confirmarTransferenciaPorTaxista]
/// (Cloud Function `confirmarTransferenciaTaxistaSeguro`). El admin sigue
/// pudiendo validar como respaldo; este botón es el "atajo" del taxista.
class _ConfirmarTransferenciaTaxistaButton extends StatefulWidget {
  const _ConfirmarTransferenciaTaxistaButton({
    required this.viajeId,
    required this.metodoPagoFallback,
  });

  final String viajeId;
  final String metodoPagoFallback;

  @override
  State<_ConfirmarTransferenciaTaxistaButton> createState() =>
      _ConfirmarTransferenciaTaxistaButtonState();
}

class _ConfirmarTransferenciaTaxistaButtonState
    extends State<_ConfirmarTransferenciaTaxistaButton> {
  bool _enviando = false;

  Future<void> _confirmar() async {
    if (_enviando) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _enviando = true);
    try {
      await ViajesRepo.confirmarTransferenciaPorTaxista(
          viajeId: widget.viajeId);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Pago confirmado.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo confirmar el pago: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('viajes')
          .doc(widget.viajeId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox.shrink();
        }
        final data = snap.data!.data() ?? const <String, dynamic>{};
        final String metodo = (data['metodoPago']?.toString().isNotEmpty == true
                ? data['metodoPago'].toString()
                : widget.metodoPagoFallback)
            .toString();
        if (!MetodoPagoViaje.esTransferencia(metodo)) {
          return const SizedBox.shrink();
        }
        final String comprobante =
            (data['comprobanteTransferenciaUrl'] ?? '').toString().trim();
        if (comprobante.isEmpty) return const SizedBox.shrink();
        if (data['transferenciaConfirmada'] == true) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade400),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified, color: Colors.greenAccent, size: 18),
                  SizedBox(width: 8),
                  Text('Pago confirmado',
                      style: TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _enviando ? null : _confirmar,
              icon: _enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_enviando
                  ? 'Confirmando...'
                  : 'Confirmar pago recibido'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Evita que un fallo del banner de cola dispare el ErrorWidget global.
class _ColaSiguienteViajeBannerSeguro extends StatelessWidget {
  const _ColaSiguienteViajeBannerSeguro();

  @override
  Widget build(BuildContext context) {
    try {
      final String? uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return const SizedBox.shrink();
      return ColaSiguienteViajeBannerTaxista(uidTaxista: uid);
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}

/// Línea informativa que muestra al taxista la comisión RAI y el neto a
/// recibir sobre el total del viaje.
///
/// IMPORTANTE: este widget es de SOLO LECTURA. No persiste ni recalcula
/// nada en Firestore: simplemente reformatea localmente lo que ya calculan
/// `PlataformaEconomia` (cliente) y la Cloud Function `finalizarViajeSeguro`
/// (backend). Si en el futuro se cambia el % nominal en
/// [PlataformaEconomia.comisionViajePorcentaje] (sincronizado desde `config/comision`), la etiqueta se actualiza sola.
class _DesgloseComisionNeto extends StatelessWidget {
  const _DesgloseComisionNeto({required this.precio});

  final double precio;

  @override
  Widget build(BuildContext context) {
    if (!precio.isFinite || precio <= 0) return const SizedBox.shrink();

    try {
      final double pct = PlataformaEconomia.comisionViajePorcentaje;
      final String pctLabel = (pct - pct.round()).abs() < 1e-9
          ? pct.round().toString()
          : pct.toStringAsFixed(1);
      final double comision = PlataformaEconomia.comisionRdDesdeTotal(precio);
      final double neto = PlataformaEconomia.gananciaTaxistaRdDesdeTotal(precio);

      final String comisionTxt = FormatosMoneda.rd(comision);
      final String netoTxt = FormatosMoneda.rd(neto);

      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📊 Comisión RAI ($pctLabel%): $comisionTxt',
              style: const TextStyle(
                fontSize: 13.5,
                color: Colors.white60,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '💵 Neto a recibir: $netoTxt',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}
