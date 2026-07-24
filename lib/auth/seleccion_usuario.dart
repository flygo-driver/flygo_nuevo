import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/legal/terms_policy_screen.dart';
import 'package:flygo_nuevo/app_flavor.dart';
import 'package:flygo_nuevo/servicios/app_flavor_rol_guard.dart';
import 'package:flygo_nuevo/widgets/rai_entrada_hero.dart';
import 'package:flygo_nuevo/widgets/rai_entrada_social_panel.dart';

/// Bienvenida unificada Play: pasajero / conductor.
/// Corporativo NO va aquí: solo por `/empresas` o `/login/corporativo`.
class SeleccionUsuario extends StatefulWidget {
  const SeleccionUsuario({
    super.key,
    this.initialRol = 'cliente',
    this.showBackButton = false,
    this.postLoginRoute,
    this.googleSolo = false,
  });

  final String initialRol;
  final bool showBackButton;
  /// Tras login exitoso (p. ej. `/corporativo` en web empresa).
  final String? postLoginRoute;
  /// Solo Google (web corporativo en laptop).
  final bool googleSolo;

  @override
  State<SeleccionUsuario> createState() => _SeleccionUsuarioState();
}

class _SeleccionUsuarioState extends State<SeleccionUsuario> {
  static String? _ultimoMotivoMostrado;
  static DateTime? _ultimoMotivoAt;

  late String _rolEntrada;

