import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';

/// Reloj en vivo hasta la próxima recogida en empresa (rutas corporativas chofer).
class CorporativoRecogidaCountdown extends StatefulWidget {
  const CorporativoRecogidaCountdown({
    super.key,
    this.horaHHmm,
    this.viajeData,
    this.completadaHoy = false,
    this.compact = false,
    this.permitirAhora = true,
  });

  final String? horaHHmm;
  final Map<String, dynamic>? viajeData;
  final bool completadaHoy;
  final bool compact;
  /// Si es false, no muestra «¡AHORA!» aunque la hora ya pasó (p. ej. recogida perdida).
  final bool permitirAhora;

  @override
  State<CorporativoRecogidaCountdown> createState() =>
      _CorporativoRecogidaCountdownState();
}

class _CorporativoRecogidaCountdownState
    extends State<CorporativoRecogidaCountdown> {
  Timer? _timer;
  DateTime? _target;

  @override
  void initState() {
    super.initState();
    _target = _resolverTarget();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _target = _resolverTarget());
    });
  }

  @override
  void didUpdateWidget(CorporativoRecogidaCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.horaHHmm != widget.horaHHmm ||
        oldWidget.completadaHoy != widget.completadaHoy ||
        oldWidget.permitirAhora != widget.permitirAhora ||
        oldWidget.viajeData != widget.viajeData) {
      _target = _resolverTarget();
    }
  }

  DateTime? _resolverTarget() {
    final viaje = widget.viajeData;
    if (viaje != null && viaje.isNotEmpty) {
      final rec = CorporativoTaxistaService.recogidaOperativaCorporativo(viaje);
      if (rec.millisecondsSinceEpoch > 0) {
        if (widget.completadaHoy) {
          return rec.add(const Duration(days: 1));
        }
        final now = DateTime.now();
        if (rec.isAfter(now)) return rec;
        if (now.difference(rec).inHours <= 3) return rec;
        return DateTime(now.year, now.month, now.day)
            .add(const Duration(days: 1))
            .add(Duration(hours: rec.hour, minutes: rec.minute));
      }
    }
    final hora = (widget.horaHHmm ?? '').trim();
    if (hora.isEmpty) return null;
    return CorporativoTaxistaService.proximaRecogidaDesdeHora(
      hora,
      completadaHoy: widget.completadaHoy,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    if (target == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final diff = target.difference(now);
    final bool enRecogida =
        diff.isNegative && diff.inMinutes > -180 && widget.permitirAhora;
    final bool manana = widget.completadaHoy || diff.inHours > 20;

    Color fg;
    Color bg;
    String etiqueta;
    String reloj;

    if (enRecogida) {
      fg = const Color(0xFF22C55E);
      bg = fg.withValues(alpha: 0.14);
      etiqueta = 'Recogida';
      reloj = '¡AHORA!';
    } else if (diff.isNegative) {
      if (!widget.permitirAhora) {
        fg = const Color(0xFFEF4444);
        bg = fg.withValues(alpha: 0.14);
        etiqueta = 'Recogida';
        reloj = 'Pasó';
      } else {
        fg = Colors.white70;
        bg = Colors.white.withValues(alpha: 0.06);
        etiqueta = manana ? 'Próxima' : 'Recogida';
        reloj = _fmtDuracion(diff.abs());
      }
    } else {
      final min = diff.inMinutes;
      if (min <= 30) {
        fg = const Color(0xFFEF4444);
      } else if (min <= 90) {
        fg = const Color(0xFFF59E0B);
      } else {
        fg = const Color(0xFF22C55E);
      }
      bg = fg.withValues(alpha: 0.14);
      etiqueta = manana ? 'Mañana en' : 'Falta';
      reloj = _fmtDuracion(diff);
    }

    final fontSize = widget.compact ? 15.0 : 18.0;
    final labelSize = widget.compact ? 9.0 : 10.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 8 : 10,
        vertical: widget.compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withValues(alpha: 0.45)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            etiqueta.toUpperCase(),
            style: TextStyle(
              color: fg.withValues(alpha: 0.85),
              fontSize: labelSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            reloj,
            style: TextStyle(
              color: fg,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDuracion(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }
}
