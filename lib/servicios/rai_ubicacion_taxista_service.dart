import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flygo_nuevo/servicios/gps_service.dart';
import 'package:flygo_nuevo/servicios/location_permission_service.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_ui_constants.dart';

/// Estado de GPS + permiso para el taxista (solo lectura del teléfono).
enum RaiUbicacionTaxistaModo {
  listo,
  gpsApagado,
  permisoPendiente,
  permisoBloqueado,
}

class RaiUbicacionTaxistaService with WidgetsBindingObserver {
  RaiUbicacionTaxistaService._();

  static final RaiUbicacionTaxistaService instance =
      RaiUbicacionTaxistaService._();

  @Deprecated('Usar RaiUbicacionUiConstants.msgEsperandoUbicacion')
  static const String kMsgActivarDesdeBanner =
      RaiUbicacionUiConstants.msgEsperandoUbicacion;

  final ValueNotifier<RaiUbicacionTaxistaModo> modo =
      ValueNotifier(RaiUbicacionTaxistaModo.permisoPendiente);

  final ValueNotifier<bool> solicitudEnCurso = ValueNotifier(false);

  final ValueNotifier<String?> feedbackSinUbicacion = ValueNotifier(null);

  static const String kMsgAunSinUbicacion =
      'No activaste la ubicación. Toca «Abrir ajustes» o ve a Cuenta → Ubicación '
      'y elige «Al usar la app».';

  static const String kMsgAunSinGps =
      'Aún no tienes el GPS activo. Toca «Activar ubicación» para abrir los '
      'ajustes del teléfono y encenderlo.';

  static const String kAccionActivarUbicacion =
      RaiUbicacionUiConstants.accionActivarUbicacion;

  static const String kMsgEsperandoCuadroTelefono =
      RaiUbicacionUiConstants.msgEsperandoCuadroTelefono;

  StreamSubscription<ServiceStatus>? _gpsSub;
  Timer? _refreshDebounce;
  DateTime _ultimoRefresco = DateTime.fromMillisecondsSinceEpoch(0);
  bool _started = false;

  bool get ubicacionLista => modo.value == RaiUbicacionTaxistaModo.listo;

  bool get bannerActivo => modo.value != RaiUbicacionTaxistaModo.listo;

