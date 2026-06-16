// Puente gira/pool deep link → tab Experiencias en [ClienteShell] (sin importar pool_deep_link).

/// Coordinación deep link gira → tab Experiencias (navigator anidado del shell).
class ClientePoolDeepLinkBridge {
  ClientePoolDeepLinkBridge._();

  static String? _pendingPoolId;

  static bool Function()? _isShellReady;
  static void Function(String poolId)? _openInShell;

  static void bindShell({
    required bool Function() isReady,
    required void Function(String poolId) openPool,
  }) {
    _isShellReady = isReady;
    _openInShell = openPool;
    _flushPending();
  }

  static void unbindShell() {
    _isShellReady = null;
    _openInShell = null;
  }

  /// Encola id desde [PoolDeepLink] (persiste hasta que el shell abra la gira).
  static void enqueuePoolId(String poolId) {
    final String id = poolId.trim();
    if (id.isEmpty) return;
    _pendingPoolId = id;
  }

  /// Devuelve `true` si el shell abrió la gira en el tab Experiencias.
  static bool tryOpenPool(String poolId) {
    final String id = poolId.trim();
    if (id.isEmpty) return false;

    if (_isShellReady?.call() == true && _openInShell != null) {
      _openInShell!(id);
      _pendingPoolId = null;
      return true;
    }

    _pendingPoolId = id;
    return false;
  }

  static void notifyShellBecameReady() {
    _flushPending();
  }

  static void _flushPending() {
    final String? id = _pendingPoolId;
    if (id == null || id.isEmpty) return;
    if (_isShellReady?.call() == true && _openInShell != null) {
      _openInShell!(id);
      _pendingPoolId = null;
    }
  }

  static void clearPending() {
    _pendingPoolId = null;
  }
}
