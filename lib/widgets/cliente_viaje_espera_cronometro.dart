import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';

enum ClienteViajeEsperaCronometroModo {
  busquedaConductor,
  conductorEnCamino,
}

/// Resuelve marcas de tiempo del viaje en Firestore (solo lectura).
class ViajeEsperaTiempoResolver {
  ViajeEsperaTiempoResolver._();

  static DateTime inicioBusqueda(Map<String, dynamic>? data) {
    for (final String key in ['creadoEn', 'createdAt', 'fechaCreacion']) {
      final DateTime? d = _ts(data?[key]);
      if (d != null) return d;
    }
    return DateTime.now();
  }

  static DateTime inicioConductor(Map<String, dynamic>? data) {
    for (final String key in ['aceptadoEn', 'aceptado_en']) {
      final DateTime? d = _ts(data?[key]);
      if (d != null) return d;
    }
    return inicioBusqueda(data);
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) {
      final DateTime d = v.toDate();
      if (d.isAfter(DateTime(2020))) return d;
    }
    return null;
  }
}

/// Cronómetro visual de espera (solo UI; no altera lógica del viaje).
class ClienteViajeEsperaCronometro extends StatefulWidget {
  const ClienteViajeEsperaCronometro({
    super.key,
    required this.inicio,
    required this.modo,
    this.compacto = false,
    this.mostrarEnVivo = true,
  });

  final DateTime inicio;
  final ClienteViajeEsperaCronometroModo modo;
  final bool compacto;
  final bool mostrarEnVivo;

  @override
  State<ClienteViajeEsperaCronometro> createState() =>
      _ClienteViajeEsperaCronometroState();
}

class _ClienteViajeEsperaCronometroState
    extends State<ClienteViajeEsperaCronometro>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  late final AnimationController _pulsoCtrl;
  Duration _transcurrido = Duration.zero;

  static const Color _acento = RaiDsColors.gold;

  @override
  void initState() {
    super.initState();
    _pulsoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant ClienteViajeEsperaCronometro oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inicio != widget.inicio) _tick();
  }

  void _tick() {
    if (!mounted) return;
    final Duration d = DateTime.now().difference(widget.inicio);
    if (d != _transcurrido) {
      setState(() => _transcurrido = d.isNegative ? Duration.zero : d);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulsoCtrl.dispose();
    super.dispose();
  }

  String get _etiqueta {
    switch (widget.modo) {
      case ClienteViajeEsperaCronometroModo.busquedaConductor:
        return 'Tiempo buscando conductor';
      case ClienteViajeEsperaCronometroModo.conductorEnCamino:
        return 'Tu conductor viene hacia ti';
    }
  }

  String get _subtitulo {
    switch (widget.modo) {
      case ClienteViajeEsperaCronometroModo.busquedaConductor:
        return 'Seguimos notificando conductores en tiempo real';
      case ClienteViajeEsperaCronometroModo.conductorEnCamino:
        return 'Sigue su recorrido en el mapa en vivo';
    }
  }

  String _formato(Duration d) {
    final int h = d.inHours;
    final int m = d.inMinutes.remainder(60);
    final int s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compacto) {
      return _buildCompacto();
    }
    return _buildFlotante();
  }

  Widget _buildCompacto() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _acento.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          _indicadorEnVivo(size: 8),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _etiqueta,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            _formato(_transcurrido),
            style: const TextStyle(
              color: _acento,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlotante() {
    return AnimatedBuilder(
      animation: _pulsoCtrl,
      builder: (context, child) {
        final double t = _pulsoCtrl.value;
        final double glow = 0.35 + (0.25 * math.sin(t * 2 * math.pi)).abs();
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _acento.withValues(alpha: 0.14 + (0.12 * glow)),
                blurRadius: 14 + (6 * glow),
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _acento.withValues(alpha: 0.42)),
        ),
        child: Row(
          children: [
            _relojCircular(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (widget.mostrarEnVivo) ...[
                        _indicadorEnVivo(size: 7),
                        const SizedBox(width: 6),
                        Text(
                          'EN VIVO',
                          style: TextStyle(
                            color: Colors.greenAccent.withValues(alpha: 0.9),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          _etiqueta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _formato(_transcurrido),
              style: const TextStyle(
                color: _acento,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
                letterSpacing: 1,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _relojCircular() {
    return AnimatedBuilder(
      animation: _pulsoCtrl,
      builder: (context, _) {
        final double t = _pulsoCtrl.value;
        final double ring = 0.5 + (0.5 * math.sin(t * 2 * math.pi)).abs();
        return Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _acento.withValues(alpha: 0.12 + (0.08 * ring)),
            border: Border.all(
              color: _acento.withValues(alpha: 0.45 + (0.35 * ring)),
              width: 1.4,
            ),
          ),
          child: const Icon(
            Icons.timer_outlined,
            color: _acento,
            size: 22,
          ),
        );
      },
    );
  }

  Widget _indicadorEnVivo({required double size}) {
    return AnimatedBuilder(
      animation: _pulsoCtrl,
      builder: (context, _) {
        final double t = _pulsoCtrl.value;
        final double a = 0.55 + (0.45 * math.sin(t * 2 * math.pi)).abs();
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.greenAccent.withValues(alpha: a),
            boxShadow: [
              BoxShadow(
                color: Colors.greenAccent.withValues(alpha: 0.35 * a),
                blurRadius: 4,
              ),
            ],
          ),
        );
      },
    );
  }
}
