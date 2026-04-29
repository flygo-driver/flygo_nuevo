// Kit visual compartido Bola Ahorro (tablero, asistente y modales).
// Sin dependencias de negocio ni Firebase.

import 'package:flutter/material.dart';

/// Colores de la sección Bola según tema claro/oscuro (marca: [BolaPuebloTheme.accent] fijo).
///
/// Contraste tipo mapa/claro (Uber): en **oscuro** el texto principal es blanco puro
/// [`0xFFFFFFFF`]; en **claro** casi negro para máxima lectura. No altera lógica ni datos.
@immutable
class BolaPuebloColors {
  const BolaPuebloColors._({
    required this.brightness,
    required this.scheme,
  });

  final Brightness brightness;
  final ColorScheme scheme;

  factory BolaPuebloColors.of(BuildContext context) {
    final t = Theme.of(context);
    return BolaPuebloColors._(brightness: t.brightness, scheme: t.colorScheme);
  }

  bool get isDark => brightness == Brightness.dark;

  /// Fondo raíz del panel Bola (negro material / blanco según tema).
  Color get bgDeep =>
      isDark ? const Color(0xFF121212) : scheme.surface;

  Color get surface =>
      isDark ? const Color(0xFF1C1C1E) : scheme.surfaceContainerHighest;

  Color get surfaceRaised =>
      isDark ? const Color(0xFF2C2C2E) : scheme.surfaceContainerHigh;

  /// Texto principal: blanco **puro** en oscuro; casi negro en claro (legibilidad máxima).
  Color get onSurface =>
      isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1D1D1F);

  /// Secundario / etiquetas: gris claro legible en oscuro; gris medio en claro.
  Color get onMuted => isDark
      ? const Color(0xFFEBEBF5).withValues(alpha: 0.72)
      : const Color(0xFF636366);

  Color get outlineSoft =>
      isDark ? const Color(0xFF48484A) : scheme.outlineVariant;

  Color get appBarScrim => isDark
      ? const Color(0xFF121212).withValues(alpha: 0.92)
      : scheme.surface.withValues(alpha: 0.94);

  Color get dragHandle =>
      isDark
          ? const Color(0xFFFFFFFF).withValues(alpha: 0.28)
          : scheme.onSurface.withValues(alpha: 0.22);

  Color get snackNeutralBg =>
      isDark ? const Color(0xFF2C2C2E) : scheme.surfaceContainerHighest;

  Color get cardShadow => isDark
      ? Colors.black.withValues(alpha: 0.45)
      : Colors.black.withValues(alpha: 0.10);

  Color get outlineOnCard =>
      isDark
          ? const Color(0xFFFFFFFF).withValues(alpha: 0.14)
          : scheme.onSurface.withValues(alpha: 0.12);

  /// Enlace / botón outline secundario (p. ej. «Ver ruta»).
  Color get linkBlue => isDark ? const Color(0xFF64B5FF) : scheme.primary;
}

/// Estilo visual tipo inDrive (solo UI; no afecta lógica ni datos).
abstract final class BolaPuebloTheme {
  static const Color accent = Color(0xFF12C97A);
  static const Color accentSecondary = Color(0xFF5C6BC0);

