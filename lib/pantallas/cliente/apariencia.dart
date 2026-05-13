import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/custom_theme_service.dart';
import 'package:flygo_nuevo/servicios/text_scale_service.dart';

/// Pantalla "Apariencia" del cliente.
///
/// Permite elegir CUALQUIER color de fondo de la app:
/// - Una grilla de presets cubriendo el espectro (incluyendo blanco/negro/grises).
/// - Tres sliders R/G/B para color totalmente libre.
/// - Preview en tiempo real con texto contrastante (blanco o negro calculado
///   por luminancia WCAG, garantizando contraste ≥ 4.5:1 sobre cualquier color).
/// - Botón "Restaurar por defecto" para volver al gris claro / negro original.
///
/// La elección se guarda en SharedPreferences vía [CustomThemeService.setColor].
/// Toda la app reacciona inmediatamente porque MaterialApp escucha el
/// ValueNotifier del servicio.
class AparienciaScreen extends StatefulWidget {
  const AparienciaScreen({super.key});

  @override
  State<AparienciaScreen> createState() => _AparienciaScreenState();
}

class _AparienciaScreenState extends State<AparienciaScreen> {
  // Color que el usuario está editando en vivo (no se guarda hasta tocar
  // "Aplicar" o un preset). Si nunca había elegido nada, arranca con el
  // color de fondo actual (default light/dark o el guardado previamente).
  Color? _draft;
  bool _initialized = false;

  static const List<Color> _presets = <Color>[
    // Neutros
    Color(0xFFF4F7FB), // gris claro (default light)
    Colors.white,
    Color(0xFFE5E7EB),
    Color(0xFF111827),
    Colors.black,
    // Cálidos
    Color(0xFFFFEBEE), // rosa pastel
    Color(0xFFFFCDD2), // rosa
    Color(0xFFEF4444), // rojo
    Color(0xFFFB7185), // rosa coral
    Color(0xFFF59E0B), // ámbar
    Color(0xFFFBBF24), // amarillo dorado
    Color(0xFFFEF3C7), // crema
    // Fríos
    Color(0xFFE0F7FA), // agua claro (moderno, suave)
    Color(0xFFB2EBF2), // cyan suave
    Color(0xFF22D3EE), // cyan vivo (acento agua)
    Color(0xFF10B981), // verde menta
    Color(0xFF16A34A), // verde RAI
    Color(0xFF065F46), // verde oscuro
    Color(0xFF38BDF8), // celeste
    Color(0xFF2563EB), // azul
    Color(0xFF1E3A8A), // azul oscuro
    Color(0xFF8B5CF6), // lila
    Color(0xFF7C3AED), // morado
    Color(0xFFA855F7), // violeta
  ];

