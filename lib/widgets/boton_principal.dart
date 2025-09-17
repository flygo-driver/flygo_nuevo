// lib/widgets/boton_principal.dart
import 'package:flutter/material.dart';

class BotonPrincipal extends StatelessWidget {
  final String texto;
  final VoidCallback onPressed;
  final IconData? icono;

  const BotonPrincipal({
    super.key,
    required this.texto,
    required this.onPressed,
    this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icono ?? Icons.check),
        label: Text(texto),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
