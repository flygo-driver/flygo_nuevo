// lib/widgets/campo_lugar_autocomplete.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../servicios/lugares_service.dart';

/// Entrada persistida: con `placeId` el toque dispara el mismo flujo que elegir de la lista (precio, ruta).
class _RecienteEntry {
  const _RecienteEntry({required this.label, required this.placeId});

  final String label;
  final String placeId;
}

class CampoLugarAutocomplete extends StatefulWidget {
  final String label;
  final String? hint;
  final String? initialText;
  final String? country; // 'DO'
  final double? biasLat;
  final double? biasLon;
  final ValueChanged<DetalleLugar> onPlaceSelected;
  final ValueChanged<String>? onTextChanged;
  final int minChars;
  final bool showQuickSuggestions; // NUEVO: mostrar sugerencias rápidas
  final bool showCategories; // NUEVO: mostrar categorías
  /// Si se define, el campo usa estos colores (p. ej. teal/azul alineado al paso origen/destino).
  final Color? fieldAccent;
  final Color? fieldFill;

  /// Si se define, sustituye el icono de lupa del campo (p. ej. caja GPS estilo “múltiples paradas”).
  final Widget? prefixIcon;

  /// Color del texto que escribe el usuario (si es null y el fondo es oscuro, se usa blanco).
  final Color? fieldTextColor;
  final Color? fieldHintColor;
  final Color? fieldLabelColor;

  const CampoLugarAutocomplete({
    super.key,
    required this.label,
    required this.onPlaceSelected,
    this.hint,
    this.initialText,
    this.country,
    this.biasLat,
    this.biasLon,
    this.onTextChanged,
    this.minChars = 1,
    this.showQuickSuggestions = true, // Activado por defecto
    this.showCategories = true, // Activado por defecto
    this.fieldAccent,
    this.fieldFill,
    this.prefixIcon,
    this.fieldTextColor,
    this.fieldHintColor,
    this.fieldLabelColor,
  });

  @override
  State<CampoLugarAutocomplete> createState() => _CampoLugarAutocompleteState();
}

