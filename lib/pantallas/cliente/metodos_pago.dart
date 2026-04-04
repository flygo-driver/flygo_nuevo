import 'package:flutter/material.dart';
import 'historial_pagos_cliente.dart';

class MetodosPago extends StatelessWidget {
  const MetodosPago({super.key});

  @override
  Widget build(BuildContext context) {
    // Reutiliza la pantalla de historial de pagos
    return const HistorialPagosCliente();
  }
}