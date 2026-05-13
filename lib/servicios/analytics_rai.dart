import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Eventos de embudo (sin PII). Falla de forma silenciosa si Analytics no está disponible.
class AnalyticsRai {
  AnalyticsRai._();

  static FirebaseAnalytics? _a;

  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      _a = FirebaseAnalytics.instance;
      await _a!.setAnalyticsCollectionEnabled(true);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AnalyticsRai] init omitido: $e');
      }
      _a = null;
    }
  }

  /// Nombres ≤ 40 caracteres, [a-zA-Z0-9_].
  static Future<void> logFunnel(
    String name, {
    Map<String, Object>? params,
  }) async {
    final analytics = _a;
    if (analytics == null) return;
    final safe = _sanitizeEventName(name);
    try {
      await analytics.logEvent(
        name: safe,
        parameters: params == null || params.isEmpty ? null : params,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AnalyticsRai] logEvent $safe: $e');
      }
    }
  }

  static String _sanitizeEventName(String raw) {
    final s = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (s.length <= 40) return s.isEmpty ? 'rai_event' : s;
    return s.substring(0, 40);
  }

  // ── Embudo principal ([FirebaseAnalytics.instance.logEvent], sin PII) ──

  static Future<void> _logStd(String name) async {
    try {
      await FirebaseAnalytics.instance.logEvent(name: name);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AnalyticsRai] $name: $e');
      }
    }
  }

  static Future<void> logTripRequested() => _logStd('trip_requested');

  static Future<void> logTripAccepted() => _logStd('trip_accepted');

  static Future<void> logTripStarted() => _logStd('trip_started');

  static Future<void> logTripCompleted() => _logStd('trip_completed');

  static Future<void> logRechargeRequested() => _logStd('recharge_requested');

  static Future<void> logRechargeApproved() => _logStd('recharge_approved');

  // ── Giras por cupos (viajes_pool) ──

  static Future<void> logGiraCreated({
    required double comisionEstimada,
    required int capacidad,
    required double precioPorAsiento,
  }) =>
      logFunnel(
        'gira_created',
        params: <String, Object>{
          'comision_estimada': comisionEstimada.round(),
          'capacidad': capacidad,
          'precio': precioPorAsiento.round(),
        },
      );

  static Future<void> logGiraStarted({
    required int asientosReales,
    required double comisionReal,
  }) =>
      logFunnel(
        'gira_started',
        params: <String, Object>{
          'asientos_reales': asientosReales,
          'comision_real': comisionReal.round(),
        },
      );

  static Future<void> logGiraCanceled({
    required String motivo,
    required double comisionDevuelta,
  }) =>
      logFunnel(
        'gira_canceled',
        params: <String, Object>{
          'motivo': motivo.length > 99 ? motivo.substring(0, 99) : motivo,
          'comision_devuelta': comisionDevuelta.round(),
        },
      );

  static Future<void> logGiraCompleted() => logFunnel('gira_completed');
}
