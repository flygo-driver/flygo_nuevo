// Puente gira/pool deep link → tab Experiencias en [ClienteShell] (sin importar pool_deep_link).

import 'package:flygo_nuevo/servicios/pool_deep_link.dart';

/// Coordinación deep link gira → tab Experiencias (navigator anidado del shell).
class ClientePoolDeepLinkBridge {
  ClientePoolDeepLinkBridge._();

  static String? _pendingPoolId;
  static bool _pendingGirasLista = false;
  static String? _navigatingPoolId;
  static bool _navigatingGirasLista = false;

  static bool Function()? _isShellReady;
  static void Function(String poolId)? _openPoolInShell;
  static void Function()? _openGirasListaInShell;
  static void Function(String poolId)? _onNavigationComplete;

  static void bindShell({
    required bool Function() isReady,
    required void Function(String poolId) openPool,
    required void Function() openGirasLista,
    void Function(String poolId)? onNavigationComplete,
  }) {
    _isShellReady = isReady;
    _openPoolInShell = openPool;
    _openGirasListaInShell = openGirasLista;
    _onNavigationComplete = onNavigationComplete;
    _flushPending();
  }

  static void unbindShell() {
    _isShellReady = null;
    _openPoolInShell = null;
    _openGirasListaInShell = null;
    _onNavigationComplete = null;
    _navigatingPoolId = null;
    _navigatingGirasLista = false;
  }

  static void enqueuePoolId(String poolId) {
    final String id = poolId.trim();
    if (id.isEmpty) return;
    _pendingGirasLista = false;
    _pendingPoolId = id;
  }

  static void enqueueGirasLista() {
    _pendingPoolId = null;
    _pendingGirasLista = true;
  }

  static bool tryOpenPool(String poolId) {
    final String id = poolId.trim();
    if (id.isEmpty) return false;

    if (_isShellReady?.call() == true && _openPoolInShell != null) {
      if (_navigatingPoolId != id) {
        _navigatingPoolId = id;
        _openPoolInShell!(id);
      }
      return false;
    }

    _pendingGirasLista = false;
    _pendingPoolId = id;
    return false;
  }

  static bool tryOpenGirasLista() {
    if (_isShellReady?.call() == true && _openGirasListaInShell != null) {
      if (!_navigatingGirasLista) {
        _navigatingGirasLista = true;
        _openGirasListaInShell!();
      }
      return false;
    }
    _pendingPoolId = null;
    _pendingGirasLista = true;
    return false;
  }

  static void markNavigationComplete(String poolId) {
    final String id = poolId.trim();
    if (id.isEmpty) return;
    _pendingPoolId = null;
    _pendingGirasLista = false;
    _navigatingPoolId = null;
    _navigatingGirasLista = false;
    _onNavigationComplete?.call(id);
  }

  static void markGirasListaNavigationComplete() {
    _pendingPoolId = null;
    _pendingGirasLista = false;
    _navigatingPoolId = null;
    _navigatingGirasLista = false;
    _onNavigationComplete?.call(PoolDeepLink.girasListaMarker);
  }

  static void notifyShellBecameReady() {
    _flushPending();
  }

  static void _flushPending() {
    if (_pendingGirasLista) {
      tryOpenGirasLista();
      return;
    }
    final String? id = _pendingPoolId;
    if (id == null || id.isEmpty) return;
    tryOpenPool(id);
  }

  static void clearPending() {
    _pendingPoolId = null;
    _pendingGirasLista = false;
    _navigatingPoolId = null;
    _navigatingGirasLista = false;
  }
}
