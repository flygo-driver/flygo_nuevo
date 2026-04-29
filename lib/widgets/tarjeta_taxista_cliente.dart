import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';

class TarjetaTaxistaCliente extends StatelessWidget {
  final Viaje viaje;
  const TarjetaTaxistaCliente({super.key, required this.viaje});

  double? _distKmTaxistaAlPickup(Viaje v) {
    if ((v.latTaxista == 0 && v.lonTaxista == 0) ||
        (v.latCliente == 0 && v.lonCliente == 0)) {
      return null;
    }
    return DistanciaService.calcularDistancia(
      v.latTaxista,
      v.lonTaxista,
      v.latCliente,
      v.lonCliente,
    );
  }

  String _etaMinTxt(double km) {
    final mins = (km / 25.0) * 60.0; // ~25km/h urbano
    final m = mins.clamp(1, 180).round();
    return '$m min';
  }

  Color _stateColor(String e) {
    switch (e) {
      case 'aceptado':
      case 'en_camino_pickup':
      case 'encaminopickup':
        return Colors.orangeAccent;
      case 'a_bordo':
      case 'abordo':
      case 'en_curso':
      case 'encurso':
        return Colors.greenAccent;
      case 'completado':
        return Colors.blueAccent;
      default:
        return Colors.white70;
    }
  }

  String _stateText(String e) {
    switch (e) {
      case 'aceptado':
        return 'Conductor asignado';
      case 'en_camino_pickup':
      case 'encaminopickup':
        return 'En camino a recogerte';
      case 'a_bordo':
      case 'abordo':
        return 'Cliente a bordo';
      case 'en_curso':
      case 'encurso':
        return 'Viaje en curso';
      case 'completado':
        return 'Completado';
      default:
        return e;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Campos que SÍ existen en tu Viaje
    final String nombre = viaje.nombreTaxista; // no usar ??
    final String placa = viaje.placa;
    final String tipo = viaje.tipoVehiculo;
    final String tel = viaje.telefono;

    final String titulo = nombre.isNotEmpty ? nombre : 'Tu conductor';
    final String vehiculoText = [
      if (tipo.isNotEmpty) tipo,
      if (placa.isNotEmpty) '• Placa $placa',
    ].join('  ');

    final distKm = _distKmTaxistaAlPickup(viaje);
    final estadoNorm = viaje.estado.toLowerCase();
    final estadoColor = _stateColor(estadoNorm);
    final estadoTxt = _stateText(estadoNorm);

    return Card(
      color: const Color(0xFF121212),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white.withAlpha(28),
                child: const Icon(Icons.person, color: Colors.white70),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 18),
                      ),
                      const SizedBox(height: 4),
                      if (vehiculoText.isNotEmpty)
                        Text(
                          vehiculoText,
                          style: const TextStyle(color: Colors.white70),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ]),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: estadoColor.withAlpha(28),
                  border: Border.all(color: estadoColor.withAlpha(178)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.local_taxi, size: 14, color: estadoColor),
                  const SizedBox(width: 6),
                  Text(estadoTxt,
                      style: TextStyle(
                          color: estadoColor, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (tipo.isNotEmpty) _chip(icon: Icons.local_taxi, text: tipo),
              if (placa.isNotEmpty)
                _chip(icon: Icons.credit_card, text: 'Placa: $placa'),
              if (distKm != null)
                _chip(icon: Icons.timer, text: 'ETA ${_etaMinTxt(distKm)}'),
            ],
          ),
          if (tel.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => launchUrl(Uri.parse('tel:$tel')),
                icon: const Icon(Icons.call),
                label: const Text('Llamar al conductor'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  minimumSize: const Size(double.infinity, 48),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _chip({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.white70),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: Colors.white70)),
      ]),
    );
  }
}
