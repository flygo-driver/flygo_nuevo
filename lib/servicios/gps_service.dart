// lib/servicios/gps_service.dart
//
// ─── Contrato de ubicación (producción) ─────────────────────────────────────
// [readServiceAndPermissionStabilizedNoRequest] → **pasivo**. Nunca invoca
//     Geolocator.requestPermission. Usar en: bootstrap, resumed, initState de
//     mapas, streams en vivo, turismo, mapa tiempo real, cliente en viaje, etc.
// [checkServiceThenRequestPermissionIfNeeded] → **explícito**. Solo donde la
//     UX acepta mostrar el diálogo del SO si tras estabilizar sigue denied+GPS.
// [requestPermissionIfDeniedThrottled] → interno / LocationPermissionService
//     con requestIfDenied: true.
// ───────────────────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GpsService {
  /// Evita llamadas repetidas a [Geolocator.requestPermission] (p. ej. cada
  /// rebuild del viaje o al volver de segundo plano con el mismo `denied`).
  static DateTime? _lastGeolocatorRequestPermissionAt;

  /// Tras [AppLifecycleState.resumed], en Android a veces el primer
  /// [Geolocator.checkPermission] devuelve [denied] un instante antes de
  /// estabilizarse en [whileInUse].
  static const Duration _kPermissionStabilizeDelay =
      Duration(milliseconds: 120);

  /// Relecturas cuando el GPS del sistema está **encendido** y Geolocator
  /// aún reporta [denied] (falso negativo al volver de Waze / segundo plano).
  static const int _kDeniedStabilizeAttempts = 14;

  static const Duration _kDeniedStabilizeGap = Duration(milliseconds: 120);

  static Future<bool> isServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  static Future<LocationPermission> checkPermission() =>
      Geolocator.checkPermission();

  /// Bypass directo al SO; en producción preferir [requestPermissionIfDeniedThrottled].
  /// Si aparece en logs, revisar el stack: no debería usarse desde pantallas pasivas.
  static Future<LocationPermission> requestPermission() async {
    final String stack = _kGpsStackHead(StackTrace.current);
    debugPrint('[GPS] GpsService.requestPermission() directo — stack:\n$stack');
    return Geolocator.requestPermission();
  }

  /// Toque explícito del usuario (banner «Permitir»). Sin throttle de 90 s.
  static Future<LocationPermission> requestPermissionExplicitUser() async {
    final bool se = await Geolocator.isLocationServiceEnabled();
    if (!se) {
      debugPrint('[GPS] requestPermissionExplicitUser: GPS apagado');
      return Geolocator.checkPermission();
    }

    var p = await Geolocator.checkPermission();
    if (permissionUsable(p)) {
      debugPrint('[GPS] requestPermissionExplicitUser: ya usable ($p)');
      return p;
    }
    if (p == LocationPermission.deniedForever) {
      debugPrint('[GPS] requestPermissionExplicitUser: deniedForever');
      return p;
    }

    // Tras volver de segundo plano Android a veces reporta denied un instante.
    if (await _ubicacionListaEnPrefs()) {
      p = await waitUntilPermissionUsable(
        timeout: const Duration(seconds: 4),
      );
      if (permissionUsable(p)) {
        debugPrint(
          '[GPS] requestPermissionExplicitUser: prefs listo → usable sin diálogo ($p)',
        );
        return p;
      }
    }

    _lastGeolocatorRequestPermissionAt = DateTime.now();
    debugPrint(
        '[GPS] requestPermissionExplicitUser → Geolocator.requestPermission()');
    p = await Geolocator.requestPermission();
    debugPrint('[GPS] requestPermissionExplicitUser resultado=$p');
    return p;
  }

  /// Tras el diálogo del SO, Android a veces tarda en reflejar whileInUse.
  static Future<LocationPermission> waitUntilPermissionUsable({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final p = await Geolocator.checkPermission();
      if (permissionUsable(p)) return p;
      if (p == LocationPermission.deniedForever) return p;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return Geolocator.checkPermission();
  }

  static String _kGpsStackHead(StackTrace st, {int maxFrames = 18}) {
    final lines = st.toString().trim().split('\n');
    if (lines.length <= maxFrames) return st.toString().trim();
    return lines.take(maxFrames).join('\n');
  }

  /// Solo si el estado es exactamente [LocationPermission.denied] **tras**
  /// [readServiceAndPermissionStabilizedNoRequest]; no llama a
  /// [Geolocator.requestPermission] más de una vez por [minInterval].
  ///
  /// **Nunca** llama a [Geolocator.requestPermission] si el GPS está apagado,
  /// si el permiso ya es usable, o si tras relectura deja de ser [denied].
  static Future<LocationPermission> requestPermissionIfDeniedThrottled({
    Duration minInterval = const Duration(seconds: 90),
  }) async {
    final ({bool serviceEnabled, LocationPermission permission}) snap =
        await readServiceAndPermissionStabilizedNoRequest();

    if (permissionUsable(snap.permission)) {
      debugPrint(
        '[GPS] requestPermissionIfDeniedThrottled: readNoRequest ya usable '
        '(${snap.permission}) → sin request',
      );
      return snap.permission;
    }
    if (!snap.serviceEnabled) {
      debugPrint(
        '[GPS] requestPermissionIfDeniedThrottled: GPS apagado → sin request',
      );
      return snap.permission;
    }
    if (snap.permission != LocationPermission.denied) {
      debugPrint(
        '[GPS] requestPermissionIfDeniedThrottled: estado ${snap.permission} '
        '(no denied) → sin request',
      );
      return snap.permission;
    }

    final DateTime now = DateTime.now();
    final DateTime? last = _lastGeolocatorRequestPermissionAt;
    if (last != null && now.difference(last) < minInterval) {
      debugPrint(
        '[GPS] requestPermissionIfDeniedThrottled: throttle '
        '(${now.difference(last).inMilliseconds}ms < ${minInterval.inMilliseconds}ms) '
        '→ sin request',
      );
      return snap.permission;
    }

    final ({bool serviceEnabled, LocationPermission permission}) pre =
        await readServiceAndPermissionStabilizedNoRequest();
    if (permissionUsable(pre.permission) ||
        pre.permission != LocationPermission.denied ||
        !pre.serviceEnabled) {
      debugPrint(
        '[GPS] requestPermissionIfDeniedThrottled: pre-request estable '
        'serviceEnabled=${pre.serviceEnabled} permission=${pre.permission} → sin request',
      );
      return pre.permission;
    }

    _lastGeolocatorRequestPermissionAt = now;
    final String stack = _kGpsStackHead(StackTrace.current);
    debugPrint(
      '[GPS] ═══ Geolocator.requestPermission() — AUDITORÍA (origen del diálogo) ═══\n'
      '$stack',
    );
    return Geolocator.requestPermission();
  }

  static bool permissionUsable(LocationPermission p) =>
      p == LocationPermission.whileInUse || p == LocationPermission.always;

  static Future<bool> _ubicacionListaEnPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      return (p.getBool('rai_cliente_ubicacion_listo_v1') ?? false) ||
          (p.getBool('rai_taxista_ubicacion_listo_v1') ?? false);
    } catch (_) {
      return false;
    }
  }

  /// Solo lectura + estabilización. **Nunca** invoca [Geolocator.requestPermission].
  /// Uso típico: [AppLifecycleState.resumed] (volver de Waze / ajustes) y
  /// pantallas que no deben volver a mostrar el diálogo del SO.
  ///
  /// Falsos `denied` tras resume: delay inicial + varias relecturas con gap fijo.
  /// Si en un dispositivo extremo aún fallara, subir [_kDeniedStabilizeAttempts] o
  /// el gap en una iteración futura (evitar backoff infinito en UI thread).
  static Future<({bool serviceEnabled, LocationPermission permission})>
      readServiceAndPermissionStabilizedNoRequest({
    bool extendedAfterPriorGrant = false,
  }) async {
    LocationPermission p = await Geolocator.checkPermission();
    debugPrint('[GPS] readNoRequest: checkPermission() => $p');

    if (permissionUsable(p)) {
      final bool se = await Geolocator.isLocationServiceEnabled();
      debugPrint('[GPS] readNoRequest: usable de entrada serviceEnabled=$se');
      return (serviceEnabled: se, permission: p);
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[GPS] readNoRequest: GPS off permission=$p (sin request)');
      return (serviceEnabled: false, permission: p);
    }

    final bool extended = extendedAfterPriorGrant ||
        await _ubicacionListaEnPrefs();
    final int maxAttempts =
        extended ? 28 : _kDeniedStabilizeAttempts;
    final Duration gap = extended
        ? const Duration(milliseconds: 150)
        : _kDeniedStabilizeGap;

    if (p == LocationPermission.denied) {
      await Future<void>.delayed(
        extended ? const Duration(milliseconds: 200) : _kPermissionStabilizeDelay,
      );
      p = await Geolocator.checkPermission();
      for (var i = 0; i < maxAttempts && p == LocationPermission.denied; i++) {
        await Future<void>.delayed(gap);
        final LocationPermission q = await Geolocator.checkPermission();
        if (q != p) {
          debugPrint(
            '[GPS] readNoRequest: relectura ${i + 1}/$maxAttempts => $q',
          );
        }
        p = q;
        if (permissionUsable(p) || p != LocationPermission.denied) break;
      }
    }

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    debugPrint(
      '[GPS] readNoRequest: fin serviceEnabled=$serviceEnabled permission=$p '
      '(Geolocator.requestPermission NUNCA llamado aquí)',
    );
    return (serviceEnabled: serviceEnabled, permission: p);
  }

  /// Comprueba GPS + permiso y solo entonces puede invocar el diálogo del SO.
  ///
  /// Implementación estricta: **siempre** estabiliza con
  /// [readServiceAndPermissionStabilizedNoRequest] antes de considerar
  /// [requestPermissionIfDeniedThrottled]. Si el permiso ya es usable, o el
  /// GPS está apagado, **nunca** llama a [Geolocator.requestPermission].
  static Future<({bool serviceEnabled, LocationPermission permission})>
      checkServiceThenRequestPermissionIfNeeded({
    Duration minInterval = const Duration(seconds: 90),
  }) async {
    final ({bool serviceEnabled, LocationPermission permission}) snap =
        await readServiceAndPermissionStabilizedNoRequest();
    debugPrint(
      '[GPS] checkServiceThenRequest: tras readNoRequest '
      'serviceEnabled=${snap.serviceEnabled} permission=${snap.permission}',
    );

    if (permissionUsable(snap.permission)) {
      return snap;
    }
    if (!snap.serviceEnabled) {
      return snap;
    }
    if (snap.permission == LocationPermission.denied) {
      if (await _ubicacionListaEnPrefs()) {
        final LocationPermission p = await waitUntilPermissionUsable(
          timeout: const Duration(seconds: 2),
        );
        final bool se = await Geolocator.isLocationServiceEnabled();
        debugPrint(
          '[GPS] checkServiceThenRequest: prefs listo → wait sin request → $p',
        );
        return (serviceEnabled: se, permission: p);
      }
      debugPrint(
        '[GPS] checkServiceThenRequest: denied sin prefs → sin request SO',
      );
      return snap;
    }
    return snap;
  }

  static Future<bool> openLocationSettings() =>
      Geolocator.openLocationSettings();

  static Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// Lectura de posición **sin** solicitar permiso al SO: si aún no hay permiso
  /// usable, devuelve null (mapa principal / arranque; el permiso se pide en
  /// flujos explícitos vía [checkServiceThenRequestPermissionIfNeeded] o
  /// [LocationPermissionService.checkAndRequestBasicPermission]).
  static Future<Position?> obtenerUbicacionActual({
    Duration timeout = const Duration(seconds: 10),
    Duration maxEdadUltima = const Duration(minutes: 2),
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    final snap = await readServiceAndPermissionStabilizedNoRequest();
    if (!snap.serviceEnabled) return null;
    if (!permissionUsable(snap.permission)) return null;

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
        timeLimit: timeout,
      );
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && _esReciente(last, maxEdadUltima)) return last;
      return null;
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && _esReciente(last, maxEdadUltima)) return last;
      return null;
    }
  }

  /// Cel / laptop / PC / tablet: pide permiso si hace falta y obtiene GPS
  /// para mapa y cotización en producción (mismo flujo en todas las plataformas).
  static Future<Position?> obtenerUbicacionMapaProduccion({
    Duration timeout = const Duration(seconds: 12),
    bool pedirPermisoSiFalta = true,
  }) async {
    var serviceOn = await isServiceEnabled();
    if (!serviceOn) {
      debugPrint('[GPS] servicio ubicación apagado');
      return null;
    }

    var perm = await checkPermission();
    if (!permissionUsable(perm) && pedirPermisoSiFalta) {
      perm = await requestPermissionExplicitUser();
    }
    serviceOn = await isServiceEnabled();
    if (!serviceOn || !permissionUsable(perm)) {
      debugPrint('[GPS] sin permiso usable ($perm)');
      // Sin diálogo: último intento pasivo (móvil con permiso previo).
      if (!pedirPermisoSiFalta) {
        return obtenerUbicacionActual(timeout: timeout);
      }
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: timeout,
      );
    } on TimeoutException {
      return Geolocator.getLastKnownPosition();
    } catch (e) {
      debugPrint('[GPS] getCurrentPosition: $e');
      return Geolocator.getLastKnownPosition();
    }
  }

  static Stream<Position> streamUbicacion({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilterMeters = 10,
  }) {
    final settings = LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilterMeters,
    );

    return Geolocator.getPositionStream(locationSettings: settings)
        .where((p) => p.latitude != 0.0 || p.longitude != 0.0);
  }

  static Future<Position?> esperarPrimeraUbicacion({
    Duration timeout = const Duration(seconds: 10),
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilterMeters = 0,
  }) async {
    try {
      return await streamUbicacion(
        accuracy: accuracy,
        distanceFilterMeters: distanceFilterMeters,
      ).first.timeout(timeout);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Position?> ultimaConocidaSiReciente({
    Duration maxEdadUltima = const Duration(minutes: 2),
  }) async {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null && _esReciente(last, maxEdadUltima)) return last;
    return null;
  }

  static bool _esReciente(Position p, Duration maxEdad) {
    return DateTime.now().difference(p.timestamp).abs() <= maxEdad;
  }
}
