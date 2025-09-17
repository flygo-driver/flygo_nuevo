// lib/widgets/campo_direccion.dart
import 'package:flutter/material.dart';

class CampoDireccion extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validador;

  // Opcionales (no rompen compatibilidad)
  final String? hint;
  final ValueChanged<String>? onChanged;
  final FormFieldSetter<String>? onSaved;
  final bool readOnly;
  final TextInputType keyboardType;

  const CampoDireccion({
    super.key,
    required this.label,
    required this.controller,
    this.validador,
    this.hint,
    this.onChanged,
    this.onSaved,
    this.readOnly = false,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validador,
      onChanged: onChanged,
      onSaved: onSaved,
      readOnly: readOnly,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.words,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint ?? 'Escribe ${label.toLowerCase()}',
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: const Icon(Icons.location_on, color: Colors.white70),
        filled: true,
        fillColor: Colors.grey[900],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.greenAccent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.greenAccent, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24),
        ),
      ),
    );
  }
}
