import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../servicios/rai_local_read_cache.dart';

/// Muestra aviso **offline** y datos en caché (solo lectura, informativos).
class RaiOfflineBanner extends StatefulWidget {
  const RaiOfflineBanner({super.key, required this.uid});

  final String? uid;

  @override
  State<RaiOfflineBanner> createState() => _RaiOfflineBannerState();
}

class _RaiOfflineBannerState extends State<RaiOfflineBanner> {
  late final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  /// Vacío = aún no hubo lectura fiable: **no** mostrar «sin conexión» (evita flash rojo al abrir).
  List<ConnectivityResult> _results = const <ConnectivityResult>[];
  String? _viajeCache;
  double? _saldoCache;
  Timer? _offlineDebounce;

  bool _sinRed(List<ConnectivityResult> r) {
    if (r.isEmpty) return false;
    return r.every((e) => e == ConnectivityResult.none);
  }

  Future<void> _refrescarCacheSiOffline() async {
    final uid = widget.uid?.trim();
    if (uid == null || uid.isEmpty) return;
    if (!_sinRed(_results)) return;
    final v = await RaiLocalReadCache.lastKnownActiveTripId(uid);
    final s = await RaiLocalReadCache.lastKnownSaldoPrepago(uid);
    if (!mounted) return;
    setState(() {
      _viajeCache = v;
      _saldoCache = s;
    });
  }

  void _onConnectivity(List<ConnectivityResult> r) {
    if (!mounted) return;
    _offlineDebounce?.cancel();
    if (!_sinRed(r)) {
      setState(() => _results = r);
      unawaited(_refrescarCacheSiOffline());
      return;
    }
    // Algunos dispositivos emiten `none` un instante antes de wifi/datos: esperar un poco
    // antes de pintar el banner rojo.
    _offlineDebounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      List<ConnectivityResult> effective = r;
      try {
        effective = await _connectivity.checkConnectivity();
      } catch (_) {
        effective = r;
      }
      if (!mounted) return;
      setState(() => _results = effective);
      unawaited(_refrescarCacheSiOffline());
    });
  }

  Future<void> _bootstrapConnectivity() async {
    try {
      final r = await _connectivity.checkConnectivity();
      _onConnectivity(r);
    } catch (_) {
      // Sin asumir offline: evita banner rojo permanente si el plugin falla al iniciar.
      _onConnectivity(const <ConnectivityResult>[]);
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrapConnectivity());
    _sub = _connectivity.onConnectivityChanged.listen(_onConnectivity);
  }

  @override
  void dispose() {
    _offlineDebounce?.cancel();
    unawaited(_sub?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_sinRed(_results)) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final buf = StringBuffer('Sin conexión · datos en caché');
    final uid = widget.uid?.trim();
    if (uid != null && uid.isNotEmpty) {
      final viaje = (_viajeCache ?? '').trim();
      final saldo = _saldoCache;
      if (viaje.isNotEmpty) {
        buf.write(' · último viaje activo: ');
        buf.write(viaje.length > 12 ? '${viaje.substring(0, 12)}…' : viaje);
      }
      if (saldo != null) {
        buf.write(' · saldo prepago (RD\$): ');
        buf.write(saldo.toStringAsFixed(2));
      }
    }

    return Material(
      color: cs.errorContainer.withValues(alpha: 0.92),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.wifi_off_rounded, color: cs.onErrorContainer, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  buf.toString(),
                  style: TextStyle(
                    color: cs.onErrorContainer,
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
