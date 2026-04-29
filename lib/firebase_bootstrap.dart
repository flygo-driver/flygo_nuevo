import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

/// Inicialización idempotente: evita carreras y el error
/// [core/duplicate-app] cuando la app default ya existe (nativo + Dart).
class FirebaseBootstrap {
  static bool _didInit = false;
  static bool _firestoreSettingsDone = false;
  static Future<void>? _inFlight;

  static Future<void> ensureInitialized() async {
    if (_didInit) return;
    if (Firebase.apps.isNotEmpty) {
      await _configureFirestoreForScale();
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
      await _configureFirestoreForScale();
      _didInit = true;
      return;
    }

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await _configureFirestoreForScale();
      _didInit = true;
    } on FirebaseException catch (e) {
      if (e.code == 'duplicate-app' ||
          e.code == 'core/duplicate-app' ||
          (e.message ?? '').toLowerCase().contains('already exists')) {
        await _configureFirestoreForScale();
        _didInit = true;
        return;
      }
      debugPrint('Error inicializando Firebase: $e');
      rethrow;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('duplicate') && msg.contains('already exists')) {
        await _configureFirestoreForScale();
        _didInit = true;
        return;
      }
      debugPrint('Error inicializando Firebase: $e');
      rethrow;
    }
  }

  /// Caché persistente acotada: muchos listeners concurrentes sin crecer sin límite en RAM.
  /// Debe ejecutarse antes del primer uso de Firestore (véase [ensureInitialized]).
  static Future<void> _configureFirestoreForScale() async {
    if (_firestoreSettingsDone) return;
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 50 * 1024 * 1024,
      );
      _firestoreSettingsDone = true;
    } catch (e) {
      debugPrint('Firestore settings (no crítico): $e');
    }
  }
}