class _CampoLugarAutocompleteState extends State<CampoLugarAutocomplete>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _svc = LugaresService.instance;

  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();

  OverlayEntry? _entry;
  List<PrediccionLugar> _sugs = const [];
  Timer? _debounce;
  bool _loading = false;

  // Evita que una respuesta anterior (petición atrasada) sobrescriba
  // el estado actual cuando el usuario escribe rápido.
  int _autocompleteSeq = 0;

  /// Evita que al asignar [_controller.text] con un lugar ya resuelto se dispare
  /// [onTextChanged] en el padre (p. ej. programar_viaje borraba lat/_destinoDet y la cotización no corría).
  bool _applyingResolvedPlace = false;

  // Lugares recientes (label + placeId para re-selección fiable).
  List<_RecienteEntry> _recientes = [];
  static const int _maxRecientes = 4;
  static const String _prefsRecientesV2 = 'lugares_recientes_v2';
  static const String _prefsRecientesLegacy = 'lugares_recientes';

  // NUEVO: lugares populares de RD
  final List<Map<String, dynamic>> _lugaresPopulares = [
    {
      'nombre': 'Santo Domingo',
      'icon': Icons.location_city,
      'color': Colors.blue
    },
    {'nombre': 'Santiago', 'icon': Icons.location_city, 'color': Colors.indigo},
    {'nombre': 'Punta Cana', 'icon': Icons.beach_access, 'color': Colors.amber},
    {
      'nombre': 'Puerto Plata',
      'icon': Icons.beach_access,
      'color': Colors.orange
    },
    {
      'nombre': 'La Romana',
      'icon': Icons.location_city,
      'color': Colors.purple
    },
    {'nombre': 'Bávaro', 'icon': Icons.beach_access, 'color': Colors.teal},
    {'nombre': 'Jarabacoa', 'icon': Icons.terrain, 'color': Colors.green},
    {'nombre': 'Constanza', 'icon': Icons.terrain, 'color': Colors.lightGreen},
  ];

  // NUEVO: categorías de búsqueda
  final List<Map<String, dynamic>> _categorias = [
    {
      'nombre': 'Restaurantes',
      'tipo': 'restaurant',
      'icon': Icons.restaurant,
      'color': Colors.red
    },
    {
      'nombre': 'Hoteles',
      'tipo': 'lodging',
      'icon': Icons.hotel,
      'color': Colors.purple
    },
    {
      'nombre': 'Aeropuerto',
      'tipo': 'airport',
      'icon': Icons.local_airport,
      'color': Colors.blue
    },
    {
      'nombre': 'Hospital',
      'tipo': 'hospital',
      'icon': Icons.local_hospital,
      'color': Colors.redAccent
    },
    {
      'nombre': 'Supermercado',
      'tipo': 'supermarket',
      'icon': Icons.shopping_cart,
      'color': Colors.green
    },
    {
      'nombre': 'Farmacia',
      'tipo': 'pharmacy',
      'icon': Icons.local_pharmacy,
      'color': Colors.cyan
    },
    {
      'nombre': 'Gasolinera',
      'tipo': 'gas_station',
      'icon': Icons.local_gas_station,
      'color': Colors.orange
    },
    {
      'nombre': 'Banco',
      'tipo': 'bank',
      'icon': Icons.account_balance,
      'color': Colors.brown
    },
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final init = (widget.initialText ?? '').trim();
    if (init.isNotEmpty) _controller.text = init;

    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _clearSugsAndOverlay();
      } else {
        if (_sugs.isNotEmpty) _showOverlay();
      }
    });

    _cargarRecientes();
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    setState(() {});
    if (_entry != null) _refreshOverlay();
  }

  Future<void> _cargarRecientes() async {
    final prefs = await SharedPreferences.getInstance();
    final rawV2 = prefs.getString(_prefsRecientesV2);
    List<_RecienteEntry> list = [];
    if (rawV2 != null && rawV2.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawV2);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is! Map) continue;
            final m = Map<String, dynamic>.from(e);
            final l = (m['l'] ?? m['label'] ?? '').toString().trim();
            if (l.isEmpty) continue;
            final p = (m['p'] ?? m['placeId'] ?? '').toString().trim();
            list.add(_RecienteEntry(label: l, placeId: p));
          }
        }
      } catch (_) {}
    }
    if (list.isEmpty) {
      final legacy = prefs.getStringList(_prefsRecientesLegacy) ?? [];
      for (final l in legacy) {
        final t = l.trim();
        if (t.isNotEmpty) list.add(_RecienteEntry(label: t, placeId: ''));
      }
    }
    if (list.length > _maxRecientes) {
      list = list.sublist(0, _maxRecientes);
    }
    if (!mounted) return;
    setState(() => _recientes = list);
  }

  Future<void> _guardarReciente(DetalleLugar det) async {
    final prefs = await SharedPreferences.getInstance();
    var list = List<_RecienteEntry>.from(_recientes);

    list.removeWhere((e) {
      if (det.placeId.isNotEmpty && e.placeId == det.placeId) return true;
      return _norm(e.label) == _norm(det.displayLabel);
    });
    list.insert(
      0,
      _RecienteEntry(label: det.displayLabel, placeId: det.placeId),
    );
    if (list.length > _maxRecientes) {
      list = list.sublist(0, _maxRecientes);
    }

    final encoded = jsonEncode(
      list.map((e) => {'l': e.label, 'p': e.placeId}).toList(),
    );
    await prefs.setString(_prefsRecientesV2, encoded);
    await prefs.remove(_prefsRecientesLegacy);
    if (!mounted) return;
    setState(() => _recientes = list);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _removeOverlay();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  void _clearSugsAndOverlay() {
    if (mounted) setState(() => _sugs = const []);
    _removeOverlay();
  }

  void _showOverlay() {
    if (!mounted) return;
    _removeOverlay();

    final overlay = Overlay.of(context, rootOverlay: true);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;
    final overlayBg = isDark ? const Color(0xFF121212) : scheme.surface;
    final overlayBorder =
        isDark ? Colors.white24 : scheme.outline.withValues(alpha: 0.35);
    final dividerColor =
        isDark ? Colors.white12 : scheme.outline.withValues(alpha: 0.2);
    final titleStyle = TextStyle(
      color: isDark ? Colors.white : scheme.onSurface,
      fontWeight: FontWeight.w600,
      fontSize: 15,
    );
    final subtitleStyle = TextStyle(
      color: isDark ? Colors.white54 : scheme.onSurface.withValues(alpha: 0.62),
      fontSize: 12,
    );
    final placeIconColor =
        isDark ? Colors.greenAccent : const Color(0xFF059669);

    _entry = OverlayEntry(
      builder: (overlayCtx) {
        final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
        final fieldSize = box?.size ?? const Size(300, 56);
        final mq = MediaQuery.of(overlayCtx);
        final kb = mq.viewInsets.bottom;
        double spaceBelow = 400;
        double spaceAbove = 200;
        if (box != null && box.hasSize) {
          final topLeft = box.localToGlobal(Offset.zero);
          final screenH = mq.size.height;
          spaceBelow = screenH - kb - (topLeft.dy + fieldSize.height) - 12;
          spaceAbove = topLeft.dy - mq.padding.top - 8;
        }
        const minComfort = 168.0;
        final openUpward = spaceBelow < minComfort &&
            spaceAbove >= 120 &&
            spaceAbove >= spaceBelow - 40;
        final maxListH =
            (openUpward ? spaceAbove : spaceBelow).clamp(140.0, 340.0);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  _focus.unfocus();
                  _clearSugsAndOverlay();
                },
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor:
                  openUpward ? Alignment.topLeft : Alignment.bottomLeft,
              followerAnchor:
                  openUpward ? Alignment.bottomLeft : Alignment.topLeft,
              offset: Offset(0, openUpward ? -8 : 8),
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: fieldSize.width,
                    maxHeight: maxListH,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: overlayBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: overlayBorder),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black54
                              : Colors.black.withValues(alpha: 0.12),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Scrollbar(
                      thumbVisibility: _sugs.length > 5,
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _sugs.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: dividerColor),
                        itemBuilder: (_, i) {
                          final p = _sugs[i];
                          final subtitle = (p.secondary ?? '').trim();
                          return ListTile(
                            dense: true,
                            leading: Icon(Icons.place,
                                color: placeIconColor, size: 20),
                            title: Text(p.primary, style: titleStyle),
                            subtitle: subtitle.isNotEmpty
                                ? Text(subtitle, style: subtitleStyle)
                                : null,
                            onTap: () => _selectPrediction(p),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_entry!);
  }

  void _refreshOverlay() {
    if (_entry == null) return;
    _entry!.markNeedsBuild();
  }

  String _norm(String s) {
    final v = s.toLowerCase().trim();
    return v
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll('ü', 'u')
        .replaceAll('à', 'a')
        .replaceAll('è', 'e')
        .replaceAll('ì', 'i')
        .replaceAll('ò', 'o')
        .replaceAll('ù', 'u')
        .replaceAll('ä', 'a')
        .replaceAll('ë', 'e')
        .replaceAll('ï', 'i')
        .replaceAll('ö', 'o')
        .replaceAll('Ä', 'a')
        .replaceAll('Ë', 'e')
        .replaceAll('Ï', 'i')
        .replaceAll('Ö', 'o')
        .replaceAll('Á', 'a')
        .replaceAll('É', 'e')
        .replaceAll('Í', 'i')
        .replaceAll('Ó', 'o')
        .replaceAll('Ú', 'u')
        .replaceAll('Ñ', 'n')
        .replaceAll('Ü', 'u');
  }

  List<PrediccionLugar> _rankPredictions(
    List<PrediccionLugar> preds,
    String q,
  ) {
    final nq = _norm(q);
    if (nq.isEmpty) return preds;

    final scored = preds.map((p) {
      final primary = _norm(p.primary);
      final secondary = _norm(p.secondary ?? '');

      int score = 0;
      if (primary.startsWith(nq)) score += 120;
      if (secondary.isNotEmpty && secondary.contains(nq)) score += 40;
      if (primary.contains(nq)) score += 20;

      return MapEntry(p, score);
    }).toList();

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList(growable: false);
  }

  void _onChanged(String text) {
    if (_applyingResolvedPlace) {
      _debounce?.cancel();
      _removeOverlay();
      if (mounted) {
        setState(() {
          _sugs = const [];
          _loading = false;
        });
      }
      return;
    }

    widget.onTextChanged?.call(text);

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () async {
      final q = text.trim();
      if (q.length < widget.minChars || !_focus.hasFocus) {
        _clearSugsAndOverlay();
        return;
      }

      final int seq = ++_autocompleteSeq;
      if (mounted) setState(() => _loading = true);

      final sugs = await _svc.autocompletar(
        q,
        biasLat: widget.biasLat,
        biasLon: widget.biasLon,
        country: widget.country ?? 'DO',
      );

      if (!mounted) return;
      if (seq != _autocompleteSeq) return;
      if (_controller.text.trim() != q) return;

      setState(() {
        _loading = false;
        _sugs = _rankPredictions(sugs, q);
      });

      if (_sugs.isEmpty) {
        _removeOverlay();
      } else {
        if (_focus.hasFocus) {
          if (_entry == null) {
            _showOverlay();
          } else {
            _refreshOverlay();
          }
        }
      }
    });
  }

  Future<void> _finalizePlaceSelection(DetalleLugar det) async {
    _debounce?.cancel();
    _autocompleteSeq++;
    _applyingResolvedPlace = true;
    try {
      _controller.text = det.displayLabel;
      // Antes de prefs async: el padre fija coords y programa cotización sin ventana intermedia.
      widget.onPlaceSelected(det);
      await _guardarReciente(det);
    } finally {
      _applyingResolvedPlace = false;
    }
    _focus.unfocus();
    _clearSugsAndOverlay();
  }

  Future<void> _selectPrediction(PrediccionLugar p) async {
    if (mounted) setState(() => _loading = true);
    _removeOverlay();

    final det = await _svc.detalle(p.placeId);

    if (!mounted) return;
    setState(() => _loading = false);

    if (det != null) {
      await _finalizePlaceSelection(det);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo obtener el detalle del lugar.'),
        ),
      );
    }
  }

  /// Toca un chip reciente: prioriza `detalle(placeId)` para disparar igual que una sugerencia.
  Future<void> _seleccionarReciente(_RecienteEntry entry) async {
    if (entry.placeId.isNotEmpty) {
      if (mounted) setState(() => _loading = true);
      _removeOverlay();
      final det = await _svc.detalle(entry.placeId);
      if (!mounted) return;
      setState(() => _loading = false);
      if (det != null) {
        await _finalizePlaceSelection(det);
        return;
      }
    }
    await _seleccionarPopular(entry.label);
  }

  // NUEVO: seleccionar lugar popular
  Future<void> _seleccionarPopular(String lugar) async {
    _debounce?.cancel();
    _autocompleteSeq++;
    _applyingResolvedPlace = true;
    try {
      _controller.text = lugar;
    } finally {
      _applyingResolvedPlace = false;
    }

    List<PrediccionLugar> sugs = await _svc.autocompletar(
      lugar,
      biasLat: widget.biasLat,
      biasLon: widget.biasLon,
      country: widget.country ?? 'DO',
    );

    if (sugs.isEmpty && lugar.contains(',')) {
      final shorter = lugar.split(',').first.trim();
      if (shorter.length >= widget.minChars) {
        sugs = await _svc.autocompletar(
          shorter,
          biasLat: widget.biasLat,
          biasLon: widget.biasLon,
          country: widget.country ?? 'DO',
        );
      }
    }

    if (!mounted) return;
    if (sugs.isNotEmpty) {
      final ranked = _rankPredictions(sugs, lugar);
      await _selectPrediction(ranked.first);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No encontramos ese lugar. Escribí de nuevo o elegí de la lista.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // NUEVO: seleccionar categoría
  Future<void> _seleccionarCategoria(String tipo, String nombre) async {
    _controller.text = nombre;
    widget.onTextChanged?.call(nombre);

    // Buscar lugares de esa categoría cerca
    if (widget.biasLat != null && widget.biasLon != null) {
      // Aquí podrías implementar búsqueda por categoría
      // Por ahora, buscamos lugares cercanos
      final sugs = await _svc.autocompletar(
        nombre,
        biasLat: widget.biasLat,
        biasLon: widget.biasLon,
        country: widget.country ?? 'DO',
      );

      if (sugs.isNotEmpty && mounted) {
        await _selectPrediction(sugs.first);
      }
    }
  }

  Color? _fillFromInputTheme(ThemeData theme) {
    final Object? fill = theme.inputDecorationTheme.fillColor;
    if (fill == null) return null;
    if (fill is Color) return fill;
    if (fill is WidgetStateProperty<Color?>) {
      return fill.resolve(const <WidgetState>{});
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent =
        widget.fieldAccent ?? (isDark ? Colors.greenAccent : scheme.primary);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide:
          BorderSide(color: accent.withValues(alpha: isDark ? 0.9 : 0.55)),
    );
    final fillColor = widget.fieldFill ??
        _fillFromInputTheme(theme) ??
        (isDark ? Colors.grey[900]! : scheme.surfaceContainerHigh);

    // Contraste fijo según luminancia del fondo (claro u oscuro), sin depender solo del tema.
    const Color textoSobreClaro = Color(0xFF101828);
    const Color hintSobreClaro = Color(0xFF667085);
    const Color etiquetaSobreClaro = Color(0xFF475467);
    final double lum = fillColor.computeLuminance();
    final bool fondoOscuro = lum < 0.45;

    final Color textoCampo =
        widget.fieldTextColor ?? (fondoOscuro ? Colors.white : textoSobreClaro);
    final Color hintCampo = widget.fieldHintColor ??
        (fondoOscuro ? const Color(0x99FFFFFF) : hintSobreClaro);
    final Color etiquetaCampo = widget.fieldLabelColor ??
        (fondoOscuro ? Colors.white70 : etiquetaSobreClaro);
    final Color iconoLimpiar =
        fondoOscuro ? Colors.white54 : const Color(0xFF667085);

    final kbInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: kbInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CompositedTransformTarget(
            link: _layerLink,
            child: TextFormField(
              key: _fieldKey,
              controller: _controller,
              focusNode: _focus,
              style: TextStyle(color: textoCampo, fontSize: 16),
              cursorColor: accent,
              scrollPadding: const EdgeInsets.fromLTRB(0, 0, 0, 320),
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hint ?? 'Ej: Santo Domingo, Punta Cana...',
                labelStyle: TextStyle(color: etiquetaCampo),
                floatingLabelStyle: TextStyle(color: etiquetaCampo),
                hintStyle: TextStyle(color: hintCampo),
                filled: true,
                fillColor: fillColor,
                prefixIcon: widget.prefixIcon ??
                    Icon(Icons.search_rounded, color: accent),
                suffixIcon: _loading
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accent,
                          ),
                        ),
                      )
                    : (_controller.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear_rounded,
                              color: iconoLimpiar,
                            ),
                            onPressed: () {
                              _controller.clear();
                              widget.onTextChanged?.call('');
                              _clearSugsAndOverlay();
                            },
                          )
                        : null),
                border: border,
                enabledBorder: border,
                focusedBorder: border.copyWith(
                  borderSide: BorderSide(color: accent, width: 2),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ).applyDefaults(theme.inputDecorationTheme),
              onChanged: _onChanged,
              onTap: () {
                if (_sugs.isNotEmpty && _focus.hasFocus) _showOverlay();
              },
            ),
          ),
          const SizedBox(height: 8),
          if (widget.showQuickSuggestions &&
              _controller.text.isEmpty &&
              _focus.hasFocus)
            _buildQuickSuggestions(),
          if (widget.showCategories &&
              _controller.text.isEmpty &&
              _focus.hasFocus)
            _buildCategoriesSection(),
          if (_recientes.isNotEmpty &&
              _controller.text.isEmpty &&
              _focus.hasFocus)
            _buildRecientesSection(),
        ],
      ),
    );
  }

  // NUEVO: sugerencias rápidas (lugares populares)
  Widget _buildQuickSuggestions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerColor = isDark
        ? Colors.white70
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Lugares populares',
              style: TextStyle(
                color: headerColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _lugaresPopulares.map((lugar) {
              return InkWell(
                onTap: () => _seleccionarPopular(lugar['nombre']),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: (lugar['color'] as Color).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: lugar['color']),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(lugar['icon'], color: lugar['color'], size: 16),
                      const SizedBox(width: 6),
                      Text(
                        lugar['nombre'],
                        style: TextStyle(
                          color: lugar['color'],
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // NUEVO: categorías de búsqueda
  Widget _buildCategoriesSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerColor = isDark
        ? Colors.white70
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Buscar por categoría',
              style: TextStyle(
                color: headerColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _categorias.length,
              itemBuilder: (context, index) {
                final cat = _categorias[index];
                return Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () =>
                        _seleccionarCategoria(cat['tipo'], cat['nombre']),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (cat['color'] as Color).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cat['color']),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(cat['icon'], color: cat['color'], size: 28),
                          const SizedBox(height: 4),
                          Text(
                            cat['nombre'],
                            style: TextStyle(
                              color: cat['color'],
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // NUEVO: lugares recientes
  Widget _buildRecientesSection() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;
    final headerColor =
        isDark ? Colors.white70 : scheme.onSurface.withValues(alpha: 0.65);
    final chipBg = isDark ? Colors.grey[800]! : scheme.surfaceContainerHighest;
    final chipBorder =
        isDark ? Colors.white24 : scheme.outline.withValues(alpha: 0.28);
    final chipText =
        isDark ? Colors.white70 : scheme.onSurface.withValues(alpha: 0.85);
    final iconColor =
        isDark ? Colors.white54 : scheme.onSurface.withValues(alpha: 0.5);

    return Container(
      margin: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              'Recientes',
              style: TextStyle(
                color: headerColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 76),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _recientes.map((entry) {
                  final lugar = entry.label;
                  return InkWell(
                    onTap: () => _seleccionarReciente(entry),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: chipBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: chipBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, color: iconColor, size: 13),
                          const SizedBox(width: 5),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 160),
                            child: Text(
                              lugar.length > 28
                                  ? '${lugar.substring(0, 26)}…'
                                  : lugar,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: chipText,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
