import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/cliente/cliente_home.dart';

/// Shell del cliente: SIEMPRE muestra la portada nueva (paracaídas).
class ClienteShell extends StatelessWidget {
  const ClienteShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const ClienteHome(); // ← portada nueva
  }
}
