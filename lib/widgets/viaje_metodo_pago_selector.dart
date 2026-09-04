import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/cliente_metodo_pago_viaje_ui.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/utils/pago_tarjeta_cliente_gate.dart';

/// Etiqueta corta para tiles estrechos o texto grande (Apariencia).
String _etiquetaMetodoPagoTile(
  BuildContext context,
  _MetodoPagoOpcion opcion,
  double anchoTile,
) {
  final double escala = MediaQuery.textScalerOf(context).scale(1.0);
  final bool apretado = anchoTile < 96 || escala >= 1.08;
  if (!apretado) return opcion.label;
  switch (opcion.value) {
    case 'transferencia':
      return 'Transf.';
    case 'efectivo':
      return 'Efectivo';
    case 'tarjeta':
      return 'Tarjeta';
    default:
      return opcion.label;
  }
}

/// Mensaje legible: las callables llegan como `[plugin/codigo] motivo`.
String _motivo(Object e) {
  final String s = e.toString().trim();
  final int cierre = s.indexOf('] ');
  if (cierre > 0 && cierre + 2 < s.length) {
    return s.substring(cierre + 2).trim();
  }
  return s;
}

/// Selector de método de pago durante el viaje (cliente).
class ViajeMetodoPagoSelector extends StatefulWidget {
  const ViajeMetodoPagoSelector({
    super.key,
    required this.viajeId,
    required this.metodoPagoActual,
    this.fondoOscuro = false,
    this.onMetodoSeleccionado,
  });

  final String viajeId;
  final String metodoPagoActual;
  final bool fondoOscuro;
  final ValueChanged<String>? onMetodoSeleccionado;

  @override
  State<ViajeMetodoPagoSelector> createState() =>
      _ViajeMetodoPagoSelectorState();
}

class _ViajeMetodoPagoSelectorState extends State<ViajeMetodoPagoSelector> {
  String? _actualizando;

  String get _metodoMostrado => MetodoPagoViaje.asientoCategoria(
        ClienteMetodoPagoViajeUi.resolver(
          viajeId: widget.viajeId,
          metodoRemoto: widget.metodoPagoActual,
        ),
      );

