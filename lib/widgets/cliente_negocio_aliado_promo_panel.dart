import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/servicios/negocio_aliado_config.dart';
import 'package:flygo_nuevo/utils/negocio_aliado_cliente_promo.dart';

/// Promo 5+1 solo para clientes registrados con código QR de negocio aliado.
class ClienteNegocioAliadoPromoPanel extends StatelessWidget {
  const ClienteNegocioAliadoPromoPanel({
    super.key,
    required this.usuarioData,
  });

  final Map<String, dynamic> usuarioData;

  @override
  Widget build(BuildContext context) {
    final estado = NegocioAliadoClientePromo.estadoDesdeUsuario(usuarioData);
    if (estado == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final double progreso = estado.m > 0
        ? (estado.contador / estado.m).clamp(0.0, 1.0)
        : 0.0;
    final String venceTxt = estado.venceAt != null
        ? DateFormat('dd/MM/yyyy').format(estado.venceAt!)
        : '—';

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Material(
        color: const Color(0xFF1B5E20).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF43A047).withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.qr_code_2_rounded, color: Color(0xFF2E7D32), size: 22),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Promo negocio aliado (QR)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (estado.nombreNegocio.isNotEmpty)
                Text(
                  'Aliado: ${estado.nombreNegocio}',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                estado.elegibleGratis
                    ? '¡Tu 6.º viaje local puede ser GRATIS!'
                    : '${estado.contador} de ${estado.m} viajes pagados · el ${estado.m + 1}.º gratis',
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progreso,
                  minHeight: 8,
                  backgroundColor: cs.surfaceContainerHighest,
                  color: const Color(0xFF43A047),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'El ${estado.m + 1}.º viaje gratis solo dentro de '
                '${estado.ciudad.isEmpty ? "el pueblo del aliado" : estado.ciudad} '
                '(origen y destino en ese pueblo, hasta RD\$${NegocioAliadoConfig.topeViajeGratisRd.toStringAsFixed(0)}). '
                'Vigente hasta $venceTxt.',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
