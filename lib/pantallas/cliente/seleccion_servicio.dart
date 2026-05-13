// lib/pantallas/cliente/seleccion_servicio.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/cliente/bola_conductores_en_ruta_cliente.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje_multi.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/custom_theme_service.dart';
import 'package:flygo_nuevo/utilidades/constante.dart' show rutaBolaPueblo;
import 'package:flygo_nuevo/pantallas/servicios_extras/pools_cliente_lista.dart';
import 'package:flygo_nuevo/widgets/cliente_bloqueo_gate.dart';
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
    // Gate de SOLO LECTURA: si `usuarios/{uid}.bloqueado == true`, muestra
    // pantalla de "Cuenta bloqueada" en vez de permitir acceder a los flujos
    // de pedir/programar viaje. No modifica navegación ni escribe en
    // Firestore; el desbloqueo se hace desde el panel admin existente.
    return ClienteBloqueoGate(
      child: _buildContenido(context),
    );
  }

  Widget _buildContenido(BuildContext context) {
    // El fondo viene del Theme global (que el usuario puede personalizar
    // desde Apariencia). Los textos se calculan automáticamente por contraste
    // WCAG sobre ese fondo, así sea blanco, negro, rojo, amarillo, etc.
    final Color bgScaffold = Theme.of(context).scaffoldBackgroundColor;
    final Color appBarBg = bgScaffold;
    final bool isDarkBg =
        ThemeData.estimateBrightnessForColor(bgScaffold) == Brightness.dark;
    final Color textPrimary = CustomThemeService.textOn(bgScaffold);
    final Color textMuted = CustomThemeService.textMutedOn(bgScaffold);
    final Color sectionLabel = CustomThemeService.textSubtleOn(bgScaffold);
    final Color promoBorder = CustomThemeService.borderOn(bgScaffold);
    final Color promoBg = CustomThemeService.cardOn(bgScaffold);
    final Color verConductoresColor =
        isDarkBg ? const Color(0xFFFFB74D) : const Color(0xFFE8590C);
    final Color footerColor = CustomThemeService.textSubtleOn(bgScaffold);

    return Scaffold(
      backgroundColor: bgScaffold,
      appBar: AppBar(
        backgroundColor: appBarBg,
        surfaceTintColor: Colors.transparent,
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
                        bannerEncabezado != null ? 8 : 20,
                        20,
                        10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '¿A dónde quieres ir?',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Pide ahora, programados u otras formas de viajar',
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
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
                          const SizedBox(height: 8),
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              tapTargetSize: MaterialTapTargetSize.padded,
                            ),
                            onPressed: () => NavigationService.push(
                              const BolaConductoresEnRutaClientePage(),
                            ),
                            child: Text(
                              'Ver conductores en ruta (desde dónde van)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: verConductoresColor,
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
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                      child: Text(
                        'Más formas de viajar',
                        style: TextStyle(
                          color: sectionLabel,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
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
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: promoBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: promoBorder),
                        ),
                        child: const ClipRRect(
                          borderRadius: BorderRadius.all(Radius.circular(15)),
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
                      color: footerColor,
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: cardWidth,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withValues(alpha: isDark ? 0.32 : 0.16),
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

/// Pide ahora + Programados — tarjetas horizontales iguales. Soportan tema.
class _HomeWhereToRow extends StatelessWidget {
  const _HomeWhereToRow({
    required this.onPedirAhora,
    required this.onProgramar,
  });

  final VoidCallback onPedirAhora;
  final VoidCallback onProgramar;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color titleColor = isDark ? Colors.white : const Color(0xFF101828);
    final Color subtitleColor = isDark
        ? Colors.white.withValues(alpha: 0.65)
        : const Color(0xFF667085);

    // Verde de marca para "Pide ahora" (acción primaria, debe destacar).
    final Color greenSolid =
        isDark ? const Color(0xFF22C55E) : const Color(0xFF10B981);
    final Color greenCardBg =
        isDark ? const Color(0xFF0F2117) : const Color(0xFFF0FDF4);
    final Color greenCardBorder =
        isDark ? const Color(0xFF22C55E) : const Color(0xFF34D399);

    // Azul para "Programados" (acción secundaria con identidad propia).
    final Color blueSolid =
        isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);
    final Color blueCardBg =
        isDark ? const Color(0xFF0F1A2E) : const Color(0xFFEFF6FF);
    final Color blueCardBorder =
        isDark ? const Color(0xFF3B82F6) : const Color(0xFF60A5FA);

    Widget card({
      required VoidCallback onTap,
      required IconData icon,
      required Color iconSolidBg,
      required Color cardBg,
      required Color cardBorder,
      required String title,
      required String subtitle,
    }) {
      return Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cardBorder, width: 1.4),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: iconSolidBg
                    .withValues(alpha: isDark ? 0.18 : 0.14),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: iconSolidBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: iconSolidBg,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final Widget pideAhoraCard = card(
      onTap: onPedirAhora,
      icon: Icons.bolt_rounded,
      iconSolidBg: greenSolid,
      cardBg: greenCardBg,
      cardBorder: greenCardBorder,
      title: 'Pide ahora',
      subtitle: 'Llega en minutos',
    );

    final Widget programadosCard = card(
      onTap: onProgramar,
      icon: Icons.event_rounded,
      iconSolidBg: blueSolid,
      cardBg: blueCardBg,
      cardBorder: blueCardBorder,
      title: 'Programados',
      subtitle: 'Elige fecha y hora',
    );

    return LayoutBuilder(
      builder: (context, c) {
        final bool narrow = c.maxWidth < 340;
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pideAhoraCard,
              const SizedBox(height: 10),
              programadosCard,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: pideAhoraCard),
            const SizedBox(width: 12),
            Expanded(child: programadosCard),
          ],
        );
      },
    );
  }
}

/// Bola Ahorro: tarjeta destacada con fondo de color suave (naranja) y soporte tema.
class _FeaturedBolaAhorroCard extends StatelessWidget {
  const _FeaturedBolaAhorroCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final TextStyle titleWord = TextStyle(
      color: isDark ? Colors.white : const Color(0xFF7C2D12),
      fontSize: 17,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.2,
      height: 1.05,
    );
    final Color subtitleColor = isDark
        ? Colors.white.withValues(alpha: 0.94)
        : const Color(0xFF9A3412);
    final Color chevronColor = isDark
        ? Colors.white.withValues(alpha: 0.9)
        : const Color(0xFFEA580C);
    final BoxDecoration deco = isDark
        ? BoxDecoration(
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
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          )
        : BoxDecoration(
            color: const Color(0xFFFFF4E6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFDBA74)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEA580C).withValues(alpha: 0.10),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: deco,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
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
                          Text('Bola', style: titleWord),
                          Image.asset(
                            'assets/icon/logo_rai_vertical.png',
                            height: 22,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                          Text('Ahorro', style: titleWord),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Viajes compartidos hasta 50% más baratos',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: chevronColor,
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
