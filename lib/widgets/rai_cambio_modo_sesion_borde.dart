// lib/widgets/rai_cambio_modo_sesion_borde.dart
//
// Barra horizontal (borde a borde) para cambiar modo conductor ↔ pasajero.

import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/rai_cambio_modo_sesion.dart';

/// Barra fija sobre la navegación inferior en la pestaña Cuenta.
class RaiCambioModoSesionBorde extends StatefulWidget {
  const RaiCambioModoSesionBorde({
    super.key,
    required this.destinoPasajero,
  });

  /// `true` → taxista cambia a pasajero; `false` → vuelve a conductor.
  final bool destinoPasajero;

  @override
  State<RaiCambioModoSesionBorde> createState() =>
      _RaiCambioModoSesionBordeState();
}

class _RaiCambioModoSesionBordeState extends State<RaiCambioModoSesionBorde> {
  bool _cambiando = false;

  Future<void> _onTap() async {
    if (_cambiando) return;
    setState(() => _cambiando = true);
    try {
      if (widget.destinoPasajero) {
        await RaiCambioModoSesion.cambiarAPasajero(context);
      } else {
        await RaiCambioModoSesion.cambiarAConductor(context);
      }
    } finally {
      if (mounted) setState(() => _cambiando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final navH = NavigationBarTheme.of(context).height ?? 80;
    final bottom = MediaQuery.paddingOf(context).bottom +
        navH +
        kRaiCambioModoSesionMargenSobreNav;

    final etiqueta = widget.destinoPasajero
        ? 'USAR MODO PASAJERO'
        : 'VOLVER A MODO CONDUCTOR';
    final subtitulo = widget.destinoPasajero
        ? 'Pedí viajes con la misma cuenta'
        : 'Volver a recibir viajes como conductor';
    final icono = widget.destinoPasajero
        ? Icons.person_outline_rounded
        : Icons.local_taxi_rounded;

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: Material(
        elevation: 6,
        shadowColor: kRaiCambioModoRojoChino.withValues(alpha: 0.35),
        color: kRaiCambioModoRojoChino,
        child: InkWell(
          onTap: _cambiando ? null : _onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                if (_cambiando)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                else
                  Icon(icono, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        etiqueta,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
