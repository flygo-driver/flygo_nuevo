// lib/widgets/selector_fecha_hora.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SelectorFechaHora extends StatelessWidget {
  final DateTime fechaHora;
  final VoidCallback onSeleccionar;

  const SelectorFechaHora({
    super.key,
    required this.fechaHora,
    required this.onSeleccionar,
  });

  @override
  Widget build(BuildContext context) {
    final formato = DateFormat('dd/MM/yyyy - HH:mm');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "¿Cuándo quieres el viaje?",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  onSeleccionar(); // función para elegir fecha y hora
                },
                child: const Text("Seleccionar Fecha y Hora"),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text("📅 Seleccionado: ${formato.format(fechaHora)}"),
      ],
    );
  }
}
