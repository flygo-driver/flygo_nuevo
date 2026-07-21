import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_ui.dart';
import 'package:flygo_nuevo/servicios/corporativo_ruta_service.dart';

/// Estimado mensual según rutas activas y precio acordado por viaje.
class CorporativoEstimadorMensualCard extends StatelessWidget {
  const CorporativoEstimadorMensualCard({
    super.key,
    required this.plantillas,
    this.tarifaViajeContratadaRd = 0,
  });

  final List<CorporativoPlantilla> plantillas;
  final double tarifaViajeContratadaRd;

  int _diasOperativosMes(CorporativoPlantilla pl, DateTime mes) {
    final ultimo = DateTime(mes.year, mes.month + 1, 0);
    var count = 0;
    for (var d = 1; d <= ultimo.day; d++) {
      final fecha = DateTime(mes.year, mes.month, d);
      if (CorporativoRutaService.correHoy(pl, dia: fecha)) count++;
    }
    return count;
  }

  double _precioViaje(CorporativoPlantilla pl) {
    if (pl.precioAcordado > 0) {
      return CorporativoRutaService.liquidacionDesdePrecioAcordado(
        pl.precioAcordado,
      ).montoTotalFacturaRd;
    }
    if (tarifaViajeContratadaRd > 0) return tarifaViajeContratadaRd;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    final mes = DateTime.now();
    final activas = plantillas.where((pl) => pl.activa).toList();
    double total = 0;
    var viajesEst = 0;
    for (final pl in activas) {
      final dias = _diasOperativosMes(pl, mes);
      final precio = _precioViaje(pl);
      viajesEst += dias;
      total += dias * precio;
    }
    final fmt = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$', decimalDigits: 0);

    return corporativoCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calculate_outlined, color: p.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                'Estimado del mes',
                style: TextStyle(
                  color: p.onCard,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            DateFormat('MMMM yyyy', 'es').format(mes),
            style: TextStyle(color: p.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Text(
            fmt.format(total),
            style: TextStyle(
              color: p.primary,
              fontWeight: FontWeight.w900,
              fontSize: 28,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '~$viajesEst viaje(s) programados · ${activas.length} ruta(s) activa(s)',
            style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
          ),
          if (total <= 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Definí el precio acordado en cada ruta o la tarifa corporativa '
                'de la empresa para ver el estimado.',
                style: TextStyle(color: Colors.orange.shade800, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
