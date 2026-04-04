// lib/pantallas/cliente/seleccion_servicio.dart
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje_multi.dart';
import 'package:flygo_nuevo/pantallas/servicios_extras/pools_cliente_lista.dart';
import 'package:flygo_nuevo/widgets/cliente_drawer.dart';
import 'package:flygo_nuevo/widgets/selector_destinos_turisticos.dart';

class SeleccionServicio extends StatelessWidget {
  const SeleccionServicio({super.key, this.bannerEncabezado});

  /// Aviso opcional (p. ej. completar registro tras Google) — no bloquea el uso de la app.
  final Widget? bannerEncabezado;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const ClienteDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: 'Menú',
          ),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            SizedBox(
              height: 40,
              child: Image.asset(
                'assets/icon/logo_rai_vertical.png',
                fit: BoxFit.contain,
              ),
            ),
            const Spacer(),
          ],
        ),
        centerTitle: false,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (bannerEncabezado != null) bannerEncabezado!,
            const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('¡Hola! 👋', style: TextStyle(color: Colors.white70, fontSize: 18)),
                  SizedBox(height: 4),
                  Text('¿A dónde quieres ir?',
                      style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
                ],
              ),
            ),

            SizedBox(
              height: 380,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _buildGiantServiceCard(
                    context,
                    id: 'ahora',
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00C853), Color(0xFF009624)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    icon: Icons.flash_on,
                    iconSize: 60,
                    title: 'PEDIR\nAHORA',
                    titleSize: 42,
                    subtitle: 'Llega en minutos',
                    price: 'DESDE RD\$ 50',
                    features: const ['⚡ Inmediato', '🛵 Motor', '🚗 Turismo'],
                    badge: const Icon(Icons.timer, color: Colors.white, size: 24),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProgramarViaje(modoAhora: true),
                        ),
                      );
                    },
                  ),

                  const SizedBox(width: 16),

                  _buildGiantServiceCard(
                    context,
                    id: 'programar',
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2979FF), Color(0xFF0D47A1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    icon: Icons.calendar_month,
                    iconSize: 60,
                    title: 'PROGRAMAR\nVIAJE',
                    titleSize: 38,
                    subtitle: 'Elige fecha y hora',
                    price: 'ANTICIPADO',
                    features: const ['📅 Hasta 7 días', '🕐 Recordatorio', '✅ Confirmación'],
                    badge: const Icon(Icons.event_available, color: Colors.white, size: 24),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProgramarViaje(modoAhora: false),
                        ),
                      );
                    },
                  ),

                  const SizedBox(width: 16),

                  _buildGiantServiceCard(
                    context,
                    id: 'multi',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    icon: Icons.route,
                    iconSize: 60,
                    title: 'MÚLTIPLES\nPARADAS',
                    titleSize: 36,
                    subtitle: 'Hasta 3 paradas',
                    price: 'FLEXIBLE',
                    features: const ['📍 3 paradas', '🔄 Cambia ruta', '💰 Mismo precio'],
                    badge: const Icon(Icons.alt_route, color: Colors.white, size: 24),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProgramarViajeMulti(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(width: 16),

                  _buildGiantServiceCard(
                    context,
                    id: 'motor',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF9100), Color(0xFFE65100)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    icon: Icons.two_wheeler,
                    iconSize: 70,
                    title: 'MOTOR',
                    titleSize: 52,
                    subtitle: 'Rápido y económico',
                    price: 'DESDE RD\$ 50',
                    features: const ['💨 1 pasajero', '⚡ Anti-tráfico', '🎧 Casco incluido'],
                    badge: const Icon(Icons.speed, color: Colors.white, size: 24),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProgramarViaje(
                            modoAhora: true,
                            tipoServicio: 'motor',
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(width: 16),

                  _buildGiantServiceCard(
                    context,
                    id: 'cupos',
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00ACC1), Color(0xFF006064)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    icon: Icons.groups_2,
                    iconSize: 64,
                    title: 'GIRAS /\nCUPOS',
                    titleSize: 42,
                    subtitle: 'Viajes de agencias',
                    price: 'CATÁLOGO',
                    features: const ['🏢 Agencias', '🚌 Tours y consulares', '🎟️ Reserva cupos'],
                    badge: const Icon(Icons.travel_explore, color: Colors.white, size: 24),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PoolsClienteLista(tipo: 'todos'),
                        ),
                      );
                    },
                  ),

                  const SizedBox(width: 16),

                  _buildGiantServiceCard(
                    context,
                    id: 'turismo',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFAA00FF), Color(0xFF4A0072)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    icon: Icons.beach_access,
                    iconSize: 70,
                    title: 'TURISMO',
                    titleSize: 48,
                    subtitle: 'Aeropuertos, hoteles',
                    price: 'DESDE RD\$ 150',
                    features: const ['🏨 Traslados', '✈️ Aeropuerto', '📍 Tours'],
                    badge: const Icon(Icons.airplanemode_active, color: Colors.white, size: 24),
                    onTap: () {
                      _mostrarSelectorDestinos(context);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.greenAccent.withValues(alpha: 0.15), Colors.transparent],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3), width: 1.5),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.local_offer, color: Colors.greenAccent, size: 28),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('15% DE DESCUENTO',
                              style: TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('Usa código: RAI15 en tu primer viaje',
                              style: TextStyle(color: Colors.white70, fontSize: 14)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🎯 FUNCIÓN OPTIMIZADA PARA PRODUCCIÓN - SIN MENSAJE GIGANTE
  void _mostrarSelectorDestinos(BuildContext context) async {
    final scaffoldContext = context;
    
    if (!scaffoldContext.mounted) return;

    // ✅ INDICADOR DISCRETO (solo ruedita, sin texto)
    showDialog(
      context: scaffoldContext,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          color: Colors.purple,
          strokeWidth: 3,
        ),
      ),
    );

    try {
      // Verificar permisos
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      
      if (!scaffoldContext.mounted) return;
      
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (scaffoldContext.mounted) {
          Navigator.of(scaffoldContext).pop(); // Cerrar indicador
          
          ScaffoldMessenger.of(scaffoldContext).showSnackBar(
            const SnackBar(
              content: Text('Necesitamos tu ubicación para mostrar destinos turísticos'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Obtener ubicación (precisión medium para velocidad)
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      if (!scaffoldContext.mounted) return;

      // Cerrar indicador
      if (scaffoldContext.mounted) {
        Navigator.of(scaffoldContext).pop();
      }

      // Abrir selector
      if (!scaffoldContext.mounted) return;
      
      showModalBottomSheet(
        context: scaffoldContext,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (modalContext) => SelectorDestinosTuristicos(
          latOrigen: position.latitude,
          lonOrigen: position.longitude,
          tipoVehiculoInicial: 'carro',
          onDestinoSeleccionado: (seleccion) {
            if (!modalContext.mounted) return;
            Navigator.push(
              modalContext,
              MaterialPageRoute(
                builder: (_) => ProgramarViaje(
                  modoAhora: true,
                  tipoServicio: 'turismo',
                  subtipoTurismo: seleccion.lugar.subtipo,
                  catalogoTurismoId: seleccion.lugar.id,
                  destinoPrecargado: seleccion.lugar.nombre,
                  latDestinoPrecargado: seleccion.lugar.lat,
                  lonDestinoPrecargado: seleccion.lugar.lon,
                ),
              ),
            );
          },
        ),
      );
    } catch (e) {
      if (scaffoldContext.mounted) {
        try {
          Navigator.of(scaffoldContext).pop(); // Cerrar indicador
        } catch (_) {}
        
        // ✅ CORREGIDO: Agregado 'const' para mejorar rendimiento
        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
          const SnackBar(
            content: Text('Error al obtener ubicación. Intenta de nuevo.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildGiantServiceCard(
    BuildContext context, {
    required String id,
    required Gradient gradient,
    required IconData icon,
    required double iconSize,
    required String title,
    required double titleSize,
    required String subtitle,
    required String price,
    required List<String> features,
    required Widget badge,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PatternPainter(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
            Positioned(
              top: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: badge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: Colors.white, size: iconSize),
                  const Spacer(),
                  Text(title,
                      style: TextStyle(color: Colors.white, fontSize: titleSize, fontWeight: FontWeight.w900, height: 1)),
                  const SizedBox(height: 8),
                  Text(subtitle,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(price, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  ...features.map((feature) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.check, color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text(feature,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13)),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  final Color color;
  _PatternPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1..style = PaintingStyle.stroke;
    for (double i = 0; i < size.width; i += 20) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 20) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}