// lib/pantallas/cliente/seleccion_servicio.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/cliente/bola_conductores_en_ruta_cliente.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje_multi.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/utilidades/constante.dart' show rutaBolaPueblo;
import 'package:flygo_nuevo/pantallas/servicios_extras/pools_cliente_lista.dart';
import 'package:flygo_nuevo/widgets/turismo_destinos_sheet_host.dart';
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
      appBar: AppBar(
        backgroundColor: Colors.black,
        automaticallyImplyLeading: false,
        leading: const SizedBox(width: 48),
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
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        bannerEncabezado != null ? 6 : 16,
                        20,
                        8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '¿A dónde quieres ir?',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.35,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Pide ahora, programados u otras formas de viajar',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: _HomeWhereToRow(
                        onPedirAhora: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const ProgramarViaje(modoAhora: true),
                            ),
                          );
                        },
                        onProgramar: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const ProgramarViaje(modoAhora: false),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _FeaturedBolaAhorroCard(
                            onTap: () =>
                                Navigator.of(context, rootNavigator: true)
                                    .pushNamed(rutaBolaPueblo),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              tapTargetSize: MaterialTapTargetSize.padded,
                            ),
                            onPressed: () => NavigationService.push(
                              const BolaConductoresEnRutaClientePage(),
                            ),
                            child: const Text(
                              'Ver conductores en ruta (desde dónde van)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFFFB74D),
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text(
                        'Más formas de viajar',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Builder(
                      builder: (context) {
                        final h = MediaQuery.sizeOf(context).height;
                        final stripH = (h * 0.26).clamp(196.0, 268.0);
                        return SizedBox(
                          height: stripH,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: [
                              _buildGiantServiceCard(
                                context,
                                id: 'programar',
                                cardWidth: 162,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF2979FF),
                                    Color(0xFF0D47A1)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                icon: Icons.calendar_month,
                                iconSize: 30,
                                title: 'PROGRAMAR\nVIAJE',
                                titleSize: 16,
                                subtitle: 'Elige fecha y hora',
                                price: 'ANTICIPADO',
                                features: const [
                                  '📅 Hasta 7 días',
                                  '🕐 Recordatorio',
                                ],
                                badge: const Icon(Icons.event_available,
                                    color: Colors.white, size: 16),
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
                              const SizedBox(width: 10),
                              _buildGiantServiceCard(
                                context,
                                id: 'multi',
                                cardWidth: 162,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFF5252),
                                    Color(0xFFD32F2F)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                icon: Icons.route,
                                iconSize: 30,
                                title: 'MÚLTIPLES\nPARADAS',
                                titleSize: 15,
                                subtitle: 'Hasta 3 paradas',
                                price: 'FLEXIBLE',
                                features: const [
                                  '📍 3 paradas',
                                  '🔄 Cambia ruta',
                                ],
                                badge: const Icon(Icons.alt_route,
                                    color: Colors.white, size: 16),
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
                              const SizedBox(width: 10),
                              _buildGiantServiceCard(
                                context,
                                id: 'motor',
                                cardWidth: 162,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFF9100),
                                    Color(0xFFE65100)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                icon: Icons.two_wheeler,
                                iconSize: 32,
                                customHeader: const MotorServicioAnimation(),
                                title: 'MOTOR',
                                titleSize: 18,
                                subtitle: 'Rápido y económico',
                                price: 'DESDE RD\$ 50',
                                features: const [
                                  '💨 1 pasajero',
                                  '⚡ Anti-tráfico',
                                ],
                                badge: const Icon(Icons.speed,
                                    color: Colors.white, size: 16),
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
                              const SizedBox(width: 10),
                              _buildGiantServiceCard(
                                context,
                                id: 'cupos',
                                cardWidth: 162,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF00ACC1),
                                    Color(0xFF006064)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                icon: Icons.groups_2,
                                iconSize: 30,
                                customHeader: const GirasCuposAnimation(),
                                title: 'GIRAS POR\nCUPOS',
                                titleSize: 15,
                                subtitle: 'Viajes de agencias',
                                price: 'CATÁLOGO',
                                features: const [
                                  '🏢 Agencias',
                                  '🚌 Tours',
                                ],
                                badge: const Icon(Icons.travel_explore,
                                    color: Colors.white, size: 16),
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
                              const SizedBox(width: 10),
                              _buildGiantServiceCard(
                                context,
                                id: 'turismo',
                                cardWidth: 162,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFAA00FF),
                                    Color(0xFF4A0072)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                icon: Icons.beach_access,
                                iconSize: 32,
                                customHeader: const TurismoServicioAnimation(),
                                title: 'TURISMO',
                                titleSize: 17,
                                subtitle: 'Aeropuertos, hoteles',
                                price: 'DESDE RD\$ 150',
                                features: const [
                                  '🏨 Traslados',
                                  '✈️ Aeropuerto',
                                ],
                                badge: const Icon(Icons.airplanemode_active,
                                    color: Colors.white, size: 16),
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
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0A0A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.07),
                          ),
                        ),
                        child: const ClipRRect(
                          borderRadius: BorderRadius.all(Radius.circular(13)),
                          child: PromoTaxiPistaAnimation(),
                        ),
                      ),
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

  /// Turismo: abre el selector al toque; la ubicación se resuelve dentro del sheet.
  void _mostrarSelectorDestinos(BuildContext context) {
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => TurismoDestinosSheetHost(
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
  }

  Widget _buildGiantServiceCard(
    BuildContext context, {
    required String id,
    double cardWidth = 218,
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
    final bool compact = cardWidth < 200;
    final double radius = compact ? 16.0 : 20.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: cardWidth,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.38),
              blurRadius: compact ? 10 : 14,
              spreadRadius: 0,
              offset: Offset(0, compact ? 4 : 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PatternPainter(
                  color:
                      Colors.white.withValues(alpha: compact ? 0.035 : 0.055),
                  step: compact ? 30 : 24,
                  strokeWidth: compact ? 0.55 : 0.75,
                ),
              ),
            ),
            Positioned(
              top: compact ? 8 : 12,
              right: compact ? 8 : 12,
              child: Container(
                padding: EdgeInsets.all(compact ? 6 : 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: badge,
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 11 : 14,
                compact ? 9 : 12,
                compact ? 11 : 14,
                compact ? 11 : 14,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double headerH = (constraints.maxHeight - 4)
                      .clamp(0.0, compact ? 52.0 : 86.0);
                  final double headerDesignW = compact ? 140 : 200;
                  final double headerDesignH = compact ? 52 : 86;
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
                                  fontSize: compact ? 11 : 12.5,
                                  fontWeight: FontWeight.w500,
                                  height: 1.2,
                                ),
                              ),
                              SizedBox(height: compact ? 6 : 8),
                              Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: compact ? 8 : 10,
                                    vertical: compact ? 3 : 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  price,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: compact ? 9.5 : 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              SizedBox(height: compact ? 5 : 7),
                              ...features.map(
                                (feature) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.check,
                                          color: Colors.white,
                                          size: compact ? 11 : 13),
                                      SizedBox(width: compact ? 4 : 5),
                                      Expanded(
                                        child: Text(
                                          feature,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.88),
                                            fontSize: compact ? 10 : 11,
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

/// Pide ahora (gris) + Programados (azul). Mismas rutas: ahora / programar.
class _HomeWhereToRow extends StatelessWidget {
  const _HomeWhereToRow({
    required this.onPedirAhora,
    required this.onProgramar,
  });

  final VoidCallback onPedirAhora;
  final VoidCallback onProgramar;

  static const Color _barBg = Color(0xFF1C1C1E);
  static const Color _programadosBlue = Color(0xFF1565C0);

  Widget _barPedirAhora() {
    return Material(
      color: _barBg,
      borderRadius: BorderRadius.circular(26),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPedirAhora,
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(
                Icons.local_taxi_rounded,
                color: Colors.greenAccent.withValues(alpha: 0.85),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Pide ahora',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'Llega en minutos',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipProgramados() {
    return Material(
      color: _programadosBlue,
      borderRadius: BorderRadius.circular(26),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        onTap: onProgramar,
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.event_note_rounded,
                color: Colors.white.withValues(alpha: 0.95),
                size: 18,
              ),
              const SizedBox(width: 6),
              const Text(
                'Programados',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final bool narrow = c.maxWidth < 340;
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _barPedirAhora(),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: _chipProgramados(),
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: _barPedirAhora()),
            const SizedBox(width: 10),
            _chipProgramados(),
          ],
        );
      },
    );
  }
}

/// Bola Ahorro: una sola franja compacta (sin duplicar el bloque gigante de antes).
class _FeaturedBolaAhorroCard extends StatelessWidget {
  const _FeaturedBolaAhorroCard({required this.onTap});

  final VoidCallback onTap;

  static const TextStyle _titleWord = TextStyle(
    color: Colors.white,
    fontSize: 17,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
    height: 1.05,
  );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFFFF8C00),
                Color(0xFFFF6B35),
                Color(0xFFE65100),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        runSpacing: 2,
                        children: [
                          const Text('Bola', style: _titleWord),
                          Image.asset(
                            'assets/icon/logo_rai_vertical.png',
                            height: 22,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                          const Text('Ahorro', style: _titleWord),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Viajes compartidos hasta 50% más baratos',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.94),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 26,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  final Color color;
  final double step;
  final double strokeWidth;

  _PatternPainter({
    required this.color,
    this.step = 24,
    this.strokeWidth = 0.75,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    for (double i = 0; i < size.width; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += step) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.step != step ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
