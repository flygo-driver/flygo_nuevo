// lib/widgets/tarjeta_viaje.dart
import 'package:flutter/material.dart';
import '../modelo/viaje.dart';
import '../utils/calculos/estados.dart';
import 'estado_badge.dart'; // 👈 requiere lib/widgets/estado_badge.dart

class TarjetaViaje extends StatelessWidget {
  final Viaje viaje;
  final VoidCallback? onTap;

  const TarjetaViaje({super.key, required this.viaje, this.onTap});

  @override
  Widget build(BuildContext context) {
    // Tomamos un estado “realista” para listas
    final estadoBase = EstadosViaje.normalizar(
      viaje.estado.isNotEmpty
          ? viaje.estado
          : (viaje.completado
              ? EstadosViaje.completado
              : (viaje.aceptado ? EstadosViaje.aceptado : EstadosViaje.pendiente)),
    );

    return Card(
      color: const Color(0xFF101010),
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.local_taxi, color: Colors.white70),
        title: Text(
          "${viaje.origen} ➝ ${viaje.destino}",
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Tipo: ${viaje.tipoVehiculo}", style: const TextStyle(color: Colors.white70)),
              Text("Pago: ${viaje.metodoPago}", style: const TextStyle(color: Colors.white70)),
              Text(
                "Precio: RD\$${viaje.precio.toStringAsFixed(2)}",
                style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              EstadoBadge(estado: estadoBase),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
      ),
    );
  }
}
