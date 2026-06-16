// lib/pantallas/taxista/taxista_home.dart
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/taxista/entry_taxista.dart';

/// Punto de entrada legado: mismo shell que tras onboarding.
class TaxistaHome extends StatelessWidget {
  const TaxistaHome({super.key});

  @override
  Widget build(BuildContext context) {
    return const TaxistaEntry();
  }
}
