// lib/pantallas/cliente/seleccion_servicio.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje_multi.dart';
import 'package:flygo_nuevo/pantallas/servicios_extras/pools_cliente_lista.dart';
import 'package:flygo_nuevo/widgets/cliente_drawer.dart';
import 'package:flygo_nuevo/widgets/selector_destinos_turisticos.dart';
import 'package:flygo_nuevo/widgets/pedir_ahora_taxi_animation.dart';
import 'package:flygo_nuevo/widgets/motor_servicio_animation.dart';
import 'package:flygo_nuevo/widgets/giras_cupos_animation.dart';
import 'package:flygo_nuevo/widgets/turismo_servicio_animation.dart';
import 'package:flygo_nuevo/widgets/promo_taxi_pista_animation.dart';

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
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 52),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                slivers: [
                  if (bannerEncabezado != null)
                    SliverToBoxAdapter(child: bannerEncabezado!),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('¡Hola! 👋',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 15)),
                          SizedBox(height: 4),
                          Text('¿A dónde quieres ir?',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3)),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Builder(
                      builder: (context) {
                        final h = MediaQuery.sizeOf(context).height;
                        final stripH = (h * 0.42).clamp(252.0, 400.0);
                        return SizedBox(
                          height: stripH,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: [
                              _buildGiantServiceCard(
                                context,
                                id: 'ahora',
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF00C853),
                                    Color(0xFF009624)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                icon: Icons.flash_on,
                                iconSize: 44,
                                customHeader: const PedirAhoraTaxiAnimation(),
                                title: 'PEDIR\nAHORA',
                                titleSize: 30,
                                subtitle: 'Llega en minutos',
                                price: 'DESDE RD\$ 50',
                                features: const [
                                  '⚡ Inmediato',
                                  '🛵 Motor',
                                  '🚗 Turismo'
                                ],
                                badge: const Icon(Icons.timer,
                                    color: Colors.white, size: 18),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ProgramarViaje(modoAhora: true),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 12),
                              _buildGiantServiceCard(
                                context,
                                id: 'programar',
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF2979FF),
                                    Color(0xFF0D47A1)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                icon: Icons.calendar_month,
                                iconSize: 44,
                                title: 'PROGRAMAR\nVIAJE',
                                titleSize: 28,
                                subtitle: 'Elige fecha y hora',
                                price: 'ANTICIPADO',
                                features: const [
                                  '📅 Hasta 7 días',
                                  '🕐 Recordatorio',
                                  '✅ Confirmación'
                                ],
                                badge: const Icon(Icons.event_available,
                                    color: Colors.white, size: 18),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const ProgramarViaje(
                                          modoAhora: false),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 12),
                              _buildGiantServiceCard(
                                context,
                                id: 'multi',
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFF5252),
                                    Color(0xFFD32F2F)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                icon: Icons.route,
                                iconSize: 44,
                                title: 'MÚLTIPLES\nPARADAS',
                                titleSize: 26,
                                subtitle: 'Hasta 3 paradas',
                                price: 'FLEXIBLE',
                                features: const [
                                  '📍 3 paradas',
                                  '🔄 Cambia ruta',
                                  '💰 Mismo precio'
                                ],
                                badge: const Icon(Icons.alt_route,
                                    color: Colors.white, size: 18),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ProgramarViajeMulti(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 12),
                              _buildGiantServiceCard(
                                context,
                                id: 'motor',
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFF9100),
                                    Color(0xFFE65100)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                icon: Icons.two_wheeler,
                                iconSize: 48,
                                customHeader: const MotorServicioAnimation(),
                                title: 'MOTOR',
                                titleSize: 36,
                                subtitle: 'Rápido y económico',
                                price: 'DESDE RD\$ 50',
                                features: const [
                                  '💨 1 pasajero',
                                  '⚡ Anti-tráfico',
                                  '🎧 Casco incluido'
                                ],
                                badge: const Icon(Icons.speed,
                                    color: Colors.white, size: 18),
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
                              const SizedBox(width: 12),
                              _buildGiantServiceCard(
                                context,
                                id: 'cupos',
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF00ACC1),
                                    Color(0xFF006064)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                icon: Icons.groups_2,
                                iconSize: 46,
                                customHeader: const GirasCuposAnimation(),
                                title: 'GIRAS POR\nCUPOS',
                                titleSize: 28,
                                subtitle: 'Viajes de agencias',
                                price: 'CATÁLOGO',
                                features: const [
                                  '🏢 Agencias',
                                  '🚌 Tours y consulares',
                                  '🎟️ Reserva cupos'
                                ],
                                badge: const Icon(Icons.travel_explore,
                                    color: Colors.white, size: 18),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const PoolsClienteLista(
                                          tipo: 'todos'),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 12),
                              _buildGiantServiceCard(
                                context,
                                id: 'turismo',
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFAA00FF),
                                    Color(0xFF4A0072)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                icon: Icons.beach_access,
                                iconSize: 48,
                                customHeader: const TurismoServicioAnimation(),
                                title: 'TURISMO',
                                titleSize: 32,
                                subtitle: 'Aeropuertos, hoteles',
                                price: 'DESDE RD\$ 150',
                                features: const [
                                  '🏨 Traslados',
                                  '✈️ Aeropuerto',
                                  '📍 Tours'
                                ],
                                badge: const Icon(Icons.airplanemode_active,
                                    color: Colors.white, size: 18),
                                onTap: () {
                                  _mostrarSelectorDestinos(context);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 6, 20, 18),
                      child: PromoTaxiPistaAnimation(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Center(
                  child: Text(
                    'by Rai Driver',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade400,
                      letterSpacing: 1.35,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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

      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (scaffoldContext.mounted) {
          Navigator.of(scaffoldContext).pop(); // Cerrar indicador

          ScaffoldMessenger.of(scaffoldContext).showSnackBar(
            const SnackBar(
              content: Text(
                  'Necesitamos tu ubicación para mostrar destinos turísticos'),
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
    Widget? customHeader,
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
        width: 218,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 14,
              spreadRadius: 0,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PatternPainter(
                    color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: badge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double headerH =
                      (constraints.maxHeight - 4).clamp(0.0, 86.0);
                  const double headerDesignW = 200;
                  const double headerDesignH = 86;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: headerH,
                        width: double.infinity,
                        child: headerH <= 0
                            ? const SizedBox.shrink()
                            : customHeader != null
                                ? FittedBox(
                                    fit: BoxFit.contain,
                                    alignment: Alignment.centerLeft,
                                    clipBehavior: Clip.hardEdge,
                                    child: SizedBox(
                                      width: headerDesignW,
                                      height: headerDesignH,
                                      child: customHeader,
                                    ),
                                  )
                                : Align(
                                    alignment: Alignment.centerLeft,
                                    child: FittedBox(
                                      fit: BoxFit.contain,
                                      child: Icon(
                                        icon,
                                        color: Colors.white,
                                        size:
                                            math.min(iconSize, headerH * 0.85),
                                      ),
                                    ),
                                  ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                softWrap: true,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.w800,
                                  height: 1.02,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  price,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 7),
                              ...features.map(
                                (feature) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.check,
                                          color: Colors.white, size: 13),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          feature,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.88),
                                            fontSize: 11,
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
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
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
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
