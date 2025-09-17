// lib/widgets/pay_method_selector.dart
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/pay_config.dart';

class PayMethodSelector extends StatelessWidget {
  final String value;
  final void Function(String) onChanged;

  const PayMethodSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: PayConfig.metodos.map((m) {
        final selected = value == m;
        return ChoiceChip(
          label: Text(m),
          selected: selected,
          labelStyle: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontWeight: FontWeight.w600,
          ),
          selectedColor: Colors.greenAccent,
          backgroundColor: const Color(0xFF1A1A1A),
          onSelected: (_) => onChanged(m),
        );
      }).toList(),
    );
  }
}
