import 'package:flutter/material.dart';

/// Encabezado de la hoja desplegable de programar viaje (estilo inDrive).
class ProgramarViajeEncabezadoPersonaliza extends StatelessWidget {
  const ProgramarViajeEncabezadoPersonaliza({
    super.key,
    required this.subtitulo,
    required this.textPrimary,
    required this.textMuted,
    this.shadows,
    this.badges = const <Widget>[],
  });

  final String subtitulo;
  final Color textPrimary;
  final Color textMuted;
  final List<Shadow>? shadows;
  final List<Widget> badges;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Personaliza tu viaje',
            style: TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 20,
              letterSpacing: -0.3,
              shadows: shadows,
            ),
          ),
          const SizedBox(height: 4),
          if (subtitulo.trim().isNotEmpty)
            Text(
              subtitulo,
              style: TextStyle(
                color: textMuted,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                shadows: shadows,
              ),
            ),
          if (badges.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: badges,
            ),
          ],
        ],
      ),
    );
  }
}

/// Chip de modo (Ahora, Programado, Turismo, etc.).
class ProgramarViajeModoChip extends StatelessWidget {
  const ProgramarViajeModoChip({
    super.key,
    required this.label,
    required this.icon,
    required this.accent,
    required this.textColor,
    this.filled = true,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final Color textColor;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? accent.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.75), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta superior del bloque de tipo de vehículo.
class ProgramarViajeEtiquetaVehiculo extends StatelessWidget {
  const ProgramarViajeEtiquetaVehiculo({
    super.key,
    required this.textPrimary,
    required this.textMuted,
    this.shadows,
    this.mostrarAyuda = true,
  });

  final Color textPrimary;
  final Color textMuted;
  final List<Shadow>? shadows;
  final bool mostrarAyuda;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.directions_car_filled_outlined,
                size: 18, color: textPrimary),
            const SizedBox(width: 6),
            Text(
              'Elige el tipo de vehículo',
              style: TextStyle(
                color: textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                shadows: shadows,
              ),
            ),
          ],
        ),
        if (mostrarAyuda) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            'Carro, jeepeta, minivan y más según tu viaje',
            style: TextStyle(
              color: textMuted,
              fontSize: 11.5,
              height: 1.25,
              shadows: shadows,
            ),
          ),
        ],
      ],
    );
  }
}

/// Botón de acción destacado en hojas de programar viaje (claro/oscuro).
class BotonAccionDestacadoHoja extends StatelessWidget {
  const BotonAccionDestacadoHoja({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.accent,
    this.mapFloating = false,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final Color accent;
  final bool mapFloating;

  Color _textoSobreAccent(Color color) {
    return color.computeLuminance() > 0.58
        ? const Color(0xFF101828)
        : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool habilitado = onPressed != null;
    final Color base = habilitado
        ? accent
        : (isDark ? const Color(0xFF475467) : const Color(0xFF98A2B3));
    final Color texto = _textoSobreAccent(base);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: base,
          elevation: habilitado && !isDark ? 1.5 : 0,
          shadowColor: base.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            splashColor: texto.withValues(alpha: 0.14),
            highlightColor: texto.withValues(alpha: 0.08),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: habilitado
                      ? (mapFloating
                          ? Colors.white.withValues(alpha: 0.38)
                          : base.withValues(alpha: isDark ? 0.85 : 0.95))
                      : base.withValues(alpha: 0.5),
                  width: 1.25,
                ),
                boxShadow: habilitado && !isDark
                    ? <BoxShadow>[
                        BoxShadow(
                          color: base.withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: texto.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: texto, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: texto,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          height: 1.15,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