  static ThemeData dialogTheme(BuildContext context) {
    final c = BolaPuebloColors.of(context);
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return ThemeData(
      useMaterial3: t.useMaterial3,
      brightness: t.brightness,
      colorScheme: cs.copyWith(
        primary: accent,
        onPrimary: Colors.white,
        surface: c.surface,
        onSurface: c.onSurface,
        secondary: accentSecondary,
        onSecondary: Colors.white,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          color: c.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceRaised,
        hintStyle: TextStyle(color: c.onMuted.withValues(alpha: 0.85)),
        labelStyle: TextStyle(color: c.onMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: c.onSurface.withValues(alpha: c.isDark ? 0.14 : 0.12),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.onMuted,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static SnackBar snack(BuildContext context, String message,
      {bool error = false}) {
    final c = BolaPuebloColors.of(context);
    final Color bg = error ? const Color(0xFFC62828) : c.snackNeutralBg;
    final Color fg = error ? Colors.white : c.onSurface;
    return SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: bg,
      content: Text(message,
          style: TextStyle(color: fg, fontWeight: FontWeight.w500)),
    );
  }
}

/// Layout y estilos visuales Bola Ahorro (cliente y conductor). Sin lógica de negocio.
abstract final class BolaPuebloUi {
  static const double radiusSheet = 24;
  static const double radiusCard = 22;
  static const double radiusButton = 16;
  static const double radiusSmall = 12;

  static ButtonStyle get filledPrimary => FilledButton.styleFrom(
        backgroundColor: BolaPuebloTheme.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusButton)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          letterSpacing: 0.15,
        ),
      );

  static ButtonStyle get filledSecondary => FilledButton.styleFrom(
        backgroundColor: BolaPuebloTheme.accentSecondary,
        foregroundColor: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusButton)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          letterSpacing: 0.15,
        ),
      );

  static ButtonStyle outlineAccent(BuildContext context) {
    final c = BolaPuebloColors.of(context);
    return OutlinedButton.styleFrom(
      foregroundColor: BolaPuebloTheme.accent,
      side: BorderSide(
        color: BolaPuebloTheme.accent.withValues(alpha: c.isDark ? 0.9 : 0.75),
        width: 1.25,
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusButton)),
      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    );
  }

  static ButtonStyle outlineLink(BuildContext context) {
    final c = BolaPuebloColors.of(context);
    return OutlinedButton.styleFrom(
      foregroundColor: c.linkBlue,
      side: BorderSide(color: c.linkBlue.withValues(alpha: 0.5)),
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusButton)),
      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    );
  }

  /// Encabezado del panel deslizable (tablero).
  static Widget boardHeader(
    BuildContext context, {
    required String subtitle,
  }) {
    final c = BolaPuebloColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                BolaPuebloTheme.accent.withValues(alpha: 0.28),
                BolaPuebloTheme.accent.withValues(alpha: 0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: BolaPuebloTheme.accent.withValues(alpha: 0.35)),
          ),
          child: const Icon(Icons.hub_rounded,
              color: BolaPuebloTheme.accent, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tablero en vivo',
                style: TextStyle(
                  color: c.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.45,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: TextStyle(
                  color: c.onMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  letterSpacing: 0.12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Caja de acciones principales (cliente) o aviso (conductor).
  static Widget actionPanel(
    BuildContext context, {
    required Widget child,
  }) {
    final c = BolaPuebloColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surfaceRaised.withValues(alpha: c.isDark ? 0.65 : 0.9),
        borderRadius: BorderRadius.circular(radiusSmall + 4),
        border: Border.all(
          color: c.onSurface.withValues(alpha: c.isDark ? 0.08 : 0.1),
        ),
      ),
      child: child,
    );
  }

  static Widget sectionLabel(BuildContext context, String text) {
    final c = BolaPuebloColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.05,
          color: c.onMuted,
          height: 1.2,
        ),
      ),
    );
  }

  /// Párrafos en paneles (sheet mapa + pestaña Bola).
  static TextStyle panelBody(BuildContext context) {
    final c = BolaPuebloColors.of(context);
    return TextStyle(
      color: c.onMuted,
      fontSize: 13,
      height: 1.4,
      fontWeight: FontWeight.w500,
    );
  }

  /// Título AppBar pantalla Bola (alineado con “Tablero en vivo”).
  static TextStyle screenTitleBola(BuildContext context) {
    final c = BolaPuebloColors.of(context);
    return TextStyle(
      color: c.onSurface,
      fontSize: 18,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.45,
      height: 1.15,
    );
  }

  static const double contentGutter = 16;

  static const EdgeInsets paddingTabHeader =
      EdgeInsets.fromLTRB(contentGutter, 8, contentGutter, 10);

  static const EdgeInsets paddingSheetBoardHeader =
      EdgeInsets.fromLTRB(contentGutter, 16, contentGutter, 10);

  static const EdgeInsets paddingActionPanelOuter =
      EdgeInsets.fromLTRB(contentGutter, 0, contentGutter, 14);

  static const EdgeInsets paddingList =
      EdgeInsets.fromLTRB(contentGutter, 6, contentGutter, 32);

  static const EdgeInsets paddingListEmpty =
      EdgeInsets.fromLTRB(contentGutter, 4, contentGutter, 32);

  static Widget metaRow(
    BuildContext context, {
    required IconData icon,
    required String text,
    bool emphasize = false,
  }) {
    final c = BolaPuebloColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: c.onMuted.withValues(alpha: 0.9)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: emphasize
                  ? TextStyle(
                      color: c.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    )
                  : panelBody(context).copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  static Widget routeBlock(
    BuildContext context, {
    required String origen,
    required String destino,
    String origenLabel = 'ESTOY EN',
    String destinoLabel = 'VOY PARA',
    Color? origenIconColor,
    Color? destinoIconColor,
  }) {
    final c = BolaPuebloColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surfaceRaised.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(radiusSmall),
        border: Border.all(color: c.outlineSoft.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.trip_origin,
                size: 16,
                color: origenIconColor ?? BolaPuebloTheme.accent,
              ),
              const SizedBox(width: 8),
              Text(
                origenLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                  color: c.onMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            origen,
            style: TextStyle(
              color: c.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                    child: Divider(
                        color: c.outlineSoft.withValues(alpha: 0.5),
                        height: 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_downward_rounded,
                      size: 16, color: c.onMuted),
                ),
                Expanded(
                    child: Divider(
                        color: c.outlineSoft.withValues(alpha: 0.5),
                        height: 1)),
              ],
            ),
          ),
          Row(
            children: [
              Icon(
                Icons.flag_rounded,
                size: 16,
                color: destinoIconColor ?? BolaPuebloTheme.accentSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                destinoLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                  color: c.onMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            destino,
            style: TextStyle(
              color: c.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  static Widget emptyBoard(
    BuildContext context, {
    required String message,
    IconData icon = Icons.chat_bubble_outline_rounded,
  }) {
    final c = BolaPuebloColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: BolaPuebloTheme.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: 36,
                color: BolaPuebloTheme.accent.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 18),
          Text(
            'Sin publicaciones por ahora',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.onMuted,
              height: 1.5,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Pasos 1–3 del asistente «Publicar en Bola» (estética alineada al tablero).
  static Widget crearPublicacionStepStrip(
      BuildContext context, int activeIndex) {
    final c = BolaPuebloColors.of(context);
    const titles = <String>['Ruta', 'Viaje', 'Precio'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      child: Row(
        children: List<Widget>.generate(3, (int i) {
          final bool done = i < activeIndex;
          final bool on = i == activeIndex;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                decoration: BoxDecoration(
                  gradient: on
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            BolaPuebloTheme.accent.withValues(alpha: 0.38),
                            BolaPuebloTheme.accent.withValues(alpha: 0.1),
                          ],
                        )
                      : null,
                  color: on
                      ? null
                      : done
                          ? BolaPuebloTheme.accent.withValues(alpha: 0.08)
                          : c.surfaceRaised
                              .withValues(alpha: c.isDark ? 0.55 : 0.92),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: on
                        ? BolaPuebloTheme.accent.withValues(alpha: 0.75)
                        : done
                            ? BolaPuebloTheme.accent.withValues(alpha: 0.4)
                            : c.outlineSoft.withValues(alpha: 0.45),
                    width: on ? 1.5 : 1,
                  ),
                  boxShadow: on
                      ? <BoxShadow>[
                          BoxShadow(
                            color:
                                BolaPuebloTheme.accent.withValues(alpha: 0.22),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  children: <Widget>[
                    Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        height: 1,
                        color: on || done ? BolaPuebloTheme.accent : c.onMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      titles[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.35,
                        color: on ? c.onSurface : c.onMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Cabecera del paso actual (icono + título + subtítulo).
  static Widget crearPublicacionHero(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final c = BolaPuebloColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                BolaPuebloTheme.accent.withValues(alpha: 0.42),
                BolaPuebloTheme.accentSecondary.withValues(alpha: 0.2),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: BolaPuebloTheme.accent.withValues(alpha: 0.42)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: BolaPuebloTheme.accent.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  color: c.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.55,
                  height: 1.12,
                ),
              ),
              const SizedBox(height: 8),
              Text(subtitle,
                  style:
                      panelBody(context).copyWith(fontSize: 14, height: 1.45)),
            ],
          ),
        ),
      ],
    );
  }
}
