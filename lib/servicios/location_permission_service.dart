// lib/servicios/location_permission_service.dart
// Gestión central de permisos y frescura de ubicación (GPS + permisos).
//
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'package:flygo_nuevo/servicios/gps_service.dart';

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
      'Esperando ubicación precisa. Asegúrate de tener el GPS activo y la app con permiso de ubicación.';
}

class LocationPermissionService {
  LocationPermissionService._();

  static bool _alwaysDialogShownThisSession = false;
  static Timer? _gentleRetryTimer;

  static bool get _nativeMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Llamar al arranque (splash / bootstrap): solo permiso **mientras se usa la app**.
  static Future<LocationBasicResult> checkAndRequestBasicPermission() async {
    print('[LOCATION] checkAndRequestBasicPermission');
    if (!_nativeMobile) {
      print('[LOCATION] skip: no es móvil nativo');
      return const LocationBasicResult(
        serviceEnabled: true,
        permission: LocationPermission.denied,
      );
    }

    final snap = await GpsService.checkServiceThenRequestPermissionIfNeeded();
    print(
        '[LOCATION] isLocationServiceEnabled=${snap.serviceEnabled} permission=${snap.permission}');

    return LocationBasicResult(
      serviceEnabled: snap.serviceEnabled,
      permission: snap.permission,
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
  }) async {
    print('[LOCATION] ensureLocationReady maxAge=${maxAge.inSeconds}s');
    if (!_nativeMobile) {
      return const LocationReadiness(permissionDenied: true);
    }

    final basic = await checkAndRequestBasicPermission();
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
      if (context?.mounted == true) {
        _snackOpenAppSettings(
          context!,
          'RAI necesita permiso de ubicación para calcular la tarifa.',
        );
      }
      return const LocationReadiness(permissionDenied: true);
    }

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
