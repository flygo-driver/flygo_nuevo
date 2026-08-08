import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'package:flygo_nuevo/servicios/calificacion_pendiente_service.dart';

/// Estado de red compartido (debounced). No bloquea la UI: solo informa offline/online.
class RaiConnectivityService {
  RaiConnectivityService._();

  static final RaiConnectivityService instance = RaiConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  final ValueNotifier<bool?> offline = ValueNotifier<bool?>(null);

  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _debounce;
  bool _started = false;

  bool get isOffline => offline.value == true;
  bool get isOnline => offline.value == false;
  bool get isKnown => offline.value != null;

  void ensureStarted() {
    if (_started) return;
    _started = true;
    unawaited(_bootstrap());
    _sub = _connectivity.onConnectivityChanged.listen(_onResults);
  }

  static bool _sinRed(List<ConnectivityResult> r) {
    if (r.isEmpty) return false;
    return r.every((e) => e == ConnectivityResult.none);
  }

  Future<void> _bootstrap() async {
    try {
      final r = await _connectivity.checkConnectivity();
      _applyResults(r);
    } catch (_) {
      _applyResults(const <ConnectivityResult>[]);
    }
  }

  void _onResults(List<ConnectivityResult> r) {
    _debounce?.cancel();
    if (!_sinRed(r)) {
      offline.value = false;
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      List<ConnectivityResult> effective = r;
      try {
        effective = await _connectivity.checkConnectivity();
      } catch (_) {
        effective = r;
      }
      _applyResults(effective);
    });
  }

  void _applyResults(List<ConnectivityResult> r) {
    if (r.isEmpty) return;
    final bool sinRed = _sinRed(r);
    final bool estabaOffline = offline.value == true;
    offline.value = sinRed;
    if (estabaOffline && !sinRed) {
      unawaited(CalificacionPendienteService.flushPendientes());
    }
  }

  @visibleForTesting
  void disposeForTest() {
    _debounce?.cancel();
    unawaited(_sub?.cancel());
    _sub = null;
    _started = false;
    offline.value = null;
  }
}
