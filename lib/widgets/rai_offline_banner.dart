import 'dart:async';

import 'package:flutter/material.dart';

import '../servicios/rai_connectivity_service.dart';
import '../servicios/rai_local_read_cache.dart';

/// Aviso no bloqueante: «No tienes internet». La app sigue usable (Firestore caché / UI local).
class RaiOfflineBanner extends StatefulWidget {
  const RaiOfflineBanner({super.key, required this.uid});

  final String? uid;

  @override
  State<RaiOfflineBanner> createState() => _RaiOfflineBannerState();
}

class _RaiOfflineBannerState extends State<RaiOfflineBanner> {
  String? _viajeCache;
  double? _saldoCache;

  @override
  void initState() {
    super.initState();
    RaiConnectivityService.instance.ensureStarted();
    RaiConnectivityService.instance.offline.addListener(_onOfflineChanged);
    _onOfflineChanged();
  }

  @override
  void dispose() {
    RaiConnectivityService.instance.offline.removeListener(_onOfflineChanged);
    super.dispose();
  }

  void _onOfflineChanged() {
    if (!mounted) return;
    if (RaiConnectivityService.instance.isOffline) {
      unawaited(_refrescarCache());
    }
    setState(() {});
  }

  Future<void> _refrescarCache() async {
    final uid = widget.uid?.trim();
    if (uid == null || uid.isEmpty) return;
    final v = await RaiLocalReadCache.lastKnownActiveTripId(uid);
    final s = await RaiLocalReadCache.lastKnownSaldoPrepago(uid);
    if (!mounted) return;
    setState(() {
      _viajeCache = v;
      _saldoCache = s;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!RaiConnectivityService.instance.isOffline) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final uid = widget.uid?.trim();

    final String detalleCache;
    if (uid != null && uid.isNotEmpty) {
      final parts = <String>[];
      final viaje = (_viajeCache ?? '').trim();
      if (viaje.isNotEmpty) {
        parts.add(
          'último viaje: ${viaje.length > 12 ? '${viaje.substring(0, 12)}…' : viaje}',
        );
      }
      if (_saldoCache != null) {
        parts.add('saldo prepago RD\$ ${_saldoCache!.toStringAsFixed(2)}');
      }
      detalleCache = parts.isEmpty
          ? 'Puedes seguir navegando con datos guardados.'
          : '${parts.join(' · ')}.';
    } else {
      detalleCache = 'Puedes seguir navegando con datos guardados.';
    }

    return Material(
      color: cs.errorContainer.withValues(alpha: 0.94),
      elevation: 2,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.wifi_off_rounded, color: cs.onErrorContainer, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No tienes internet',
                      style: TextStyle(
                        color: cs.onErrorContainer,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'La app sigue abierta. Las acciones en línea se actualizarán cuando vuelva la conexión.',
                      style: TextStyle(
                        color: cs.onErrorContainer.withValues(alpha: 0.92),
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                    if (detalleCache.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        detalleCache,
                        style: TextStyle(
                          color: cs.onErrorContainer.withValues(alpha: 0.85),
                          fontSize: 11,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
