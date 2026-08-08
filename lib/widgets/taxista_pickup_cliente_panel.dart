import 'package:flutter/material.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/widgets/cliente_perfil_conductor_chip.dart';
import 'package:flygo_nuevo/widgets/metodo_pago_visual_badge.dart';

/// Resumen compacto para fase pickup (ir al cliente). Solo presentación.
class TaxistaPickupClientePanel extends StatelessWidget {
  const TaxistaPickupClientePanel({
    super.key,
    required this.viaje,
    required this.navegacionIniciada,
    required this.clienteCerca,
    this.onVerCliente,
    this.onContactar,
  });

  final Viaje viaje;
  final bool navegacionIniciada;
  final bool clienteCerca;
  final VoidCallback? onVerCliente;
  final VoidCallback? onContactar;

  static const Color _acento = Color(0xFF64B5F6);

  int get _pasoActivo => navegacionIniciada ? 1 : 0;

  double get _precio =>
      viaje.precioFinal > 0 ? viaje.precioFinal : viaje.precio;

  @override
  Widget build(BuildContext context) {
    final MetodoPagoVisualTheme pago =
        MetodoPagoVisualTheme.deMetodo(viaje.metodoPago);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ir al punto de recogida',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    navegacionIniciada
                        ? 'Al llegar, confirmá «Cliente a bordo»'
                        : 'Abrí Maps o Waze con el botón de abajo',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _PagoChip(theme: pago, precio: _precio),
          ],
        ),
        const SizedBox(height: 12),
        _PickupStepper(pasoActivo: _pasoActivo),
        const SizedBox(height: 12),
        _TarjetaRecogida(
          origen: viaje.origen,
          clienteCerca: clienteCerca,
          uidCliente: viaje.uidCliente.trim(),
          onVerCliente: onVerCliente,
          onContactar: onContactar,
        ),
      ],
    );
  }
}

class _PagoChip extends StatelessWidget {
  const _PagoChip({required this.theme, required this.precio});

  final MetodoPagoVisualTheme theme;
  final double precio;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.accentDeep.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(theme.icon, color: theme.accent, size: 14),
              const SizedBox(width: 4),
              Text(
                theme.label,
                style: TextStyle(
                  color: theme.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            FormatosMoneda.rd(precio),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PickupStepper extends StatelessWidget {
  const _PickupStepper({required this.pasoActivo});

  final int pasoActivo;

  static const List<String> _pasos = <String>[
    'Recogida',
    'Abordo',
    'PIN',
    'Destino',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List<Widget>.generate(_pasos.length * 2 - 1, (int i) {
        if (i.isOdd) {
          final int pasoIdx = i ~/ 2;
          final bool completado = pasoIdx < pasoActivo;
          return Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.only(bottom: 18),
              color: completado
                  ? TaxistaPickupClientePanel._acento
                  : Colors.white12,
            ),
          );
        }
        final int idx = i ~/ 2;
        final bool activo = idx == pasoActivo;
        final bool completado = idx < pasoActivo;
        final Color color = completado || activo
            ? TaxistaPickupClientePanel._acento
            : Colors.white24;
        return Column(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: activo
                    ? TaxistaPickupClientePanel._acento.withValues(alpha: 0.2)
                    : Colors.transparent,
                border: Border.all(color: color, width: activo ? 2 : 1.2),
              ),
              child: Center(
                child: completado
                    ? Icon(Icons.check_rounded, size: 14, color: color)
                    : Text(
                        '${idx + 1}',
                        style: TextStyle(
                          color: activo ? Colors.white : Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _pasos[idx],
              style: TextStyle(
                color: activo ? Colors.white : Colors.white.withValues(alpha: 0.45),
                fontSize: 9.5,
                fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _TarjetaRecogida extends StatelessWidget {
  const _TarjetaRecogida({
    required this.origen,
    required this.clienteCerca,
    required this.uidCliente,
    this.onVerCliente,
    this.onContactar,
  });

  final String origen;
  final bool clienteCerca;
  final String uidCliente;
  final VoidCallback? onVerCliente;
  final VoidCallback? onContactar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: TaxistaPickupClientePanel._acento.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: RaiDsColors.neon.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.trip_origin,
                  color: RaiDsColors.neon,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recogida',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      origen.trim().isEmpty ? 'Punto de recogida' : origen,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (clienteCerca) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.near_me_rounded,
                      color: Colors.greenAccent, size: 16),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Estás cerca del punto de recogida',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (uidCliente.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClientePerfilConductorChip(uidCliente: uidCliente),
          ],
          if (onVerCliente != null || onContactar != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (onVerCliente != null)
                  Expanded(
                    child: _AccionMini(
                      icon: Icons.person_outline_rounded,
                      label: 'Ver cliente',
                      onTap: onVerCliente!,
                    ),
                  ),
                if (onVerCliente != null && onContactar != null)
                  const SizedBox(width: 8),
                if (onContactar != null)
                  Expanded(
                    child: _AccionMini(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'Contactar',
                      onTap: onContactar!,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AccionMini extends StatelessWidget {
  const _AccionMini({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
