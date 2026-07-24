import 'dart:async';

import 'package:flutter/material.dart';
import '../servicios/lugares_service.dart';
import '../servicios/rai_speech_busqueda_direccion.dart';
import '../utils/rai_aplicar_destino_desde_voz.dart';
import 'rai_direccion_inteligente_sheet.dart';

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
  /// Conservados por compatibilidad con callsites existentes, pero la sección
  /// "Lugares populares" se eliminó por UX. Cualquier valor pasado se ignora.
  final bool showQuickSuggestions;

  /// Conservados por compatibilidad con callsites existentes, pero la sección
  /// "Buscar por categoría" se eliminó por UX. Cualquier valor pasado se ignora.
  final bool showCategories;
  /// Si se define, el campo usa estos colores (p. ej. teal/azul alineado al paso origen/destino).
  final Color? fieldAccent;
  final Color? fieldFill;

  /// Si se define, sustituye el icono de lupa del campo (p. ej. caja GPS estilo “múltiples paradas”).
  final Widget? prefixIcon;

  /// Color del texto que escribe el usuario (si es null y el fondo es oscuro, se usa blanco).
  final Color? fieldTextColor;
  final Color? fieldHintColor;
  final Color? fieldLabelColor;

  /// Botón RAI: búsqueda inteligente (IA + Places) para destinos difíciles.
  final bool asistenteDireccionHabilitado;

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
    this.showQuickSuggestions = false, // Sección eliminada por UX
    this.showCategories = false, // Sección eliminada por UX
    this.fieldAccent,
    this.fieldFill,
    this.prefixIcon,
    this.fieldTextColor,
    this.fieldHintColor,
    this.fieldLabelColor,
    this.asistenteDireccionHabilitado = true,
  });

  @override
  State<CampoLugarAutocomplete> createState() => CampoLugarAutocompleteState();
}

