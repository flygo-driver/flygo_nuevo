import 'package:flutter/material.dart';

import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/servicios/corporativo_abordaje_service.dart';
import 'package:flygo_nuevo/widgets/corporativo_pasajeros_chofer_card.dart';

/// Chofer: confirma abordaje de cada pasajero.
class CorporativoAbordajeChoferPanel extends StatefulWidget {
  const CorporativoAbordajeChoferPanel({super.key, required this.viaje});

  final Viaje viaje;

  @override
  State<CorporativoAbordajeChoferPanel> createState() =>
      _CorporativoAbordajeChoferPanelState();
}

class _CorporativoAbordajeChoferPanelState
    extends State<CorporativoAbordajeChoferPanel> {
  final Set<String> _procesando = {};

  Future<void> _confirmar(String pasajeroId) async {
    if (_procesando.contains(pasajeroId)) return;
    setState(() => _procesando.add(pasajeroId));
    try {
      await CorporativoAbordajeService.confirmarAbordaje(
        viajeId: widget.viaje.id,
        pasajeroId: pasajeroId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Abordaje registrado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _procesando.remove(pasajeroId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!CorporativoPasajerosChoferCard.esViajeCorporativo(widget.viaje)) {
      return const SizedBox.shrink();
    }
    final pasajeros =
        CorporativoPasajerosChoferCard.pasajerosDesdeViaje(widget.viaje);
    if (pasajeros.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Confirmar abordaje',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Marcá quién subió al vehículo',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          ...pasajeros.map((p) {
            final busy = _procesando.contains(p.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.nombre,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          p.abordado ? 'Abordó ✓' : 'Pendiente',
                          style: TextStyle(
                            color: p.abordado
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!p.abordado)
                    FilledButton.tonal(
                      onPressed: busy ? null : () => _confirmar(p.id),
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Subió'),
                    )
                  else
                    const Icon(Icons.check_circle, color: Colors.greenAccent),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
