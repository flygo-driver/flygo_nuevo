import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flygo_nuevo/servicios/gps_service.dart';
import 'package:flygo_nuevo/servicios/location_permission_service.dart';

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

  static const String _prefsListo =
      LocationPermissionService.prefsTaxistaUbicacionListo;

  static const String kMsgActivarDesdeBanner =
      'Activa el GPS y toca «Permitir» en el banner superior '
      '(elige «Al usar la app» en el mensaje del teléfono).';

  final ValueNotifier<RaiUbicacionTaxistaModo> modo =
      ValueNotifier(RaiUbicacionTaxistaModo.permisoPendiente);

  final ValueNotifier<bool> solicitudEnCurso = ValueNotifier(false);

  final ValueNotifier<String?> feedbackSinUbicacion = ValueNotifier(null);

  static const String kMsgAunSinUbicacion =
      'Aún no tienes ubicación activa. En el mensaje del teléfono elige '
      '«Permitir» o «Al usar la app». Si tocaste «Denegar», «No» o cerraste '
      'el cuadro sin aceptar, toca «Permitir» otra vez.';

  static const String kMsgAunSinGps =
      'Aún no tienes el GPS activo. Actívalo en ajustes del teléfono para '
      'que RAI Conductor pueda publicar tu posición.';

  StreamSubscription<ServiceStatus>? _gpsSub;
  bool _started = false;

  bool get ubicacionLista => modo.value == RaiUbicacionTaxistaModo.listo;

  bool get bannerActivo => modo.value != RaiUbicacionTaxistaModo.listo;

  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    LocationPermissionService.taxistaBannerManejaUi = true;
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

    RaiUbicacionTaxistaModo next;
    if (!snap.serviceEnabled) {
      next = RaiUbicacionTaxistaModo.gpsApagado;
    } else if (snap.permission == LocationPermission.deniedForever) {
      next = RaiUbicacionTaxistaModo.permisoBloqueado;
    } else if (!GpsService.permissionUsable(snap.permission)) {
      if (await prefsIndicaListoAntes()) {
        final p = await GpsService.waitUntilPermissionUsable(
          timeout: const Duration(seconds: 2),
        );
        if (GpsService.permissionUsable(p)) {
          next = RaiUbicacionTaxistaModo.listo;
          feedbackSinUbicacion.value = null;
          await _marcarListoEnPrefs();
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
            'Ubicación bloqueada. Abre Ajustes de RAI Conductor y permite «Ubicación».';
        await LocationPermissionService.openAppSettingsPage();
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
        return;
      }

      if (perm == LocationPermission.deniedForever) {
        feedbackSinUbicacion.value =
            'Ubicación bloqueada. Abre Ajustes de RAI Conductor y permite «Ubicación».';
        modo.value = RaiUbicacionTaxistaModo.permisoBloqueado;
      } else {
        feedbackSinUbicacion.value = kMsgAunSinUbicacion;
        modo.value = RaiUbicacionTaxistaModo.permisoPendiente;
      }
    } finally {
      solicitudEnCurso.value = false;
      await refrescar();
      if (modo.value != RaiUbicacionTaxistaModo.listo &&
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
        return 'Activa el GPS para recibir viajes y que los clientes vean tu posición.';
      case RaiUbicacionTaxistaModo.permisoPendiente:
        return 'RAI Conductor necesita tu ubicación para operar. '
            'Toca «Permitir» y elige «Al usar la app» en el mensaje del teléfono.';
      case RaiUbicacionTaxistaModo.permisoBloqueado:
        return 'Ubicación bloqueada. Abre Ajustes de RAI Conductor y permite «Ubicación».';
      case RaiUbicacionTaxistaModo.listo:
        return '';
    }
  }

  String get accionPrincipal {
    switch (modo.value) {
      case RaiUbicacionTaxistaModo.gpsApagado:
        return 'Activar GPS';
      case RaiUbicacionTaxistaModo.permisoPendiente:
        return 'Permitir';
      case RaiUbicacionTaxistaModo.permisoBloqueado:
        return 'Abrir ajustes';
      case RaiUbicacionTaxistaModo.listo:
        return '';
    }
  }
}