  bool get bannerEnAlertaRoja {
    if (modo.value == RaiUbicacionTaxistaModo.permisoBloqueado) return true;
    if ((feedbackSinUbicacion.value ?? '').trim().isNotEmpty) return true;
    return false;
  }

  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    LocationPermissionService.taxistaBannerManejaUi = true;
    WidgetsBinding.instance.addObserver(this);
    try {
      _gpsSub = Geolocator.getServiceStatusStream().listen((_) {
        _programarRefrescar();
      });
    } catch (_) {}
    await refrescar();
  }

  void _programarRefrescar() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(refrescar());
    });
  }

  void disposeService() {
    if (!_started) return;
    WidgetsBinding.instance.removeObserver(this);
    _gpsSub?.cancel();
    _gpsSub = null;
    _refreshDebounce?.cancel();
    _refreshDebounce = null;
    _started = false;
    LocationPermissionService.taxistaBannerManejaUi = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _programarRefrescar();
      unawaited(_continuarActivacionSiUsuarioVolvioDeAjustes());
    }
  }

  Future<void> _continuarActivacionSiUsuarioVolvioDeAjustes() async {
    if (!await LocationPermissionService.activacionDesdeAppRaiPendiente()) {
      return;
    }
    if (solicitudEnCurso.value) return;

    final bool gpsOn = await Geolocator.isLocationServiceEnabled();
    if (!gpsOn) {
      await refrescar();
      return;
    }

    solicitudEnCurso.value = true;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.deniedForever) {
        await _registrarIntentoFallido(
          'Ubicación bloqueada. Toca «Activar ubicación» para abrir Ajustes de RAI.',
        );
        modo.value = RaiUbicacionTaxistaModo.permisoBloqueado;
        await LocationPermissionService.limpiarActivacionDesdeAppRai();
        return;
      }

      if (!GpsService.permissionUsable(perm)) {
        await GpsService.requestPermissionExplicitUser();
        perm = await GpsService.waitUntilPermissionUsable();
      }

      if (GpsService.permissionUsable(perm)) {
        feedbackSinUbicacion.value = null;
        modo.value = RaiUbicacionTaxistaModo.listo;
        await _marcarListoEnPrefs();
        await LocationPermissionService.limpiarActivacionDesdeAppRai();
        return;
      }

      await _registrarIntentoFallido(kMsgAunSinUbicacion);
      modo.value = RaiUbicacionTaxistaModo.permisoPendiente;
    } finally {
      solicitudEnCurso.value = false;
      await refrescar();
    }
  }

  Future<void> refrescar() async {
    final DateTime ahora = DateTime.now();
    if (ahora.difference(_ultimoRefresco) < const Duration(seconds: 2)) {
      return;
    }
    _ultimoRefresco = ahora;

    final bool yaConcedio = await prefsIndicaListoAntes();
    final snap = await GpsService.readServiceAndPermissionStabilizedNoRequest(
      extendedAfterPriorGrant: yaConcedio,
    );

    RaiUbicacionTaxistaModo next;
    if (!snap.serviceEnabled) {
      next = RaiUbicacionTaxistaModo.gpsApagado;
    } else if (snap.permission == LocationPermission.deniedForever) {
      next = RaiUbicacionTaxistaModo.permisoBloqueado;
    } else if (!GpsService.permissionUsable(snap.permission)) {
      if (yaConcedio) {
        final p = await GpsService.waitUntilPermissionUsable(
          timeout: const Duration(seconds: 4),
        );
        if (GpsService.permissionUsable(p)) {
          next = RaiUbicacionTaxistaModo.listo;
          feedbackSinUbicacion.value = null;
          await _marcarListoEnPrefs();
        } else if (modo.value == RaiUbicacionTaxistaModo.listo) {
          return;
        } else {
          next = RaiUbicacionTaxistaModo.permisoPendiente;
        }
      } else {
        next = RaiUbicacionTaxistaModo.permisoPendiente;
      }
    } else {
      next = RaiUbicacionTaxistaModo.listo;
      feedbackSinUbicacion.value = null;
      await _marcarListoEnPrefs();
    }

    if (modo.value != next) {
      modo.value = next;
    }

    if (next == RaiUbicacionTaxistaModo.listo) {
      feedbackSinUbicacion.value = null;
      return;
    }

    await _restaurarFeedbackDenegadoSiCorresponde(next);
  }

  Future<void> _restaurarFeedbackDenegadoSiCorresponde(
    RaiUbicacionTaxistaModo modoActual,
  ) async {
    if (modoActual == RaiUbicacionTaxistaModo.permisoBloqueado) {
      feedbackSinUbicacion.value = RaiUbicacionUiConstants.msgIrAjustesManualPlataforma;
      return;
    }
    if (modoActual == RaiUbicacionTaxistaModo.gpsApagado &&
        await LocationPermissionService.ubicacionDenegadaTrasBannerEnPrefs()) {
      feedbackSinUbicacion.value = kMsgAunSinGps;
      return;
    }
    if (await LocationPermissionService.ubicacionDenegadaTrasBannerEnPrefs()) {
      feedbackSinUbicacion.value = kMsgAunSinUbicacion;
    }
  }

  Future<void> _registrarIntentoFallido(String mensaje) async {
    await LocationPermissionService.marcarUbicacionDenegadaTrasBanner();
    feedbackSinUbicacion.value = mensaje;
  }

  Future<void> _marcarListoEnPrefs() async {
    await LocationPermissionService.marcarUbicacionConcedidaEnPrefs();
  }

  Future<bool> prefsIndicaListoAntes() async {
    return LocationPermissionService.ubicacionConcedidaAntesEnPrefs();
  }

  Future<void> activarUbicacionDesdeApp({BuildContext? context}) async {
    if (solicitudEnCurso.value) return;
    await LocationPermissionService.marcarActivacionDesdeAppRai();
    solicitudEnCurso.value = true;
    try {
      final r = await LocationPermissionService.activarUbicacionRai(
        bannerEnAlertaRoja: bannerEnAlertaRoja,
        modoPermisoBloqueado:
            modo.value == RaiUbicacionTaxistaModo.permisoBloqueado,
        context: context,
      );

      if (r.concedido) {
        feedbackSinUbicacion.value = null;
        modo.value = RaiUbicacionTaxistaModo.listo;
        await _marcarListoEnPrefs();
        await LocationPermissionService.limpiarActivacionDesdeAppRai();
        return;
      }

      if (r.gpsApagado) {
        await _registrarIntentoFallido(kMsgAunSinGps);
        modo.value = RaiUbicacionTaxistaModo.gpsApagado;
        return;
      }

      if (r.permission == LocationPermission.deniedForever) {
        await _registrarIntentoFallido(
          RaiUbicacionUiConstants.msgIrAjustesManualPlataforma,
        );
        modo.value = RaiUbicacionTaxistaModo.permisoBloqueado;
        return;
      }

      if (r.abrioAjustesApp) {
        await _registrarIntentoFallido(
          RaiUbicacionUiConstants.msgIrAjustesManualPlataforma,
        );
        modo.value = RaiUbicacionTaxistaModo.permisoPendiente;
      } else {
        await _registrarIntentoFallido(kMsgAunSinUbicacion);
        modo.value = RaiUbicacionTaxistaModo.permisoPendiente;
      }
    } finally {
      solicitudEnCurso.value = false;
      await refrescar();
      if (modo.value != RaiUbicacionTaxistaModo.listo &&
          !GpsService.permissionUsable(await Geolocator.checkPermission())) {
        await _restaurarFeedbackDenegadoSiCorresponde(modo.value);
      }
    }
  }

  Future<void> solicitarPermisoDesdeBanner() => activarUbicacionDesdeApp();

  String get tituloBanner {
    if (bannerEnAlertaRoja) {
      return 'Ubicación requerida';
    }
    switch (modo.value) {
      case RaiUbicacionTaxistaModo.gpsApagado:
        return 'GPS desactivado';
      case RaiUbicacionTaxistaModo.permisoPendiente:
        return 'Ubicación necesaria';
      case RaiUbicacionTaxistaModo.permisoBloqueado:
        return 'Ubicación bloqueada';
      case RaiUbicacionTaxistaModo.listo:
        return '';
    }
  }

  String get mensajeBannerVisible {
    final fb = feedbackSinUbicacion.value?.trim();
    if (fb != null && fb.isNotEmpty) return fb;
    return mensajeBanner;
  }

  String get mensajeBanner {
    switch (modo.value) {
      case RaiUbicacionTaxistaModo.gpsApagado:
        return kIsWeb
            ? 'Activa la ubicación del equipo o permite ubicación en el navegador. '
                'Toca «Activar ubicación».'
            : 'Enciende el GPS del teléfono. Toca «Activar ubicación» y RAI te lleva ahí.';
      case RaiUbicacionTaxistaModo.permisoPendiente:
        return kIsWeb
            ? 'Para recibir viajes y navegar, toca «Activar ubicación». '
                'Elige «Permitir» en el cuadro del navegador.'
            : 'Para recibir viajes y navegar, toca «Activar ubicación». '
                'Elige «Al usar la app» en el cuadro del teléfono.';
      case RaiUbicacionTaxistaModo.permisoBloqueado:
        return kIsWeb
            ? RaiUbicacionUiConstants.msgIrAjustesManualWeb
            : 'Toca «Abrir ajustes» o ve a Cuenta → Ubicación para permitir ubicación.';
      case RaiUbicacionTaxistaModo.listo:
        return '';
    }
  }

  String get accionActivarUbicacion => kAccionActivarUbicacion;

  String get etiquetaAccionBanner {
    if (modo.value == RaiUbicacionTaxistaModo.listo) {
      return kAccionActivarUbicacion;
    }
    if (bannerEnAlertaRoja ||
        modo.value == RaiUbicacionTaxistaModo.permisoBloqueado) {
      return RaiUbicacionUiConstants.accionAbrirAjustesUbicacion;
    }
    return kAccionActivarUbicacion;
  }

  @Deprecated('Usar accionActivarUbicacion')
  String get accionPrincipal => accionActivarUbicacion;
}
