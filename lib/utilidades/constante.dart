// lib/utilidades/constantes.dart

import 'package:flutter/material.dart';

// Colores del tema principal
const kColorPrimario = Color(0xFF0D47A1);
const kColorSecundario = Color(0xFF1976D2);
const kColorFondo = Color(0xFFF5F5F5);

// Estilo para botones principales
final kEstiloBoton = ElevatedButton.styleFrom(
  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
);

// Rutas (por si decides usar Navigator.pushNamed en vez de MaterialPageRoute)
const rutaPanelCliente = '/panel_cliente';
const rutaPanelTaxista = '/panel_taxista';
const rutaLoginCliente = '/login_cliente';
const rutaLoginTaxista = '/login_taxista';
