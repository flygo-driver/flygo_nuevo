import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/pantallas/cliente/bola_conductores_en_ruta_cliente.dart';
import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_actions.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje_multi.dart';
import 'package:flygo_nuevo/servicios/cliente_viaje_navegacion.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/bola_pueblo_repo.dart';
import 'package:flygo_nuevo/servicios/productos_config_service.dart';
import 'package:flygo_nuevo/servicios/custom_theme_service.dart';
import 'package:flygo_nuevo/utilidades/constante.dart' show rutaBolaPueblo, etiquetaBolaAhorroUi;
import 'package:flygo_nuevo/pantallas/servicios_extras/pools_cliente_lista.dart';
import 'package:flygo_nuevo/widgets/cliente_bloqueo_gate.dart';
import 'package:flygo_nuevo/widgets/promo_taxi_pista_animation.dart';
import 'package:flygo_nuevo/widgets/motor_servicio_animation.dart';
import 'package:flygo_nuevo/widgets/giras_cupos_animation.dart';
import 'package:flygo_nuevo/widgets/turismo_servicio_animation.dart';
import 'package:flygo_nuevo/widgets/rai_direccion_inteligente_sheet.dart';
import 'package:flygo_nuevo/widgets/rai_header_logo.dart';

/// Colores del inicio derivados del fondo real (Apariencia + claro/oscuro).
class _HomePalette {
  const _HomePalette({required this.scaffold, required this.card});

  final Color scaffold;
  final Color card;

  factory _HomePalette.of(BuildContext context) {
    final Color scaffold = Theme.of(context).scaffoldBackgroundColor;
    return _HomePalette(
      scaffold: scaffold,
      card: CustomThemeService.cardOn(scaffold),
    );
  }

  bool get scaffoldIsDark =>
      ThemeData.estimateBrightnessForColor(scaffold) == Brightness.dark;

  bool get cardIsDark =>
      ThemeData.estimateBrightnessForColor(card) == Brightness.dark;

  Color get textOnScaffold => CustomThemeService.textOn(scaffold);
  Color get textMutedScaffold => CustomThemeService.textMutedOn(scaffold);
  Color get textOnCard => CustomThemeService.textOn(card);
  Color get textMutedCard => CustomThemeService.textMutedOn(card);
  Color get borderScaffold => CustomThemeService.borderOn(scaffold);
  Color get borderCard => CustomThemeService.borderOn(card);

  /// Campo «¿A dónde vas?» y fondo del segmento no seleccionado.
  Color get inputFill => cardIsDark
      ? Colors.white.withValues(alpha: 0.07)
      : CustomThemeService.darken(card, 0.035);

  Color get cardShadow =>
      Colors.black.withValues(alpha: cardIsDark ? 0.32 : 0.08);

  Color get accentGreen =>
      scaffoldIsDark ? const Color(0xFF34D399) : const Color(0xFF059669);

