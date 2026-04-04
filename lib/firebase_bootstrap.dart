import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

/// Inicialización idempotente: evita carreras y el error
/// [core/duplicate-app] cuando la app default ya existe (nativo + Dart).
class FirebaseBootstrap {
  static bool _didInit = false;
  static Future<void>? _inFlight;

  static Future<void> ensureInitialized() async {
    if (_didInit) return;
    if (Firebase.apps.isNotEmpty) {
      _didInit = true;
      return;
    }

    _inFlight ??= _initLocked();
    try {
      await _inFlight;
    } finally {
      _inFlight = null;
    }
  }

  static Future<void> _initLocked() async {
    if (_didInit) return;
    if (Firebase.apps.isNotEmpty) {
      _didInit = true;
      return;
    }

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _didInit = true;
    } on FirebaseException catch (e) {
      if (e.code == 'duplicate-app' ||
          e.code == 'core/duplicate-app' ||
          (e.message ?? '').toLowerCase().contains('already exists')) {
        _didInit = true;
        return;
      }
      debugPrint('Error inicializando Firebase: $e');
      rethrow;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('duplicate') && msg.contains('already exists')) {
        _didInit = true;
        return;
      }
      debugPrint('Error inicializando Firebase: $e');
      rethrow;
    }
  }
}
