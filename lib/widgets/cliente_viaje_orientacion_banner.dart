import 'package:flutter/material.dart';

/// Cita breve para orientar al cliente al pedir un viaje (claro / oscuro).
class ClienteViajeOrientacionBanner extends StatelessWidget {
  const ClienteViajeOrientacionBanner({
    super.key,
    required this.mensaje,
    this.icon = Icons.lightbulb_outline_rounded,
    this.accentColor,
  });

  final String mensaje;
  final IconData icon;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = accentColor ?? cs.primary;
    final bg = isDark
        ? accent.withValues(alpha: 0.16)
        : accent.withValues(alpha: 0.11);
    final border = accent.withValues(alpha: isDark ? 0.50 : 0.38);
    final textColor =
        isDark ? Colors.white.withValues(alpha: 0.94) : const Color(0xFF1A2233);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1.15),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                height: 1.42,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Textos de orientación por flujo de pedido de viaje.
abstract final class ClienteViajeOrientacionCopy {
  ClienteViajeOrientacionCopy._();

  static String programarViaje({
    required bool modoAhora,
    required String tipoServicio,
  }) {
    switch (tipoServicio) {
      case 'turismo':
        return modoAhora
            ? 'Deslizá la hoja hacia arriba, buscá aeropuerto, hotel o destino turístico '
                '(o abrí el catálogo) y confirmá cuando veas el precio.'
            : 'Elegí destino en el catálogo o buscador. Después definí fecha y hora, '
                'vehículo e ida y vuelta antes de confirmar la reserva.';
      case 'motor':
        return 'Deslizá la hoja hacia arriba, escribí a dónde vas en motor y '
            'confirmá el viaje cuando veas el precio en pantalla.';
      default:
        if (modoAhora) {
          return 'Deslizá la hoja hacia arriba, buscá tu destino en el campo de abajo '
              'y confirmá el viaje cuando veas el precio.';
        }
        return 'Deslizá la hoja, completá origen y destino, elegí fecha y hora de recogida '
            'y confirmá cuando tengas el precio.';
    }
  }

  static IconData iconoProgramarViaje(String tipoServicio, {bool modoAhora = true}) {
    switch (tipoServicio) {
      case 'turismo':
        return Icons.flight_takeoff_rounded;
      case 'motor':
        return Icons.two_wheeler_rounded;
      default:
        return modoAhora ? Icons.bolt_rounded : Icons.event_rounded;
    }
  }

  static String multiParadas({required String tipoServicio, required bool esAhora}) {
    if (tipoServicio == 'turismo') {
      return esAhora
          ? 'Indicá origen y destino turístico (paradas opcionales), deslizá para ver '
              'opciones y confirmá cuando calcule el precio.'
          : 'Completá la ruta con paradas opcionales, elegí fecha/hora y confirmá '
              'cuando veas el precio del traslado.';
    }
    if (tipoServicio == 'motor') {
      return 'Indicá origen, paradas opcionales y destino en motor; confirmá cuando '
          'aparezca el precio.';
    }
    return esAhora
        ? 'Completá origen → paradas (opcional) → destino. Deslizá la pantalla y '
            'confirmá cuando calcule el precio.'
        : 'Completá origen, paradas y destino; elegí fecha/hora y confirmá cuando '
            'tengas el precio.';
  }

  static const String motorRai =
      'Deslizá la hoja hacia arriba, escribí a dónde vas en motor y confirmá '
      'cuando veas el precio. Activá el GPS si te lo pide.';

  static const String bolaAhora =
      'Elegí un conductor en ruta, negociá el monto en su tarjeta y seguí los '
      'pasos para encontrarlo y subir al vehículo.';
}
