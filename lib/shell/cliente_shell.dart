import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/widgets/cliente_drawer.dart';

class ClienteShell extends StatelessWidget {
  const ClienteShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const ClienteDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('FlyGo', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            tooltip: 'Menú',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _bigButton(
              context: context,
              title: 'Solicitar viaje ahora',
              subtitle: 'Usar mi ubicación actual',
              icon: Icons.rocket_launch_outlined,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProgramarViaje(modoAhora: true),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _bigButton(
              context: context,
              title: 'Programar viaje',
              subtitle: 'Elegir fecha y hora',
              icon: Icons.calendar_month_outlined,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProgramarViaje(modoAhora: false),
                  ),
                );
              },
            ),
            const Spacer(),
            const Text(
              'Usa el menú para:\n'
              '• Ver estado de mi viaje\n'
              '• Historial de viajes y pagos\n'
              '• Soporte y más',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _bigButton({
    required BuildContext context,
    required String title,
    String? subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.greenAccent, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}
