// lib/servicios/notification_service.dart
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Notificaciones locales con sonido + anti-spam (dedupe + debounce).
/// Requisitos:
/// - android/app/src/main/res/raw/notification.wav (minúsculas; mismo audio que assets/sounds/)
/// - Android 13+: permiso POST_NOTIFICATIONS en el Manifest.
/// Uso:
///   await NotificationService.I.ensureInited();
///   await NotificationService.I.notifyNuevoViaje(
///     viajeId: 'abc123',
///     titulo: 'Nuevo viaje disponible',
///     cuerpo: 'AILA → Bonao • RD$ 4,436.40',
///   );
class NotificationService {
  NotificationService._();
  static final NotificationService I = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inited = false;
  AudioPlayer? _timbrePlayer;

  // 🔔 CANALES ANDROID ACTUALIZADOS (SIN RASTRO DE FLYGO)
  static const String _channelId = 'rai_driver_offers_v1'; // ✅ NUEVO ID
  static const String _channelName = 'Viajes disponibles'; // ✅ SIN FlyGo
  static const String _channelDesc = 'Alertas de nuevos viajes'; // ✅ SIN FlyGo

  /// Requisitos:
  /// - Coloca el audio en: android/app/src/main/res/raw/notification.wav  (minúsculas)
  static const String _rawSound = 'notification';

  // Preferencias (anti-spam)
  static const String _kSeenIds = 'notif_seen_ids_v1';
  static const String _kLastTs = 'notif_last_ts_v1';
  static const int _debounceSeconds = 8;

  /// Inicializa plugin + canal con el sonido personalizado (idempotente).
  /// 🔐 Blindado con try/catch para que NUNCA tumbe el arranque de la app.
  Future<void> ensureInited() async {
    if (_inited) return;

    try {
      const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initDarwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      await _plugin.initialize(
        const InitializationSettings(android: initAndroid, iOS: initDarwin),
      );

      // Canal Android 8+ (con sonido personalizado) - ACTUALIZADO
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(_rawSound),
          enableVibration: true,
        ),
      );

      // ⚠️ Canal por defecto para FCM - ACTUALIZADO para coincidir con AndroidManifest
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          'rai_driver_notifications', // ✅ Debe coincidir con AndroidManifest
          'RAI Driver', // ✅ Nombre visible
          description: 'Notificaciones de viajes y chat',
          importance: Importance.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(_rawSound),
          enableVibration: true,
        ),
      );

      // Android 13+: pedir permiso si el plugin lo expone
      try {
        await android?.requestNotificationsPermission();
      } catch (_) {
        // ignoramos fallo de permiso
      }

      _inited = true;
    } catch (e, st) {
      debugPrint('Error inicializando NotificationService: $e');
      debugPrint(st.toString());
      // Aunque falle, marcamos como inited para no intentar en bucle
      _inited = true;
    }
  }

  /// Timbre inmediato (app abierta) con el mismo WAV que el canal Android.
  Future<void> _playTimbreAsset() async {
    try {
      _timbrePlayer ??= AudioPlayer();
      await _timbrePlayer!.stop();
      await _timbrePlayer!.setReleaseMode(ReleaseMode.stop);
      // El asset está declarado en pubspec.yaml como `assets/sounds/notification.wav`.
      await _timbrePlayer!.play(
        AssetSource('assets/sounds/notification.wav'),
      );
    } catch (e, st) {
      debugPrint('Error timbre in-app: $e');
      debugPrint(st.toString());
    }
  }

  /// Detiene cualquier timbre in-app en reproducción.
  Future<void> stopTimbre() async {
    try {
      await _timbrePlayer?.stop();
    } catch (_) {}
  }

  /// Timbre inmediato para el pool con la pantalla abierta: **no** usa el dedupe
  /// global de SharedPreferences (ese dedupe silenciaba el sonido si el ID ya
  /// había sido notificado antes). La pantalla [ViajeDisponible] evita repeticiones
  /// con `_vistosParaTimbre`.
  Future<void> playPoolOfferSoundInApp() async {
    try {
      await ensureInited();
      await _playTimbreAsset();
    } catch (e, st) {
      debugPrint('playPoolOfferSoundInApp: $e');
      debugPrint(st.toString());
    }
  }

  /// Notifica “nuevo viaje” con sonido, evitando duplicados por ID
  /// y limitando frecuencia a 1 cada [_debounceSeconds] segundos.
  ///
  /// [skipSound]: si es true, no reproduce WAV aquí (p. ej. ya sonó con
  /// [playPoolOfferSoundInApp] en el pool con la pantalla abierta).
  Future<void> notifyNuevoViaje({
    required String viajeId,
    required String titulo,
    required String cuerpo,
    bool skipSound = false,
  }) async {
    await ensureInited();

    final prefs = await SharedPreferences.getInstance();

    // Dedupe por ID
    final ids = prefs.getStringList(_kSeenIds) ?? <String>[];
    if (ids.contains(viajeId)) return;

    // Timbre al instante (primer plano); el debounce solo limita la tarjeta en bandeja.
    if (!skipSound) {
      await _playTimbreAsset();
    }

    // Debounce temporal (solo notificación visual; el sonido ya sonó arriba)
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastMs = prefs.getInt(_kLastTs) ?? 0;
    final diffSec = ((nowMs - lastMs) / 1000).floor();
    if (diffSec < _debounceSeconds) {
      await _markSeen(prefs, ids, viajeId, nowMs);
      return;
    }

    try {
      // Android: sin playSound en la notificación para no duplicar el timbre asset.
      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        playSound: false,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(
          cuerpo,
          contentTitle: titulo,
          summaryText: 'RAI Driver', // ✅ ANTES: 'FlyGo' → AHORA: 'RAI Driver'
        ),
        category: AndroidNotificationCategory.event,
        ticker: 'RAI Driver', // ✅ ANTES: 'FlyGo' → AHORA: 'RAI Driver'
      );

      // iOS: sin sonido del sistema (ya va por asset); alerta sí.
      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      // ID estable por viaje
      final notifId = viajeId.hashCode & 0x7fffffff;

      await _plugin.show(
        notifId,
        titulo,
        cuerpo,
        details,
        payload: viajeId,
      );
    } catch (e, st) {
      debugPrint('Error mostrando notificación local: $e');
      debugPrint(st.toString());
    }

    await _markSeen(prefs, ids, viajeId, nowMs);
  }

  /// Prueba manual del tono (no hace dedupe).
  Future<void> testOfferSound() async {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    await notifyNuevoViaje(
      viajeId: 'test_$ts',
      titulo: '🔔 Prueba de sonido RAI Driver', // ✅ Actualizado
      cuerpo:
          'Este es el tono RAI Driver (canal $_channelId).', // ✅ Actualizado
    );
  }

  /// Limpia cache de IDs vistos (útil en QA).
  Future<void> clearSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSeenIds);
    await prefs.remove(_kLastTs);
  }

  // ---- Helpers ----
  Future<void> _markSeen(
    SharedPreferences prefs,
    List<String> ids,
    String viajeId,
    int nowMs,
  ) async {
    ids.add(viajeId);
    // limite a 200 entradas
    if (ids.length > 200) {
      ids.removeRange(0, ids.length - 200);
    }
    await prefs.setStringList(_kSeenIds, ids);
    await prefs.setInt(_kLastTs, nowMs);
  }
}
