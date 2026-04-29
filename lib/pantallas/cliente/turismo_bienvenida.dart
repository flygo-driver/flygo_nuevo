import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/cliente/turismo_selector_screen.dart';
import 'package:flygo_nuevo/pantallas/cliente/turismo_selector.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

class TurismoBienvenida extends StatelessWidget {
  const TurismoBienvenida({super.key});

  final List<Map<String, dynamic>> _opciones = const [
    {
      'icon': Icons.map,
      'color': Colors.purple,
      'titulo': 'Por destino turístico',
      'subtitulo': 'Aeropuertos, playas, hoteles, tours',
      'descripcion': 'Selecciona primero el lugar que quieres visitar',
      'screen': 'destino',
    },
    {
      'icon': Icons.directions_car,
      'color': Colors.orange,
      'titulo': 'Por tipo de vehículo',
      'subtitulo': 'Carro, jeepeta, minivan, bus',
      'descripcion': 'Elige primero el vehículo que necesitas',
      'screen': 'vehiculo',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: const RaiAppBar(
        title: '🏝️ Turismo RAI',
        backWhenCanPop: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '¿Cómo quieres\nbuscar tu viaje?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Elige la opción que prefieras',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 32),

              // Opciones dinámicas
              ..._opciones.map((Map<String, dynamic> opcion) {
                return _buildOpcion(
                  context,
                  icon: opcion['icon'] as IconData,
                  color: opcion['color'] as Color,
                  titulo: opcion['titulo'] as String,
                  subtitulo: opcion['subtitulo'] as String,
                  descripcion: opcion['descripcion'] as String,
                  screen: opcion['screen'] as String,
                );
              }).toList(),

              const SizedBox(height: 24),

              // Información adicional
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.purple.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: <Widget>[
                    Icon(Icons.info_outline, color: Colors.purple, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Todos los viajes turísticos incluyen seguro y asistencia 24/7',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOpcion(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String titulo,
    required String subtitulo,
    required String descripcion,
    required String screen,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (screen == 'destino') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const TurismoSelectorScreen(),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const TurismoSelector(),
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF121212),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: color.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, color: color, size: 30),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            titulo,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitulo,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: color,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_forward,
                        color: color,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          descripcion,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
