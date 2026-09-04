import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/lugares_service.dart';
import 'package:flygo_nuevo/servicios/rai_speech_busqueda_direccion.dart';
import 'package:flygo_nuevo/utils/rai_aplicar_destino_desde_voz.dart';
import 'package:flygo_nuevo/widgets/buscar_lugar_mapa_page.dart';

/// Sheet RAI: búsqueda exacta Google Maps + IA, todo dentro del panel.
class RaiDireccionInteligenteSheet extends StatefulWidget {
  const RaiDireccionInteligenteSheet({
    super.key,
    this.textoInicial,
    this.biasLat,
    this.biasLon,
    this.tituloMapa = 'Elegir en mapa',
    this.mostrarBotonMapa = true,
  });

  final String? textoInicial;
  final double? biasLat;
  final double? biasLon;
  final String tituloMapa;
  /// false si ya estás en la pantalla mapa (evita mapa sobre mapa).
  final bool mostrarBotonMapa;

  static Future<DetalleLugar?> mostrar(
    BuildContext context, {
    String? textoInicial,
    double? biasLat,
    double? biasLon,
    String tituloMapa = 'Elegir en mapa',
    bool mostrarBotonMapa = true,
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
        tituloMapa: tituloMapa,
        mostrarBotonMapa: mostrarBotonMapa,
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
  final _svc = LugaresService.instance;

  bool _buscandoIa = false;
  bool _buscandoGoogle = false;
  bool _escuchando = false;
  List<DetalleLugar> _resultadosIa = const [];
  List<PrediccionLugar> _sugerenciasGoogle = const [];
  String? _error;
  Timer? _debounceGoogle;
  int _seqGoogle = 0;

  bool get _buscando => _buscandoIa || _buscandoGoogle;

  @override
  void initState() {
    super.initState();
    final init = (widget.textoInicial ?? '').trim();
    if (init.isNotEmpty) {
      _input.text = init;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_buscarGoogleEnVivo(init));
      });
    }
    _input.addListener(_onTextoCambiado);
  }

  @override
  void dispose() {
    _debounceGoogle?.cancel();
    _input.removeListener(_onTextoCambiado);
    _input.dispose();
    if (_voz.isListening) unawaited(_voz.stop());
    super.dispose();
  }

  void _onTextoCambiado() {
    _debounceGoogle?.cancel();
    _debounceGoogle = Timer(const Duration(milliseconds: 150), () {
      unawaited(_buscarGoogleEnVivo(_input.text.trim()));
    });
    if (mounted) setState(() {});
  }

  Future<void> _buscarGoogleEnVivo(String q) async {
    if (q.length < 2) {
      if (!mounted) return;
      setState(() {
        _sugerenciasGoogle = const [];
        _buscandoGoogle = false;
      });
      return;
    }

    final int seq = ++_seqGoogle;
    if (mounted) setState(() => _buscandoGoogle = true);

    try {
      final sugs = await _svc.autocompletar(
        q,
        country: 'DO',
        biasLat: widget.biasLat,
        biasLon: widget.biasLon,
        modoMapa: true,
        onParcial: (parcial) {
          if (!mounted || seq != _seqGoogle) return;
          if (_input.text.trim() != q) return;
          setState(() {
            _sugerenciasGoogle = parcial;
            _buscandoGoogle = false;
          });
        },
      );

      if (!mounted || seq != _seqGoogle) return;
      if (_input.text.trim() != q) return;
      setState(() {
        _sugerenciasGoogle = sugs;
        _buscandoGoogle = false;
      });
    } catch (_) {
      if (!mounted || seq != _seqGoogle) return;
      setState(() => _buscandoGoogle = false);
    }
  }

  Future<void> _toggleVoz() async {
    if (_buscando) return;
    if (_escuchando) {
      await _voz.stop();
      if (mounted) setState(() => _escuchando = false);
      return;
    }
    final ok = await _voz.toggleListen(
      onListeningChanged: (active) {
        if (mounted) setState(() => _escuchando = active);
      },
      onResult: (words, isFinal) {
        if (!mounted) return;
        _input.text = words;
        if (isFinal) {
          final texto = words.trim();
          if (texto.length >= 2) {
            unawaited(_resolverConIa(texto));
          }
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

  Future<void> _buscarConIa() async {
    final q = _input.text.trim();
    if (q.length < 2 || _buscandoIa) return;
    await _resolverConIa(q);
  }

  Future<void> _resolverConIa(String texto) async {
    if (texto.length < 2 || _buscandoIa) return;

    await _voz.stop();
    if (mounted) setState(() => _escuchando = false);

    setState(() {
      _buscandoIa = true;
      _error = null;
      _resultadosIa = const [];
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
      _buscandoIa = false;
      _escuchando = false;
      _resultadosIa = res.candidatos;
      if (!res.encontroAlgo && _sugerenciasGoogle.isEmpty) {
        _error =
            'No encontramos coordenadas exactas. Prueba con sector, ciudad '
            'o referencia (ej. «Los Minas, Santo Domingo»).';
      } else {
        _error = null;
      }
    });
  }

  Future<void> _elegirSugerenciaGoogle(PrediccionLugar p) async {
    if (_buscando) return;
    setState(() => _buscandoIa = true);
    final det = await _svc.detalleDesdePrediccion(p);
    if (!mounted) return;
    setState(() => _buscandoIa = false);
    if (det != null) {
      await _svc.guardarReciente(det);
      if (!mounted) return;
      Navigator.pop(context, det);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo cargar ese lugar.')),
    );
  }

  Future<void> _abrirMapaGoogle() async {
    if (_buscando) return;
    final det = await BuscarLugarMapaPage.mostrar(
      context,
      titulo: widget.tituloMapa,
      textoInicial: _input.text.trim(),
      biasLat: widget.biasLat,
      biasLon: widget.biasLon,
      enSheet: true,
    );
    if (!mounted || det == null) return;
    Navigator.pop(context, det);
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
                        Icon(Icons.smart_toy_rounded, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Búsqueda exacta RAI',
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
                      'Escribe o dicta — RAI muestra sugerencias de Google Maps '
                      'al instante. También podés tocar cualquier punto en el mapa.',
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
                            onSubmitted: (_) => _buscarConIa(),
                            decoration: InputDecoration(
                              hintText:
                                  'Ej. calle Barney Morgan, Los Minas, tu barrio…',
                              prefixIcon: Icon(
                                Icons.smart_toy_rounded,
                                color: cs.primary,
                              ),
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
                            onPressed: _buscandoIa ? null : _buscarConIa,
                            tooltip: 'Normalizar con IA',
                            icon: const Icon(Icons.auto_awesome_rounded),
                          ),
                        ),
                      ],
                    ),
                    if (!kIsWeb && widget.mostrarBotonMapa) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _buscando ? null : _abrirMapaGoogle,
                        icon: const Icon(Icons.map_rounded, size: 20),
                        label: const Text('Buscar en mapa Google'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                      ),
                    ],
                    if (_buscandoIa)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
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
                                'RAI normalizando con IA…',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_sugerenciasGoogle.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(Icons.place_rounded,
                              size: 18, color: cs.primary),
                          const SizedBox(width: 6),
                          Text(
                            'Google Maps',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                              fontSize: 13,
                            ),
                          ),
                          if (_buscandoGoogle) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      ..._sugerenciasGoogle.take(12).map(
                            (p) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                p.placeId.startsWith('local:poi:')
                                    ? Icons.star_rounded
                                    : Icons.location_on_outlined,
                                color: cs.primary,
                                size: 22,
                              ),
                              title: Text(
                                p.primary,
                                style: const TextStyle(fontSize: 14),
                              ),
                              subtitle: (p.secondary ?? '').trim().isNotEmpty
                                  ? Text(
                                      p.secondary!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    )
                                  : null,
                              onTap: () => unawaited(_elegirSugerenciaGoogle(p)),
                            ),
                          ),
                    ],
                    if (_error != null && !_buscandoIa)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _error!,
                          style: TextStyle(color: cs.error, fontSize: 13),
                        ),
                      ),
                    if (_resultadosIa.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded,
                              size: 18, color: cs.tertiary),
                          const SizedBox(width: 6),
                          Text(
                            'Sugerencias RAI (IA)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ..._resultadosIa.map(
                        (d) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: cs.outlineVariant),
                            ),
                            leading:
                                Icon(Icons.place_rounded, color: cs.primary),
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
