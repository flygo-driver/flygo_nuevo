// lib/servicios/location_permission_service.dart
// Gestión central de permisos y frescura de ubicación (GPS + permisos).
//
// Política: lectura pasiva por defecto. El diálogo del SO solo desde
// «Activar ubicación» ([RaiUbicacionActivarButton] / servicios cliente+taxista).
//
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flygo_nuevo/servicios/gps_service.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_ui_constants.dart';

/// Resultado del chequeo básico (solo “al usar la app”, sin “siempre”).
class LocationBasicResult {
  const LocationBasicResult({
    required this.serviceEnabled,
    required this.permission,
  });

  final bool serviceEnabled;
  final LocationPermission permission;

  bool get canUseLocation =>
      permission == LocationPermission.whileInUse ||
      permission == LocationPermission.always;

  bool get deniedForever => permission == LocationPermission.deniedForever;

  bool get denied => permission == LocationPermission.denied;
}

/// Resultado de [ensureLocationReady] (ubicación reciente y válida).
class LocationReadiness {
  const LocationReadiness({
    this.ok = false,
    this.position,
    this.serviceDisabled = false,
    this.permissionDenied = false,
    this.permissionDeniedForever = false,
    this.staleOrInvalid = false,
  });

  final bool ok;
  final Position? position;
  final bool serviceDisabled;
  final bool permissionDenied;
  final bool permissionDeniedForever;
  final bool staleOrInvalid;

  bool get isUsable =>
      ok &&
      position != null &&
      !serviceDisabled &&
      !permissionDenied &&
      !permissionDeniedForever &&
      !staleOrInvalid;

  static const String kMsgEsperandoUbicacion =
      RaiUbicacionUiConstants.msgEsperandoUbicacion;
}

class LocationPermissionService {
  LocationPermissionService._();

  /// Misma clave que [RaiUbicacionClienteService] — permiso concedido alguna vez.
  static const String prefsClienteUbicacionListo = 'rai_cliente_ubicacion_listo_v1';

  /// Taxista: permiso «al usar la app» ya concedido (no repetir diálogo del SO).
  static const String prefsTaxistaUbicacionListo = 'rai_taxista_ubicacion_listo_v1';

  /// Diálogo in-app «Permitir siempre» ya mostrado (taxista o cliente).
  static const String prefsAlwaysPromptHandled = 'rai_ubicacion_always_prompt_v1';

  /// Tocó «Activar ubicación» en RAI y no concedió → banner rojo hasta permitir.
  static const String prefsUbicacionDenegadaTrasBanner =
      'rai_ubicacion_denegada_banner_v1';

  /// Flujo iniciado desde el botón único de RAI (GPS/permiso/ajustes); al volver a la app se continúa solo.
  static const String prefsActivacionDesdeAppRai =
      'rai_ubicacion_activacion_desde_app_v1';

  /// Cliente: el banner del shell ya guía; no duplicar SnackBars al cotizar.
  static bool clienteBannerManejaUi = false;

  /// Taxista: mismo patrón que cliente ([RaiUbicacionTaxistaBanner]).
  static bool taxistaBannerManejaUi = false;

  /// Si el banner del shell está activo, no pedir permiso al SO desde cotizar/confirmar.
  static bool get clienteEvitaRequestPermisoAlSo => clienteBannerManejaUi;

  static bool get taxistaEvitaRequestPermisoAlSo => taxistaBannerManejaUi;

  /// Siempre false: el diálogo del SO solo desde el banner «Permitir».
  static bool get clienteRequestIfDeniedAlSo => false;

  static bool get taxistaRequestIfDeniedAlSo => false;

  /// Cliente o taxista ya concedió «al usar la app» en esta instalación.
  static Future<bool> ubicacionConcedidaAntesEnPrefs() async {
    return (await _clienteConcedioUbicacionAntes()) ||
        (await taxistaUbicacionListaAntes());
  }

  /// ¿Mostrar [Geolocator.requestPermission] ahora? Solo toque «Permitir» en banner
  /// ([GpsService.requestPermissionExplicitUser]). Flujos pasivos: siempre false.
  static Future<bool> deboPedirPermisoAlSistemaAhora({
    required LocationPermission permission,
  }) async {
    if (GpsService.permissionUsable(permission)) return false;
    if (permission != LocationPermission.denied) return false;
    if (clienteEvitaRequestPermisoAlSo || taxistaEvitaRequestPermisoAlSo) {
      return false;
    }
    if (await ubicacionConcedidaAntesEnPrefs()) return false;
    return false;
  }

  static Future<bool> _clienteConcedioUbicacionAntes() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(prefsClienteUbicacionListo) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _marcarClienteUbicacionListoEnPrefs() async {
    await marcarUbicacionConcedidaEnPrefs();
  }

