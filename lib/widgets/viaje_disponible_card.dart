import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ViajeDisponibleCard extends StatelessWidget {
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
    required this.onAceptar,
    this.textoBoton, // ⬅️ NUEVO
  });

  final String origen;
  final String destino;
  final DateTime fechaHora;
  final double precio;
  final double? gananciaTaxista;
  final double? distanciaKm;
  final String metodoPago;
  final String tipoVehiculo;
  final bool programado;
  final Future<void> Function()? onAceptar;
  final String? textoBoton;

  @override
  Widget build(BuildContext context) {
    final fFecha = DateFormat('EEE d MMM, HH:mm', 'es');
    final fNum = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.place, color: Colors.greenAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  origen,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (programado ? Colors.teal : Colors.green).withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: (programado ? Colors.tealAccent : Colors.greenAccent).withValues(alpha: .5),
                  ),
                ),
                child: Text(
                  programado ? 'programado' : 'ahora',
                  style: TextStyle(
                    color: programado ? Colors.tealAccent : Colors.greenAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(fFecha.format(fechaHora), style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(icon: Icons.straighten, label: (distanciaKm != null) ? 'Dist.: ${distanciaKm!.toStringAsFixed(2)} km' : 'Dist.: —'),
              _chip(icon: Icons.credit_card, label: metodoPago),
              _chip(icon: Icons.directions_car_filled, label: tipoVehiculo),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total', style: TextStyle(color: Colors.white60)),
                  Text(
                    fNum.format(precio),
                    style: const TextStyle(color: Colors.amber, fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Ganas', style: TextStyle(color: Colors.white60)),
                  Text(
                    (gananciaTaxista != null) ? fNum.format(gananciaTaxista) : '—',
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onAceptar == null ? null : () async => onAceptar!.call(),
            icon: const Icon(Icons.check_circle, color: Colors.green),
            label: Text(textoBoton ?? 'Aceptar viaje'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              minimumSize: const Size(double.infinity, 50),
              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: Colors.white70),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ]),
    );
  }
}
