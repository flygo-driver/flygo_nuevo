import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

class TurismoSelectorScreen extends StatelessWidget {
  const TurismoSelectorScreen({super.key});

  final List<Map<String, dynamic>> _destinos = const [
    {
      'titulo': 'Aeropuertos',
      'subtitulo': 'SDQ, STI, PUJ, AZS, POP',
      'icono': Icons.flight_takeoff,
      'subtipo': 'aeropuerto',
      'color': Colors.blue,
      'descripcion': 'Traslados a todos los aeropuertos del país',
    },
    {
      'titulo': 'Hoteles',
      'subtitulo': 'Plaza, city hotel, boutique, todo incluido',
      'icono': Icons.hotel,
      'subtipo': 'hotel',
      'color': Colors.green,
      'descripcion': 'Recogida y regreso a tu hotel',
    },
    {
      'titulo': 'Resorts',
      'subtitulo': 'Punta Cana, Bávaro, La Romana, Puerto Plata',
      'icono': Icons.apartment,
      'subtipo': 'resort',
      'color': Colors.orange,
      'descripcion': 'Traslados a los mejores resorts',
    },
    {
      'titulo': 'Playas',
      'subtitulo': 'Bávaro, Macao, Juanillo, Sosúa, Cofresí',
      'icono': Icons.beach_access,
      'subtipo': 'playa',
      'color': Colors.cyan,
      'descripcion': 'Tours a las playas más hermosas',
    },
    {
      'titulo': 'Tours',
      'subtitulo': 'Excursiones, city tours, aventura',
      'icono': Icons.map_outlined,
      'subtipo': 'tour',
      'color': Colors.purple,
      'descripcion': 'Rutas turísticas personalizadas',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: const RaiAppBar(
        title: '🏝️ Turismo RAI',
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '¿Qué tipo de destino\nturístico buscas?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Selecciona la categoría de tu viaje',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              
              Expanded(
                child: ListView.separated(
                  itemCount: _destinos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final destino = _destinos[i];
                    return _TarjetaDestinoTurismo(
                      titulo: destino['titulo'],
                      subtitulo: destino['subtitulo'],
                      descripcion: destino['descripcion'],
                      icono: destino['icono'],
                      color: destino['color'],
                      subtipo: destino['subtipo'],
                    );
                  },
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Información adicional
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.purple, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Todos los viajes turísticos son gestionados por nuestro equipo de expertos.',
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
}

class _TarjetaDestinoTurismo extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final String descripcion;
  final IconData icono;
  final Color color;
  final String subtipo;

  const _TarjetaDestinoTurismo({
    required this.titulo,
    required this.subtitulo,
    required this.descripcion,
    required this.icono,
    required this.color,
    required this.subtipo,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProgramarViaje(
                modoAhora: true,
                tipoServicio: 'turismo',
                subtipoTurismo: subtipo,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icono, color: color, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitulo,
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
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        descripcion,
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
    );
  }
}