  /// Presets translúcidos: tienen alpha < 1 para que en pantallas con mapa
  /// (Programar Viaje) el mapa se vea por debajo del sheet, dando la
  /// sensación de "agua / cristal". El sheet de Programar Viaje detecta
  /// el alpha y lo respeta automáticamente.
  static const List<Color> _presetsTranslucidos = <Color>[
    Color.fromARGB(140, 34, 211, 238),  // Agua translúcida (cyan vivo ~55%)
    Color.fromARGB(120, 178, 235, 242), // Agua suave (~47%)
    Color.fromARGB(110, 226, 232, 240), // Cristal (gris muy claro ~43%)
    Color.fromARGB(125, 56, 189, 248),  // Cielo translúcido (~49%)
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _draft = CustomThemeService.color.value ??
          CustomThemeService.resolveScaffoldBg(Theme.of(context).brightness);
    }
  }

  Future<void> _applyDraft() async {
    final color = _draft;
    if (color == null) return;
    await CustomThemeService.setColor(color);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Color aplicado')),
    );
  }

  Future<void> _resetDefault() async {
    await CustomThemeService.resetToDefault();
    if (!mounted) return;
    setState(() {
      _draft = CustomThemeService.resolveScaffoldBg(
          Theme.of(context).brightness);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Color restaurado al valor por defecto')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color current = _draft ??
        CustomThemeService.resolveScaffoldBg(Theme.of(context).brightness);

    // Texto de preview calculado por contraste WCAG sobre el color elegido.
    final Color previewText = CustomThemeService.textOn(current);
    final Color previewMuted = CustomThemeService.textMutedOn(current);
    final Color previewBorder = CustomThemeService.borderOn(current);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Apariencia'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Color de fondo',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Elige cualquier color. Las letras se ajustan automáticamente '
            '(blanco o negro) para que siempre se lean bien.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          _PreviewCard(
            color: current,
            previewText: previewText,
            previewMuted: previewMuted,
            previewBorder: previewBorder,
          ),

          const SizedBox(height: 20),

          Text(
            'Sugeridos',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          _PresetGrid(
            presets: _presets,
            selected: current,
            onPick: (c) => setState(() => _draft = c),
          ),

          const SizedBox(height: 24),

          Text(
            'Translúcidos (se ve el mapa abajo)',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'En la pantalla de Programar Viaje, estos colores dejan ver el '
            'mapa por debajo del panel para un efecto agua / cristal moderno.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          _PresetGrid(
            presets: _presetsTranslucidos,
            selected: current,
            onPick: (c) => setState(() => _draft = c),
          ),

          const SizedBox(height: 20),

          ValueListenableBuilder<bool>(
            valueListenable: CustomThemeService.mapFloatingChrome,
            builder: (context, floating, _) {
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Icon(
                  Icons.layers_outlined,
                  color: floating ? cs.primary : cs.onSurfaceVariant,
                ),
                title: Text(
                  'Flotante sobre mapa',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'En Programar Viaje: sin fondo del panel, solo campos y '
                  'botones con borde, flotando sobre el mapa (efecto moderno). '
                  'El resto de la app sigue igual.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                value: floating,
                onChanged: (v) async {
                  await CustomThemeService.setMapFloatingChrome(v);
                },
              );
            },
          ),

          const SizedBox(height: 24),

          Text(
            'Color personalizado (RGB)',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _RgbSliders(
            color: current,
            onChanged: (c) => setState(() => _draft = c),
          ),

          const SizedBox(height: 28),

          // ----- Tamaño de texto (tipo inDrive) -----
          Text(
            'Tamaño del texto',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Ajusta el tamaño de las letras de toda la app. El rango está '
            'limitado para que ninguna pantalla se desborde.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          const _TextScaleSection(),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _resetDefault,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Restaurar'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _applyDraft,
                  icon: const Icon(Icons.check),
                  label: const Text('Aplicar'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.color,
    required this.previewText,
    required this.previewMuted,
    required this.previewBorder,
  });

  final Color color;
  final Color previewText;
  final Color previewMuted;
  final Color previewBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: previewBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vista previa',
            style: TextStyle(
              color: previewText,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Así se ve el texto principal y el secundario sobre tu color.',
            style: TextStyle(
              color: previewMuted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: previewText.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: previewBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.bolt_rounded, color: previewText, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Botón ejemplo',
                  style: TextStyle(
                    color: previewText,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetGrid extends StatelessWidget {
  const _PresetGrid({
    required this.presets,
    required this.selected,
    required this.onPick,
  });

  final List<Color> presets;
  final Color selected;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 6,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: presets.map((c) {
        final bool isSelected = _sameColor(c, selected);
        // Si el preset es translúcido (alpha < 1), se dibuja sobre un fondo
        // tipo "tablero de ajedrez" para que el usuario VEA que es
        // transparente y no se confunda con un color sólido pálido.
        final bool isTranslucido = c.a < 0.97;
        return InkWell(
          onTap: () => onPick(c),
          borderRadius: BorderRadius.circular(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (isTranslucido)
                  const _CheckerboardPattern(),
                Container(
                  decoration: BoxDecoration(
                    color: c,
                    border: Border.all(
                      color: isSelected
                          ? CustomThemeService.textOn(c)
                          : CustomThemeService.borderOn(c),
                      width: isSelected ? 2.4 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: isSelected
                      ? Icon(Icons.check,
                          color: CustomThemeService.textOn(c))
                      : (isTranslucido
                          ? Icon(Icons.water_drop_rounded,
                              color: CustomThemeService.textOn(c)
                                  .withValues(alpha: 0.55),
                              size: 18)
                          : null),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  static bool _sameColor(Color a, Color b) {
    return (a.r - b.r).abs() < 0.004 &&
        (a.g - b.g).abs() < 0.004 &&
        (a.b - b.b).abs() < 0.004 &&
        (a.a - b.a).abs() < 0.004;
  }
}

class _RgbSliders extends StatelessWidget {
  const _RgbSliders({required this.color, required this.onChanged});

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final int r = (color.r * 255.0).round();
    final int g = (color.g * 255.0).round();
    final int b = (color.b * 255.0).round();

    Widget slider({
      required String label,
      required int value,
      required Color activeColor,
      required ValueChanged<int> onChange,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: Slider(
                value: value.toDouble(),
                min: 0,
                max: 255,
                divisions: 255,
                activeColor: activeColor,
                label: '$value',
                onChanged: (v) => onChange(v.round()),
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                '$value',
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        slider(
          label: 'R',
          value: r,
          activeColor: const Color(0xFFEF4444),
          onChange: (v) => onChanged(Color.fromARGB(255, v, g, b)),
        ),
        slider(
          label: 'G',
          value: g,
          activeColor: const Color(0xFF10B981),
          onChange: (v) => onChanged(Color.fromARGB(255, r, v, b)),
        ),
        slider(
          label: 'B',
          value: b,
          activeColor: const Color(0xFF3B82F6),
          onChange: (v) => onChanged(Color.fromARGB(255, r, g, v)),
        ),
      ],
    );
  }
}

/// Sección de tamaño de texto (tipo inDrive).
///
/// Muestra:
/// - 4 botones rápidos (Pequeño / Normal / Grande / Muy grande).
/// - Un slider continuo para ajuste fino.
/// - Una vista previa en vivo con texto que cambia de tamaño.
///
/// El factor se guarda inmediatamente vía [TextScaleService.setFactor], así
/// el usuario ve el efecto en toda la app al instante.
class _TextScaleSection extends StatelessWidget {
  const _TextScaleSection();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ValueListenableBuilder<double>(
      valueListenable: TextScaleService.factor,
      builder: (context, factor, _) {
        final String label = TextScaleService.labelFor(factor);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vista previa',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Pide ahora',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Solicita un viaje en segundos',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _scaleChip(context, 'Pequeño', 0.88, factor),
                _scaleChip(context, 'Normal', 1.00, factor),
                _scaleChip(context, 'Grande', 1.15, factor),
                _scaleChip(context, 'Muy grande', 1.30, factor),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.text_decrease, color: cs.onSurfaceVariant, size: 20),
                Expanded(
                  child: Slider(
                    value: factor,
                    min: TextScaleService.minFactor,
                    max: TextScaleService.maxFactor,
                    divisions:
                        ((TextScaleService.maxFactor -
                                    TextScaleService.minFactor) *
                                100)
                            .round(),
                    label: label,
                    onChanged: (v) => TextScaleService.setFactor(v),
                  ),
                ),
                Icon(Icons.text_increase, color: cs.onSurfaceVariant, size: 22),
              ],
            ),
            Center(
              child: Text(
                '$label · ${(factor * 100).round()}%',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _scaleChip(
    BuildContext context,
    String label,
    double value,
    double current,
  ) {
    final bool selected = (current - value).abs() < 0.02;
    final cs = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => TextScaleService.setFactor(value),
      selectedColor: cs.primary.withValues(alpha: 0.18),
      labelStyle: TextStyle(
        color: selected ? cs.primary : cs.onSurface,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(
        color: selected ? cs.primary : cs.outlineVariant,
      ),
    );
  }
}

/// Patrón "tablero de ajedrez" gris/blanco usado como fondo bajo los presets
/// translúcidos. Es la convención universal para indicar que un color tiene
/// transparencia (estilo Photoshop / editores de imagen). Pintado en código,
/// sin assets.
class _CheckerboardPattern extends StatelessWidget {
  const _CheckerboardPattern();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CheckerboardPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  static const double _cell = 6.0;
  static final Paint _light = Paint()..color = const Color(0xFFFFFFFF);
  static final Paint _dark = Paint()..color = const Color(0xFFE5E7EB);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _light);
    final int cols = (size.width / _cell).ceil();
    final int rows = (size.height / _cell).ceil();
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        if ((row + col).isEven) continue;
        canvas.drawRect(
          Rect.fromLTWH(col * _cell, row * _cell, _cell, _cell),
          _dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
