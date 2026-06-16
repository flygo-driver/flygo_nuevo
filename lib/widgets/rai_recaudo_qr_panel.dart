import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:flygo_nuevo/servicios/finance_config_service.dart';

/// QR recaudo RAI (payload generado en Cloud Functions).
class RaiRecaudoQrPanel extends StatelessWidget {
  const RaiRecaudoQrPanel({
    super.key,
    required this.viajeData,
    this.fondoOscuro = false,
    this.mostrarAunSinFlag = false,
  });

  final Map<String, dynamic> viajeData;
  final bool fondoOscuro;
  final bool mostrarAunSinFlag;

  String get _payload =>
      (viajeData['qrRecaudoPayload'] ?? '').toString().trim();

  bool get _visible {
    if (_payload.isEmpty) return false;
    if (mostrarAunSinFlag) return true;
    return FinanceConfigService.qrRecaudoPopularHabilitado;
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final labelColor = fondoOscuro ? Colors.white54 : cs.onSurfaceVariant;
    final tipo = (viajeData['qrRecaudoTipo'] ?? '').toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fondoOscuro
            ? const Color(0xFF1A1A1A)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: fondoOscuro
              ? Colors.white12
              : cs.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          Text(
            'Escaneá con App Popular',
            style: TextStyle(
              color: fondoOscuro ? Colors.white : cs.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tipo.contains('stub')
                ? 'QR cableado (stub). Reemplazar payload cuando el banco entregue API.'
                : 'Pagá a cuenta RAI con referencia del viaje.',
            textAlign: TextAlign.center,
            style: TextStyle(color: labelColor, fontSize: 11.5, height: 1.35),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: QrImageView(
              data: _payload,
              version: QrVersions.auto,
              size: 180,
              backgroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
