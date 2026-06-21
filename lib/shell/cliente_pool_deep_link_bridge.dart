// Puente gira/pool deep link → tab Experiencias en [ClienteShell] (sin importar pool_deep_link).

/// Coordinación deep link gira → tab Experiencias (navigator anidado del shell).
class ClientePoolDeepLinkBridge {
  ClientePoolDeepLinkBridge._();

  static String? _pendingPoolId;
  static String? _navigatingPoolId;

  static bool Function()? _isShellReady;
  static void Function(String poolId)? _openInShell;
  static void Function(String poolId)? _onNavigationComplete;

  static void bindShell({
    required bool Function() isReady,
    required void Function(String poolId) openPool,
    void Function(String poolId)? onNavigationComplete,
  }) {
    _isShellReady = isReady;
    _openInShell = openPool;
    _onNavigationComplete = onNavigationComplete;
    _flushPending();
  }

  static void unbindShell() {
    _isShellReady = null;
    _openInShell = null;
    _onNavigationComplete = null;
    _navigatingPoolId = null;
  }

  /// Encola id desde [PoolDeepLink] (persiste hasta que el shell abra la gira).
  static void enqueuePoolId(String poolId) {
    final String id = poolId.trim();
    if (id.isEmpty) return;
    _pendingPoolId = id;
  }

  /// Inicia navegación si el shell está listo. `true` solo tras [markNavigationComplete].
  static bool tryOpenPool(String poolId) {
    final String id = poolId.trim();
    if (id.isEmpty) return false;

    if (_isShellReady?.call() == true && _openInShell != null) {
      if (_navigatingPoolId != id) {
        _navigatingPoolId = id;
        _openInShell!(id);
      }
      return false;
    }

    _pendingPoolId = id;
    return false;
  }

  /// Llamar cuando [PoolsClienteDetalle] quedó en el stack del tab Experiencias.
  static void markNavigationComplete(String poolId) {
    final String id = poolId.trim();
    if (id.isEmpty) return;
    _pendingPoolId = null;
    _navigatingPoolId = null;
    _onNavigationComplete?.call(id);
  }

  static void notifyShellBecameReady() {
    _flushPending();
  }

  static void _flushPending() {
    final String? id = _pendingPoolId;
    if (id == null || id.isEmpty) return;
    tryOpenPool(id);
  }

  static void clearPending() {
    _pendingPoolId = null;
    _navigatingPoolId = null;
  }
}
