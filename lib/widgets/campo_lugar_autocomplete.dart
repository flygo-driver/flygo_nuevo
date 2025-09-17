// lib/widgets/campo_lugar_autocomplete.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../servicios/lugares_service.dart';

class CampoLugarAutocomplete extends StatefulWidget {
  final String label;
  final String? hint;

  /// Texto inicial opcional (no dispara sugerencias hasta que el usuario edite)
  final String? initialText;

  /// Filtros/sesgos opcionales
  final String? country; // ej: 'DO'
  final double? biasLat;
  final double? biasLon;

  /// Callbacks
  final ValueChanged<DetalleLugar> onPlaceSelected;
  final ValueChanged<String>? onTextChanged;

  /// Config
  final int minChars; // mínimo de letras para sugerir (por defecto: 2)

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
    this.minChars = 2,
  });

  @override
  State<CampoLugarAutocomplete> createState() => _CampoLugarAutocompleteState();
}

class _CampoLugarAutocompleteState extends State<CampoLugarAutocomplete> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _svc = LugaresService.instance;

  List<PrediccionLugar> _sugs = const [];
  Timer? _debounce;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final init = (widget.initialText ?? '').trim();
    if (init.isNotEmpty) _controller.text = init;

    _focus.addListener(() {
      if (!_focus.hasFocus && mounted) {
        // Oculta lista al perder foco
        setState(() => _sugs = const []);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    widget.onTextChanged?.call(text);

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      final q = text.trim();
      // No mostrar nada si no hay suficientes letras o no hay foco
      if (q.length < widget.minChars || !_focus.hasFocus) {
        if (mounted) setState(() => _sugs = const []);
        return;
      }

      if (mounted) setState(() => _loading = true);

      final sugs = await _svc.autocompletar(
        q,
        biasLat: widget.biasLat,
        biasLon: widget.biasLon,
        country: widget.country ?? 'DO',
      );

      if (!mounted) return;
      setState(() {
        _loading = false;
        _sugs = sugs;
      });
    });
  }

  Future<void> _selectPrediction(PrediccionLugar p) async {
    setState(() {
      _sugs = const [];
      _loading = true;
    });

    final det = await _svc.detalle(p.placeId);

    if (!mounted) return;
    setState(() => _loading = false);

    if (det != null) {
      _controller.text = det.displayLabel; // nombre/dir bonita
      widget.onTextChanged?.call(det.displayLabel);
      widget.onPlaceSelected(det);
      _focus.unfocus(); // cerrar teclado
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo obtener el detalle del lugar.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.greenAccent),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: _controller,
          focusNode: _focus,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint ?? 'Escribe para buscar…',
            labelStyle: const TextStyle(color: Colors.white70),
            filled: true,
            fillColor: Colors.grey[900],
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: const BorderSide(color: Colors.greenAccent, width: 2),
            ),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.search, color: Colors.white70),
          ),
          onChanged: _onChanged,
        ),

        // Lista de sugerencias: SOLO aparece si hay foco y resultados
        if (_focus.hasFocus && _sugs.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _sugs.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Colors.white12),
              itemBuilder: (ctx, i) {
                final p = _sugs[i];
                final subtitle = (p.secondary ?? '').trim();
                return ListTile(
                  dense: true,
                  title: Text(
                    p.primary,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: subtitle.isNotEmpty
                      ? Text(
                          subtitle,
                          style: const TextStyle(color: Colors.white54),
                        )
                      : null,
                  onTap: () => _selectPrediction(p),
                );
              },
            ),
          ),
      ],
    );
  }
}
