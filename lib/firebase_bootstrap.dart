import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

import 'firebase_options.dart';

/// Inicialización idempotente: evita carreras y el error
/// [core/duplicate-app] cuando la app default ya existe (nativo + Dart).
class FirebaseBootstrap {
  static bool _didInit = false;
  static bool _firestoreSettingsDone = false;
  static Future<void>? _inFlight;

  /// `true` tras [ensureInitialized] o si la app nativa ya inicializó Firebase.
  static bool get isReady => _didInit || Firebase.apps.isNotEmpty;

  static Future<void> ensureInitialized() async {
    if (_didInit) return;

    _inFlight ??= _initLocked();
    try {
      await _inFlight;
    } finally {
      _inFlight = null;
    }
  }

  /// Cada flavor Android tiene su propio `appId` en google-services.json.
  /// Si siempre usamos [DefaultFirebaseOptions.android] (cliente), Storage
  /// falla en `com.flygo.rd2.conductor` con firebase_storage/unknown.
  static Future<FirebaseOptions> _optionsForPlatform() async {
    if (kIsWeb) return DefaultFirebaseOptions.web;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return DefaultFirebaseOptions.ios;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final pkg = (await PackageInfo.fromPlatform()).packageName.trim();
        if (pkg == 'com.flygo.rd2.conductor') {
          debugPrint('[FirebaseBootstrap] Android app=conductor');
          return DefaultFirebaseOptions.androidConductor;
        }
        if (pkg == 'com.flygo.rd2') {
          debugPrint('[FirebaseBootstrap] Android app=cliente');
          return DefaultFirebaseOptions.android;
        }
      } catch (e) {
        debugPrint('[FirebaseBootstrap] PackageInfo falló, uso android cliente: $e');
      }
      return DefaultFirebaseOptions.android;
    }
    return DefaultFirebaseOptions.currentPlatform;
  }

  static Future<void> _initLocked() async {
    if (_didInit) return;

    final FirebaseOptions options = await _optionsForPlatform();

    if (Firebase.apps.isNotEmpty) {
      final FirebaseApp app = Firebase.app();
      if (app.options.appId != options.appId) {
        debugPrint(
          '[FirebaseBootstrap] appId incorrecto actual=${app.options.appId} '
          'esperado=${options.appId} → reinicializando',
        );
        try {
          await app.delete();
        } catch (e) {
          debugPrint('[FirebaseBootstrap] no se pudo borrar app previa: $e');
        }
        await Firebase.initializeApp(options: options);
      } else {
        debugPrint(
          '[FirebaseBootstrap] app ok appId=${app.options.appId} '
          'bucket=${app.options.storageBucket}',
        );
      }
      await _configureFirestoreForScale();
      _didInit = true;
      return;
    }

    try {
      await Firebase.initializeApp(options: options);
      debugPrint(
        '[FirebaseBootstrap] init appId=${options.appId} '
        'bucket=${options.storageBucket}',
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
