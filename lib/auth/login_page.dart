import 'package:flutter/material.dart';
import 'package:flygo_nuevo/auth/login_cliente.dart';
import 'package:flygo_nuevo/auth/login_taxista.dart';

/// Pantalla de login con pestañas Cliente / Taxista.
/// Puedes abrirla así:
///   Navigator.pushNamed(context, '/login'); // cliente por defecto
///   Navigator.pushNamed(context, '/login', arguments: {'role': 'taxista'});
class LoginPageTabs extends StatelessWidget {
  const LoginPageTabs({super.key});

  int _initialIndexFromArgs(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && (args['role'] is String)) {
      final r = (args['role'] as String).toLowerCase().trim();
      if (r == 'taxista') return 1;
    }
    return 0; // cliente
  }

  @override
  Widget build(BuildContext context) {
    final initialIndex = _initialIndexFromArgs(context);

    return DefaultTabController(
      length: 2,
      initialIndex: initialIndex,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Iniciar sesión'),
          centerTitle: true,
          bottom: const TabBar(
            indicatorColor: Colors.greenAccent,
            labelColor: Colors.greenAccent,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.person_outline), text: 'Cliente'),
              Tab(icon: Icon(Icons.local_taxi_outlined), text: 'Taxista'),
            ],
          ),
        ),
        body: const TabBarView(
          physics: BouncingScrollPhysics(),
          children: [
            // 👇 Reusamos tus pantallas existentes
            LoginCliente(),
            LoginTaxista(),
          ],
        ),
      ),
    );
  }
}

