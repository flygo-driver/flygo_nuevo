// lib/pantallas/taxista/taxista_home.dart
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/shell/taxista_shell.dart';

/// Punto de entrada legado: mismo shell que tras onboarding.
class TaxistaHome extends StatelessWidget {
  const TaxistaHome({super.key});

  @override
  Widget build(BuildContext context) {
    return const TaxistaShell();
  }
}
