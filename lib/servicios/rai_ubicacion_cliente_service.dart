import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flygo_nuevo/servicios/gps_service.dart';
import 'package:flygo_nuevo/servicios/location_permission_service.dart';

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

  static const String _prefsListo =
      LocationPermissionService.prefsClienteUbicacionListo;

  final ValueNotifier<RaiUbicacionClienteModo> modo =
      ValueNotifier(RaiUbicacionClienteModo.permisoPendiente);

  /// True mientras se abre el diálogo del sistema o se espera confirmación.
  final ValueNotifier<bool> solicitudEnCurso = ValueNotifier(false);

  /// Tras tocar «Permitir» sin conceder ubicación (Denegar / cerrar cuadro).
  final ValueNotifier<String?> feedbackSinUbicacion = ValueNotifier(null);

  static const String kMsgAunSinUbicacion =
      'Aún no tienes ubicación activa. En el mensaje del teléfono elige '
      '«Permitir» o «Al usar la app». Si tocaste «Denegar», «No» o cerraste '
      'el cuadro sin aceptar, toca «Permitir» otra vez.';

  static const String kMsgAunSinGps =
      'Aún no tienes el GPS activo. Actívalo en ajustes del teléfono para '
      'que RAI pueda usar tu ubicación.';

  StreamSubscription<ServiceStatus>? _gpsSub;
  bool _started = false;

  bool get ubicacionLista => modo.value == RaiUbicacionClienteModo.listo;

  /// Banner visible en shell → evita SnackBars duplicados en cotizar viaje.
  bool get bannerActivo => modo.value != RaiUbicacionClienteModo.listo;

  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    LocationPermissionService.clienteBannerManejaUi = true;
    WidgetsBinding.instance.addObserver(this);
    try {
      _gpsSub = Geolocator.getServiceStatusStream().listen((_) {
        unawaited(refrescar());
      });
    } catch (_) {}
    await refrescar();
  }

  void disposeService() {
    if (!_started) return;
    WidgetsBinding.instance.removeObserver(this);
    _gpsSub?.cancel();
    _gpsSub = null;
    _started = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refrescar());
    }
  }

  Future<void> refrescar() async {
    final snap = await GpsService.readServiceAndPermissionStabilizedNoRequest();

    RaiUbicacionClienteModo next;
    if (!snap.serviceEnabled) {
      next = RaiUbicacionClienteModo.gpsApagado;
    } else if (snap.permission == LocationPermission.deniedForever) {
      next = RaiUbicacionClienteModo.permisoBloqueado;
    } else if (!GpsService.permissionUsable(snap.permission)) {
      if (await prefsIndicaListoAntes()) {
        final p = await GpsService.waitUntilPermissionUsable(
          timeout: const Duration(seconds: 2),
        );
        if (GpsService.permissionUsable(p)) {
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
  }

  Future<void> _marcarListoEnPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_prefsListo, true);
    } catch (_) {}
  }

  Future<bool> prefsIndicaListoAntes() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_prefsListo) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Un toque en «Permitir»: abre el diálogo del SO sin throttle ni esperas largas.
  Future<void> solicitarPermisoDesdeBanner() async {
    if (solicitudEnCurso.value) return;
    solicitudEnCurso.value = true;
    try {
      final bool gpsOn = await Geolocator.isLocationServiceEnabled();
      if (!gpsOn) {
        await LocationPermissionService.openSystemLocationSettings();
        if (!await Geolocator.isLocationServiceEnabled()) {
          feedbackSinUbicacion.value = kMsgAunSinGps;
        }
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.deniedForever) {
        feedbackSinUbicacion.value =
            'Ubicación bloqueada. Abre Ajustes de RAI y permite «Ubicación».';
        await LocationPermissionService.openAppSettingsPage();
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
        return;
      }

      if (perm == LocationPermission.deniedForever) {
        feedbackSinUbicacion.value =
            'Ubicación bloqueada. Abre Ajustes de RAI y permite «Ubicación».';
        modo.value = RaiUbicacionClienteModo.permisoBloqueado;
      } else {
        feedbackSinUbicacion.value = kMsgAunSinUbicacion;
        modo.value = RaiUbicacionClienteModo.permisoPendiente;
      }
    } finally {
      solicitudEnCurso.value = false;
      await refrescar();
      if (modo.value != RaiUbicacionClienteModo.listo &&
          !GpsService.permissionUsable(await Geolocator.checkPermission())) {
        feedbackSinUbicacion.value ??= kMsgAunSinUbicacion;
      }
    }
  }

  String get tituloBanner {
    final fb = feedbackSinUbicacion.value?.trim();
    if (fb != null && fb.isNotEmpty) {
      return 'Aún no tienes ubicación';
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
        return 'Activa el GPS del teléfono para cotizar viajes con precisión.';
      case RaiUbicacionClienteModo.permisoPendiente:
        return 'RAI necesita tu ubicación para calcular la tarifa. '
            'Toca «Permitir» y elige «Al usar la app» en el mensaje del teléfono.';
      case RaiUbicacionClienteModo.permisoBloqueado:
        return 'Ubicación bloqueada. Abre Ajustes de RAI y permite «Ubicación».';
      case RaiUbicacionClienteModo.listo:
        return '';
    }
  }

  String get accionPrincipal {
    switch (modo.value) {
      case RaiUbicacionClienteModo.gpsApagado:
        return 'Activar GPS';
      case RaiUbicacionClienteModo.permisoPendiente:
        return 'Permitir';
      case RaiUbicacionClienteModo.permisoBloqueado:
        return 'Abrir ajustes';
      case RaiUbicacionClienteModo.listo:
        return '';
    }
  }
}
