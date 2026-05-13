import 'package:flutter/material.dart';

import 'package:flygo_nuevo/shell/taxista_shell.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/servicios/ubicacion_taxista.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

/// Un solo lugar: promover cola, disponibilidad en mapa y navegación tras finalizar viaje (taxista).
class TaxistaColaPostCompletar {
  TaxistaColaPostCompletar._();

  static Future<void> navegarTrasCompletar({
    required BuildContext context,
    required String uidTaxista,
  }) async {
    final PromoverColaTaxistaOutcome outcome =
        await ViajesRepo.promoverColaTrasFinalizarTaxista(
            uidTaxista: uidTaxista);

    if (outcome.hadPromotion) {
      await UbicacionTaxista.marcarNoDisponible();
    } else {
      await UbicacionTaxista.marcarDisponible();
    }

    if (!context.mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      final nav = Navigator.of(context, rootNavigator: true);

      if (outcome.hadPromotion && outcome.promotedViajeId != null) {
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
        final buf = StringBuffer(
          '🏁 Viaje marcado como completado. Estás disponible en el mapa.',
        );
        if (outcome.code == 'bloqueado_operativo') {
          buf.write(' ');
          buf.write(outcome.message ??
              PagosTaxistaRepo.mensajeRecargaTomarViajes);
        } else if (outcome.code.startsWith('functions_') ||
            outcome.code == 'invalid_response' ||
            outcome.code == 'error') {
          buf.write(' No se pudo asignar el siguiente viaje: ');
          buf.write(outcome.message ?? outcome.code);
        } else if (outcome.code == 'nothing_to_promote' &&
            (outcome.message ?? '').isNotEmpty) {
          buf.write(' ');
          buf.write(outcome.message!);
        }
        messenger?.showSnackBar(
          SnackBar(
            content: Text(buf.toString()),
            backgroundColor: outcome.code == 'bloqueado_operativo' ||
                    outcome.code.startsWith('functions_') ||
                    outcome.code == 'invalid_response' ||
                    outcome.code == 'error'
                ? Colors.orange
                : null,
            duration: const Duration(seconds: 5),
          ),
        );
        nav.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const TaxistaShell()),
          (route) => false,
        );
      }
    });
  }
}
