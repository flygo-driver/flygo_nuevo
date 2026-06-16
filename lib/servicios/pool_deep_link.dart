import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flygo_nuevo/app_flavor.dart';
import 'package:flygo_nuevo/shell/cliente_pool_deep_link_bridge.dart';
import 'package:flygo_nuevo/servicios/pool_share_link.dart';

import 'pool_deep_link_uri_stub.dart'
    if (dart.library.html) 'pool_deep_link_uri_web.dart';

/// Registra `raidriver://pool?id=...` y `https://flygo-rd.web.app/pool?id=...`
/// → detalle gira en tab **Experiencias** del [ClienteShell] (RAI Pasajero).
class PoolDeepLink {
  PoolDeepLink._();

  static final AppLinks _appLinks = AppLinks();
  static StreamSubscription<Uri>? _sub;
  static Timer? _pendingRetryTimer;

  static String? _pendingPoolId;
  static int _openGeneration = 0;

  /// Evita doble push si llegan initialLink + uriLinkStream casi a la vez.
  static String? _lastOpenedPoolId;
  static DateTime? _lastOpenedAt;

  /// Mensaje para mostrar en shell conductor si abren link de pasajero.
  static String? consumeConductorDeepLinkHint() {
    final m = _conductorDeepLinkHint;
    _conductorDeepLinkHint = null;
    return m;
  }

  static String? _conductorDeepLinkHint;

  static const List<int> _retryDelaysMs = <int>[
    0,
    150,
    400,
    700,
    1200,
    2000,
    3500,
    5000,
    8000,
    12000,
    18000,
    25000,
    30000,
  ];

  static const Duration _pendingPollInterval = Duration(milliseconds: 600);
  static const Duration _pendingMaxWait = Duration(seconds: 45);

  static Future<void> install() async {
    await dispose();
    _schedulePendingPoll();

    if (kIsWeb) {
      final Uri? webUri = poolDeepLinkUriFromPlatform();
      if (webUri != null) {
        _enqueueOpen(webUri);
      }
    }

    if (kIsWeb) return;

    try {
      final Uri? initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _enqueueOpen(initial);
      }
      _sub = _appLinks.uriLinkStream.listen(_enqueueOpen);
    } catch (_) {
      // Plataformas sin plugin completo
    }
  }

  static void _schedulePendingPoll() {
    _pendingRetryTimer?.cancel();
    final DateTime deadline = DateTime.now().add(_pendingMaxWait);
    _pendingRetryTimer = Timer.periodic(_pendingPollInterval, (Timer t) {
      if (DateTime.now().isAfter(deadline)) {
        t.cancel();
        _pendingRetryTimer = null;
        return;
      }
      if (_pendingPoolId == null || _pendingPoolId!.isEmpty) {
        t.cancel();
        _pendingRetryTimer = null;
        return;
      }
      _tryOpenPending();
    });
  }

  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _pendingRetryTimer?.cancel();
    _pendingRetryTimer = null;
    _pendingPoolId = null;
    ClientePoolDeepLinkBridge.clearPending();
  }

  /// Llamar cuando [ClienteShell] ya está montado (p. ej. tras login).
  static void notifyClienteShellReady() {
    ClientePoolDeepLinkBridge.notifyShellBecameReady();
    if (_pendingPoolId != null && _pendingPoolId!.isNotEmpty) {
      _tryOpenPending();
    }
  }

  static void _enqueueOpen(Uri uri) {
    final String? id = PoolShareLink.parsePoolId(uri);
    if (id == null || id.isEmpty) return;

    if (!isClienteFlavor) {
      if (isConductorFlavor) {
        _conductorDeepLinkHint =
            'Este enlace es para pasajeros. Abrilo con RAI Pasajero (Google Play) '
            'para ver la gira y reservar cupos.';
      }
      return;
    }

    _pendingPoolId = id;
    _openGeneration++;
    final int generation = _openGeneration;
    ClientePoolDeepLinkBridge.enqueuePoolId(id);

    for (final int delayMs in _retryDelaysMs) {
      Future<void>.delayed(Duration(milliseconds: delayMs), () {
        if (generation != _openGeneration) return;
        _tryOpenPending();
      });
    }
  }

  static void _tryOpenPending() {
    final String? id = _pendingPoolId;
    if (id == null || id.isEmpty) return;

    final DateTime now = DateTime.now();
    if (_lastOpenedPoolId == id &&
        _lastOpenedAt != null &&
        now.difference(_lastOpenedAt!) < const Duration(seconds: 2)) {
      return;
    }

    if (!ClientePoolDeepLinkBridge.tryOpenPool(id)) {
      return;
    }

    _pendingPoolId = null;
    _lastOpenedPoolId = id;
    _lastOpenedAt = now;
    _pendingRetryTimer?.cancel();
    _pendingRetryTimer = null;
  }
}
