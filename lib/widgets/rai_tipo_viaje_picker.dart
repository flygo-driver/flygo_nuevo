import 'package:flutter/material.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/servicios/custom_theme_service.dart';

/// Selector visual «Ahora» / «Programado» (diseño tarjetas RAI).
class RaiTipoViajePicker extends StatelessWidget {
  const RaiTipoViajePicker({
    super.key,
    this.titulo = '¿Qué tipo de viaje quieres?',
    this.subtitulo,
    this.onElegirAhora,
    this.onElegirProgramado,
  });

  final String titulo;
  final String? subtitulo;
  final VoidCallback? onElegirAhora;
  final VoidCallback? onElegirProgramado;

  /// `false` = ahora, `true` = programado, `null` = cancelado.
  static Future<bool?> mostrar(
    BuildContext context, {
    String titulo = '¿Qué tipo de viaje quieres?',
    String? subtitulo,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RaiTipoViajePicker(
        titulo: titulo,
        subtitulo: subtitulo,
        onElegirAhora: () => Navigator.pop(ctx, false),
        onElegirProgramado: () => Navigator.pop(ctx, true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color scaffold = Theme.of(context).scaffoldBackgroundColor;
    final bool oscuro =
        ThemeData.estimateBrightnessForColor(scaffold) == Brightness.dark;
    final Color card = CustomThemeService.cardOn(scaffold);
    final Color text = CustomThemeService.textOn(scaffold);
    final Color muted = CustomThemeService.textMutedOn(scaffold);
    final Color border = CustomThemeService.borderOn(card);
    final Color accent = oscuro ? RaiDsColors.neon : const Color(0xFF16A34A);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: muted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: text,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.2,
                ),
              ),
              if (subtitulo != null && subtitulo!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  subtitulo!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: muted,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _TipoViajeCard(
                icon: Icons.bolt_rounded,
                titulo: 'Ahora',
                subtitulo: 'Pide un viaje al instante',
                accent: accent,
                card: card,
                border: border,
                text: text,
                muted: muted,
                onTap: onElegirAhora,
              ),
              const SizedBox(height: 12),
              _TipoViajeCard(
                icon: Icons.event_rounded,
                titulo: 'Programado',
                subtitulo: 'Elige día y hora',
                accent: accent,
                card: card,
                border: border,
                text: text,
                muted: muted,
                onTap: onElegirProgramado,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TipoViajeCard extends StatelessWidget {
  const _TipoViajeCard({
    required this.icon,
    required this.titulo,
    required this.subtitulo,
    required this.accent,
    required this.card,
    required this.border,
    required this.text,
    required this.muted,
    this.onTap,
  });

  final IconData icon;
  final String titulo;
  final String subtitulo;
  final Color accent;
  final Color card;
  final Color border;
  final Color text;
  final Color muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool oscuro =
        ThemeData.estimateBrightnessForColor(card) == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: oscuro
                ? Colors.white.withValues(alpha: 0.04)
                : accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accent.withValues(alpha: oscuro ? 0.28 : 0.22),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: oscuro ? 0.16 : 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: accent, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          color: text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitulo,
                        style: TextStyle(
                          color: muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: muted, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
