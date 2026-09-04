import 'package:flutter/material.dart';

import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/utils/pago_tarjeta_cliente_gate.dart';

/// Selector compacto de método de pago al cotizar / confirmar viaje (antes de crear el doc).
class ClienteMetodoPagoSolicitudTiles extends StatelessWidget {
  const ClienteMetodoPagoSolicitudTiles({
    super.key,
    required this.categoriaSeleccionada,
    required this.onCategoriaChanged,
    this.fondoOscuro = false,
    this.mostrarTitulo = true,
  });

  /// `efectivo` | `transferencia` | `tarjeta`
  final String categoriaSeleccionada;
  final ValueChanged<String> onCategoriaChanged;
  final bool fondoOscuro;
  final bool mostrarTitulo;

  @override
  Widget build(BuildContext context) {
    final Color fg =
        fondoOscuro ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final Color fgMuted =
        fondoOscuro ? Colors.white70 : fg.withValues(alpha: 0.65);
    final String cat = categoriaSeleccionada.trim().toLowerCase();

    final List<_TileOpcion> opciones = <_TileOpcion>[
      _TileOpcion(
        value: 'efectivo',
        label: 'Efectivo',
        icon: Icons.payments_rounded,
        accent: const Color(0xFF69F0AE),
      ),
      _TileOpcion(
        value: 'transferencia',
        label: 'Transferencia',
        icon: Icons.account_balance_rounded,
        accent: const Color(0xFF64B5F6),
      ),
      if (PagoTarjetaClienteGate.mostrarOpcionTarjeta)
        _TileOpcion(
          value: 'tarjeta',
          label: 'Tarjeta',
          icon: Icons.credit_card_rounded,
          accent: const Color(0xFFB388FF),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (mostrarTitulo) ...<Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.wallet_rounded, color: fgMuted, size: 20),
              const SizedBox(width: 8),
              Text(
                'Forma de pago',
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double gap = 8;
            final int n = opciones.length;
            final double tileW =
                (constraints.maxWidth - gap * (n - 1)) / n;
            return Row(
              children: <Widget>[
                for (int i = 0; i < n; i++) ...<Widget>[
                  if (i > 0) SizedBox(width: gap),
                  SizedBox(
                    width: tileW,
                    child: _MetodoTile(
                      opcion: opciones[i],
                      selected: cat == opciones[i].value,
                      fondoOscuro: fondoOscuro,
                      onTap: () => _elegir(context, opciones[i].value),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        if (MetodoPagoViaje.esTarjeta(cat) &&
            PagoTarjetaClienteGate.bloqueado) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'Tarjeta seleccionada (AZUL en desarrollo). Podés pagar en efectivo '
            'o transferencia al conductor si preferís.',
            style: TextStyle(color: fgMuted, fontSize: 12, height: 1.35),
          ),
        ],
      ],
    );
  }

  Future<void> _elegir(BuildContext context, String value) async {
    if (value == 'tarjeta' &&
        !PagoTarjetaClienteGate.cobroHabilitado &&
        cat != 'tarjeta') {
      await PagoTarjetaClienteGate.avisarEnDesarrollo(context);
    }
    onCategoriaChanged(value);
  }

  String get cat => categoriaSeleccionada.trim().toLowerCase();
}

class _TileOpcion {
  const _TileOpcion({
    required this.value,
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color accent;
}

class _MetodoTile extends StatelessWidget {
  const _MetodoTile({
    required this.opcion,
    required this.selected,
    required this.fondoOscuro,
    required this.onTap,
  });

  final _TileOpcion opcion;
  final bool selected;
  final bool fondoOscuro;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color border = selected
        ? opcion.accent
        : (fondoOscuro
            ? Colors.white24
            : Theme.of(context).colorScheme.outline.withValues(alpha: 0.25));
    final Color bg = selected
        ? opcion.accent.withValues(alpha: fondoOscuro ? 0.22 : 0.14)
        : (fondoOscuro
            ? Colors.white.withValues(alpha: 0.06)
            : Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.5));
    final Color fg =
        fondoOscuro ? Colors.white : Theme.of(context).colorScheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: selected ? 2 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                opcion.icon,
                color: selected ? opcion.accent : fg.withValues(alpha: 0.75),
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                opcion.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
