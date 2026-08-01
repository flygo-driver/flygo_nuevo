import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/pantallas/cliente/bola_conductores_en_ruta_cliente.dart';
import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_actions.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje_multi.dart';
import 'package:flygo_nuevo/servicios/cliente_viaje_navegacion.dart';
import 'package:flygo_nuevo/servicios/cliente_viaje_activo_gate.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/bola_pueblo_repo.dart';
import 'package:flygo_nuevo/servicios/productos_config_service.dart';
import 'package:flygo_nuevo/servicios/custom_theme_service.dart';
import 'package:flygo_nuevo/utilidades/constante.dart' show rutaBolaPueblo, etiquetaBolaAhorroUi;
import 'package:flygo_nuevo/pantallas/servicios_extras/pools_cliente_lista.dart';
import 'package:flygo_nuevo/widgets/cliente_bloqueo_gate.dart';
import 'package:flygo_nuevo/widgets/promo_taxi_pista_animation.dart';
import 'package:flygo_nuevo/widgets/cliente_home_live_map.dart';
import 'package:flygo_nuevo/widgets/rai_direccion_inteligente_sheet.dart';
import 'package:flygo_nuevo/widgets/rai_header_logo.dart';
import 'package:flygo_nuevo/widgets/rai_tipo_viaje_picker.dart';
import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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

  /// Verde marca RAI (#00E676), no el verde tipo inDrive.
  Color get accentGreen =>
      scaffoldIsDark ? RaiDsColors.neon : const Color(0xFF16A34A);

  Color get conductoresAccent =>
      scaffoldIsDark ? const Color(0xFFFFB74D) : const Color(0xFFE8590C);
}

