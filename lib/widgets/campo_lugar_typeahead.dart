// lib/widgets/campo_lugar_typeahead.dart
import 'package:flutter/material.dart';
import '../servicios/lugares_service.dart';
import 'campo_lugar_autocomplete.dart';

class CampoLugarTypeAhead extends StatelessWidget {
  final String etiqueta;
  final ValueChanged<DetalleLugar> onSeleccion;

  const CampoLugarTypeAhead({
    super.key,
    required this.etiqueta,
    required this.onSeleccion,
  });

  @override
  Widget build(BuildContext context) {
    return CampoLugarAutocomplete(
      label: etiqueta,
      hint: 'Escribe para buscar…',
      onPlaceSelected: onSeleccion,
    );
  }
}
