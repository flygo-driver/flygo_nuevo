// lib/pantallas/taxista/pantalla_taxista.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'panel_taxista.dart';

/// PantallaTaxista es un wrapper del panel principal de taxista.
/// Mantiene compatibilidad con rutas antiguas que apuntaban a esta pantalla.
class PantallaTaxista extends StatelessWidget {
  const PantallaTaxista({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.greenAccent,
          title: const Text('RAI Driver — Taxista'),
          centerTitle: true,
        ),
        body: const Center(
          child: Text(
            'Inicia sesión para continuar',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    // Si hay sesión, renderiza el panel real.
    return const PanelTaxista();
  }
}