class CampoLugarAutocompleteState extends State<CampoLugarAutocomplete>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _svc = LugaresService.instance;

  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();

  OverlayEntry? _entry;
  List<PrediccionLugar> _sugs = const [];
  Timer? _debounce;
  Timer? _unfocusClearTimer;
  bool _loading = false;
  /// Evita que al hacer clic en laptop/web el unfocus borre el overlay antes del tap.
  bool _seleccionEnCurso = false;
  /// Scroll/toques en el panel de sugerencias (no cerrar al perder foco del TextField).
  bool _overlayInteracting = false;
  /// Campo + lista de sugerencias: mismo grupo para no cerrar al tocar una opción.
  final Object _tapRegionGroup = Object();
  /// En móvil el teclado quita el foco al tocar un chip; sin esto desaparecen antes del tap.
  bool _mostrarRecientes = false;

  // Evita que una respuesta anterior (petición atrasada) sobrescriba
  // el estado actual cuando el usuario escribe rápido.
  int _autocompleteSeq = 0;

  /// Evita que al asignar [_controller.text] con un lugar ya resuelto se dispare
  /// [onTextChanged] en el padre (p. ej. programar_viaje borraba lat/_destinoDet y la cotización no corría).
  bool _applyingResolvedPlace = false;

  List<RecienteLugar> _recientes = [];
  List<DetalleLugar> _candidatosVozResueltos = const [];

  final RaiSpeechBusquedaDireccion _voz = RaiSpeechBusquedaDireccion();
  bool _escuchando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final init = (widget.initialText ?? '').trim();
    if (init.isNotEmpty) _controller.text = init;

    _focus.addListener(() {
      if (_focus.hasFocus) {
        _unfocusClearTimer?.cancel();
        _mostrarRecientes = true;
        if (_sugs.isNotEmpty) _showOverlay();
        return;
      }
      // No cerrar recientes ni overlay al perder foco: en móvil el tap en chip
      // quita el foco del TextField antes de registrar el gesto.
      _unfocusClearTimer?.cancel();
    });

    _cargarRecientes();
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    setState(() {});
    if (_entry != null) _refreshOverlay();
  }

  void _onVozListeningChanged(bool active) {
    if (!mounted) return;
    setState(() => _escuchando = active);
  }

  Future<void> _toggleVoz() async {
    if (_loading) return;
    if (_escuchando) {
      await _voz.stop();
      if (mounted) setState(() => _escuchando = false);
      return;
    }
    _focus.requestFocus();
    final ok = await _voz.toggleListen(
      onListeningChanged: _onVozListeningChanged,
      onResult: (words, isFinal) {
        if (!mounted) return;
        _applyingResolvedPlace = true;
        try {
          _controller.text = words;
          widget.onTextChanged?.call(words);
        } finally {
          _applyingResolvedPlace = false;
        }
        _onChanged(words);
        if (isFinal && words.trim().length >= 2) {
          unawaited(_resolverYAplicarTrasVoz(words.trim()));
        }
      },
    );
    if (!ok && mounted) {
      final msg = _voz.ultimoFallo?.trim();
      if (msg != null && msg.isNotEmpty) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    }
  }

  /// Dictado terminado → resolver dirección → [onPlaceSelected] → cotización en el padre.
  Future<void> _resolverYAplicarTrasVoz(String texto) async {
    if (!mounted || texto.trim().length < 2) return;

    setState(() => _loading = true);
    final res = await RaiAplicarDestinoDesdeVoz.resolver(
      textoReconocido: texto,
      biasLat: widget.biasLat,
      biasLon: widget.biasLon,
      desdeVoz: true,
    );
    if (!mounted) return;

    final confiable = res.lugarConfiable;
    if (confiable != null) {
      setState(() => _loading = false);
      await _finalizePlaceSelection(confiable);
      return;
    }

    if (res.candidatos.isNotEmpty) {
      setState(() {
        _loading = false;
        _candidatosVozResueltos = res.candidatos;
        _sugs = res.candidatos
            .map(
              (d) => PrediccionLugar(
                placeId: d.placeId,
                primary: d.displayLabel,
                secondary: 'Sugerencia por voz',
              ),
            )
            .toList(growable: false);
      });
      _focus.requestFocus();
      if (_entry == null) {
        _showOverlay();
      } else {
        _refreshOverlay();
      }
      return;
    }

    setState(() => _loading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No encontramos ese lugar. Prueba con más detalle o usa RAI (✨).',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _cargarRecientes() async {
    final list = await _svc.cargarRecientes();
    if (!mounted) return;
    setState(() => _recientes = list);
  }

  Future<void> _guardarReciente(DetalleLugar det) async {
    await _svc.guardarReciente(det);
    final list = await _svc.cargarRecientes();
    if (!mounted) return;
    setState(() => _recientes = list);
  }

  List<PrediccionLugar> _recientesComoPredicciones(String q) {
    final nq = _norm(q.trim());
    final out = <PrediccionLugar>[];
    for (final e in _recientes) {
      if (nq.isNotEmpty && !_norm(e.label).contains(nq)) continue;
      out.add(
        PrediccionLugar(
          placeId: e.placeId.isNotEmpty ? e.placeId : 'recent:${e.label}',
          primary: e.label,
          secondary: 'Reciente',
        ),
      );
    }
    return out;
  }

  bool _esPrediccionReciente(PrediccionLugar p) =>
      p.secondary == 'Reciente' || p.placeId.startsWith('recent:');

  @override
  void didUpdateWidget(covariant CampoLugarAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nuevo = (widget.initialText ?? '').trim();
    final anterior = (oldWidget.initialText ?? '').trim();
    if (nuevo.isNotEmpty &&
        nuevo != anterior &&
        nuevo != _controller.text.trim()) {
      _applyingResolvedPlace = true;
      try {
        _controller.text = nuevo;
      } finally {
        _applyingResolvedPlace = false;
      }
    }
  }

  /// Sincroniza el texto visible sin volver a disparar [onPlaceSelected].
  void sincronizarTexto(String texto) {
    if (texto == _controller.text) return;
    _applyingResolvedPlace = true;
    try {
      _controller.text = texto;
    } finally {
      _applyingResolvedPlace = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _unfocusClearTimer?.cancel();
    if (_voz.isListening) unawaited(_voz.stop());
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
            // Barrera DETRÁS de la lista: cierra al tocar fuera, pero no
            // intercepta scroll/tap de las opciones (van encima en el Stack).
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_seleccionEnCurso || _overlayInteracting) return;
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
              child: TapRegion(
                groupId: _tapRegionGroup,
                child: Material(
                  color: Colors.transparent,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) {
                      _overlayInteracting = true;
                      _unfocusClearTimer?.cancel();
                    },
                    onPointerUp: (_) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _overlayInteracting = false;
                      });
                    },
                    onPointerCancel: (_) {
                      _overlayInteracting = false;
                    },
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
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (_) => true,
                          child: Scrollbar(
                            thumbVisibility: _sugs.length > 5,
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              primary: false,
                              physics: const ClampingScrollPhysics(),
                              itemCount: _sugs.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, color: dividerColor),
                              itemBuilder: (_, i) {
                                final p = _sugs[i];
                                final esReciente = _esPrediccionReciente(p);
                                final esRai =
                                    p.placeId == '__rai_inteligente__';
                                final subtitle = esRai
                                    ? (p.secondary ?? '').trim()
                                    : esReciente
                                        ? null
                                        : (p.secondary ?? '').trim();
                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () =>
                                        _manejarSeleccionSugerencia(p),
                                    child: ListTile(
                                      dense: true,
                                      mouseCursor: SystemMouseCursors.click,
                                      leading: Icon(
                                        esRai
                                            ? Icons.auto_awesome_rounded
                                            : esReciente
                                                ? Icons.history
                                                : Icons.place,
                                        color: esReciente
                                            ? (isDark
                                                ? Colors.amber.shade200
                                                : Colors.amber.shade800)
                                            : placeIconColor,
                                        size: 20,
                                      ),
                                      title:
                                          Text(p.primary, style: titleStyle),
                                      subtitle: subtitle != null &&
                                              subtitle.isNotEmpty
                                          ? Text(subtitle,
                                              style: subtitleStyle)
                                          : null,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
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

  void _manejarSeleccionSugerencia(PrediccionLugar p) {
    _seleccionEnCurso = true;
    _unfocusClearTimer?.cancel();
    if (_esPrediccionReciente(p)) {
      _pegarTextoEnCampo(p.primary);
    }
    if (p.placeId == '__rai_inteligente__') {
      _focus.unfocus();
      _clearSugsAndOverlay();
      _seleccionEnCurso = false;
      unawaited(abrirBusquedaInteligenteRai());
      return;
    }
    // Reciente y Places: mismo flujo (detalle → texto → onPlaceSelected → cotización).
    unawaited(_selectPrediction(p).whenComplete(() {
      _seleccionEnCurso = false;
    }));
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
    _debounce = Timer(const Duration(milliseconds: 110), () async {
      final q = text.trim();
      if (!_focus.hasFocus) {
        // Mantener recientes/sugerencias visibles aunque el teclado quite el foco;
        // el usuario está eligiendo en el overlay.
        if (_entry != null || _sugs.isNotEmpty) {
          // seguir con la búsqueda/redibujo abajo
        } else {
          return;
        }
      }

      if (q.isEmpty) {
        final soloRecientes = _recientesComoPredicciones('');
        if (soloRecientes.isEmpty) {
          _clearSugsAndOverlay();
          return;
        }
        if (!mounted) return;
        setState(() {
          _loading = false;
          _sugs = soloRecientes;
        });
        _ensureOverlayVisible();
        return;
      }

      if (q.length < widget.minChars) {
        final parcial = _recientesComoPredicciones(q);
        if (parcial.isEmpty) {
          _clearSugsAndOverlay();
          return;
        }
        if (!mounted) return;
        setState(() {
          _loading = false;
          _sugs = parcial;
        });
        _ensureOverlayVisible();
        return;
      }

      final int seq = ++_autocompleteSeq;
      if (mounted) setState(() => _loading = true);

      final remotas = await _svc.autocompletar(
        q,
        biasLat: widget.biasLat,
        biasLon: widget.biasLon,
        country: widget.country ?? 'DO',
      );

      if (!mounted) return;
      if (seq != _autocompleteSeq) return;
      if (_controller.text.trim() != q) return;

      final recientes = _recientesComoPredicciones(q);
      final seen = <String>{};
      final merged = <PrediccionLugar>[...recientes, ...remotas]
          .where((p) {
            final k = '${p.placeId}|${_norm(p.primary)}';
            if (seen.contains(k)) return false;
            seen.add(k);
            return true;
          })
          .toList(growable: false);

      setState(() {
        _loading = false;
        _sugs = _svc.rankearPredicciones(merged, q);
      });

      if (_sugs.isEmpty) {
        _removeOverlay();
        if (widget.asistenteDireccionHabilitado &&
            q.length >= 3 &&
            remotas.isEmpty) {
          if (mounted) {
            setState(() {
              _sugs = [
                const PrediccionLugar(
                  placeId: '__rai_inteligente__',
                  primary: 'Buscar con RAI (IA + Google)',
                  secondary: 'Para direcciones difíciles',
                ),
              ];
            });
            _showOverlay();
          }
        }
      } else {
        _ensureOverlayVisible();
      }
    });
  }

  /// Mantiene o abre el panel aunque el teclado quite el foco
  /// (típico al tocar/scroll las opciones).
  void _ensureOverlayVisible() {
    if (!mounted || _sugs.isEmpty) return;
    if (_entry != null) {
      _refreshOverlay();
      return;
    }
    if (_focus.hasFocus || _overlayInteracting || _seleccionEnCurso) {
      _showOverlay();
    }
  }

  Future<void> aplicarDetalleExterno(DetalleLugar det) async {
    await _finalizePlaceSelection(det);
  }

  Future<void> abrirBusquedaInteligenteRai() async {
    final det = await RaiDireccionInteligenteSheet.mostrar(
      context,
      textoInicial: _controller.text.trim(),
      biasLat: widget.biasLat,
      biasLon: widget.biasLon,
    );
    if (det != null && mounted) {
      await _finalizePlaceSelection(det);
    }
  }

  Future<void> _finalizePlaceSelection(DetalleLugar det) async {
    await _voz.stop();
    if (mounted) setState(() => _escuchando = false);
    _debounce?.cancel();
    _unfocusClearTimer?.cancel();
    _autocompleteSeq++;
    _applyingResolvedPlace = true;
    _seleccionEnCurso = true;
    try {
      _controller.text = det.displayLabel;
      // Solo onPlaceSelected: onTextChanged en el padre limpia lat/_destinoDet
      // y cancela la cotización (viajes normales / motor).
      widget.onPlaceSelected(det);
      await _guardarReciente(det);
    } finally {
      _applyingResolvedPlace = false;
      _seleccionEnCurso = false;
      _mostrarRecientes = false;
    }
    _focus.unfocus();
    _clearSugsAndOverlay();
  }

  /// Pega el texto en el buscador al instante (chips/overlay recientes).
  void _pegarTextoEnCampo(String texto) {
    final t = texto.trim();
    if (t.isEmpty) return;
    _applyingResolvedPlace = true;
    try {
      _controller.text = t;
    } finally {
      _applyingResolvedPlace = false;
    }
    if (mounted) setState(() {});
  }

  DetalleLugar? _detalleDesdeRecienteLocal(RecienteLugar entry) {
    if (entry.tieneCoordenadas) {
      final nombre = (entry.name ?? entry.label).trim();
      return DetalleLugar(
        placeId: entry.placeId.isNotEmpty
            ? entry.placeId
            : 'recent:${entry.label}',
        name: nombre.isNotEmpty ? nombre : entry.label,
        address: entry.label,
        lat: entry.lat!,
        lon: entry.lon!,
      );
    }
    return null;
  }

  DetalleLugar? _detalleDesdeRecientePrediccion(PrediccionLugar p) {
    final pid = p.placeId.trim();
    final primary = p.primary.trim();
    for (final e in _recientes) {
      if (pid.isNotEmpty && e.placeId.isNotEmpty && e.placeId == pid) {
        return _detalleDesdeRecienteLocal(e);
      }
      if (pid.startsWith('recent:') &&
          _norm(e.label) == _norm(pid.substring('recent:'.length))) {
        return _detalleDesdeRecienteLocal(e);
      }
      if (_norm(e.label) == _norm(primary)) {
        return _detalleDesdeRecienteLocal(e);
      }
    }
    return null;
  }

  Future<void> _selectPrediction(PrediccionLugar p) async {
    await _voz.stop();
    if (mounted) setState(() => _escuchando = false);
    if (mounted) setState(() => _loading = true);
    _removeOverlay();

    if (_esPrediccionReciente(p)) {
      _pegarTextoEnCampo(p.primary);
      final detMem = _detalleDesdeRecientePrediccion(p);
      if (detMem != null) {
        if (!mounted) return;
        setState(() => _loading = false);
        await _finalizePlaceSelection(detMem);
        return;
      }
    }

    if (p.secondary == 'Sugerencia por voz') {
      for (final d in _candidatosVozResueltos) {
        if (d.placeId == p.placeId ||
            d.displayLabel.trim() == p.primary.trim()) {
          if (!mounted) return;
          setState(() => _loading = false);
          await _finalizePlaceSelection(d);
          return;
        }
      }
    }

    if (_esPrediccionReciente(p)) {
      final detRec = await _svc.detalleDesdeReciente(p);
      if (!mounted) return;
      if (detRec != null) {
        setState(() => _loading = false);
        await _finalizePlaceSelection(detRec);
        return;
      }
    }

    final det = await _svc.detalleDesdePrediccion(p);

    if (!mounted) return;
    setState(() => _loading = false);

    if (det != null) {
      await _finalizePlaceSelection(det);
    } else if (widget.asistenteDireccionHabilitado) {
      await abrirBusquedaInteligenteRai();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo obtener el detalle del lugar.'),
        ),
      );
    }
  }

  Future<void> _seleccionarRecienteChip(RecienteLugar entry) async {
    if (_loading || _seleccionEnCurso) return;
    _seleccionEnCurso = true;
    _overlayInteracting = true;
    _mostrarRecientes = true;
    _unfocusClearTimer?.cancel();
    _pegarTextoEnCampo(entry.label);

    final detLocal = _detalleDesdeRecienteLocal(entry);
    if (detLocal != null) {
      try {
        await _finalizePlaceSelection(detLocal);
      } finally {
        _seleccionEnCurso = false;
        _overlayInteracting = false;
      }
      return;
    }

    final p = PrediccionLugar(
      placeId:
          entry.placeId.isNotEmpty ? entry.placeId : 'recent:${entry.label}',
      primary: entry.label,
      secondary: 'Reciente',
    );
    try {
      await _selectPrediction(p);
    } finally {
      _seleccionEnCurso = false;
      _overlayInteracting = false;
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

    return TapRegion(
        groupId: _tapRegionGroup,
        onTapOutside: (_) {
          if (_seleccionEnCurso || _overlayInteracting) return;
          if (!_focus.hasFocus && _entry == null && !_mostrarRecientes) return;
          _mostrarRecientes = false;
          _focus.unfocus();
          _clearSugsAndOverlay();
        },
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
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.asistenteDireccionHabilitado)
                            IconButton(
                              tooltip: _escuchando
                                  ? 'Detener dictado'
                                  : 'Dictar destino',
                              icon: Icon(
                                _escuchando
                                    ? Icons.mic_rounded
                                    : Icons.mic_none_rounded,
                                color: _escuchando
                                    ? Colors.redAccent
                                    : accent,
                                size: 22,
                              ),
                              onPressed: _toggleVoz,
                            ),
                          if (widget.asistenteDireccionHabilitado)
                            IconButton(
                              tooltip: 'Búsqueda inteligente RAI',
                              icon: Icon(
                                Icons.auto_awesome_rounded,
                                color: accent,
                                size: 22,
                              ),
                              onPressed: abrirBusquedaInteligenteRai,
                            ),
                          if (_controller.text.isNotEmpty)
                            IconButton(
                              icon: Icon(
                                Icons.clear_rounded,
                                color: iconoLimpiar,
                              ),
                              onPressed: () {
                                _controller.clear();
                                _mostrarRecientes = true;
                                widget.onTextChanged?.call('');
                                _clearSugsAndOverlay();
                              },
                            ),
                        ],
                      ),
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
                if (!_focus.hasFocus) return;
                if (_sugs.isNotEmpty) {
                  _showOverlay();
                  return;
                }
                final rec = _recientesComoPredicciones(_controller.text.trim());
                if (rec.isNotEmpty) {
                  setState(() => _sugs = rec);
                  _showOverlay();
                }
              },
            ),
            ),
            const SizedBox(height: 8),
            // Chips dentro del mismo TapRegion: en móvil el tap no pierde
            // el foco antes de registrar la selección (antes eran "outside").
            if (_recientes.isNotEmpty &&
                _controller.text.isEmpty &&
                _entry == null &&
                (_mostrarRecientes ||
                    _seleccionEnCurso ||
                    _overlayInteracting))
              _buildRecientesSection(),
            // Espaciador bajo los chips (no envolver todo el Column): en móvil
            // el padding del teclado movía los chips y el tap fallaba al cerrarse.
            if (kbInset > 0) SizedBox(height: kbInset),
          ],
        ),
      );
  }

  // Lugares recientes (única sección visible junto al autocomplete).
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
                  return Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) {
                      _mostrarRecientes = true;
                      _overlayInteracting = true;
                    },
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          unawaited(_seleccionarRecienteChip(entry));
                        },
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
                                constraints:
                                    const BoxConstraints(maxWidth: 160),
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
