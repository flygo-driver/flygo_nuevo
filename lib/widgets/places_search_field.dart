// lib/widgets/places_search_field.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/places_api.dart';
import 'package:flygo_nuevo/servicios/places_service.dart';
import 'package:uuid/uuid.dart';

class PlacesSearchField extends StatefulWidget {
  const PlacesSearchField({
    super.key,
    required this.hintText,
    required this.onPlacePicked,
    this.initialText,
    this.enabled = true,
    this.biasLat,
    this.biasLon,
    this.biasRadiusMeters,
  });

  final String hintText;
  final String? initialText;
  final bool enabled;
  final void Function(PlaceDetails picked) onPlacePicked;

  // Opcional: sesgo de ubicación para resultados
  final double? biasLat;
  final double? biasLon;
  final int? biasRadiusMeters;

  @override
  State<PlacesSearchField> createState() => _PlacesSearchFieldState();
}

class _PlacesSearchFieldState extends State<PlacesSearchField> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _uuid = const Uuid();

  Timer? _deb;
  String? _sessionToken; // una por “sesión de búsqueda”
  bool _loading = false;
  List<PlacePrediction> _items = const [];

  @override
  void initState() {
    super.initState();
    final init = widget.initialText;
    if (init != null) _ctrl.text = init;
    _ctrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _deb?.cancel();
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _ensureSession() {
    _sessionToken ??= _uuid.v4();
  }

  void _endSession() {
    _sessionToken = null;
  }

  void _onChanged() {
    if (!_focus.hasFocus) return;
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 260), () async {
      final q = _ctrl.text.trim();
      if (q.isEmpty) {
        if (mounted) setState(() => _items = const []);
        return;
      }
      try {
        if (mounted) setState(() => _loading = true);
        _ensureSession();
        final r = await PlacesApi.autocomplete(
          q,
          sessionToken: _sessionToken,
          biasLat: widget.biasLat,
          biasLon: widget.biasLon,
          biasRadiusMeters: widget.biasRadiusMeters ?? 30000,
        );
        if (mounted) setState(() => _items = r);
      } catch (_) {
        if (mounted) setState(() => _items = const []);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  Future<void> _pick(PlacePrediction p) async {
    setState(() {
      _loading = true;
      _items = const [];
    });
    try {
      final det =
          await PlacesApi.details(p.placeId, sessionToken: _sessionToken);
      _endSession(); // cerrar la sesión de Places

      if (det == null) {
        final fallback = _composeFallbackText(p);
        _ctrl.text = fallback;
        _focus.unfocus();
        return;
      }

      final addr = (det.address).trim();
      _ctrl.text = addr.isNotEmpty ? addr : _composeFallbackText(p);
      widget.onPlacePicked(det);
      _focus.unfocus();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _composeFallbackText(PlacePrediction p) {
    final pri = (p.primary).trim();
    final sec = (p.secondary ?? '').trim();
    if (pri.isNotEmpty && sec.isNotEmpty) return '$pri, $sec';
    if (pri.isNotEmpty) return pri;
    if (sec.isNotEmpty) return sec;
    final full = (p.fullDescription).trim();
    return full.isNotEmpty ? full : 'Lugar';
  }

  void _onSubmitted(String _) {
    if (_items.isNotEmpty) {
      _pick(_items.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    const green = Colors.greenAccent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          focusNode: _focus,
          enabled: widget.enabled,
          onSubmitted: _onSubmitted,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: const TextStyle(color: Colors.white54),
            prefixIcon: const Icon(Icons.search, color: Colors.white70),
            filled: true,
            fillColor: const Color(0xFF101010),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: green),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: green, width: 2),
            ),
          ),
          onTap: () {
            if (_sessionToken == null) _ensureSession();
          },
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_items.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F0F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _items.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Colors.white12),
              itemBuilder: (_, i) {
                final p = _items[i];
                final pri = (p.primary).trim();
                final sec = (p.secondary ?? '').trim();
                final title = pri.isNotEmpty
                    ? pri
                    : (sec.isNotEmpty
                        ? sec
                        : ((p.fullDescription).trim().isNotEmpty
                            ? p.fullDescription
                            : 'Lugar'));
                return ListTile(
                  onTap: () => _pick(p),
                  dense: true,
                  leading: const Icon(Icons.place, color: Colors.greenAccent),
                  title:
                      Text(title, style: const TextStyle(color: Colors.white)),
                  subtitle: sec.isEmpty
                      ? null
                      : Text(sec,
                          style: const TextStyle(color: Colors.white60)),
                );
              },
            ),
          ),
      ],
    );
  }
}
