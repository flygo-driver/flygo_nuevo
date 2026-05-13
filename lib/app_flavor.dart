// lib/app_flavor.dart
// FLAVOR SPLIT central. Detecta el flavor automáticamente desde el
// applicationId del paquete Android/iOS, con fallback al --dart-define.
//
// Valores soportados:
//   - 'cliente'   -> APK construida solo para pasajero (RAI Pasajero)
//   - 'conductor' -> APK construida solo para taxista  (RAI Conductor)
//   - 'all'       -> debug local sin --flavor: muestra ambos botones
//
// === Por qué autodetectar desde el applicationId ===
// El comando `flutter build apk --release --dart-define=APP_FLAVOR=cliente`
// (sin --flavor) hace que Gradle construya AMBOS APKs (cliente + conductor),
// pero a los dos les inyecta APP_FLAVOR=cliente — entonces el APK del
// conductor se comporta como cliente. Bug muy fácil de cometer.
//
// Solución: el applicationId SIEMPRE es distinto entre flavors:
//   - com.flygo.rd2          → cliente (RAI Pasajero)
//   - com.flygo.rd2.conductor → conductor (RAI Conductor)
//
// Leemos el packageName con `package_info_plus` y derivamos el flavor real,
// independiente del --dart-define. Así NUNCA se confunde el cliente con el
// conductor en el mismo build.

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

const String _kAppFlavorDefine = String.fromEnvironment(
  'APP_FLAVOR',
  defaultValue: 'all',
);

/// Estado actual del flavor (lazy-init).
/// Se rellena por [AppFlavor.init] en `main()` antes de `runApp`.
String _resolvedFlavor = _kAppFlavorDefine;
bool _initialized = false;

class AppFlavor {
  AppFlavor._();

  /// Llamar una sola vez en `main()` (antes de runApp) para autodetectar el
  /// flavor desde el `applicationId` real del paquete instalado.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final pkg = info.packageName.trim();
      final fromPkg = _flavorFromPackageName(pkg);
      if (fromPkg != null) {
        _resolvedFlavor = fromPkg;
      }
      // Si no matchea ningún paquete conocido, dejamos el valor del
      // --dart-define (o 'all' por defecto).
    } catch (e) {
      if (kDebugMode) {
        // No bloqueamos el arranque por esto; solo log.
        debugPrint('AppFlavor.init: no se pudo leer PackageInfo → $e');
      }
    } finally {
      _initialized = true;
    }
  }

  /// Mapea el applicationId al nombre de flavor.
  /// Devuelve null si no es un paquete conocido (debug local sin --flavor).
  static String? _flavorFromPackageName(String pkg) {
    // RAI Conductor — applicationId del taxista.
    if (pkg == 'com.flygo.rd2.conductor') return 'conductor';
    // RAI Pasajero — applicationId del cliente.
    if (pkg == 'com.flygo.rd2') return 'cliente';
    return null;
  }

  /// Flavor resuelto en runtime (autodetectado o desde --dart-define).
  static String get current => _resolvedFlavor;
}

/// Helpers de conveniencia con la misma API anterior (no breaking).
bool get isClienteFlavor => _resolvedFlavor == 'cliente';
bool get isConductorFlavor => _resolvedFlavor == 'conductor';
bool get isAllFlavors => !isClienteFlavor && !isConductorFlavor;

/// Compatibilidad con código existente que leía la constante.
String get kAppFlavor => _resolvedFlavor;
