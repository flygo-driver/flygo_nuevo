import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:flygo_nuevo/servicios/gps_service.dart';
import 'package:flygo_nuevo/servicios/lugares_populares_service.dart';
import 'package:flygo_nuevo/servicios/lugares_service.dart';
import 'package:flygo_nuevo/utils/rai_map_presentation.dart';
import 'package:flygo_nuevo/utils/rai_region_operativa.dart';
import 'package:flygo_nuevo/widgets/rai_direccion_inteligente_sheet.dart';

/// Buscador estilo Google Maps: texto + cámara sincronizados con Google Places.
class BuscarLugarMapaPage extends StatefulWidget {
  const BuscarLugarMapaPage({
    super.key,
    required this.titulo,
    this.hint,
    this.textoInicial,
    this.country = 'DO',
    this.biasLat,
    this.biasLon,
    this.accentColor,
    this.esCampoOrigen = false,
  });

  final String titulo;
  final String? hint;
  final String? textoInicial;
  final String country;
  final double? biasLat;
  final double? biasLon;
  final Color? accentColor;
  /// Para aprendizaje FlyGo (origen vs destino en lugares frecuentes).
  final bool esCampoOrigen;

  static Future<DetalleLugar?> mostrar(
    BuildContext context, {
    required String titulo,
    String? hint,
    String? textoInicial,
    String country = 'DO',
    double? biasLat,
    double? biasLon,
    Color? accentColor,
    bool esCampoOrigen = false,
    bool enSheet = true,
  }) {
    if (enSheet) {
      return mostrarEnSheet(
        context,
        titulo: titulo,
        hint: hint,
        textoInicial: textoInicial,
        country: country,
        biasLat: biasLat,
        biasLon: biasLon,
        accentColor: accentColor,
        esCampoOrigen: esCampoOrigen,
      );
    }
    return Navigator.of(context).push<DetalleLugar>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BuscarLugarMapaPage(
          titulo: titulo,
          hint: hint,
          textoInicial: textoInicial,
          country: country,
          biasLat: biasLat,
          biasLon: biasLon,
          accentColor: accentColor,
          esCampoOrigen: esCampoOrigen,
        ),
      ),
    );
  }

  /// Mismo buscador + mapa, pero dentro de un panel inferior (no pantalla aparte).
  static Future<DetalleLugar?> mostrarEnSheet(
    BuildContext context, {
    required String titulo,
    String? hint,
    String? textoInicial,
    String country = 'DO',
    double? biasLat,
    double? biasLon,
    Color? accentColor,
    bool esCampoOrigen = false,
  }) {
    return showModalBottomSheet<DetalleLugar>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        final double altura =
            MediaQuery.sizeOf(ctx).height * 0.92 - MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: SizedBox(
              height: altura.clamp(420.0, MediaQuery.sizeOf(ctx).height * 0.96),
              child: BuscarLugarMapaPage(
                titulo: titulo,
                hint: hint,
                textoInicial: textoInicial,
                country: country,
                biasLat: biasLat,
                biasLon: biasLon,
                accentColor: accentColor,
                esCampoOrigen: esCampoOrigen,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  State<BuscarLugarMapaPage> createState() => _BuscarLugarMapaPageState();
}

class _BuscarLugarMapaPageState extends State<BuscarLugarMapaPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _svc = LugaresService.instance;

  GoogleMapController? _map;
  LatLng? _centro;
  LatLng? _centroMapa;
  DetalleLugar? _preview;
  Set<Marker> _markers = {};

  List<PrediccionLugar> _sugs = const [];
  int _sugDestacada = 0;
  bool _loading = false;
  bool _resolviendoMapa = false;
  bool _busquedaActiva = false;
  Timer? _debounce;
  Timer? _debounceMapa;
  int _seq = 0;
  int _seqMapa = 0;

  // Paleta fija estilo Google Maps (siempre legible sobre el mapa).
  static const Color _textoPrincipal = Color(0xFF202124);
  static const Color _textoSecundario = Color(0xFF5F6368);
  static const Color _fondoTarjeta = Color(0xFFFFFFFF);
  static const Color _fondoCampo = Color(0xFFF1F3F4);
  static const Color _bordeSuave = Color(0xFFDADCE0);
  static const Color _mapsAzul = Color(0xFF1A73E8);
  static const Color _pinMaps = Color(0xFFEA4335);

  Color get _accent => widget.accentColor ?? _mapsAzul;

  /// Acento legible sobre fondo blanco (evita amarillo/claro invisible).
  Color get _accentLegible {
    final lum = _accent.computeLuminance();
    return lum > 0.55 ? _mapsAzul : _accent;
  }

  String get _textoConfirmar {
    final t = widget.titulo.toLowerCase();
    if (t.contains('origen') ||
        t.contains('salida') ||
        t.contains('partida')) {
      return 'Confirmar origen';
    }
    return 'Confirmar destino';
  }

  double? get _biasLat =>
      _centroMapa?.latitude ?? widget.biasLat ?? _centro?.latitude;

  double? get _biasLon =>
      _centroMapa?.longitude ?? widget.biasLon ?? _centro?.longitude;

  bool get _hayTextoBusqueda => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final init = (widget.textoInicial ?? '').trim();
    if (init.isNotEmpty) {
      _controller.text = init;
      _busquedaActiva = true;
    }

    _cargarCentro();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (init.isNotEmpty) {
        _focus.requestFocus();
        _buscar(init);
      } else if (mounted) {
        _focus.unfocus();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _debounceMapa?.cancel();
    _controller.dispose();
    _focus.dispose();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _cargarCentro() async {
    LatLng centro;
    if (widget.biasLat != null && widget.biasLon != null) {
      centro = LatLng(widget.biasLat!, widget.biasLon!);
    } else {
      final pos = await GpsService.obtenerUbicacionActual(
        timeout: const Duration(seconds: 6),
        maxEdadUltima: const Duration(minutes: 5),
      );
      centro = pos != null
          ? LatLng(pos.latitude, pos.longitude)
          : RaiRegionOperativa.centroNacional;
    }
    if (!mounted) return;
    setState(() {
      _centro = centro;
      _centroMapa = centro;
    });
    _programarResolverMapa(centro);
  }

  void _programarResolverMapa(LatLng punto) {
    if (_busquedaActiva) return;
    _debounceMapa?.cancel();
    _debounceMapa = Timer(const Duration(milliseconds: 450), () {
      unawaited(_resolverPuntoMapa(punto));
    });
  }

  Future<void> _resolverPuntoMapa(LatLng punto) async {
    if (_busquedaActiva) return;
    final int seq = ++_seqMapa;
    if (mounted) setState(() => _resolviendoMapa = true);

    final det = await _svc.detalleDesdeCoordenadas(
      punto.latitude,
      punto.longitude,
    );

    if (!mounted || seq != _seqMapa || _busquedaActiva) return;
    setState(() {
      _resolviendoMapa = false;
      if (det != null) {
        final exacto = DetalleLugar(
          placeId: det.placeId,
          name: det.name,
          address: det.address,
          lat: punto.latitude,
          lon: punto.longitude,
        );
        _preview = exacto;
        _controller.text = exacto.displayLabel;
        _busquedaActiva = false;
        _sugs = const [];
        _markers = _buildMarkers(sugs: const [], preview: exacto);
      }
    });
  }

  Future<void> _persistirLugar(DetalleLugar det) async {
    await _svc.guardarReciente(det);
    unawaited(
      LugaresPopularesService.instance.registrarSeleccion(
        det: det,
        esOrigen: widget.esCampoOrigen,
      ),
    );
  }

  Set<Marker> _buildMarkers({
    required List<PrediccionLugar> sugs,
    DetalleLugar? preview,
    int destacada = 0,
  }) {
    final out = <Marker>{};
    if (preview != null && !_busquedaActiva) {
      out.add(
        Marker(
          markerId: const MarkerId('destino_preview'),
          position: LatLng(preview.lat, preview.lon),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(
            title: preview.name,
            snippet: preview.address ?? preview.displayLabel,
          ),
        ),
      );
    }

    var i = 0;
    for (final p in sugs) {
      final lat = p.lat;
      final lon = p.lon;
      if (lat == null || lon == null) {
        i++;
        continue;
      }
      if (preview != null &&
          !_busquedaActiva &&
          (lat - preview.lat).abs() < 1e-5 &&
          (lon - preview.lon).abs() < 1e-5) {
        i++;
        continue;
      }

      final bool esDestacada = i == destacada;
      final sec = (p.secondary ?? '').trim();
      final idx = i;

      out.add(
        Marker(
          markerId: MarkerId('sug_$idx'),
          position: LatLng(lat, lon),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            esDestacada
                ? BitmapDescriptor.hueOrange
                : p.placeId.startsWith('local:poi:')
                    ? BitmapDescriptor.hueViolet
                    : BitmapDescriptor.hueAzure,
          ),
          alpha: esDestacada ? 1.0 : 0.88,
          zIndexInt: esDestacada ? 2 : 1,
          infoWindow: InfoWindow(
            title: p.primary,
            snippet: sec.isNotEmpty ? sec : 'República Dominicana',
          ),
          onTap: () => unawaited(_elegir(p, indice: idx)),
        ),
      );
      i++;
      if (i >= 10) break;
    }
    return out;
  }

  List<LatLng> _puntosDeSugerencias(List<PrediccionLugar> sugs) {
    final pts = <LatLng>[];
    for (final p in sugs) {
      final lat = p.lat;
      final lon = p.lon;
      if (lat == null || lon == null) continue;
      pts.add(LatLng(lat, lon));
    }
    return pts;
  }

  /// La cámara sigue las sugerencias mientras escribes (como Google Maps).
  Future<void> _sincronizarCamaraConSugerencias(
    List<PrediccionLugar> sugs, {
    int destacada = 0,
  }) async {
    final c = _map;
    if (c == null || sugs.isEmpty) return;

    final pts = _puntosDeSugerencias(sugs);
    if (pts.isEmpty) return;

    if (pts.length == 1) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 16));
      return;
    }

    final idx = destacada.clamp(0, sugs.length - 1);
    final top = sugs[idx];
    if (top.lat != null && top.lon != null) {
      await c.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(top.lat!, top.lon!), 14.5),
      );
    }

    if (pts.length >= 2) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await RaiMapPresentation.fitBounds(
        c,
        RaiMapPresentation.boundsFromPoints(pts),
        padding: 220,
        maxZoom: 15.5,
      );
    }
  }

  Future<void> _procesarResultadosBusqueda(
    List<PrediccionLugar> parcial, {
    required int seq,
    required String query,
  }) async {
    if (!mounted || seq != _seq) return;
    if (_controller.text.trim() != query) return;

    setState(() {
      _loading = false;
      _sugs = parcial;
      _sugDestacada = 0;
      _markers = _buildMarkers(sugs: parcial, destacada: 0);
    });
    unawaited(_sincronizarCamaraConSugerencias(parcial));

    final enriquecidas = await _enriquecerCoordsParalelo(parcial);
    if (!mounted || seq != _seq) return;
    if (_controller.text.trim() != query) return;

    setState(() {
      _sugs = enriquecidas;
      _markers = _buildMarkers(sugs: enriquecidas, destacada: _sugDestacada);
    });
    await _sincronizarCamaraConSugerencias(
      enriquecidas,
      destacada: _sugDestacada,
    );
  }

  Future<List<PrediccionLugar>> _enriquecerCoordsParalelo(
    List<PrediccionLugar> lista,
  ) async {
    final top = lista.take(10).toList();
    final enriquecidas = await Future.wait(top.map(_enriquecerUna));
    if (lista.length <= top.length) return enriquecidas;
    return [...enriquecidas, ...lista.skip(top.length)];
  }

  Future<PrediccionLugar> _enriquecerUna(PrediccionLugar p) async {
    if (p.lat != null && p.lon != null) return p;
    if (p.placeId.startsWith('local:poi:')) {
      final det = await _svc.detalleDesdePrediccion(p);
      if (det != null) {
        return PrediccionLugar(
          placeId: p.placeId,
          primary: p.primary,
          secondary: p.secondary,
          distanceMeters: p.distanceMeters,
          lat: det.lat,
          lon: det.lon,
        );
      }
    }
    if (_svc.esPlaceIdGooglePublico(p.placeId)) {
      final det = await _svc.detalleDesdePrediccion(p);
      if (det != null) {
        return PrediccionLugar(
          placeId: p.placeId,
          primary: p.primary,
          secondary: p.secondary,
          distanceMeters: p.distanceMeters,
          lat: det.lat,
          lon: det.lon,
        );
      }
    }
    return p;
  }

  void _buscar(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () async {
      final q = text.trim();
      final busquedaActiva = q.isNotEmpty;
      if (mounted && busquedaActiva != _busquedaActiva) {
        setState(() => _busquedaActiva = busquedaActiva);
      }

      if (q.isEmpty) {
        if (mounted) {
          setState(() {
            _sugs = const [];
            _loading = false;
            _busquedaActiva = false;
            _sugDestacada = 0;
            _markers = _buildMarkers(sugs: const [], preview: _preview);
          });
          final centro = _centroMapa ?? _centro;
          if (centro != null) _programarResolverMapa(centro);
        }
        return;
      }

      final int seq = ++_seq;
      if (mounted) {
        setState(() {
          _loading = true;
          _preview = null;
        });
      }

      try {
        final remotas = await _svc.autocompletar(
          q,
          country: widget.country,
          biasLat: _biasLat,
          biasLon: _biasLon,
          modoMapa: true,
          onParcial: (parcial) {
            unawaited(
              _procesarResultadosBusqueda(parcial, seq: seq, query: q),
            );
          },
        );

        if (!mounted || seq != _seq) return;
        if (_controller.text.trim() != q) return;
        await _procesarResultadosBusqueda(remotas, seq: seq, query: q);
      } catch (_) {
        if (!mounted || seq != _seq) return;
        setState(() => _loading = false);
      }
    });
  }

  Future<void> _destacarSugerencia(int i, {bool moverCamara = true}) async {
    if (i < 0 || i >= _sugs.length) return;
    setState(() {
      _sugDestacada = i;
      _markers = _buildMarkers(sugs: _sugs, destacada: i);
    });
    if (!moverCamara) return;
    final p = _sugs[i];
    if (p.lat == null || p.lon == null) return;
    final c = _map;
    if (c == null) return;
    await c.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(p.lat!, p.lon!), 16),
    );
  }

  Future<void> _elegir(PrediccionLugar p, {int? indice}) async {
    if (indice != null) await _destacarSugerencia(indice, moverCamara: true);

    _focus.unfocus();
    if (mounted) {
      setState(() {
        _loading = true;
        _busquedaActiva = false;
        _sugs = const [];
      });
    }

    final det = await _svc.detalleDesdePrediccion(p);
    if (!mounted) return;
    setState(() => _loading = false);

    if (det == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cargar ese lugar.')),
      );
      return;
    }

    await _aplicarDetalleEnMapa(det);
  }

  Future<void> _aplicarDetalleEnMapa(DetalleLugar det) async {
    await _persistirLugar(det);
    final pos = LatLng(det.lat, det.lon);
    if (!mounted) return;
    setState(() {
      _preview = det;
      _centroMapa = pos;
      _controller.text = det.displayLabel;
      _busquedaActiva = false;
      _sugs = const [];
      _loading = false;
      _markers = _buildMarkers(sugs: const [], preview: det);
    });
    final c = _map;
    if (c != null) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(pos, 16.5));
    }
  }

  Future<void> _abrirRaiDesdeMapa() async {
    _focus.unfocus();
    final det = await RaiDireccionInteligenteSheet.mostrar(
      context,
      textoInicial: _controller.text.trim(),
      biasLat: _biasLat,
      biasLon: _biasLon,
      tituloMapa: widget.titulo,
      mostrarBotonMapa: false,
    );
    if (!mounted || det == null) return;
    await _aplicarDetalleEnMapa(det);
  }

  Future<void> _onTapMapa(LatLng pos) async {
    if (_busquedaActiva) return;
    _focus.unfocus();
    setState(() {
      _sugs = const [];
      _busquedaActiva = false;
      _preview = null;
      _centroMapa = pos;
    });
    final c = _map;
    if (c != null) {
      await c.animateCamera(CameraUpdate.newLatLng(pos));
    }
    await _resolverPuntoMapa(pos);
  }

  Future<void> _confirmar() async {
    final det = _preview;
    if (det == null || _resolviendoMapa) return;
    await _persistirLugar(det);
    if (!mounted) return;
    Navigator.of(context).pop(det);
  }

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.of(context).viewInsets.bottom;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final h = MediaQuery.sizeOf(context).height;
    final listaVisible = _hayTextoBusqueda && _preview == null;
    final queryActual = _controller.text.trim();

    return Theme(
      data: ThemeData.light(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFFE8EAED),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: _textoPrincipal,
              displayColor: _textoPrincipal,
            ),
        iconTheme: const IconThemeData(color: _textoPrincipal),
        dividerColor: _bordeSuave,
      ),
      child: Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFE8EAED),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_centro != null)
            GoogleMap(
              onMapCreated: (c) => _map = c,
              initialCameraPosition: CameraPosition(target: _centro!, zoom: 14),
              markers: _markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              onTap: _onTapMapa,
              onCameraMove: (pos) => _centroMapa = pos.target,
              onCameraIdle: () {
                if (_busquedaActiva) return;
                final c = _centroMapa;
                if (c != null) _programarResolverMapa(c);
              },
            )
          else
            const Center(child: CircularProgressIndicator()),

          if (!listaVisible)
            IgnorePointer(
              child: Align(
                alignment: Alignment.center,
                child: Padding(
                  padding: EdgeInsets.only(bottom: h * 0.12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: 56,
                        color: _pinMaps,
                        shadows: const [
                          Shadow(
                            color: Colors.black38,
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 14,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: _fondoTarjeta,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back,
                                color: _textoPrincipal,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                focusNode: _focus,
                                autofocus: false,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: _textoPrincipal,
                                  fontWeight: FontWeight.w500,
                                ),
                                cursorColor: _accentLegible,
                                decoration: InputDecoration(
                                  hintText: widget.hint ??
                                      'Dirección, barrio o lugar en RD…',
                                  hintStyle: const TextStyle(
                                    color: _textoSecundario,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  filled: true,
                                  fillColor: _fondoCampo,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(28),
                                    borderSide: const BorderSide(
                                      color: _bordeSuave,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(28),
                                    borderSide: const BorderSide(
                                      color: _bordeSuave,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(28),
                                    borderSide: BorderSide(
                                      color: _accentLegible,
                                      width: 2,
                                    ),
                                  ),
                                  prefixIcon: Icon(
                                    Icons.search_rounded,
                                    color: _accentLegible,
                                  ),
                                  suffixIcon: _loading
                                      ? Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: _accentLegible,
                                            ),
                                          ),
                                        )
                                      : (_controller.text.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(
                                                Icons.clear,
                                                color: _textoSecundario,
                                              ),
                                              onPressed: () {
                                                _controller.clear();
                                                setState(() {
                                                  _sugs = const [];
                                                  _busquedaActiva = false;
                                                  _sugDestacada = 0;
                                                  _markers = _buildMarkers(
                                                    sugs: const [],
                                                    preview: _preview,
                                                  );
                                                });
                                                final centro =
                                                    _centroMapa ?? _centro;
                                                if (centro != null) {
                                                  _programarResolverMapa(
                                                      centro);
                                                }
                                              },
                                            )
                                          : null),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                                onChanged: _buscar,
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 12, top: 6),
                          child: Text(
                            listaVisible
                                ? (_sugs.isNotEmpty
                                    ? 'Toca un resultado · el mapa muestra cada lugar'
                                    : _loading
                                        ? 'Buscando lugares…'
                                        : 'Sin resultados — prueba otro nombre')
                                : 'Mueve el mapa o busca — estilo Google Maps',
                            style: const TextStyle(
                              color: _textoSecundario,
                              fontSize: 12.5,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (listaVisible)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: _fondoTarjeta,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    height: (h * 0.42).clamp(220.0, 400.0),
                    child: _loading && _sugs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: _accentLegible,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Buscando lugares…',
                                  style: TextStyle(
                                    color: _textoSecundario,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _sugs.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Sin resultados para "$queryActual".',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: _textoSecundario,
                                          fontSize: 14,
                                          height: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Probá otro nombre, mové el mapa o tocá el punto exacto.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: _textoSecundario,
                                          fontSize: 13,
                                          height: 1.35,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      TextButton.icon(
                                        onPressed: _abrirRaiDesdeMapa,
                                        icon: Icon(
                                          Icons.smart_toy_rounded,
                                          size: 20,
                                          color: _accentLegible,
                                        ),
                                        label: Text(
                                          '¿No lo encuentras? Buscar con RAI',
                                          style: TextStyle(
                                            color: _accentLegible,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: EdgeInsets.only(bottom: kb > 0 ? 8 : 0),
                                itemCount: _sugs.length,
                                separatorBuilder: (_, __) => const Divider(
                                  height: 1,
                                  color: _bordeSuave,
                                ),
                                itemBuilder: (_, i) => _tileSugerencia(i),
                              ),
                  ),
                ),
            ],
          ),

          if (_preview != null && !listaVisible)
            Positioned(
              left: 12,
              right: 12,
              bottom: (kb > 0 ? kb : bottomSafe) + 8,
              child: Material(
                elevation: 8,
                color: _fondoTarjeta,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_resolviendoMapa)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: LinearProgressIndicator(
                            color: _accentLegible,
                            backgroundColor:
                                _accentLegible.withValues(alpha: 0.15),
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.place_rounded,
                            color: _pinMaps,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _preview!.displayLabel,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: _textoPrincipal,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Se guarda en lugares recientes al confirmar',
                        style: TextStyle(
                          color: _textoSecundario,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _resolviendoMapa ? null : _confirmar,
                        style: FilledButton.styleFrom(
                          backgroundColor: _accentLegible,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              _accentLegible.withValues(alpha: 0.45),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _textoConfirmar,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }

  Widget _tileSugerencia(int i) {
    final p = _sugs[i];
    final esLocal = p.placeId.startsWith('local:poi:');
    final esFlygo = p.placeId.startsWith('flygo_popular:') ||
        (p.secondary ?? '').toLowerCase().contains('frecuente en flygo');
    final sec = (p.secondary ?? '').trim();
    final destacada = i == _sugDestacada;

    String subtitulo;
    if (esLocal) {
      subtitulo = sec.isNotEmpty ? 'Catálogo RAI · $sec' : 'Catálogo RAI';
    } else if (esFlygo) {
      subtitulo = sec.isNotEmpty ? sec : 'Frecuente en FlyGo';
    } else {
      subtitulo = sec;
    }

    return Material(
      color: destacada
          ? _mapsAzul.withValues(alpha: 0.08)
          : Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: destacada
                ? _mapsAzul.withValues(alpha: 0.12)
                : _fondoCampo,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            esLocal
                ? Icons.map_rounded
                : esFlygo
                    ? Icons.trending_up_rounded
                    : Icons.place_rounded,
            color: destacada ? _mapsAzul : _textoSecundario,
            size: 22,
          ),
        ),
        title: Text(
          p.primary,
          style: TextStyle(
            fontWeight: destacada ? FontWeight.w700 : FontWeight.w600,
            fontSize: 15,
            color: _textoPrincipal,
          ),
        ),
        subtitle: subtitulo.isNotEmpty
            ? Text(
                subtitulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _textoSecundario,
                  fontSize: 13,
                  height: 1.3,
                ),
              )
            : null,
        trailing: p.lat != null
            ? Icon(
                Icons.near_me_rounded,
                size: 18,
                color: destacada ? _mapsAzul : _bordeSuave,
              )
            : null,
        onTap: () => _elegir(p, indice: i),
      ),
    );
  }
}
