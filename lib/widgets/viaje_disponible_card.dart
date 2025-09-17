import 'package:flutter/material.dart';
import '../utils/formatos_moneda.dart';

class ViajeDisponibleCard extends StatelessWidget {
  final String origen;
  final String destino;
  final DateTime fechaHora;
  final double precio;
  final double? gananciaTaxista;
  final double? distanciaKm;
  final String metodoPago;
  final String tipoVehiculo;
  final bool programado;
  final VoidCallback? onAceptar;

  const ViajeDisponibleCard({
    super.key,
    required this.origen,
    required this.destino,
    required this.fechaHora,
    required this.precio,
    this.gananciaTaxista,
    this.distanciaKm,
    required this.metodoPago,
    required this.tipoVehiculo,
    required this.programado,
    this.onAceptar,
  });

  // --------- Helpers de resumen ----------
  String _ellipsis(String s, int max) =>
      (s.length <= max) ? s : '${s.substring(0, max - 1)}…';

  String _compacta(String raw) {
    if (raw.trim().isEmpty) return '—';
    var s = raw
        .replaceAll(
          RegExp(r',?\s*(Rep(ú|u)blica\s+Dominicana|RD|Dominican Republic)\b',
              caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\bSto\.?\s*Dgo\.?', caseSensitive: false),
            'Santo Domingo')
        .replaceAll(RegExp(r'Higuey', caseSensitive: false), 'Higüey')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    // Aeropuerto Las Américas
    if (RegExp(r'aeropuerto.*las amer', caseSensitive: false).hasMatch(s)) {
      s = 'Aeropuerto Las Américas (AILA), Santo Domingo';
    }

    final parts = s.split(',');
    String principal = parts.isNotEmpty ? parts[0].trim() : s;
    String ciudad =
        parts.length > 1 ? parts[1].trim() : (parts.isNotEmpty ? parts.last.trim() : '');

    principal = _ellipsis(principal, 28);
    ciudad = _ellipsis(ciudad, 18);

    return (ciudad.isEmpty) ? principal : '$principal • $ciudad';
  }

  Color get _chipBg => Colors.white.withValues(alpha: 0.07);
  BorderRadius get _chipRadius => BorderRadius.circular(12);

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _chipBg,
        borderRadius: _chipRadius,
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = _compacta(origen);
    final d = _compacta(destino);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -------- Direcciones (1 línea) + precio a la derecha --------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            size: 18, color: Colors.greenAccent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            o,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.flag,
                            size: 16, color: Colors.redAccent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            d,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    FormatosMoneda.rd(precio),
                    style: const TextStyle(
                      color: Colors.yellowAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  if (gananciaTaxista != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Gana: ${FormatosMoneda.rd(gananciaTaxista!)}',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),

          // -------- Chips compactos --------
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (distanciaKm != null)
                _chip(Icons.straighten, FormatosMoneda.km(distanciaKm!)),
              _chip(Icons.credit_card, metodoPago),
              _chip(Icons.directions_car, tipoVehiculo),
              _chip(
                programado ? Icons.schedule : Icons.flash_on,
                programado
                    ? '${fechaHora.day.toString().padLeft(2, '0')}/${fechaHora.month.toString().padLeft(2, '0')} '
                      '${fechaHora.hour.toString().padLeft(2, '0')}:${fechaHora.minute.toString().padLeft(2, '0')}'
                    : 'AHORA',
              ),
            ],
          ),

          if (onAceptar != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onAceptar,
                icon: const Icon(Icons.check_circle, color: Colors.green),
                label: const Text('Aceptar viaje'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.green,
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
