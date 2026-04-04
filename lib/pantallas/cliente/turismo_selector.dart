import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

class TurismoSelector extends StatelessWidget {
  const TurismoSelector({super.key});

  final List<Map<String, dynamic>> _opciones = const [
    {
      'subtipo': 'carro',
      'titulo': 'Carro Turismo',
      'subtitulo': '4 pasajeros • Aeropuertos, city tours',
      'icono': Icons.directions_car,
      'color': Colors.purple,
      'descripcion': 'Ideal para traslados ejecutivos y city tours',
    },
    {
      'subtipo': 'jeepeta',
      'titulo': 'Jeepeta Turismo',
      'subtitulo': '6 pasajeros • Montañas, playas',
      'icono': Icons.directions_car,
      'color': Colors.deepPurple,
      'descripcion': 'Perfecta para aventuras y terrenos difíciles',
    },
    {
      'subtipo': 'minivan',
      'titulo': 'Minivan Turismo',
      'subtitulo': '8 pasajeros • Grupos familiares',
      'icono': Icons.directions_bus,
      'color': Colors.indigo,
      'descripcion': 'Comodidad para toda la familia',
    },
    {
      'subtipo': 'bus',
      'titulo': 'Bus Turismo',
      'subtitulo': '15 pasajeros • Excursiones',
      'icono': Icons.directions_bus,
      'color': Colors.blue,
      'descripcion': 'Para grupos grandes y excursiones',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: const RaiAppBar(
        title: '🏝️ Turismo',
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Elige tu vehículo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Selecciona el tipo de vehículo para tu experiencia turística',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              
              Expanded(
                child: ListView.separated(
                  itemCount: _opciones.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final op = _opciones[i];
                    return _TarjetaVehiculoTurismo(
                      subtipo: op['subtipo'],
                      titulo: op['titulo'],
                      subtitulo: op['subtitulo'],
                      descripcion: op['descripcion'],
                      icono: op['icono'],
                      color: op['color'],
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
                        'Todos nuestros vehículos turísticos incluyen aire acondicionado y seguro de viaje.',
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

class _TarjetaVehiculoTurismo extends StatelessWidget {
  final String subtipo;
  final String titulo;
  final String subtitulo;
  final String descripcion;
  final IconData icono;
  final Color color;

  const _TarjetaVehiculoTurismo({
    required this.subtipo,
    required this.titulo,
    required this.subtitulo,
    required this.descripcion,
    required this.icono,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          // Navegar a programar viaje con el tipo de turismo seleccionado
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