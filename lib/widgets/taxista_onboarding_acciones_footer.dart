import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/logout.dart';

/// Pie fijo onboarding taxista: acción principal + salida al inicio (una sola vez, siempre visible).
class TaxistaOnboardingAccionesFooter extends StatelessWidget {
  const TaxistaOnboardingAccionesFooter({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryIcon,
    this.busy = false,
    this.onSalirInicio,
    this.mostrarSalirInicio = true,
    this.fondoOscuro = false,
    this.primaryClaroSobreOscuro = false,
  });

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final IconData? primaryIcon;
  final bool busy;
  final VoidCallback? onSalirInicio;
  final bool mostrarSalirInicio;
  final bool fondoOscuro;
  /// Estilo documentos pool (botón blanco sobre fondo negro).
  final bool primaryClaroSobreOscuro;

  /// Espacio inferior para [ListView] cuando el pie está fijo (evita tapar campos).
  static double scrollBottomPadding(
    BuildContext context, {
    bool conSalirInicio = true,
  }) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return (conSalirInicio ? 118.0 : 68.0) + bottom;
  }

  Future<void> _salir(BuildContext context) async {
    if (onSalirInicio != null) {
      onSalirInicio!();
      return;
    }
    await cerrarSesion(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color barBg =
        fondoOscuro ? const Color(0xFF0A0A0A) : cs.surface;
    final Color borderColor =
        fondoOscuro ? Colors.white12 : cs.outlineVariant.withValues(alpha: 0.7);
    final Color salirFg =
        fondoOscuro ? Colors.white70 : cs.onSurfaceVariant;

    final Widget primaryChild = busy
        ? SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: primaryClaroSobreOscuro ? Colors.green : cs.onPrimary,
            ),
          )
        : Text(
            primaryLabel,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: primaryClaroSobreOscuro ? Colors.green : null,
            ),
          );

    final Widget primaryButton = SizedBox(
      height: 52,
      width: double.infinity,
      child: primaryClaroSobreOscuro
          ? ElevatedButton.icon(
              onPressed: busy ? null : onPrimary,
              icon: Icon(
                primaryIcon ?? Icons.arrow_forward_rounded,
                color: Colors.green,
              ),
              label: primaryChild,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.green,
                disabledBackgroundColor: Colors.white38,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            )
          : FilledButton.icon(
              onPressed: busy ? null : onPrimary,
              icon: primaryIcon != null
                  ? Icon(primaryIcon, size: 22)
                  : const SizedBox.shrink(),
              label: primaryChild,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
    );

    return Material(
      color: barBg,
      elevation: fondoOscuro ? 0 : 4,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: borderColor)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primaryButton,
              if (mostrarSalirInicio) ...[
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: busy ? null : () => _salir(context),
                  icon: Icon(Icons.home_outlined, size: 18, color: salirFg),
                  label: Text(
                    'Volver al inicio',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: salirFg,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: salirFg,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
