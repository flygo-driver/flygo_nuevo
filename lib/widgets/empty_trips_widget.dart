import 'package:flutter/material.dart';

class EmptyTripsWidget extends StatelessWidget {
  final bool esTabAhora;
  final String? poolModoConductor;

  const EmptyTripsWidget({
    super.key,
    required this.esTabAhora,
    this.poolModoConductor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF111827);
    final textSecondary =
        isDark ? Colors.white.withValues(alpha: 0.62) : const Color(0xFF4B5563);
    final iconColor =
        isDark ? Colors.white.withValues(alpha: 0.45) : const Color(0xFF6B7280);
    final bubbleColor =
        isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE5E7EB);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 280;
        final circleSize = compact ? 84.0 : 96.0;
        final iconSize = compact ? 40.0 : 46.0;
        final titleSize = compact ? 17.0 : 18.0;
        final gapL = compact ? 16.0 : 20.0;
        final gapS = compact ? 8.0 : 10.0;

        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: 28,
            vertical: compact ? 8 : 12,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight > 0
                  ? (constraints.maxHeight - 16).clamp(120.0, double.infinity)
                  : 0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: circleSize,
                  height: circleSize,
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    esTabAhora
                        ? Icons.timer_off_outlined
                        : Icons.event_busy_outlined,
                    size: iconSize,
                    color: iconColor,
                  ),
                ),
                SizedBox(height: gapL),
                Text(
                  _titulo(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: gapS),
                Text(
                  _descripcion(context),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: compact ? 13 : 14,
                    height: 1.35,
                  ),
                ),
                if (!compact) ...[
                  SizedBox(height: gapL),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Text(
                      _chipMotivacional(),
                      style: TextStyle(
                        color: isDark
                            ? Colors.green.shade300
                            : Colors.green.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _titulo() {
    if (poolModoConductor == 'motor') {
      return esTabAhora ? 'No hay motores ahora' : 'No hay motores programados';
    }
    return esTabAhora ? 'No hay viajes ahora' : 'No hay viajes programados aún';
  }

  String _descripcion(BuildContext context) {
    if (poolModoConductor == 'motor') {
      return esTabAhora
          ? 'Cuando un cliente pida motor, aparecerá aquí al instante.'
          : 'Los motores programados se listan aquí cuando estén listos.';
    }
    if (esTabAhora) {
      return 'Taxi y multiparada llegan solos mientras estés disponible.';
    }
    return 'Los programados aparecen aquí unos 45 min antes de la recogida, '
        'cuando ya puedes aceptarlos. Si no ves nada, aún no se liberó ninguno.';
  }

  String _chipMotivacional() {
    if (poolModoConductor == 'motor') {
      return esTabAhora ? 'Listo para motores' : 'Revisa programados';
    }
    return esTabAhora ? 'Mantente disponible' : 'Revisa más cerca de la hora';
  }
}
