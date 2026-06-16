import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/lugares_service.dart';
import 'package:flygo_nuevo/servicios/rai_speech_busqueda_direccion.dart';
import 'package:flygo_nuevo/utils/rai_aplicar_destino_desde_voz.dart';

/// Sheet enfocado en resolver direcciones complejas → coordenadas para cotizar.
class RaiDireccionInteligenteSheet extends StatefulWidget {
  const RaiDireccionInteligenteSheet({
    super.key,
    this.textoInicial,
    this.biasLat,
    this.biasLon,
  });

  final String? textoInicial;
  final double? biasLat;
  final double? biasLon;

  static Future<DetalleLugar?> mostrar(
    BuildContext context, {
    String? textoInicial,
    double? biasLat,
    double? biasLon,
  }) {
    return showModalBottomSheet<DetalleLugar>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RaiDireccionInteligenteSheet(
        textoInicial: textoInicial,
        biasLat: biasLat,
        biasLon: biasLon,
      ),
    );
  }

  @override
  State<RaiDireccionInteligenteSheet> createState() =>
      _RaiDireccionInteligenteSheetState();
}

class _RaiDireccionInteligenteSheetState
    extends State<RaiDireccionInteligenteSheet> {
  final _input = TextEditingController();
  final _voz = RaiSpeechBusquedaDireccion();
  bool _buscando = false;
  bool _escuchando = false;
  bool _vozOk = false;
  List<DetalleLugar> _resultados = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    final init = (widget.textoInicial ?? '').trim();
    if (init.isNotEmpty) _input.text = init;
    unawaited(_initVoz());
    if (init.length >= 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _buscar());
    }
  }

  Future<void> _initVoz() async {
    try {
      final ok = await _voz.initialize();
      if (mounted) setState(() => _vozOk = ok);
    } catch (_) {}
  }

  @override
  void dispose() {
    _input.dispose();
    if (_voz.isListening) unawaited(_voz.stop());
    super.dispose();
  }

  Future<void> _toggleVoz() async {
    if (!_vozOk || _buscando) return;
    if (_escuchando) {
      await _voz.stop();
      if (mounted) setState(() => _escuchando = false);
      return;
    }
    await _voz.toggleListen(
      onListeningChanged: (active) {
        if (mounted) setState(() => _escuchando = active);
      },
      onResult: (words, isFinal) {
        if (!mounted) return;
        _input.text = words;
        if (isFinal) {
          final texto = words.trim();
          if (texto.length >= 2) {
            unawaited(_resolverYAplicarTrasVoz(texto));
          }
        }
      },
    );
  }

  Future<void> _buscar() async {
    final q = _input.text.trim();
    if (q.length < 2 || _buscando) return;
    await _resolverYAplicarTrasVoz(q);
  }

  Future<void> _resolverYAplicarTrasVoz(String texto) async {
    if (texto.length < 2 || _buscando) return;

    await _voz.stop();
    if (mounted) setState(() => _escuchando = false);

    setState(() {
      _buscando = true;
      _error = null;
      _resultados = const [];
    });

    final res = await RaiAplicarDestinoDesdeVoz.resolver(
      textoReconocido: texto,
      biasLat: widget.biasLat,
      biasLon: widget.biasLon,
      desdeVoz: true,
    );

    if (!mounted) return;

    final confiable = res.lugarConfiable;
    if (confiable != null) {
      Navigator.pop(context, confiable);
      return;
    }

    setState(() {
      _buscando = false;
      _escuchando = false;
      _resultados = res.candidatos;
      if (!res.encontroAlgo) {
        _error =
            'No encontramos coordenadas exactas. Prueba con sector, ciudad '
            'o referencia (ej. «Los Minas, Santo Domingo»).';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) {
        return Material(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
                  children: [
                    Row(
                      children: [
                        Icon(Icons.travel_explore_rounded, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Búsqueda inteligente RAI',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    Text(
                      'Describe el lugar como lo dirías en voz alta. '
                      'RAI normaliza la dirección y Google Places devuelve '
                      'coordenadas para cotizar el viaje.',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (_vozOk)
                          Padding(
                            padding: const EdgeInsets.only(right: 4, bottom: 4),
                            child: IconButton.filledTonal(
                              onPressed: _buscando ? null : _toggleVoz,
                              icon: Icon(
                                _escuchando
                                    ? Icons.mic_rounded
                                    : Icons.mic_none_rounded,
                                color: _escuchando ? cs.error : null,
                              ),
                            ),
                          ),
                        Expanded(
                          child: TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _buscar(),
                            decoration: InputDecoration(
                              hintText:
                                  'Ej. colmado esquina Los Minas, malecón SD…',
                              prefixIcon:
                                  Icon(Icons.search_rounded, color: cs.primary),
                              filled: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: IconButton.filled(
                            onPressed: _buscando ? null : _buscar,
                            icon: const Icon(Icons.search_rounded),
                          ),
                        ),
                      ],
                    ),
                    if (_buscando)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                'Buscando con IA y Google Places…',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_error != null && !_buscando)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _error!,
                          style: TextStyle(color: cs.error, fontSize: 13),
                        ),
                      ),
                    if (_resultados.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Elige el destino exacto (se guarda en el campo destino):',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ..._resultados.map(
                        (d) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: cs.outlineVariant),
                            ),
                            leading: Icon(Icons.place_rounded, color: cs.primary),
                            title: Text(
                              d.displayLabel,
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              'Lat ${d.lat.toStringAsFixed(5)}, '
                              'Lon ${d.lon.toStringAsFixed(5)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            trailing: FilledButton(
                              onPressed: () => Navigator.pop(context, d),
                              child: const Text('Usar'),
                            ),
                            onTap: () => Navigator.pop(context, d),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