  Color get conductoresAccent =>
      scaffoldIsDark ? const Color(0xFFFFB74D) : const Color(0xFFE8590C);
}

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
    return ValueListenableBuilder<int>(
      valueListenable: ProductosConfigService.revision,
      builder: (context, _, __) => _buildHome(context),
    );
  }

  Widget _buildHome(BuildContext context) {
    // El fondo viene del Theme global (que el usuario puede personalizar
    // desde Apariencia). Los textos se calculan automáticamente por contraste
    // WCAG sobre ese fondo, así sea blanco, negro, rojo, amarillo, etc.
    final _HomePalette palette = _HomePalette.of(context);
    final Color bgScaffold = palette.scaffold;
    final Color appBarBg = bgScaffold;
    final Color textPrimary = palette.textOnScaffold;
    final Color textMuted = palette.textMutedScaffold;
    final Color promoBorder = palette.borderScaffold;
    final Color promoBg = palette.card;
    final Color verConductoresColor = palette.conductoresAccent;

    return Scaffold(
      backgroundColor: bgScaffold,
      appBar: AppBar(
        backgroundColor: appBarBg,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        centerTitle: true,
        toolbarHeight: 56,
        elevation: 0,
        title: const RaiHeaderLogo(height: 38),
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
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.7,
                              height: 1.12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Toca abajo para pedir tu viaje en minutos',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      child: _HomePrimaryTripBlock(
                        onPedirAhora: () {
                          unawaited(ClienteViajeNavegacion.pushTrasVerificacion(
                            context,
                            const ProgramarViaje(modoAhora: true),
                          ));
                        },
                        onProgramar: () {
                          unawaited(ClienteViajeNavegacion.pushTrasVerificacion(
                            context,
                            const ProgramarViaje(modoAhora: false),
                          ));
                        },
                      ),
                    ),
                  ),
                  if (ProductosConfigService.muestraBola ||
                      ProductosConfigService.muestraConductoresEnRuta)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (ProductosConfigService.muestraBola) ...[
                              StreamBuilder<Map<String, String>?>(
                                stream: BolaPuebloRepo.streamBolaActivaCliente(
                                  FirebaseAuth.instance.currentUser?.uid ?? '',
                                ),
                                builder: (context, bolaSnap) {
                                  final Map<String, String>? bolaActiva =
                                      bolaSnap.data;
                                  return _FeaturedBolaAhorroCard(
                                    bolaActiva: bolaActiva,
                                    onTap: () async {
                                      if (bolaActiva != null) {
                                        final String? id = bolaActiva['id'];
                                        if (id != null && id.isNotEmpty) {
                                          await BolaPuebloDialogs
                                              .abrirModoViajeBolaPorId(
                                            context: context,
                                            bolaId: id,
                                          );
                                          return;
                                        }
                                      }
                                      if (!context.mounted) return;
                                      Navigator.of(context, rootNavigator: true)
                                          .pushNamed(rutaBolaPueblo);
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                            ],
                            if (ProductosConfigService.muestraConductoresEnRuta)
                              _HomeConductoresTile(
                                onTap: () => NavigationService.pushEnTabShell(
                                  context,
                                  const BolaConductoresEnRutaClientePage(),
                                ),
                                accentColor: verConductoresColor,
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (ProductosConfigService.hayOpcionesExtrasHome)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Más opciones',
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            Icon(Icons.swipe_rounded,
                                size: 18, color: textMuted),
                            const SizedBox(width: 4),
                            Text(
                              'Desliza',
                              style: TextStyle(
                                color: textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (ProductosConfigService.hayOpcionesExtrasHome)
                    SliverToBoxAdapter(
                      child: Builder(
                        builder: (context) {
                          final double h = MediaQuery.sizeOf(context).height;
                          final double stripH =
                              (h * 0.26).clamp(196.0, 268.0);
                          const double cardW = 168.0;
                          final cards = <Widget>[];
                          if (ProductosConfigService.muestraMultiparada) {
                            cards.add(
                              _HomeGiantServiceCard(
                                cardWidth: cardW,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFF5252),
                                    Color(0xFFD32F2F),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                icon: Icons.route,
                                iconSize: 30,
                                title: 'MÚLTIPLES\nPARADAS',
                                titleSize: 15,
                                subtitle: 'Hasta 5 paradas',
                                price: 'FLEXIBLE',
                                features: const [
                                  '📍 5 paradas',
                                  '🔄 Cambia ruta',
                                ],
                                badge: const Icon(Icons.alt_route,
                                    color: Colors.white, size: 16),
                                onTap: () {
                                  unawaited(ClienteViajeNavegacion.pushTrasVerificacion(
                                    context,
                                    const ProgramarViajeMulti(),
                                  ));
                                },
                              ),
                            );
                          }
                          if (ProductosConfigService.muestraMotor) {
                            if (cards.isNotEmpty) {
                              cards.add(const SizedBox(width: 10));
                            }
                            cards.add(
                              _HomeGiantServiceCard(
                                cardWidth: cardW,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFF9100),
                                    Color(0xFFE65100),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                icon: Icons.two_wheeler,
                                iconSize: 32,
                                customHeader: const MotorServicioAnimation(),
                                title: 'MOTORES',
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
                                  unawaited(ClienteViajeNavegacion.pushTrasVerificacion(
                                    context,
                                    const ProgramarViaje(
                                      modoAhora: true,
                                      tipoServicio: 'motor',
                                    ),
                                  ));
                                },
                              ),
                            );
                          }
                          if (ProductosConfigService.muestraGiras) {
                            if (cards.isNotEmpty) {
                              cards.add(const SizedBox(width: 10));
                            }
                            cards.add(
                              _HomeGiantServiceCard(
                                cardWidth: cardW,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF00ACC1),
                                    Color(0xFF006064),
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
                            );
                          }
                          if (ProductosConfigService.muestraTurismo) {
                            if (cards.isNotEmpty) {
                              cards.add(const SizedBox(width: 10));
                            }
                            cards.add(
                              _HomeGiantServiceCard(
                                cardWidth: cardW,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFAA00FF),
                                    Color(0xFF4A0072),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                icon: Icons.beach_access,
                                iconSize: 32,
                                customHeader:
                                    const TurismoServicioAnimation(),
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
                                onTap: () =>
                                    _mostrarEleccionTurismo(context),
                              ),
                            );
                          }
                          return SizedBox(
                            height: stripH,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              children: cards,
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
                      color: textMuted,
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

  /// Turismo: elegir Ahora o Programar y abrir [ProgramarViaje].
  Future<void> _mostrarEleccionTurismo(BuildContext context) async {
    if (!context.mounted) return;
    bool programar = false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                20 + MediaQuery.paddingOf(ctx).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Turismo RAI',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Traslados a aeropuertos, hoteles y destinos turísticos',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        icon: Icon(Icons.bolt_rounded, size: 18),
                        label: Text('Ahora'),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        icon: Icon(Icons.event_rounded, size: 18),
                        label: Text('Programar'),
                      ),
                    ],
                    selected: {programar},
                    onSelectionChanged: (selection) {
                      setModalState(() => programar = selection.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _abrirTurismoDesdeInicio(
                        context,
                        modoAhora: !programar,
                      );
                    },
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Continuar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFAA00FF),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _abrirTurismoDesdeInicio(
    BuildContext context, {
    required bool modoAhora,
  }) {
    if (!context.mounted) return;
    unawaited(ClienteViajeNavegacion.pushTrasVerificacion(
      context,
      ProgramarViaje(
        modoAhora: modoAhora,
        tipoServicio: 'turismo',
      ),
    ));
  }
}

/// Bloque superior: selector Pide ahora / Programar + destino + CTA.
class _HomePrimaryTripBlock extends StatefulWidget {
  const _HomePrimaryTripBlock({
    required this.onPedirAhora,
    required this.onProgramar,
  });

  final VoidCallback onPedirAhora;
  final VoidCallback onProgramar;

  @override
  State<_HomePrimaryTripBlock> createState() => _HomePrimaryTripBlockState();
}

class _HomePrimaryTripBlockState extends State<_HomePrimaryTripBlock> {
  bool _programar = false;

  void _continuar() {
    if (_programar) {
      widget.onProgramar();
    } else {
      widget.onPedirAhora();
    }
  }

  Future<void> _abrirDestinoConVoz() async {
    final det = await RaiDireccionInteligenteSheet.mostrar(context);
    if (det == null || !mounted) return;
    if (!context.mounted) return;
    unawaited(ClienteViajeNavegacion.pushTrasVerificacion(
      context,
      ProgramarViaje(
        modoAhora: !_programar,
        destinoPrecargado: det.displayLabel,
        latDestinoPrecargado: det.lat,
        lonDestinoPrecargado: det.lon,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final _HomePalette p = _HomePalette.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.borderCard),
        boxShadow: [
          BoxShadow(
            color: p.cardShadow,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool narrow = constraints.maxWidth < 340;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.bolt_rounded, size: narrow ? 18 : 20),
                      label: Text(
                        'Pide ahora',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: narrow ? 13 : 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.event_rounded, size: narrow ? 18 : 20),
                      label: Text(
                        'Programar',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: narrow ? 13 : 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  selected: {_programar},
                  showSelectedIcon: !narrow,
                  emptySelectionAllowed: false,
                  onSelectionChanged: (selection) {
                    setState(() => _programar = selection.first);
                  },
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: p.accentGreen,
                    selectedForegroundColor: Colors.white,
                    backgroundColor: p.inputFill,
                    foregroundColor: p.textOnCard,
                    side: BorderSide(color: p.borderCard),
                    padding: EdgeInsets.symmetric(
                      vertical: narrow ? 8 : 12,
                      horizontal: narrow ? 2 : 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    visualDensity: narrow
                        ? VisualDensity.compact
                        : VisualDensity.standard,
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ),
                const SizedBox(height: 14),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _continuar,
                    borderRadius: BorderRadius.circular(14),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: p.inputFill,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: p.borderCard),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.search_rounded,
                                color: p.textMutedCard, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '¿A dónde vas?',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.textMutedCard,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Dictar destino con RAI',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              icon: Icon(
                                Icons.mic_none_rounded,
                                color: p.accentGreen,
                                size: 22,
                              ),
                              onPressed: _abrirDestinoConVoz,
                            ),
                            Icon(Icons.arrow_forward_ios_rounded,
                                size: 14, color: p.textMutedCard),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _continuar,
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accentGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _programar ? Icons.event_rounded : Icons.bolt_rounded,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _programar
                              ? 'Elegir fecha y destino'
                              : 'Pedir viaje ahora',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Tile compacto: conductores en ruta cerca del usuario.
class _HomeConductoresTile extends StatelessWidget {
  const _HomeConductoresTile({
    required this.onTap,
    required this.accentColor,
  });

  final VoidCallback onTap;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final _HomePalette p = _HomePalette.of(context);

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.borderCard),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentColor
                        .withValues(alpha: p.cardIsDark ? 0.22 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.directions_car_filled_rounded,
                      color: accentColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Conductores en ruta',
                        style: TextStyle(
                          color: p.textOnCard,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ver quién pasa cerca de ti',
                        style: TextStyle(
                          color: p.textMutedCard,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: p.textMutedCard),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta grande con gradiente para «Más opciones» (motor, turismo, etc.).
class _HomeGiantServiceCard extends StatelessWidget {
  const _HomeGiantServiceCard({
    required this.cardWidth,
    required this.gradient,
    required this.icon,
    required this.iconSize,
    required this.title,
    required this.titleSize,
    required this.subtitle,
    required this.price,
    required this.features,
    required this.badge,
    required this.onTap,
    this.customHeader,
  });

  final double cardWidth;
  final Gradient gradient;
  final IconData icon;
  final double iconSize;
  final Widget? customHeader;
  final String title;
  final double titleSize;
  final String subtitle;
  final String price;
  final List<String> features;
  final Widget badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool compact = cardWidth < 200;
    final double radius = compact ? 16.0 : 20.0;
    final bool isDarkBg = _HomePalette.of(context).scaffoldIsDark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: cardWidth,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDarkBg ? 0.32 : 0.16),
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
                  color: Colors.white
                      .withValues(alpha: compact ? 0.035 : 0.055),
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
                  const double headerDesignW = 140;
                  const double headerDesignH = 52;
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
                                        size: math.min(
                                            iconSize, headerH * 0.85),
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
                                  fontWeight: FontWeight.w900,
                                  height: 1.02,
                                  letterSpacing: -0.2,
                                  shadows: const [
                                    Shadow(
                                      offset: Offset(0, 1),
                                      blurRadius: 4,
                                      color: Color(0x59000000),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  fontSize: compact ? 11.5 : 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                  shadows: const [
                                    Shadow(
                                      offset: Offset(0, 1),
                                      blurRadius: 3,
                                      color: Color(0x45000000),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: compact ? 6 : 8),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: compact ? 8 : 10,
                                  vertical: compact ? 3 : 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  price,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: compact ? 10 : 11.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
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
                                      Icon(
                                        Icons.check,
                                        color: Colors.white
                                            .withValues(alpha: 0.98),
                                        size: compact ? 12 : 14,
                                      ),
                                      SizedBox(width: compact ? 4 : 5),
                                      Expanded(
                                        child: Text(
                                          feature,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.96),
                                            fontSize: compact ? 10.5 : 11.5,
                                            fontWeight: FontWeight.w600,
                                            height: 1.28,
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

/// Bola Ahorro: tarjeta destacada con contraste sobre cualquier fondo custom.
class _FeaturedBolaAhorroCard extends StatelessWidget {
  const _FeaturedBolaAhorroCard({
    required this.onTap,
    this.bolaActiva,
  });

  final VoidCallback onTap;
  final Map<String, String>? bolaActiva;

  String get _subtitle {
    if (bolaActiva == null) {
      return 'Viajes compartidos · hasta 50% menos';
    }
    switch ((bolaActiva!['estado'] ?? '').toString()) {
      case 'abierta':
        return 'Pedido activo — continuar';
      case 'acordada':
        return 'Precio acordado — continuar';
      case 'en_curso':
        return 'En viaje — abrir';
      default:
        return 'Ahorra activo — continuar';
    }
  }

  static const Color _lightSurface = Color(0xFFFFF4E6);
  static const Color _darkGradientMid = Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context) {
    final _HomePalette p = _HomePalette.of(context);
    final bool useGradient = p.scaffoldIsDark;

    final Color titleColor = useGradient
        ? Colors.white
        : CustomThemeService.textOn(_lightSurface);
    final Color subtitleColor = useGradient
        ? Colors.white.withValues(alpha: 0.95)
        : CustomThemeService.textMutedOn(_lightSurface);
    final Color chevronColor = useGradient
        ? Colors.white.withValues(alpha: 0.95)
        : CustomThemeService.textOn(_lightSurface);
    final Color borderColor = useGradient
        ? Colors.white.withValues(alpha: 0.22)
        : CustomThemeService.borderOn(_lightSurface);

    final BoxDecoration deco = useGradient
        ? BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFFFF8C00),
                _darkGradientMid,
                Color(0xFFE65100),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          )
        : BoxDecoration(
            color: _lightSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEA580C).withValues(alpha: 0.10),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          );

    final TextStyle titleWord = TextStyle(
      color: titleColor,
      fontSize: 17,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.2,
      height: 1.05,
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: useGradient
                                  ? Colors.white.withValues(alpha: 0.22)
                                  : const Color(0xFF00C853)
                                      .withValues(alpha: 0.18),
                              border: Border.all(
                                color: useGradient
                                    ? Colors.white.withValues(alpha: 0.55)
                                    : const Color(0xFF00C853),
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: useGradient
                                      ? Colors.white
                                      : const Color(0xFF00C853),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(etiquetaBolaAhorroUi, style: titleWord),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
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
