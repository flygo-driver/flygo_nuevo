// lib/pantallas/taxista/taxista_home.dart
import 'package:flutter/material.dart';

import '../../widgets/taxista_drawer.dart';
import 'viaje_disponible.dart';
import 'viaje_en_curso_taxista.dart';
import 'ganancia_taxista.dart';

class TaxistaHome extends StatelessWidget {
  const TaxistaHome({super.key});

  void _go(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const TaxistaDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            tooltip: 'Menú',
          ),
        ),
        title: const Text(
          'FlyGo • Taxista',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // Ver viajes disponibles
              ElevatedButton.icon(
                onPressed: () => _go(context, const ViajeDisponible()),
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Ver viajes disponibles',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.green,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Mi viaje en curso
              OutlinedButton.icon(
                onPressed: () => _go(context, const ViajeEnCursoTaxista()),
                icon: const Icon(Icons.directions_car),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Mi viaje en curso',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.greenAccent, width: 2),
                  foregroundColor: Colors.greenAccent,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Mis ganancias
              OutlinedButton.icon(
                onPressed: () => _go(context, const GananciaTaxista()),
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Mis ganancias',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.greenAccent, width: 2),
                  foregroundColor: Colors.greenAccent,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
