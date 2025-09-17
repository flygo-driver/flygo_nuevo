import 'package:flutter/material.dart';

// Importa por paquete para evitar rutas relativas frágiles
import 'package:flygo_nuevo/pantallas/taxista/viaje_disponible.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/billetera_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/perfil_taxista.dart';

class TaxistaShell extends StatefulWidget {
  const TaxistaShell({super.key});

  @override
  State<TaxistaShell> createState() => _TaxistaShellState();
}

class _TaxistaShellState extends State<TaxistaShell> {
  int _currentIndex = 0;

  late final List<Widget> _pages = const [
    // 👇 Usa tu clase real
    ViajeDisponible(),
    ViajeEnCursoTaxista(),
    BilleteraTaxista(),
    PerfilTaxista(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.black,
        selectedItemColor: Colors.greenAccent,
        unselectedItemColor: Colors.white70,
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_car),
            label: 'Disponibles',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'En curso'),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Billetera',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}
