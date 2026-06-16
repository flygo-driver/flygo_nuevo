import 'package:flutter/material.dart';

import '../servicios/rai_offline_cotizacion_service.dart';

/// Aviso compacto bajo el precio cuando la cotización es estimada sin internet.
class RaiCotizacionOfflineHint extends StatelessWidget {
  const RaiCotizacionOfflineHint({
    super.key,
    required this.visible,
    this.mensaje,
  });

  final bool visible;
  final String? mensaje;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.tertiaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: cs.tertiary.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.wifi_off_rounded, size: 18, color: cs.tertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                mensaje ?? RaiOfflineCotizacionService.mensajeBannerEstimado,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
