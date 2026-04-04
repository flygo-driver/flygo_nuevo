import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/servicios_extras/pools_cliente_detalle.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/pool_share_link.dart';

/// Registra `raidriver://pool?id=...` y `https://flygo-rd.web.app/pool?id=...` → [PoolsClienteDetalle].
class PoolDeepLink {
  PoolDeepLink._();

  static final AppLinks _appLinks = AppLinks();
  static StreamSubscription<Uri>? _sub;

  static Future<void> install() async {
    await dispose();
    try {
      final Uri? initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _scheduleOpen(initial);
      }
      _sub = _appLinks.uriLinkStream.listen(_scheduleOpen);
    } catch (_) {
      // Web u otras plataformas sin plugin completo
    }
  }

  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  static void _scheduleOpen(Uri uri) {
    final String? id = PoolShareLink.parsePoolId(uri);
    if (id == null || id.isEmpty) return;

    void tryPush() {
      final NavigatorState? nav = NavigationService.navigatorKey.currentState;
      if (nav == null) return;
      nav.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PoolsClienteDetalle(poolId: id),
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 500), tryPush);
    });
  }
}
