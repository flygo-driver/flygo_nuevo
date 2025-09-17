import 'package:flutter/material.dart';
import '../modelo/viaje.dart';
import '../utils/calculos/estados.dart';

class TarjetaViaje extends StatelessWidget {
  final Viaje viaje;
  final VoidCallback? onTap;

  const TarjetaViaje({super.key, required this.viaje, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: ListTile(
        onTap: onTap,
        title: Text(
          "${viaje.origen} ➝ ${viaje.destino}",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text("Tipo: ${viaje.tipoVehiculo}"),
            Text("Método de pago: ${viaje.metodoPago}"),
            Text("Precio: RD\$${viaje.precio.toStringAsFixed(2)}"),
            Text(
              "Estado: ${EstadosViaje.descripcion(viaje.completado
                  ? EstadosViaje.completado
                  : viaje.aceptado
                  ? EstadosViaje.enCurso
                  : EstadosViaje.pendiente)}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        trailing: const Icon(Icons.directions_car),
      ),
    );
  }
}
