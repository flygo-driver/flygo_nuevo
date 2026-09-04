import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/negocio_aliado_config.dart';
import 'package:flygo_nuevo/servicios/negocio_aliado_promo_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';

/// Banner compacto en cotización: 6.º gratis aplicado, aviso de pueblo o progreso 5+1.
class ClienteNegocioAliadoCotizacionBanner extends StatelessWidget {
  const ClienteNegocioAliadoCotizacionBanner({
    super.key,
    required this.eval,
  });

  final NegocioAliadoPromoEval? eval;

  @override
  Widget build(BuildContext context) {
    final e = eval;
    if (e == null || !e.activa) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final ciudad =
        e.ciudadNegocio.isEmpty ? 'el pueblo del aliado' : e.ciudadNegocio;
    final elegibleGratis = e.contador >= e.m && e.k > 0;

    if (e.esViajeGratis) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1B5E20).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF43A047).withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.celebration_rounded, color: Color(0xFF2E7D32)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '6.º viaje GRATIS aplicado',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2E7D32),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              if (e.descuentoRd > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Ahorras ${FormatosMoneda.rd(e.descuentoRd)} '
                  '(tope RD\$${NegocioAliadoConfig.topeViajeGratisRd.toStringAsFixed(0)})',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (elegibleGratis && !e.viajeLocalEnPueblo) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.45)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.amber.shade800, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ya ganaste el 6.º viaje gratis, pero origen y destino deben estar en $ciudad.',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!elegibleGratis && e.m > 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          'Promo aliado: ${e.contador} de ${e.m} pagados · el ${e.m + 1}.º gratis en $ciudad',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
