import 'package:flutter/material.dart';

/// Fila **icono + etiqueta + dropdown** que no desborda con texto del sistema grande.
///
/// El [dropdown] debe ser un [DropdownButton] con `isExpanded: true` para que
/// use bien el ancho asignado (p. ej. texto del valor seleccionado con ellipsis).
class OverflowSafeLabeledDropdown extends StatelessWidget {
  const OverflowSafeLabeledDropdown({
    super.key,
    required this.leading,
    required this.label,
    required this.labelStyle,
    required this.dropdown,
    this.gapAfterLeading = 10,
  });

  final Widget leading;
  final String label;
  final TextStyle labelStyle;
  final Widget dropdown;
  final double gapAfterLeading;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        leading,
        SizedBox(width: gapAfterLeading),
        Expanded(
          flex: 11,
          child: Text(
            label,
            style: labelStyle,
            maxLines: 3,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 10,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: dropdown,
          ),
        ),
      ],
    );
  }
}
