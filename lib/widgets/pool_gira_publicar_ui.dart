import 'package:flutter/material.dart';
import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';

/// Cabecera de marca para organizadores de giras por cupos.
class OrganizadorGirasBrandHeader extends StatelessWidget {
  const OrganizadorGirasBrandHeader({
    super.key,
    this.compact = false,
    this.subtitulo,
  });

  final bool compact;
  final String? subtitulo;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(compact ? 12 : 16, compact ? 8 : 12, compact ? 12 : 16, 8),
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const <Color>[Color(0xFF0F4C5C), Color(0xFF1B6B5A), Color(0xFF2D8F7B)]
              : const <Color>[Color(0xFF0D9488), Color(0xFF14B8A6), Color(0xFF5EEAD4)],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF0D9488).withValues(alpha: isDark ? 0.35 : 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: compact ? 44 : 52,
            height: compact ? 44 : 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
            child: Icon(
              Icons.tour_rounded,
              color: Colors.white,
              size: compact ? 24 : 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Organizador de giras',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: compact ? 17 : 20,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitulo ??
                      'Publicá excursiones, vendé cupos y RAI cobra al pasajero.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: compact ? 12.5 : 13.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra de pasos del formulario de publicar gira.
class PoolGiraCrearPasoBar extends StatelessWidget {
  const PoolGiraCrearPasoBar({
    super.key,
    required this.pasoActual,
    required this.onPaso,
    this.labels = const <String>['Viaje', 'Ruta', 'Fotos', 'Cobro'],
  });

  final int pasoActual;
  final ValueChanged<int> onPaso;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = isDark ? RaiDsColors.neon : const Color(0xFF0D9488);
    final Color bg = isDark ? RaiDsColors.cardElevated : Colors.white;
    final Color border = isDark ? RaiDsColors.border : const Color(0xFFE2E8F0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Row(
          children: List<Widget>.generate(labels.length, (int i) {
            final bool sel = i == pasoActual;
            final bool done = i < pasoActual;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onPaso(i),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                      decoration: BoxDecoration(
                        color: sel
                            ? accent.withValues(alpha: isDark ? 0.22 : 0.14)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sel ? accent.withValues(alpha: 0.55) : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            done
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            size: 16,
                            color: sel || done ? accent : (isDark ? Colors.white38 : Colors.black38),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            labels[i],
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                              color: sel
                                  ? accent
                                  : (isDark ? Colors.white70 : const Color(0xFF475467)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Navegación inferior del wizard de publicar gira.
class PoolGiraCrearBottomNav extends StatelessWidget {
  const PoolGiraCrearBottomNav({
    super.key,
    required this.pasoActual,
    required this.totalPasos,
    required this.onAnterior,
    required this.onSiguiente,
    this.onPublicar,
    this.publicando = false,
    this.labelPublicar = 'Publicar gira',
  });

  final int pasoActual;
  final int totalPasos;
  final VoidCallback? onAnterior;
  final VoidCallback? onSiguiente;
  final VoidCallback? onPublicar;
  final bool publicando;
  final String labelPublicar;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool ultimo = pasoActual >= totalPasos - 1;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        12 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? RaiDsColors.card : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? RaiDsColors.border : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          if (pasoActual > 0)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onAnterior,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Anterior'),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: publicando
                  ? null
                  : (ultimo ? onPublicar : onSiguiente),
              icon: Icon(ultimo ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded),
              label: Text(
                publicando
                    ? 'Publicando…'
                    : (ultimo ? labelPublicar : 'Siguiente'),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: const Color(0xFF0D9488),
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
