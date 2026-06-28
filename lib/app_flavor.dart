// lib/app_flavor.dart
// FLAVOR SPLIT central. Detecta el flavor automáticamente desde el
// applicationId del paquete Android/iOS, con fallback al --dart-define.
//
// Valores soportados:
//   - 'cliente'   -> solo pasajero (split / --dart-define APP_FLAVOR=cliente)
//   - 'conductor' -> solo taxista (com.flygo.rd2.conductor)
//   - 'all'       -> unificada Play (com.flygo.rd2: cliente + taxista)
//
// === Play Store (unificada) ===
//   flutter build appbundle --flavor cliente --release -t lib/main.dart
//   → applicationId com.flygo.rd2, flavor runtime `all`
//
// === Split pruebas (dos APK) ===
//   Pasajero:  --flavor cliente  + --dart-define=APP_FLAVOR=cliente
//   Chofer:    --flavor conductor → com.flygo.rd2.conductor
//
// Autodetectamos desde applicationId (no confiar solo en --dart-define).

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

  static const String _playStorePasajeroPackage = 'com.flygo.rd2';
  static const String _playStoreConductorPackage = 'com.flygo.rd2.conductor';

  /// Mapea el applicationId al nombre de flavor.
  /// `com.flygo.rd2` → null → flavor `all` (Play unificado cliente + taxista).
  /// Solo `com.flygo.rd2.conductor` fuerza modo conductor.
  static String? _flavorFromPackageName(String pkg) {
    if (pkg == _playStoreConductorPackage) return 'conductor';
    if (pkg == _playStorePasajeroPackage) return null;
    return null;
  }

  /// Flavor resuelto en runtime (autodetectado o desde --dart-define).
  static String get current => _resolvedFlavor;
}

/// Helpers de conveniencia con la misma API anterior (no breaking).
bool get isClienteFlavor => _resolvedFlavor == 'cliente';
bool get isConductorFlavor => _resolvedFlavor == 'conductor';
bool get isAllFlavors => !isClienteFlavor && !isConductorFlavor;

/// APK solo pasajero o Play unificada (`all`): lógica de cliente/Giras/pool pasajero.
bool get isPasajeroCapableFlavor => !isConductorFlavor;

/// APK solo conductor o Play unificada (`all`): timbre pool y lógica taxista.
bool get isTaxistaCapableFlavor => !isClienteFlavor;

/// Compatibilidad con código existente que leía la constante.
String get kAppFlavor => _resolvedFlavor;
