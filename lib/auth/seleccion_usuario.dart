import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/legal/terms_policy_screen.dart';
import 'package:flygo_nuevo/app_flavor.dart';
import 'package:flygo_nuevo/widgets/rai_entrada_hero.dart';
import 'package:flygo_nuevo/widgets/rai_entrada_social_panel.dart';

/// Bienvenida unificada Play: paracaídas + pasajero/conductor, mismo diseño.
class SeleccionUsuario extends StatefulWidget {
  const SeleccionUsuario({
    super.key,
    this.initialRol = 'cliente',
    this.showBackButton = false,
  });

  final String initialRol;
  final bool showBackButton;

  @override
  State<SeleccionUsuario> createState() => _SeleccionUsuarioState();
}

class _SeleccionUsuarioState extends State<SeleccionUsuario> {
  static const Color _raiVerde = Color(0xFF00C853);

  late String _rolEntrada;

  @override
  void initState() {
    super.initState();
    _rolEntrada = _rolInicial();
  }

  String _rolInicial() {
    if (isConductorFlavor) return 'taxista';
    if (isClienteFlavor) return 'cliente';
    final r = widget.initialRol.trim().toLowerCase();
    return r == 'taxista' ? 'taxista' : 'cliente';
  }

  bool get _mostrarSelectorRol => isAllFlavors;
  bool get _esConductor => _rolEntrada == 'taxista';

  void _snackError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _selectorPasajeroConductor() {
    final c = RaiEntradaColores.de(context);
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.chipFondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.campoBorde, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: _chipRol(
              label: 'Pasajero',
              icon: Icons.person_outline,
              seleccionado: !_esConductor,
              onTap: () => setState(() => _rolEntrada = 'cliente'),
            ),
          ),
          Expanded(
            child: _chipRol(
              label: 'Conductor',
              icon: Icons.local_taxi_outlined,
              seleccionado: _esConductor,
              onTap: () => setState(() => _rolEntrada = 'taxista'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipRol({
    required String label,
    required IconData icon,
    required bool seleccionado,
    required VoidCallback onTap,
  }) {
    final c = RaiEntradaColores.de(context);
    return Material(
      color: seleccionado ? _raiVerde : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      elevation: seleccionado ? 2 : 0,
      shadowColor: _raiVerde.withValues(alpha: 0.4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: seleccionado ? Colors.white : c.chipInactivo,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: seleccionado ? FontWeight.w800 : FontWeight.w500,
                color: seleccionado ? Colors.white : c.chipInactivo,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtituloRol(bool esConductor) {
    if (esConductor) {
      return 'Teléfono o Google. Verificás el código y listo — nuevo o existente.';
    }
    return 'Celular, Google o correo. Mismo paso para entrar o crear cuenta.';
  }

  @override
  Widget build(BuildContext context) {
    final rol = isConductorFlavor
        ? 'taxista'
        : (isClienteFlavor ? 'cliente' : _rolEntrada);
    final esConductorUi = _esConductor || isConductorFlavor;

    return RaiEntradaScaffold(
      mostrarAtras: widget.showBackButton,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RaiEntradaHero(),
            const SizedBox(height: 22),
            if (_mostrarSelectorRol) ...[
              _selectorPasajeroConductor(),
              const SizedBox(height: 16),
            ],
            RaiEntradaRegistroBanner(esConductor: esConductorUi),
            const SizedBox(height: 18),
            RaiEntradaSocialPanel(
              key: ValueKey<String>('entrada-$rol'),
              entradaRol: rol,
              ocultarTitulo: true,
              subtitulo: _subtituloRol(esConductorUi),
              mostrarCorreo: rol == 'cliente',
              onError: _snackError,
            ),
            const SizedBox(height: 28),
            const _RaiLegalFooter(),
          ],
        ),
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