  Future<void> _elegir(String metodo) async {
    if (_actualizando != null) return;
    final String actual = _metodoMostrado;
    if (actual == metodo) return;

    final bool tarjetaSinCobro =
        metodo == 'tarjeta' && !PagoTarjetaClienteGate.cobroHabilitado;

    ClienteMetodoPagoViajeUi.marcar(
      viajeId: widget.viajeId,
      categoria: metodo,
    );
    setState(() => _actualizando = metodo);
    widget.onMetodoSeleccionado?.call(metodo);
    try {
      await ViajesRepo.actualizarMetodoPagoViaje(
        viajeId: widget.viajeId,
        metodoPago: metodo,
      );
      if (!mounted) return;
      final String etiqueta = switch (metodo) {
        'efectivo' => 'Efectivo',
        'transferencia' => 'Transferencia',
        _ => 'Tarjeta',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tarjetaSinCobro
                ? 'Tarjeta seleccionada (AZUL en desarrollo). Podés cambiar '
                    'a efectivo o transferencia cuando quieras.'
                : 'Pago actualizado: $etiqueta',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ClienteMetodoPagoViajeUi.limpiar(widget.viajeId);
      if (!mounted) return;
      setState(() {});
      widget.onMetodoSeleccionado?.call(
        MetodoPagoViaje.asientoCategoria(widget.metodoPagoActual),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cambiar el pago: ${_motivo(e)}')),
      );
    } finally {
      if (mounted) setState(() => _actualizando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool oscuro = widget.fondoOscuro;
    final Color fg =
        oscuro ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final Color fgMuted =
        oscuro ? Colors.white70 : fg.withValues(alpha: 0.65);
    final String metodo = _metodoMostrado;
    final bool tarjetaOn = PagoTarjetaClienteGate.mostrarOpcionTarjeta;

    final List<_MetodoPagoOpcion> opciones = <_MetodoPagoOpcion>[
      _MetodoPagoOpcion(
        value: 'efectivo',
        label: 'Efectivo',
        icon: Icons.payments_rounded,
        accent: const Color(0xFF69F0AE),
        accentDeep: const Color(0xFF1B5E20),
      ),
      _MetodoPagoOpcion(
        value: 'transferencia',
        label: 'Transferencia',
        icon: Icons.account_balance_rounded,
        accent: const Color(0xFF64B5F6),
        accentDeep: const Color(0xFF0D47A1),
      ),
      if (tarjetaOn)
        _MetodoPagoOpcion(
          value: 'tarjeta',
          label: 'Tarjeta',
          icon: Icons.credit_card_rounded,
          accent: const Color(0xFFB388FF),
          accentDeep: const Color(0xFF4A148C),
          badge: 'AZUL',
        ),
    ];

    bool selectedFor(String value) {
      switch (value) {
        case 'efectivo':
          return MetodoPagoViaje.esEfectivo(metodo);
        case 'transferencia':
          return MetodoPagoViaje.esTransferencia(metodo);
        case 'tarjeta':
          return MetodoPagoViaje.esTarjeta(metodo);
        default:
          return false;
      }
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: oscuro
              ? <Color>[
                  const Color(0xFF141B2D),
                  const Color(0xFF0F1524),
                ]
              : <Color>[
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                  Theme.of(context).colorScheme.surfaceContainerLow,
                ],
        ),
        border: Border.all(
          color: oscuro
              ? Colors.white.withValues(alpha: 0.12)
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: oscuro ? 0.35 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: <Widget>[
            Positioned(
              right: -24,
              top: -24,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF69F0AE).withValues(alpha: 0.06),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: const LinearGradient(
                            colors: <Color>[
                              Color(0xFF2E7D32),
                              Color(0xFF1B5E20),
                            ],
                          ),
                        ),
                        child: const Icon(
                          Icons.wallet_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Método de pago',
                              style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w800,
                                fontSize: 15.5,
                                letterSpacing: 0.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tarjetaOn
                                  ? (PagoTarjetaClienteGate.bloqueado
                                      ? 'Efectivo, transferencia o tarjeta (próximamente)'
                                      : 'Elegí cómo pagarás este viaje')
                                  : 'Efectivo o transferencia',
                              style: TextStyle(
                                color: fgMuted,
                                fontSize: 12,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints rowBox) {
                      final int n = opciones.length;
                      final double gap = 8.0 * (n - 1);
                      final double anchoTile =
                          n > 0 ? (rowBox.maxWidth - gap) / n : rowBox.maxWidth;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          for (int i = 0; i < opciones.length; i++) ...<Widget>[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(
                              child: _MetodoPagoTile(
                                opcion: opciones[i],
                                anchoTile: anchoTile,
                                selected: selectedFor(opciones[i].value),
                                busy: _actualizando == opciones[i].value,
                                oscuro: oscuro,
                                onTap: () => _elegir(opciones[i].value),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Podés cambiar hasta que termine el viaje.',
                    style: TextStyle(
                      color: fgMuted.withValues(alpha: 0.85),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetodoPagoOpcion {
  const _MetodoPagoOpcion({
    required this.value,
    required this.label,
    required this.icon,
    required this.accent,
    required this.accentDeep,
    this.badge,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color accent;
  final Color accentDeep;
  final String? badge;
}

class _MetodoPagoTile extends StatelessWidget {
  const _MetodoPagoTile({
    required this.opcion,
    required this.anchoTile,
    required this.selected,
    required this.busy,
    required this.oscuro,
    required this.onTap,
  });

  final _MetodoPagoOpcion opcion;
  final double anchoTile;
  final bool selected;
  final bool busy;
  final bool oscuro;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = selected
        ? opcion.accent.withValues(alpha: 0.9)
        : (oscuro
            ? Colors.white.withValues(alpha: 0.14)
            : Theme.of(context)
                .colorScheme
                .outline
                .withValues(alpha: 0.28));

    final List<Color> bgColors = selected
        ? <Color>[
            opcion.accentDeep.withValues(alpha: oscuro ? 0.55 : 0.22),
            opcion.accentDeep.withValues(alpha: oscuro ? 0.28 : 0.1),
          ]
        : <Color>[
            oscuro
                ? Colors.white.withValues(alpha: 0.05)
                : Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: 0.9),
            oscuro
                ? Colors.white.withValues(alpha: 0.02)
                : Theme.of(context)
                    .colorScheme
                    .surfaceContainerLow
                    .withValues(alpha: 0.85),
          ];

    return Semantics(
      button: true,
      selected: selected,
      label: opcion.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: bgColors,
            ),
            border: Border.all(
              color: borderColor,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? <BoxShadow>[
                    BoxShadow(
                      color: opcion.accent.withValues(alpha: 0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? opcion.accent.withValues(alpha: 0.22)
                          : (oscuro
                              ? Colors.white.withValues(alpha: 0.08)
                              : opcion.accentDeep.withValues(alpha: 0.1)),
                      border: Border.all(
                        color: selected
                            ? opcion.accent.withValues(alpha: 0.55)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: busy
                        ? Padding(
                            padding: const EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: opcion.accent,
                            ),
                          )
                        : Icon(
                            opcion.icon,
                            color: selected
                                ? opcion.accent
                                : (oscuro
                                    ? Colors.white70
                                    : opcion.accentDeep.withValues(alpha: 0.75)),
                            size: 22,
                          ),
                  ),
                  if (selected && !busy)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: opcion.accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: oscuro
                                ? const Color(0xFF0F1524)
                                : Colors.white,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 11,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  if (opcion.badge != null && !selected)
                    Positioned(
                      right: -10,
                      top: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: opcion.accentDeep,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: opcion.accent.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          opcion.badge!,
                          style: TextStyle(
                            color: opcion.accent,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: MediaQuery.textScalerOf(context).scale(28).clamp(26, 40),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    _etiquetaMetodoPagoTile(context, opcion, anchoTile),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    softWrap: true,
                    style: TextStyle(
                      color: selected
                          ? (oscuro ? Colors.white : opcion.accentDeep)
                          : (oscuro ? Colors.white70 : Colors.black87),
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 11.5,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
