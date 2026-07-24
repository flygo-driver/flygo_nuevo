import 'package:flutter/material.dart';

/// Colores de entrada adaptados a modo claro y oscuro del sistema.
class RaiEntradaColores {
  const RaiEntradaColores(this.brightness);

  final Brightness brightness;

  bool get esOscuro => brightness == Brightness.dark;

  static const Color raiVerde = Color(0xFF00C853);

  static RaiEntradaColores de(BuildContext context) =>
      RaiEntradaColores(Theme.of(context).brightness);

  Color get fondoScaffold => esOscuro ? const Color(0xFF121212) : Colors.white;

  Color get fondoSuave =>
      esOscuro ? const Color(0xFF1A2E1C) : const Color(0xFFE8F5E9);

  Color get textoPrincipal =>
      esOscuro ? Colors.white : const Color(0xDE000000);

  Color get textoSecundario =>
      esOscuro ? const Color(0xB3FFFFFF) : const Color(0x8A000000);

  Color get textoBanner =>
      esOscuro ? const Color(0xE6FFFFFF) : const Color(0xB3000000);

  Color get campoFondo =>
      esOscuro ? const Color(0xFF2C2C2E) : const Color(0xFFF1F1F2);

  Color get campoBorde =>
      esOscuro ? const Color(0xFF636366) : const Color(0xFFC7C7CC);

  Color get campoTexto => esOscuro ? Colors.white : Colors.black87;

  Color get campoLabel =>
      esOscuro ? const Color(0xE6FFFFFF) : const Color(0xFF1C1C1E);

  Color get campoHint =>
      esOscuro ? const Color(0x99FFFFFF) : const Color(0x8A000000);

  Color get icono => esOscuro ? const Color(0xCCFFFFFF) : Colors.black54;

  Color get chipFondo =>
      esOscuro ? const Color(0xFF2C2C2E) : const Color(0xFFF1F1F2);

  Color get chipInactivo =>
      esOscuro ? const Color(0xB3FFFFFF) : Colors.black54;

  Color get link => esOscuro ? const Color(0xFF82B1FF) : const Color(0xFF1565C0);

  Color get bannerFondo =>
      raiVerde.withValues(alpha: esOscuro ? 0.22 : 0.1);

  Color get bannerBorde =>
      raiVerde.withValues(alpha: esOscuro ? 0.45 : 0.28);

  BoxDecoration get gradienteBienvenida => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: esOscuro
              ? [fondoSuave, const Color(0xFF121212), const Color(0xFF121212)]
              : [fondoSuave, Colors.white, Colors.white],
          stops: const [0.0, 0.28, 1.0],
        ),
      );

  TextStyle get estiloTitulo => TextStyle(
        color: textoPrincipal,
        fontSize: 26,
        fontWeight: FontWeight.w800,
        height: 1.1,
      );

  TextStyle get estiloSubtitulo => TextStyle(
        color: textoSecundario,
        fontSize: 14,
        height: 1.4,
      );

  TextStyle get estiloCampo => TextStyle(
        color: campoTexto,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      );
}

/// Compatibilidad con código existente.
abstract final class RaiEntradaDecoracion {
  static const Color fondoSuave = Color(0xFFE8F5E9);
  static const Color raiVerde = RaiEntradaColores.raiVerde;
  static const Color campoFondo = Color(0xFFF1F1F2);

  static BoxDecoration gradiente(BuildContext context) =>
      RaiEntradaColores.de(context).gradienteBienvenida;
}

/// Scaffold de entrada con tema claro/oscuro coherente.
class RaiEntradaScaffold extends StatelessWidget {
  const RaiEntradaScaffold({
    super.key,
    required this.body,
    this.mostrarAtras = true,
    this.resizeToAvoidBottomInset = true,
  });

  final Widget body;
  final bool mostrarAtras;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final c = RaiEntradaColores.de(context);

