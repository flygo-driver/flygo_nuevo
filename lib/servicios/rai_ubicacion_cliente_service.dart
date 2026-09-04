import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flygo_nuevo/servicios/gps_service.dart';
import 'package:flygo_nuevo/servicios/location_permission_service.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_ui_constants.dart';

/// Estado de GPS + permiso para el cliente (solo lectura del teléfono).
enum RaiUbicacionClienteModo {
  listo,
  gpsApagado,
  permisoPendiente,
  permisoBloqueado,
}

class RaiUbicacionClienteService with WidgetsBindingObserver {
  RaiUbicacionClienteService._();

  static final RaiUbicacionClienteService instance =
      RaiUbicacionClienteService._();

  final ValueNotifier<RaiUbicacionClienteModo> modo =
      ValueNotifier(RaiUbicacionClienteModo.permisoPendiente);

  /// True mientras se abre el diálogo del sistema o se espera confirmación.
  final ValueNotifier<bool> solicitudEnCurso = ValueNotifier(false);

  /// Tras tocar «Permitir» sin conceder ubicación (Denegar / cerrar cuadro).
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

  bool get ubicacionLista => modo.value == RaiUbicacionClienteModo.listo;

  /// Banner visible en shell → evita SnackBars duplicados en cotizar viaje.
  bool get bannerActivo => modo.value != RaiUbicacionClienteModo.listo;