  /// Una sola instalación: cliente y conductor comparten el mismo permiso del SO.
  static Future<void> marcarUbicacionConcedidaEnPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(prefsClienteUbicacionListo, true);
      await p.setBool(prefsTaxistaUbicacionListo, true);
      await p.setBool(prefsUbicacionDenegadaTrasBanner, false);
      await p.setBool(prefsActivacionDesdeAppRai, false);
    } catch (_) {}
  }

  /// Usuario tocó el botón único «Activar ubicación» en RAI.
  static Future<void> marcarActivacionDesdeAppRai() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(prefsActivacionDesdeAppRai, true);
    } catch (_) {}
  }

  static Future<bool> activacionDesdeAppRaiPendiente() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(prefsActivacionDesdeAppRai) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> limpiarActivacionDesdeAppRai() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(prefsActivacionDesdeAppRai, false);
    } catch (_) {}
  }

  static Future<void> marcarUbicacionDenegadaTrasBanner() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(prefsUbicacionDenegadaTrasBanner, true);
    } catch (_) {}
  }

  static Future<void> limpiarUbicacionDenegadaTrasBanner() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(prefsUbicacionDenegadaTrasBanner, false);
    } catch (_) {}
  }

  static Future<bool> ubicacionDenegadaTrasBannerEnPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(prefsUbicacionDenegadaTrasBanner) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> taxistaUbicacionListaAntes() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(prefsTaxistaUbicacionListo) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> marcarTaxistaUbicacionListoEnPrefs() async {
    await marcarUbicacionConcedidaEnPrefs();
  }

  static Future<bool> _alwaysPromptHandledBefore() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(prefsAlwaysPromptHandled) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _markAlwaysPromptHandled() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(prefsAlwaysPromptHandled, true);
    } catch (_) {}
  }

  static bool _alwaysDialogShownThisSession = false;
  static Timer? _gentleRetryTimer;

  static bool get _nativeMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Lectura pasiva (+ espera corta si prefs indican permiso ya concedido).
  /// [requestIfDenied] debe ser false en producción; el diálogo del SO solo desde el banner.
  static Future<LocationBasicResult> checkAndRequestBasicPermission({
    bool requestIfDenied = false,
  }) async {
    print('[LOCATION] checkAndRequestBasicPermission requestIfDenied=$requestIfDenied');
    if (!_nativeMobile) {
      print('[LOCATION] skip: no es móvil nativo');
      return const LocationBasicResult(
        serviceEnabled: true,
        permission: LocationPermission.denied,
      );
    }

    final snap =
        await GpsService.readServiceAndPermissionStabilizedNoRequest();
    print(
        '[LOCATION] readNoRequest serviceEnabled=${snap.serviceEnabled} permission=${snap.permission}',
    );

    if (GpsService.permissionUsable(snap.permission)) {
      unawaited(_marcarClienteUbicacionListoEnPrefs());
      unawaited(marcarTaxistaUbicacionListoEnPrefs());
      return LocationBasicResult(
        serviceEnabled: snap.serviceEnabled,
        permission: snap.permission,
      );
    }
    if (!snap.serviceEnabled) {
      return LocationBasicResult(
        serviceEnabled: false,
        permission: snap.permission,
      );
    }
    if (snap.permission == LocationPermission.denied) {
      var p = snap.permission;
      if (await ubicacionConcedidaAntesEnPrefs()) {
        p = await GpsService.waitUntilPermissionUsable(
          timeout: const Duration(seconds: 2),
        );
        if (GpsService.permissionUsable(p)) {
          unawaited(_marcarClienteUbicacionListoEnPrefs());
          unawaited(marcarTaxistaUbicacionListoEnPrefs());
        }
        print('[LOCATION] denied + prefs listo → wait sin request SO → $p');
        return LocationBasicResult(
          serviceEnabled: snap.serviceEnabled,
          permission: p,
        );
      }
      if (requestIfDenied &&
          await deboPedirPermisoAlSistemaAhora(permission: snap.permission)) {
        final LocationPermission pReq =
            await GpsService.requestPermissionIfDeniedThrottled();
        final bool se = await Geolocator.isLocationServiceEnabled();
        if (GpsService.permissionUsable(pReq)) {
          unawaited(_marcarClienteUbicacionListoEnPrefs());
          unawaited(marcarTaxistaUbicacionListoEnPrefs());
        }
        print(
          '[LOCATION] tras request throttled serviceEnabled=$se permission=$pReq',
        );
        return LocationBasicResult(serviceEnabled: se, permission: pReq);
      }
      print(
        '[LOCATION] denied → sin Geolocator.requestPermission (banner / sin prefs)',
      );
      return LocationBasicResult(
        serviceEnabled: snap.serviceEnabled,
        permission: p,
      );
    }

    return LocationBasicResult(
      serviceEnabled: snap.serviceEnabled,
      permission: snap.permission,
    );
  }

  /// GPS + permiso para cotizar turismo / multiparada / widgets cliente.
  /// Respeta [clienteEvitaRequestPermisoAlSo]: no repite el diálogo del SO si el
  /// banner ya guía al usuario o ya concedió ubicación antes.
  static Future<({bool serviceEnabled, LocationPermission permission})>
      checkServiceThenRequestIfNeeded({
    bool requestIfDenied = false,
  }) async {
    final snap =
        await GpsService.readServiceAndPermissionStabilizedNoRequest();
    if (GpsService.permissionUsable(snap.permission) ||
        !snap.serviceEnabled ||
        snap.permission != LocationPermission.denied) {
      return snap;
    }
    final basic = await checkAndRequestBasicPermission(
      requestIfDenied: requestIfDenied,
    );
    return (
      serviceEnabled: basic.serviceEnabled,
      permission: basic.permission,
    );
  }

  /// Abre ajustes de **ubicación del sistema** (activar GPS).
  static Future<void> openSystemLocationSettings() async {
    print('[LOCATION] openSystemLocationSettings');
    await Geolocator.openLocationSettings();
  }

  /// Abre la ficha de la app en ajustes (permisos revocados permanentemente).
  static Future<void> openAppSettingsPage() async {
    print('[LOCATION] openAppSettingsPage');
    await ph.openAppSettings();
  }

  /// Reintento suave cada 30 s (p. ej. pantalla de mapa esperando GPS/permiso).
  static void startGentleRetry(VoidCallback onTick) {
    stopGentleRetry();
    print('[LOCATION] startGentleRetry cada 30s');
    _gentleRetryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      print('[LOCATION] gentle retry tick');
      onTick();
    });
  }

  static void stopGentleRetry() {
    if (_gentleRetryTimer != null) {
      print('[LOCATION] stopGentleRetry');
      _gentleRetryTimer!.cancel();
      _gentleRetryTimer = null;
    }
  }

  /// Diálogo “Permitir siempre” al solicitar viaje o ponerse en línea (una vez por sesión de app).
  static Future<void> maybePromptAlwaysForCriticalFlow(
    BuildContext context, {
    required bool isTaxista,
  }) async {
    if (!_nativeMobile || !context.mounted) return;
    if (!await Geolocator.isLocationServiceEnabled()) {
      print('[LOCATION] skip always dialog: GPS apagado');
      return;
    }
    if (_alwaysDialogShownThisSession) return;
    if (await _alwaysPromptHandledBefore()) return;

    final perm = await Geolocator.checkPermission();
    if (!context.mounted) return;
    if (perm == LocationPermission.always) {
      _alwaysDialogShownThisSession = true;
      print('[LOCATION] ya tiene permiso always');
      return;
    }
    if (perm != LocationPermission.whileInUse) {
      print('[LOCATION] skip always dialog: sin whenInUse ($perm)');
      return;
    }

    if (!context.mounted) return;

    _alwaysDialogShownThisSession = true;
    await _markAlwaysPromptHandled();
    print('[LOCATION] mostrar diálogo permiso always (isTaxista=$isTaxista)');

    final String body = isTaxista
        ? 'Para que los clientes vean tu posición en tiempo real y el sistema asigne viajes con precisión, '
            'necesitamos acceso a tu ubicación incluso cuando la app no esté en primer plano. ¿Permitir siempre?'
        : 'Para que el conductor pueda ver tu ubicación en tiempo real y la tarifa sea precisa, '
            'necesitamos acceso a tu ubicación incluso cuando no estés usando la app. ¿Permitir siempre?';

    final agreed = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final cs = Theme.of(ctx).colorScheme;
            return AlertDialog(
              title: Text(
                'Ubicación en segundo plano',
                style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
              ),
              content: SingleChildScrollView(
                child: Text(body, style: TextStyle(color: cs.onSurface)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Ahora no'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Permitir siempre'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!context.mounted) return;

    if (!agreed) {
      print('[LOCATION] usuario rechazó always → experiencia limitada');
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Sin ubicación en segundo plano la experiencia será limitada '
            '(p. ej. menos precisión al minimizar la app). Podés cambiarlo en Ajustes cuando quieras.',
          ),
          duration: Duration(seconds: 6),
        ),
      );
      return;
    }

    if (Platform.isAndroid) {
      final st = await ph.Permission.locationAlways.request();
      print('[LOCATION] Android Permission.locationAlways → $st');
    } else {
      final st = await ph.Permission.locationAlways.request();
      print('[LOCATION] iOS Permission.locationAlways → $st');
    }
  }

  /// Ubicación válida y con antigüedad ≤ [maxAge] (por defecto 10 s).
  static Future<LocationReadiness> ensureLocationReady({
    BuildContext? context,
    Duration maxAge = const Duration(seconds: 10),
    Duration timeout = const Duration(seconds: 14),
    bool? requestIfDenied,
  }) async {
    final bool req = requestIfDenied ?? false;
    print(
      '[LOCATION] ensureLocationReady maxAge=${maxAge.inSeconds}s '
      'requestIfDenied=$req',
    );
    if (!_nativeMobile) {
      return const LocationReadiness(permissionDenied: true);
    }

    final basic = await checkAndRequestBasicPermission(
      requestIfDenied: req,
    );
    if (!basic.serviceEnabled) {
      print('[LOCATION] ensureLocationReady: GPS apagado');
      if (context?.mounted == true) {
        _snackOpenLocationSettings(
          context!,
          'El GPS está desactivado. Actívalo para continuar.',
        );
      }
      return const LocationReadiness(serviceDisabled: true);
    }
    if (basic.deniedForever) {
      print('[LOCATION] ensureLocationReady: deniedForever');
      if (context?.mounted == true) {
        _snackOpenAppSettings(
          context!,
          'Permiso de ubicación bloqueado. Abre Ajustes de la app para permitirlo.',
        );
      }
      return const LocationReadiness(permissionDeniedForever: true);
    }
    if (!basic.canUseLocation) {
      print('[LOCATION] ensureLocationReady: sin permiso usable');
      final bool yaListo = await ubicacionConcedidaAntesEnPrefs();
      if (context?.mounted == true) {
        if (yaListo || clienteBannerManejaUi || taxistaBannerManejaUi) {
          ScaffoldMessenger.maybeOf(context!)?.showSnackBar(
            const SnackBar(
              content: Text(LocationReadiness.kMsgEsperandoUbicacion),
              duration: Duration(seconds: 6),
            ),
          );
        } else {
          _snackOpenAppSettings(
            context!,
            'RAI necesita permiso de ubicación. Toca «Permitir» en el banner superior.',
          );
        }
      }
      return const LocationReadiness(permissionDenied: true);
    }

    unawaited(marcarTaxistaUbicacionListoEnPrefs());
    unawaited(_marcarClienteUbicacionListoEnPrefs());

    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: timeout,
      );
    } on TimeoutException {
      print('[LOCATION] getCurrentPosition timeout → lastKnown');
      pos = await Geolocator.getLastKnownPosition();
    } catch (e) {
      print('[LOCATION] getCurrentPosition error: $e');
      pos = await Geolocator.getLastKnownPosition();
    }

    if (pos == null) {
      print('[LOCATION] ensureLocationReady: pos null');
      return const LocationReadiness(staleOrInvalid: true);
    }

    Position current = pos;
    var age = DateTime.now().difference(current.timestamp).abs();
    print('[LOCATION] pos age=${age.inMilliseconds}ms');
    if (age > maxAge) {
      try {
        final pos2 = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: timeout,
        );
        final age2 = DateTime.now().difference(pos2.timestamp).abs();
        if (age2 <= maxAge ||
            age2 < age) {
          current = pos2;
          age = age2;
        }
      } catch (e) {
        print('[LOCATION] segundo getCurrentPosition: $e');
      }
    }

    if (!current.latitude.isFinite ||
        !current.longitude.isFinite ||
        (current.latitude == 0 && current.longitude == 0)) {
      return LocationReadiness(staleOrInvalid: true, position: current);
    }

    if (age > maxAge) {
      print('[LOCATION] ubicación aún demasiado antigua');
      return LocationReadiness(staleOrInvalid: true, position: current);
    }

    return LocationReadiness(ok: true, position: current);
  }

  static void _snackOpenLocationSettings(
      BuildContext context, String message) {
    if (clienteBannerManejaUi) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Ajustes de ubicación',
          onPressed: () {
            print('[LOCATION] user tap abrir ajustes ubicación sistema');
            unawaited(openSystemLocationSettings());
          },
        ),
      ),
    );
  }

  static void _snackOpenAppSettings(BuildContext context, String message) {
    if (clienteBannerManejaUi) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Ajustes de la app',
          onPressed: () {
            print('[LOCATION] user tap abrir ajustes app');
            unawaited(openAppSettingsPage());
          },
        ),
      ),
    );
  }
}
