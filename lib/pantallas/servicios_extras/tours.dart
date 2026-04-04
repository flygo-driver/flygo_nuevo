import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje_multi.dart';
import 'package:flygo_nuevo/pantallas/servicios_extras/pools_cliente_lista.dart';

class ToursTuristicosScreen extends StatelessWidget {
  const ToursTuristicosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textPrimary = isDark ? Colors.white : const Color(0xFF101828);
    final Color textSecondary = isDark ? Colors.white70 : const Color(0xFF475467);
    final Color accent = isDark ? Colors.greenAccent : const Color(0xFF0F9D58);
    final Color tipColor = isDark ? Colors.greenAccent : const Color(0xFF0B6B3A);
    final Color cardBg = isDark ? const Color(0xFF121212) : Colors.white;
    final Color cardBorder = isDark ? Colors.white24 : const Color(0xFFD0D5DD);
    final Color scaffoldBg = isDark ? Colors.black : const Color(0xFFE8EAED);

    final cardDecoration = BoxDecoration(
      color: cardBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: cardBorder),
    );

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: textPrimary,
        elevation: isDark ? 0 : 0.5,
        title: Text(
          'Tours / Giras Turísticas',
          style: TextStyle(color: accent, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: cardDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tours privados o en grupo con FlyGo',
                  style: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Programa recorridos a playas, montañas, ciudades cercanas o rutas gastronómicas. '
                  'Coordina el transporte con puntualidad y elige el vehículo ideal (carro, jeepeta, minivan, guagua).',
                  style: TextStyle(color: textSecondary, height: 1.35),
                ),
                const SizedBox(height: 10),
                Text(
                  'Tip: si habrá varias paradas, usa "múltiples paradas".',
                  style: TextStyle(color: tipColor, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProgramarViaje(modoAhora: false)),
                );
              },
              icon: const Icon(Icons.event_available),
              label: const Text('Programar tour (fecha y hora)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: isDark ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProgramarViajeMulti()),
                );
              },
              icon: Icon(Icons.alt_route, color: accent),
              label: const Text('Programar tour con múltiples paradas'),
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withValues(alpha: 0.8)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PoolsClienteLista(tipo: 'tour'),
                  ),
                );
              },
              icon: Icon(Icons.groups, color: accent),
              label: const Text('Ver tours/giras por cupos de agencias'),
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withValues(alpha: 0.8)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