String? _primerNombreUsuario() {
  final String? nombre = FirebaseAuth.instance.currentUser?.displayName?.trim();
  if (nombre == null || nombre.isEmpty) return null;
  final String primero = nombre.split(RegExp(r'\s+')).first;
  if (primero.isEmpty) return null;
  return primero[0].toUpperCase() + primero.substring(1).toLowerCase();
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
    final String? primerNombre = _primerNombreUsuario();

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
              padding: const EdgeInsets.only(bottom: 72),
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
                            primerNombre != null
                                ? '¡Hola, $primerNombre!'
                                : '¿A dónde vamos hoy?',
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
                            primerNombre != null
                                ? 'Ingresa tu destino y pide tu viaje en minutos'
                                : 'Toca abajo para pedir tu viaje en minutos',
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
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: _HomeSearchDestinoBar(
                        onElegirTipo: (programar) {
                          unawaited(ClienteViajeNavegacion.pushTrasVerificacion(
                            context,
                            ProgramarViaje(modoAhora: !programar),
                          ));
                        },
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: _HomeTipoViajeCards(
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
                                      if (!await ClienteViajeActivoGate
                                          .intentarFlujoNuevoViaje(context)) {
                                        return;
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
                                onTap: () async {
                                  if (!await ClienteViajeActivoGate
                                      .intentarFlujoNuevoViaje(context)) {
                                    return;
                                  }
                                  if (!context.mounted) return;
                                  NavigationService.pushEnTabShell(
                                    context,
                                    const BolaConductoresEnRutaClientePage(),
                                  );
                                },
                                accentColor: verConductoresColor,
                              ),
                          ],
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                      child: Text(
                        'Servicios',
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: _HomeExtrasServiceGrid(
                          onViajeAhora: () {
                            unawaited(ClienteViajeNavegacion.pushTrasVerificacion(
                              context,
                              const ProgramarViaje(modoAhora: true),
                            ));
                          },
                          onProgramado: () {
                            unawaited(ClienteViajeNavegacion.pushTrasVerificacion(
                              context,
                              const ProgramarViaje(modoAhora: false),
                            ));
                          },
                          onMultiparada: () {
                            unawaited(ClienteViajeNavegacion.pushTrasVerificacion(
                              context,
                              const ProgramarViajeMulti(),
                            ));
                          },
                          onMotor: () {
                            unawaited(ClienteViajeNavegacion.pushTrasVerificacion(
                              context,
                              const ProgramarViaje(
                                modoAhora: true,
                                tipoServicio: 'motor',
                              ),
                            ));
                          },
                          onGiras: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const PoolsClienteLista(tipo: 'todos'),
                              ),
                            );
                          },
                          onTurismo: () => _mostrarEleccionTurismo(context),
                          onCorporativo: () {
                            unawaited(
                              ClienteViajeNavegacion.pushCorporativoHub(context),
                            );
                          },
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: promoBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: promoBorder),
                            ),
                            child: const ClipRRect(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(15)),
                              child: PromoTaxiPistaAnimation(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ClienteHomeLiveMap(
                            accentGreen: palette.accentGreen,
                            isDark: palette.scaffoldIsDark,
                          ),
                        ],
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

  /// Turismo: elegir Ahora o Programar con el mismo diseño de tarjetas.
  Future<void> _mostrarEleccionTurismo(BuildContext context) async {
    if (!context.mounted) return;
    final bool? programar = await RaiTipoViajePicker.mostrar(
      context,
      titulo: 'Turismo RAI',
      subtitulo:
          'Traslados a aeropuertos, hoteles y destinos turísticos',
    );
    if (programar == null || !context.mounted) return;
    _abrirTurismoDesdeInicio(context, modoAhora: !programar);
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

/// Spec interno para cada cuadrito de servicio.
class _ServiceTileSpec {
  const _ServiceTileSpec({
    required this.icon,
    required this.title,
    required this.gradient,
    required this.glowColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Gradient gradient;
  final Color glowColor;
  final VoidCallback onTap;
}

/// Grilla compacta de servicios (mismo flujo que antes, diseño moderno).
class _HomeExtrasServiceGrid extends StatelessWidget {
  const _HomeExtrasServiceGrid({
    required this.onViajeAhora,
    required this.onProgramado,
    required this.onMultiparada,
    required this.onMotor,
    required this.onGiras,
    required this.onTurismo,
    required this.onCorporativo,
  });

  final VoidCallback onViajeAhora;
  final VoidCallback onProgramado;
  final VoidCallback onMultiparada;
  final VoidCallback onMotor;
  final VoidCallback onGiras;
  final VoidCallback onTurismo;
  final VoidCallback onCorporativo;

  @override
  Widget build(BuildContext context) {
    final _HomePalette p = _HomePalette.of(context);
    const int cols = 3;

    final tiles = <_ServiceTileSpec>[
      _ServiceTileSpec(
        icon: PhosphorIconsFill.lightning,
        title: 'Pide ahora',
        glowColor: const Color(0xFF00FF88),
        gradient: const LinearGradient(
          colors: [Color(0xFF00FF88), Color(0xFF00C853)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        onTap: onViajeAhora,
      ),
      _ServiceTileSpec(
        icon: PhosphorIconsFill.calendarBlank,
        title: 'Programado',
        glowColor: const Color(0xFF5DFFA8),
        gradient: const LinearGradient(
          colors: [Color(0xFF5DFFA8), Color(0xFF00A86B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        onTap: onProgramado,
      ),
      if (ProductosConfigService.muestraMultiparada)
        _ServiceTileSpec(
          icon: PhosphorIconsFill.signpost,
          title: 'Paradas múltiples',
          glowColor: const Color(0xFFFF5C8A),
          gradient: const LinearGradient(
            colors: [Color(0xFFFF6B9D), Color(0xFFFF1744)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          onTap: onMultiparada,
        ),
      if (ProductosConfigService.muestraMotor)
        _ServiceTileSpec(
          icon: PhosphorIconsFill.motorcycle,
          title: 'Motores',
          glowColor: const Color(0xFFFFAB40),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFB74D), Color(0xFFFF6D00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          onTap: onMotor,
        ),
      if (ProductosConfigService.muestraGiras)
        _ServiceTileSpec(
          icon: PhosphorIconsFill.bus,
          title: 'Giras y excursiones',
          glowColor: const Color(0xFF40E0FF),
          gradient: const LinearGradient(
            colors: [Color(0xFF4DEEFF), Color(0xFF00B8D4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          onTap: onGiras,
        ),
      if (ProductosConfigService.muestraTurismo)
        _ServiceTileSpec(
          icon: PhosphorIconsFill.airplaneTilt,
          title: 'Turismo',
          glowColor: const Color(0xFFD05CFF),
          gradient: const LinearGradient(
            colors: [Color(0xFFE879FF), Color(0xFF9C27B0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          onTap: onTurismo,
        ),
      if (ProductosConfigService.muestraCorporativo)
        _ServiceTileSpec(
          icon: PhosphorIconsFill.buildings,
          title: 'Corporativo',
          glowColor: const Color(0xFF3DFFE8),
          gradient: const LinearGradient(
            colors: [Color(0xFF5CFFE8), Color(0xFF00BFA5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          onTap: onCorporativo,
        ),
    ];

    if (tiles.isEmpty) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.borderCard),
        boxShadow: [
          BoxShadow(
            color: p.cardShadow,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const double gap = 8;
            final double cellW =
                (constraints.maxWidth - gap * (cols - 1)) / cols;
            final double box = cellW * 0.96;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: gap,
                crossAxisSpacing: gap,
                childAspectRatio: 1.0,
              ),
              itemCount: tiles.length,
              itemBuilder: (context, index) {
                final _ServiceTileSpec spec = tiles[index];
                return _HomeServiceGridTile(
                  icon: spec.icon,
                  title: spec.title,
                  gradient: spec.gradient,
                  glowColor: spec.glowColor,
                  boxSize: box,
                  onTap: spec.onTap,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _HomeServiceGridTile extends StatelessWidget {
  const _HomeServiceGridTile({
    required this.icon,
    required this.title,
    required this.gradient,
    required this.glowColor,
    required this.onTap,
    required this.boxSize,
  });

  final IconData icon;
  final String title;
  final Gradient gradient;
  final Color glowColor;
  final VoidCallback onTap;
  final double boxSize;

  @override
  Widget build(BuildContext context) {
    final _HomePalette p = _HomePalette.of(context);
    final double radius = boxSize * 0.18;
    final double iconSize = (boxSize * 0.26).clamp(20.0, 30.0);
    final bool largo = title.length > 12;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Center(
          child: Container(
            width: boxSize,
            height: boxSize,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.35),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.45),
                  blurRadius: 16,
                  spreadRadius: -2,
                  offset: const Offset(0, 5),
                ),
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: p.cardIsDark ? 0.28 : 0.12,
                  ),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.28),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.08),
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: largo ? 5 : 7,
                    vertical: 7,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        color: Colors.white,
                        size: iconSize,
                        shadows: const [
                          Shadow(
                            color: Color(0x88000000),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      SizedBox(height: largo ? 3 : 5),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            title,
                            maxLines: largo ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              letterSpacing: -0.15,
                              shadows: [
                                Shadow(
                                  color: Color(0x77000000),
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
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

/// Barra de búsqueda de destino (abre selector Ahora/Programado).
class _HomeSearchDestinoBar extends StatelessWidget {
  const _HomeSearchDestinoBar({required this.onElegirTipo});

  final void Function(bool programar) onElegirTipo;

  Future<void> _abrirBusqueda(BuildContext context) async {
    final bool? programar = await RaiTipoViajePicker.mostrar(context);
    if (programar == null || !context.mounted) return;
    onElegirTipo(programar);
  }

  Future<void> _abrirDestinoConVoz(BuildContext context) async {
    final det = await RaiDireccionInteligenteSheet.mostrar(context);
    if (det == null || !context.mounted) return;
    final bool? programar = await RaiTipoViajePicker.mostrar(context);
    if (programar == null || !context.mounted) return;
    unawaited(ClienteViajeNavegacion.pushTrasVerificacion(
      context,
      ProgramarViaje(
        modoAhora: !programar,
        destinoPrecargado: det.displayLabel,
        latDestinoPrecargado: det.lat,
        lonDestinoPrecargado: det.lon,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final _HomePalette p = _HomePalette.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _abrirBusqueda(context),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.borderCard),
            boxShadow: [
              BoxShadow(
                color: p.cardShadow,
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.location_on_outlined,
                    color: p.accentGreen, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Ingresa tu destino',
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
                  onPressed: () => _abrirDestinoConVoz(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjetas Ahora / Programado en el inicio (mismo diseño del mockup).
class _HomeTipoViajeCards extends StatelessWidget {
  const _HomeTipoViajeCards({
    required this.onPedirAhora,
    required this.onProgramar,
  });

  final VoidCallback onPedirAhora;
  final VoidCallback onProgramar;

  @override
  Widget build(BuildContext context) {
    final _HomePalette p = _HomePalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '¿Qué tipo de viaje quieres?',
          style: TextStyle(
            color: p.textOnScaffold,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        _HomeTipoViajeCard(
          icon: Icons.bolt_rounded,
          titulo: 'Ahora',
          subtitulo: 'Pide un viaje al instante',
          accent: p.accentGreen,
          palette: p,
          onTap: onPedirAhora,
        ),
        const SizedBox(height: 10),
        _HomeTipoViajeCard(
          icon: Icons.event_rounded,
          titulo: 'Programado',
          subtitulo: 'Elige día y hora',
          accent: p.accentGreen,
          palette: p,
          onTap: onProgramar,
        ),
      ],
    );
  }
}

class _HomeTipoViajeCard extends StatelessWidget {
  const _HomeTipoViajeCard({
    required this.icon,
    required this.titulo,
    required this.subtitulo,
    required this.accent,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String titulo;
  final String subtitulo;
  final Color accent;
  final _HomePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accent.withValues(
                alpha: palette.cardIsDark ? 0.30 : 0.22,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: palette.cardShadow,
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: accent.withValues(
                      alpha: palette.cardIsDark ? 0.16 : 0.12,
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: accent, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          color: palette.textOnCard,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitulo,
                        style: TextStyle(
                          color: palette.textMutedCard,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: palette.textMutedCard, size: 22),
              ],
            ),
          ),
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