    return Theme(
      data: Theme.of(context).copyWith(
        brightness: c.brightness,
        scaffoldBackgroundColor: c.fondoScaffold,
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: c.link),
        ),
      ),
      child: Scaffold(
        backgroundColor: c.fondoScaffold,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        body: DecoratedBox(
          decoration: c.gradienteBienvenida,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RaiEntradaBarraNav(mostrarAtras: mostrarAtras),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RaiEntradaBarraNav extends StatelessWidget {
  const RaiEntradaBarraNav({
    super.key,
    this.mostrarAtras = true,
  });

  final bool mostrarAtras;

  @override
  Widget build(BuildContext context) {
    final puedeVolver = Navigator.canPop(context);
    if (!mostrarAtras || !puedeVolver) {
      return const SizedBox(height: 8);
    }
    final c = RaiEntradaColores.de(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: c.textoPrincipal),
        tooltip: 'Volver',
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}

class RaiEntradaHero extends StatelessWidget {
  const RaiEntradaHero({
    super.key,
    this.compacto = false,
    this.mostrarEslogan = true,
  });

  final bool compacto;
  final bool mostrarEslogan;

  @override
  Widget build(BuildContext context) {
    final c = RaiEntradaColores.de(context);
    final w = MediaQuery.sizeOf(context).width;
    final paracaidasH = compacto
        ? (w * 0.28).clamp(88.0, 120.0)
        : (w * 0.38).clamp(120.0, 168.0);
    final logoSize = compacto ? 64.0 : 80.0;
    final stackExtra = compacto ? 24.0 : 36.0;

    return Column(
      children: [
        SizedBox(
          height: paracaidasH + stackExtra,
          child: Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Image.asset(
                  'assets/icon/paracaida_color.png',
                  height: paracaidasH,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              Positioned(
                bottom: 0,
                child: Container(
                  width: logoSize,
                  height: logoSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.esOscuro ? const Color(0xFF2C2C2E) : Colors.white,
                    border: Border.all(color: RaiEntradaColores.raiVerde, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: RaiEntradaColores.raiVerde.withValues(alpha: 0.25),
                        blurRadius: compacto ? 14 : 20,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/icon/logo_rai_app.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (mostrarEslogan) ...[
          SizedBox(height: compacto ? 10 : 16),
          Text(
            compacto ? 'RAI Driver' : 'Largos viajes,\nfáciles y seguros',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textoPrincipal,
              fontSize: compacto ? 20 : 22,
              fontWeight: FontWeight.w900,
              height: 1.15,
              letterSpacing: -0.3,
            ),
          ),
          if (!compacto) ...[
            const SizedBox(height: 6),
            Text(
              'Comparte ruta, ahorra y viaja mejor.',
              textAlign: TextAlign.center,
              style: c.estiloSubtitulo,
            ),
          ],
        ],
      ],
    );
  }
}

class RaiEntradaRolEtiqueta extends StatelessWidget {
  const RaiEntradaRolEtiqueta({super.key, required this.entradaRol});

  final String entradaRol;

  bool get _esConductor =>
      entradaRol.trim().toLowerCase() == 'taxista';

  @override
  Widget build(BuildContext context) {
    final c = RaiEntradaColores.de(context);
    final label = _esConductor ? 'Conductor' : 'Pasajero';
    final icon =
        _esConductor ? Icons.local_taxi_outlined : Icons.person_outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: c.bannerFondo,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.bannerBorde),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: RaiEntradaColores.raiVerde),
          const SizedBox(width: 8),
          Text(
            'Entrando como $label',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: c.textoPrincipal,
            ),
          ),
        ],
      ),
    );
  }
}

class RaiEntradaRegistroBanner extends StatelessWidget {
  const RaiEntradaRegistroBanner({
    super.key,
    required this.esConductor,
    this.esCorporativo = false,
  });

  final bool esConductor;
  final bool esCorporativo;

  @override
  Widget build(BuildContext context) {
    final c = RaiEntradaColores.de(context);
    final texto = esCorporativo
        ? 'Encargado de empresa: entrá con Google o correo. '
            'RAI debe habilitar tu cuenta; luego programás rutas y '
            'compartís el código con tus empleados.'
        : esConductor
            ? '¿Sos nuevo conductor? Verificá tu teléfono o Google y creamos tu cuenta. '
                'Después completás vehículo y documentos.'
            : '¿Primera vez en RAI? Poné tu celular, te mandamos un código y '
                'tu cuenta queda lista. Si ya tenés cuenta, entrás con el mismo paso.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.bannerFondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.bannerBorde),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.person_add_alt_1_rounded,
            size: 22,
            color: RaiEntradaColores.raiVerde,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: c.textoBanner,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration raiCampoEntradaDecoration(
  BuildContext context, {
  required String label,
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  final c = RaiEntradaColores.de(context);

  Widget? prefix;
  if (prefixIcon != null) {
    prefix = IconTheme(
      data: IconThemeData(color: c.icono, size: 22),
      child: prefixIcon,
    );
  }

  Widget? suffix;
  if (suffixIcon != null) {
    suffix = IconTheme(
      data: IconThemeData(color: c.icono, size: 22),
      child: suffixIcon,
    );
  }

  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefix,
    suffixIcon: suffix,
    labelStyle: TextStyle(
      color: c.campoLabel,
      fontWeight: FontWeight.w600,
      fontSize: 15,
    ),
    hintStyle: TextStyle(color: c.campoHint, fontSize: 16),
    floatingLabelStyle: TextStyle(
      color: RaiEntradaColores.raiVerde,
      fontWeight: FontWeight.w700,
    ),
    filled: true,
    fillColor: c.campoFondo,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c.campoBorde, width: 1.2),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c.campoBorde, width: 1.2),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: RaiEntradaColores.raiVerde, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: Colors.red.shade400,
        width: 1.2,
      ),
    ),
  );
}

Widget raiBotonContinuar({
  required VoidCallback? onPressed,
  required String label,
  bool cargando = false,
}) {
  return Material(
    elevation: onPressed == null ? 0 : 4,
    shadowColor: RaiEntradaColores.raiVerde.withValues(alpha: 0.5),
    borderRadius: BorderRadius.circular(12),
    child: Ink(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: onPressed == null
              ? [
                  RaiEntradaColores.raiVerde.withValues(alpha: 0.45),
                  RaiEntradaColores.raiVerde.withValues(alpha: 0.35),
                ]
              : [const Color(0xFF00E676), RaiEntradaColores.raiVerde],
        ),
      ),
      child: SizedBox(
        height: 52,
        width: double.infinity,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: cargando
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
      ),
    ),
  );
}
