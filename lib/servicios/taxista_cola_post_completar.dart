import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/taxista/viaje_disponible.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
import 'package:flygo_nuevo/servicios/ubicacion_taxista.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

/// Un solo lugar: promover cola, disponibilidad en mapa y navegación tras finalizar viaje (taxista).
class TaxistaColaPostCompletar {
  TaxistaColaPostCompletar._();

  static Future<void> navegarTrasCompletar({
    required BuildContext context,
    required String uidTaxista,
  }) async {
    final String? siguienteId =
        await ViajesRepo.promoverColaTrasFinalizarTaxista(uidTaxista: uidTaxista);

    if (siguienteId != null && siguienteId.isNotEmpty) {
      await UbicacionTaxista.marcarNoDisponible();
    } else {
      await UbicacionTaxista.marcarDisponible();
    }

    if (!context.mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      final nav = Navigator.of(context);

      if (siguienteId != null && siguienteId.isNotEmpty) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              '🏁 Viaje completado. Conectando con tu siguiente recogida…',
            ),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 3),
          ),
        );
        nav.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const ViajeEnCursoTaxista()),
          (route) => false,
        );
      } else {
        messenger?.showSnackBar(
          const SnackBar(content: Text('🏁 Viaje marcado como completado')),
        );
        nav.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const ViajeDisponible()),
          (route) => false,
        );
      }
    });
  }
}