  @override
  void initState() {
    super.initState();
    _rolEntrada = _rolInicial();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pendiente = AppFlavorRolGuard.consumirMotivoRechazo();
      if (pendiente != null && pendiente.isNotEmpty) {
        _mostrarMotivoNoEntrada(pendiente);
      }
    });
  }

  /// Entrada dedicada de empresa (no mezclar con pasajero/conductor).
  bool get _entradaCorporativoDedicada {
    final r = widget.initialRol.trim().toLowerCase();
    return r == 'corporativo' ||
        widget.postLoginRoute == '/corporativo' ||
        widget.googleSolo;
  }

  String _rolInicial() {
    if (_entradaCorporativoDedicada) return 'corporativo';
    if (isConductorFlavor) return 'taxista';
    if (isClienteFlavor) return 'cliente';
    final r = widget.initialRol.trim().toLowerCase();
    if (r == 'taxista') return 'taxista';
    return 'cliente';
  }

  /// Selector pasajero/conductor: Play unificada (`all`) en móvil, tablet y web.
  bool get _mostrarSelectorRol =>
      !_entradaCorporativoDedicada && isAllFlavors;
  bool get _mostrarConductor => isAllFlavors;
  bool get _esConductor => _rolEntrada == 'taxista';
  bool get _esCorporativo => _entradaCorporativoDedicada;

  /// Solo en web y al pie: el cliente de taxi no debe “caer” en corporativo.
  /// Empresas entran por /empresas (enlace propio / WhatsApp comercial).
  bool get _mostrarLinkEmpresas =>
      !_entradaCorporativoDedicada && kIsWeb && isAllFlavors;

  void _snackError(String msg) {
    _mostrarMotivoNoEntrada(msg);
  }

  void _mostrarMotivoNoEntrada(String msg) {
    if (!mounted) return;
    final t = msg.trim();
    if (t.isEmpty) return;

    final ahora = DateTime.now();
    if (_ultimoMotivoMostrado == t &&
        _ultimoMotivoAt != null &&
        ahora.difference(_ultimoMotivoAt!) < const Duration(seconds: 4)) {
      return;
    }
    _ultimoMotivoMostrado = t;
    _ultimoMotivoAt = ahora;
    // Evitar segundo diálogo al remontar tras cerrar sesión.
    AppFlavorRolGuard.consumirMotivoRechazo();

    // Mensajes largos (rol incorrecto): diálogo legible, no snack corto.
    if (t.length > 80 || t.contains('\n')) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No puedes entrar'),
          content: SingleChildScrollView(
            child: Text(t, style: const TextStyle(height: 1.4)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _irPortalEmpresas() {
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/login/corporativo',
      (r) => false,
    );
  }

  Widget _selectorRolEntrada() {
    final c = RaiEntradaColores.de(context);
    final w = MediaQuery.sizeOf(context).width;
    // Móvil principal: 2 columnas. Solo apilar si es muy estrecho.
    final sideBySide = w >= 340 && _mostrarConductor;
    final compact = w < 420;

    final cards = <Widget>[
      _tarjetaRol(
        label: 'Pasajero',
        subtitulo: 'Pedir viaje',
        icon: Icons.person_rounded,
        seleccionado: _rolEntrada == 'cliente',
        colorActivo: const Color(0xFF00C853),
        colorSuave: const Color(0xFF00C853),
        compact: compact,
        onTap: () => setState(() => _rolEntrada = 'cliente'),
      ),
      if (_mostrarConductor)
        _tarjetaRol(
          label: 'Conductor',
          subtitulo: 'Recibir viajes',
          icon: Icons.local_taxi_rounded,
          seleccionado: _esConductor,
          colorActivo: const Color(0xFF0D9488),
          colorSuave: const Color(0xFF14B8A6),
          compact: compact,
          onTap: () => setState(() => _rolEntrada = 'taxista'),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '¿Cómo vas a usar RAI?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.textoPrincipal,
            fontSize: compact ? 18 : 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tocá tu perfil para entrar',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.textoSecundario,
            fontSize: compact ? 13 : 14,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        SizedBox(height: compact ? 12 : 14),
        if (sideBySide)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) SizedBox(width: compact ? 10 : 12),
                  Expanded(child: cards[i]),
                ],
              ],
            ),
          )
        else
          Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                cards[i],
              ],
            ],
          ),
      ],
    );
  }

  Widget _tarjetaRol({
    required String label,
    required String subtitulo,
    required IconData icon,
    required bool seleccionado,
    required Color colorActivo,
    required Color colorSuave,
    required VoidCallback onTap,
    bool compact = true,
  }) {
    final c = RaiEntradaColores.de(context);
    final bg = seleccionado
        ? colorActivo
        : (c.esOscuro ? const Color(0xFF1C1C1E) : Colors.white);
    final border = seleccionado
        ? colorActivo
        : (c.esOscuro ? const Color(0xFF48484A) : const Color(0xFFD1D5DB));
    final fg = seleccionado ? Colors.white : c.textoPrincipal;
    final fgMuted = seleccionado
        ? Colors.white.withValues(alpha: 0.9)
        : c.textoSecundario;
    final iconBox = compact ? 48.0 : 56.0;
    final iconSize = compact ? 26.0 : 30.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 112),
          padding: EdgeInsets.fromLTRB(
            compact ? 10 : 14,
            compact ? 14 : 16,
            compact ? 10 : 14,
            compact ? 12 : 14,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: border,
              width: seleccionado ? 2.5 : 1.25,
            ),
            boxShadow: [
              if (seleccionado)
                BoxShadow(
                  color: colorActivo.withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              else
                BoxShadow(
                  color:
                      Colors.black.withValues(alpha: c.esOscuro ? 0.22 : 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: iconBox,
                height: iconBox,
                decoration: BoxDecoration(
                  color: seleccionado
                      ? Colors.white.withValues(alpha: 0.22)
                      : colorSuave.withValues(alpha: c.esOscuro ? 0.22 : 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: iconSize,
                  color: seleccionado ? Colors.white : colorActivo,
                ),
              ),
              SizedBox(height: compact ? 8 : 10),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 16 : 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  color: fg,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitulo,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 11.5 : 12.5,
                  fontWeight: FontWeight.w600,
                  color: fgMuted,
                  height: 1.2,
                ),
              ),
              if (seleccionado) ...[
                SizedBox(height: compact ? 6 : 8),
                Icon(
                  Icons.check_circle_rounded,
                  size: compact ? 18 : 20,
                  color: Colors.white,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkEmpresas() {
    final c = RaiEntradaColores.de(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: TextButton(
        onPressed: _irPortalEmpresas,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          foregroundColor: c.textoSecundario,
        ),
        child: Text(
          'Acceso empresas · transporte de empleados',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.textoSecundario,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  String _subtituloRol(bool esConductor) {
    if (_esCorporativo) {
      return kIsWeb
          ? 'Portal de empresa — encargados en PC o laptop.'
          : 'Google o correo. RAI debe habilitarte como encargado.';
    }
    if (esConductor) {
      return 'Teléfono o Google. Verificás el código y listo — nuevo o existente.';
    }
    return 'Celular, Google o correo. Mismo paso para entrar o crear cuenta.';
  }

  @override
  Widget build(BuildContext context) {
    final rol = isConductorFlavor
        ? 'taxista'
        : (_esCorporativo
            ? 'cliente'
            : (isClienteFlavor ? 'cliente' : _rolEntrada));
    final esConductorUi = _esConductor || isConductorFlavor;
    final postRoute = _esCorporativo ? '/corporativo' : widget.postLoginRoute;
    // Corporativo web ya no fuerza “solo Google”: correo/contraseña también.
    final googleSoloUi = widget.googleSolo;

    return RaiEntradaScaffold(
      mostrarAtras: widget.showBackButton,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          // Móvil a full; tablet/PC centra columna de lectura (~480).
          final contentMax = maxW >= 720
              ? 480.0
              : (maxW >= 520 ? 440.0 : double.infinity);
          final hPad = maxW >= 720 ? 32.0 : 20.0;

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMax),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 24),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const RaiEntradaHero(),
                    const SizedBox(height: 18),
                    if (_mostrarSelectorRol) ...[
                      _selectorRolEntrada(),
                      const SizedBox(height: 18),
                    ],
                    RaiEntradaRegistroBanner(
                      esConductor: esConductorUi,
                      esCorporativo: _esCorporativo,
                    ),
                    const SizedBox(height: 16),
                    RaiEntradaSocialPanel(
                      key: ValueKey<String>(
                        'entrada-$rol-${_esCorporativo ? 'corp' : 'std'}',
                      ),
                      entradaRol: rol,
                      ocultarTitulo: true,
                      subtitulo: googleSoloUi
                          ? 'Entrá con Google — sin correo ni SMS.'
                          : _subtituloRol(esConductorUi),
                      mostrarCorreo: !googleSoloUi,
                      onError: _snackError,
                      postLoginRoute: postRoute,
                      googleSolo: googleSoloUi,
                      modoCorporativo: _esCorporativo,
                    ),
                    const SizedBox(height: 20),
                    const _RaiLegalFooter(),
                    // Pie: no compite con Pasajero/Conductor (evitar confusión taxi → corp).
                    if (_mostrarLinkEmpresas) _linkEmpresas(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RaiLegalFooter extends StatefulWidget {
  const _RaiLegalFooter();

  @override
  State<_RaiLegalFooter> createState() => _RaiLegalFooterState();
}

class _RaiLegalFooterState extends State<_RaiLegalFooter> {
  late final TapGestureRecognizer _tapCondiciones;
  late final TapGestureRecognizer _tapPrivacidad;

  void _abrirPoliticasLargas() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TermsPolicyScreen(
          requireAcceptance: true,
          onAccepted: () => nav.pop(),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tapCondiciones = TapGestureRecognizer()..onTap = _abrirPoliticasLargas;
    _tapPrivacidad = TapGestureRecognizer()..onTap = _abrirPoliticasLargas;
  }

  @override
  void dispose() {
    _tapCondiciones.dispose();
    _tapPrivacidad.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = RaiEntradaColores.de(context);
    return Text.rich(
      TextSpan(
        style: TextStyle(
          color: c.textoSecundario,
          fontSize: 12,
          height: 1.5,
        ),
        children: [
          const TextSpan(text: 'Al continuar, aceptás los '),
          TextSpan(
            text: 'Términos del servicio',
            style: TextStyle(
              color: c.link,
              fontWeight: FontWeight.w600,
            ),
            recognizer: _tapCondiciones,
          ),
          const TextSpan(text: ' y la '),
          TextSpan(
            text: 'Política de privacidad',
            style: TextStyle(
              color: c.link,
              fontWeight: FontWeight.w600,
            ),
            recognizer: _tapPrivacidad,
          ),
          const TextSpan(text: ' de RAI.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
