// lib/servicios/notification_service.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Notificaciones locales con sonido + anti-spam (dedupe + debounce).
/// Requisitos:
/// - Coloca el audio en: android/app/src/main/res/raw/flygo_tone_05_glass_14s.wav  (minúsculas)
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

  // 🔔 Canal Android (CAMBIA el ID si vuelves a cambiar el sonido)
  static const String _channelId   = 'flygo_offers_v7';
  static const String _channelName = 'Viajes disponibles (FlyGo)';
  static const String _channelDesc = 'Alertas de nuevos viajes con sonido FlyGo';

  // Nombre del recurso RAW (sin extensión)
  static const String _rawSound = 'flygo_tone_05_glass_14s';

  // Preferencias (anti-spam)
  static const String _kSeenIds  = 'notif_seen_ids_v1';
  static const String _kLastTs   = 'notif_last_ts_v1';
  static const int    _debounceSeconds = 8;

  /// Inicializa plugin + canal con el sonido personalizado (idempotente).
  Future<void> ensureInited() async {
    if (_inited) return;

    const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initDarwin  = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: initAndroid, iOS: initDarwin),
    );

    // Canal Android 8+ (con sonido personalizado)
    final android = _plugin
        .resolvePlatformSpecificImplementation<
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

    // ⚠️ Canal por defecto para FCM (debe coincidir con AndroidManifest: taxi_new_rides)
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'taxi_new_rides',
        'Nuevos viajes',
        description: 'Notificaciones de viajes y chat',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    // Android 13+: pedir permiso si el plugin lo expone
    try { await android?.requestNotificationsPermission(); } catch (_) {}

    _inited = true;
  }

  /// Notifica “nuevo viaje” con sonido, evitando duplicados por ID
  /// y limitando frecuencia a 1 cada [_debounceSeconds] segundos.
  Future<void> notifyNuevoViaje({
    required String viajeId,
    required String titulo,
    required String cuerpo,
  }) async {
    await ensureInited();

    final prefs = await SharedPreferences.getInstance();

    // Dedupe por ID
    final ids = prefs.getStringList(_kSeenIds) ?? <String>[];
    if (ids.contains(viajeId)) return;

    // Debounce temporal
    final nowMs  = DateTime.now().millisecondsSinceEpoch;
    final lastMs = prefs.getInt(_kLastTs) ?? 0;
    final diffSec = ((nowMs - lastMs) / 1000).floor();
    if (diffSec < _debounceSeconds) {
      await _markSeen(prefs, ids, viajeId, nowMs);
      return;
    }

    // Android: canal + sonido + estilo BigText
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(_rawSound),
      enableVibration: true,
      styleInformation: BigTextStyleInformation(
        cuerpo,
        contentTitle: titulo,
        summaryText: 'FlyGo',
      ),
      category: AndroidNotificationCategory.event,
      ticker: 'FlyGo',
    );

    // iOS (opcional): si subes el .wav al bundle de iOS/Runner, descomenta "sound"
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
      // sound: 'flygo_tone_05_glass_14s.wav',
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

    await _markSeen(prefs, ids, viajeId, nowMs);
  }

  /// Prueba manual del tono (no hace dedupe).
  Future<void> testOfferSound() async {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    await notifyNuevoViaje(
      viajeId: 'test_$ts',
      titulo: '🔔 Prueba de sonido FlyGo',
      cuerpo: 'Este es el tono FlyGo (canal $_channelId).',
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