  /// Tras tocar «Permitir» sin conceder: banner rojo hasta que haya permiso usable.
  bool get bannerEnAlertaRoja {
    if (modo.value == RaiUbicacionClienteModo.permisoBloqueado) return true;
    if ((feedbackSinUbicacion.value ?? '').trim().isNotEmpty) return true;
    return false;
  }

  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    LocationPermissionService.clienteBannerManejaUi = true;
    WidgetsBinding.instance.addObserver(this);
    try {
      _gpsSub = Geolocator.getServiceStatusStream().listen((_) {
        _programarRefrescar();
      });
    } catch (_) {}
    await refrescar(forzar: true);
  }

  void _programarRefrescar({bool forzar = false}) {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(refrescar(forzar: forzar));
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
    LocationPermissionService.clienteBannerManejaUi = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _programarRefrescar(forzar: true);
      unawaited(_continuarActivacionSiUsuarioVolvioDeAjustes());
    }
  }

  /// Tras tocar «Activar ubicación» y volver de ajustes/GPS del teléfono: sigue el flujo sin otro toque.
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
        modo.value = RaiUbicacionClienteModo.permisoBloqueado;
        await LocationPermissionService.limpiarActivacionDesdeAppRai();
        return;
      }

      if (!GpsService.permissionUsable(perm)) {
        await GpsService.requestPermissionExplicitUser();
        perm = await GpsService.waitUntilPermissionUsable();
      }

      if (GpsService.permissionUsable(perm)) {
        feedbackSinUbicacion.value = null;
        modo.value = RaiUbicacionClienteModo.listo;
        await _marcarListoEnPrefs();
        await LocationPermissionService.limpiarActivacionDesdeAppRai();
        return;
      }

      await _registrarIntentoFallido(kMsgAunSinUbicacion);
      modo.value = RaiUbicacionClienteModo.permisoPendiente;
    } finally {
      solicitudEnCurso.value = false;
      await refrescar();
    }
  }

  Future<void> refrescar({bool forzar = false}) async {
    final DateTime ahora = DateTime.now();
    if (!forzar &&
        ahora.difference(_ultimoRefresco) < const Duration(milliseconds: 800)) {
      return;
    }
    _ultimoRefresco = ahora;

    final bool yaConcedio = await prefsIndicaListoAntes();
    final snap = await GpsService.readServiceAndPermissionStabilizedNoRequest(
      extendedAfterPriorGrant: yaConcedio,
    );

    RaiUbicacionClienteModo next;
    if (!snap.serviceEnabled) {
      next = RaiUbicacionClienteModo.gpsApagado;
    } else if (snap.permission == LocationPermission.deniedForever) {
      next = RaiUbicacionClienteModo.permisoBloqueado;
    } else if (!GpsService.permissionUsable(snap.permission)) {
      if (yaConcedio) {
        final p = await GpsService.waitUntilPermissionUsable(
          timeout: const Duration(seconds: 4),
        );
        if (GpsService.permissionUsable(p)) {
          next = RaiUbicacionClienteModo.listo;
          feedbackSinUbicacion.value = null;
          await _marcarListoEnPrefs();
        } else if (modo.value == RaiUbicacionClienteModo.listo ||
            await _gpsRespondeTrasConcesionPrevia()) {
          next = RaiUbicacionClienteModo.listo;
          feedbackSinUbicacion.value = null;
          await _marcarListoEnPrefs();
        } else {
          next = RaiUbicacionClienteModo.permisoPendiente;
        }
      } else {
        next = RaiUbicacionClienteModo.permisoPendiente;
      }
    } else {
      next = RaiUbicacionClienteModo.listo;
      feedbackSinUbicacion.value = null;
      await _marcarListoEnPrefs();
    }

    if (modo.value != next) {
      modo.value = next;
    }

    if (next == RaiUbicacionClienteModo.listo) {
      feedbackSinUbicacion.value = null;
      await LocationPermissionService.limpiarUbicacionDenegadaTrasBanner();
      await LocationPermissionService.limpiarActivacionDesdeAppRai();
      return;
    }

    await _restaurarFeedbackDenegadoSiCorresponde(next);
  }

  /// Si ya concedió antes y el teléfono tiene GPS activo, confiar en última posición
  /// conocida (evita pedir «Activar ubicación» otra vez al reabrir la app).
  Future<bool> _gpsRespondeTrasConcesionPrevia() async {
    try {
      final Position? pos = await Geolocator.getLastKnownPosition();
      return pos != null &&
          pos.latitude.isFinite &&
          pos.longitude.isFinite &&
          !(pos.latitude == 0 && pos.longitude == 0);
    } catch (_) {
      return false;
    }
  }

  Future<void> _restaurarFeedbackDenegadoSiCorresponde(
    RaiUbicacionClienteModo modoActual,
  ) async {
    if (modoActual == RaiUbicacionClienteModo.permisoBloqueado) {
      feedbackSinUbicacion.value = RaiUbicacionUiConstants.msgIrAjustesManualPlataforma;
      return;
    }
    if (modoActual == RaiUbicacionClienteModo.gpsApagado &&
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

  /// Botón único de RAI → GPS del teléfono, cuadro «Permitir» o Ajustes de la app.
  Future<void> activarUbicacionDesdeApp({BuildContext? context}) async {
    if (solicitudEnCurso.value) return;
    await LocationPermissionService.marcarActivacionDesdeAppRai();
    solicitudEnCurso.value = true;
    try {
      final r = await LocationPermissionService.activarUbicacionRai(
        bannerEnAlertaRoja: bannerEnAlertaRoja,
        modoPermisoBloqueado:
            modo.value == RaiUbicacionClienteModo.permisoBloqueado,
        context: context,
      );

      if (r.concedido) {
        feedbackSinUbicacion.value = null;
        modo.value = RaiUbicacionClienteModo.listo;
        await _marcarListoEnPrefs();
        await LocationPermissionService.limpiarActivacionDesdeAppRai();
        return;
      }

      if (r.gpsApagado) {
        await _registrarIntentoFallido(kMsgAunSinGps);
        modo.value = RaiUbicacionClienteModo.gpsApagado;
        return;
      }

      if (r.permission == LocationPermission.deniedForever) {
        await _registrarIntentoFallido(
          RaiUbicacionUiConstants.msgIrAjustesManualPlataforma,
        );
        modo.value = RaiUbicacionClienteModo.permisoBloqueado;
        return;
      }

      if (r.abrioAjustesApp) {
        await _registrarIntentoFallido(RaiUbicacionUiConstants.msgIrAjustesManualPlataforma);
        modo.value = RaiUbicacionClienteModo.permisoPendiente;
      } else {
        await _registrarIntentoFallido(kMsgAunSinUbicacion);
        modo.value = RaiUbicacionClienteModo.permisoPendiente;
      }
    } finally {
      solicitudEnCurso.value = false;
      await refrescar();
      if (modo.value != RaiUbicacionClienteModo.listo &&
          !GpsService.permissionUsable(await Geolocator.checkPermission())) {
        await _restaurarFeedbackDenegadoSiCorresponde(modo.value);
      }
    }
  }

  /// Alias histórico — usar [activarUbicacionDesdeApp].
  Future<void> solicitarPermisoDesdeBanner() => activarUbicacionDesdeApp();

  String get tituloBanner {
    if (bannerEnAlertaRoja) {
      return 'Ubicación requerida';
    }
    switch (modo.value) {
      case RaiUbicacionClienteModo.gpsApagado:
        return 'GPS desactivado';
      case RaiUbicacionClienteModo.permisoPendiente:
        return 'Ubicación necesaria';
      case RaiUbicacionClienteModo.permisoBloqueado:
        return 'Ubicación bloqueada';
      case RaiUbicacionClienteModo.listo:
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
      case RaiUbicacionClienteModo.gpsApagado:
        return kIsWeb
            ? 'Activa la ubicación del equipo o permite ubicación en el navegador. '
                'Toca «Activar ubicación».'
            : 'Enciende el GPS del teléfono. Toca «Activar ubicación» y RAI te lleva ahí.';
      case RaiUbicacionClienteModo.permisoPendiente:
        return kIsWeb
            ? 'Para cotizar tu viaje, toca «Activar ubicación». '
                'Elige «Permitir» en el cuadro del navegador.'
            : 'Para cotizar tu viaje, toca «Activar ubicación». '
                'Se abrirá el cuadro del teléfono: elige «Al usar la app».';
      case RaiUbicacionClienteModo.permisoBloqueado:
        return kIsWeb
            ? RaiUbicacionUiConstants.msgIrAjustesManualWeb
            : 'Toca «Abrir ajustes» o ve a Cuenta → Ubicación para permitir ubicación.';
      case RaiUbicacionClienteModo.listo:
        return '';
    }
  }

  /// Subtítulo corto para Cuenta → Ubicación (estado en tiempo real).
  String get subtituloCuentaMenu {
    switch (modo.value) {
      case RaiUbicacionClienteModo.listo:
        return 'GPS activo · listo para cotizar y viajar';
      case RaiUbicacionClienteModo.gpsApagado:
        return 'GPS desactivado · tócalo para activarlo';
      case RaiUbicacionClienteModo.permisoPendiente:
        return 'Permiso pendiente · necesario para cotizar';
      case RaiUbicacionClienteModo.permisoBloqueado:
        return 'Permiso bloqueado · abre ajustes del teléfono';
    }
  }

  /// Misma etiqueta en banner, mapa y botón GPS.
  String get accionActivarUbicacion => kAccionActivarUbicacion;

  String get etiquetaAccionBanner {
    if (modo.value == RaiUbicacionClienteModo.listo) {
      return kAccionActivarUbicacion;
    }
    if (bannerEnAlertaRoja ||
        modo.value == RaiUbicacionClienteModo.permisoBloqueado) {
      return RaiUbicacionUiConstants.accionAbrirAjustesUbicacion;
    }
    return kAccionActivarUbicacion;
  }

  @Deprecated('Usar accionActivarUbicacion')
  String get accionPrincipal => accionActivarUbicacion;
}
