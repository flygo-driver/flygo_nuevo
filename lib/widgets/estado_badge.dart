// lib/widgets/estado_badge.dart
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';

class EstadoBadge extends StatelessWidget {
  /// Estado del viaje (puede venir crudo; lo normalizamos adentro)
  final String estado;

  /// Padding interno del badge
  final EdgeInsetsGeometry padding;

  /// Tamaño de la tipografía
  final double fontSize;

  const EstadoBadge({
    super.key,
    required this.estado,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    final norm = EstadosViaje.normalizar(estado);
    final label = EstadosViaje.descripcion(norm);
    final (bg, fg, ic) = _colorsFor(norm);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        // Reemplazo de withOpacity(.25) -> withValues(alpha: 0.25)
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ic, size: fontSize + 4, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: fontSize,
              letterSpacing: .2,
            ),
          ),
        ],
      ),
    );
  }

  /// Paleta básica por estado (tema oscuro)
  (Color bg, Color fg, IconData icon) _colorsFor(String e) {
    switch (e) {
      case EstadosViaje.pendiente:
      case EstadosViaje.pendientePago:
        return (const Color(0xFF1E2530), const Color(0xFF7FB8FF), Icons.hourglass_bottom);

      case EstadosViaje.aceptado:
        return (const Color(0xFF17261B), const Color(0xFF7CE9A4), Icons.check_circle_outline);

      case EstadosViaje.enCaminoPickup:
        return (const Color(0xFF16251B), const Color(0xFF6FE9B9), Icons.directions_car);

      case EstadosViaje.aBordo:
        return (const Color(0xFF201B26), const Color(0xFFD2A8FF), Icons.event_seat);

      case EstadosViaje.enCurso:
        return (const Color(0xFF231B12), const Color(0xFFFFD68A), Icons.route);

      case EstadosViaje.completado:
        return (const Color(0xFF162116), const Color(0xFF81E18A), Icons.flag);

      case EstadosViaje.cancelado:
        return (const Color(0xFF2A1616), const Color(0xFFFF9AA2), Icons.cancel_outlined);

      case EstadosViaje.rechazado:
        return (const Color(0xFF2A1D16), const Color(0xFFFFC58A), Icons.block);

      default:
        return (const Color(0xFF1E1E1E), const Color(0xFFBDBDBD), Icons.help_outline);
    }
  }
}
