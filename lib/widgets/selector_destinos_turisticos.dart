// selector_destinos_turisticos.dart - CORRECCIÓN COMPLETA

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/turismo_destinos_repo.dart';
import 'package:flygo_nuevo/servicios/turismo_catalogo_rd.dart';
import 'package:flygo_nuevo/servicios/lugares_service.dart';
import 'package:flygo_nuevo/servicios/custom_theme_service.dart';
import 'package:flygo_nuevo/servicios/gps_service.dart';
import 'package:flygo_nuevo/servicios/location_permission_service.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_cliente_service.dart';
import 'package:flygo_nuevo/widgets/rai_direccion_inteligente_sheet.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flygo_nuevo/servicios/rai_speech_busqueda_direccion.dart';
import 'package:flygo_nuevo/utils/rai_aplicar_destino_desde_voz.dart';

/// Destino elegido en catálogo; la cotización la hace [ProgramarViaje].
class DestinoSeleccionado {
  final TurismoLugar lugar;
  final String tipoVehiculo;
  final int pasajeros;
  final double? latOrigen;
  final double? lonOrigen;

  DestinoSeleccionado({
    required this.lugar,
    required this.tipoVehiculo,
    required this.pasajeros,
    this.latOrigen,
    this.lonOrigen,
  });
}

class SelectorDestinosTuristicos extends StatefulWidget {
  final Function(DestinoSeleccionado) onDestinoSeleccionado;
  final double? latOrigen;
  final double? lonOrigen;
  final String? tipoVehiculoInicial;
  final bool esViajeProgramado;

  const SelectorDestinosTuristicos({
    super.key,
    required this.onDestinoSeleccionado,
    this.latOrigen,
    this.lonOrigen,
    this.tipoVehiculoInicial,
    this.esViajeProgramado = false,
  });

  @override
  State<SelectorDestinosTuristicos> createState() =>
      _SelectorDestinosTuristicosState();
}

class _SelectorDestinosTuristicosState extends State<SelectorDestinosTuristicos>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<TabController> _tabControllersPendientesDispose = <TabController>[];
  String _searchQuery = '';
  String? _tipoVehiculoSeleccionado;
  int _pasajeros = 1;
  TurismoLugar? _destinoSeleccionado;

  List<Map<String, dynamic>> _resultadosGoogle = [];
  bool _buscandoGoogle = false;
  Timer? _debounceTimer;

  final TextEditingController _searchCtrl = TextEditingController();
  final RaiSpeechBusquedaDireccion _voz = RaiSpeechBusquedaDireccion();
  bool _escuchando = false;

  final Map<String, List<TurismoLugar>> _destinosPorSubtipo = {};
  List<String> _subtiposOrdenados = [];
  bool _resolviendoDestino = false;

  static const Map<String, String> _subtitulos = {
    TurismoCatalogoRD.aeropuerto: 'Aeropuertos de RD',
    TurismoCatalogoRD.muelle: 'Puertos y Muelles',
    TurismoCatalogoRD.zonaColonial: 'Zona Colonial',
    TurismoCatalogoRD.ciudad: 'Centros Urbanos',
    TurismoCatalogoRD.playa: 'Playas Paradisíacas',
    TurismoCatalogoRD.resort: 'Zonas Turísticas',
    TurismoCatalogoRD.hotel: 'Hoteles',
    TurismoCatalogoRD.tour: 'Tours y Excursiones',
    TurismoCatalogoRD.parque: 'Parques',
    TurismoCatalogoRD.montana: 'Montañas',
    TurismoCatalogoRD.cascada: 'Cascadas',
    TurismoCatalogoRD.lago: 'Lagos',
    TurismoCatalogoRD.museo: 'Museos',
    TurismoCatalogoRD.atraccion: 'Atracciones',
  };

  static const Map<String, IconData> _iconos = {
    TurismoCatalogoRD.aeropuerto: Icons.local_airport,
    TurismoCatalogoRD.muelle: Icons.directions_boat,
    TurismoCatalogoRD.zonaColonial: Icons.account_balance,
    TurismoCatalogoRD.ciudad: Icons.location_city,
    TurismoCatalogoRD.playa: Icons.beach_access,
    TurismoCatalogoRD.resort: Icons.hotel,
    TurismoCatalogoRD.hotel: Icons.bed,
    TurismoCatalogoRD.tour: Icons.tour,
    TurismoCatalogoRD.parque: Icons.park,
    TurismoCatalogoRD.montana: Icons.terrain,
    TurismoCatalogoRD.cascada: Icons.water_drop,
    TurismoCatalogoRD.lago: Icons.waves,
    TurismoCatalogoRD.museo: Icons.museum,
    TurismoCatalogoRD.atraccion: Icons.attractions,
  };

  final List<Map<String, dynamic>> _opcionesVehiculo = [
    {
      'value': 'carro',
      'label': 'Carro Turismo',
      'icon': '🚗',
      'maxPasajeros': 4
    },
    {
      'value': 'jeepeta',
      'label': 'Jeepeta Turismo',
      'icon': '🚙',
      'maxPasajeros': 5
    },
    {
      'value': 'minivan',
      'label': 'Minivan Turismo',
      'icon': '🚐',
      'maxPasajeros': 8
    },
    {'value': 'bus', 'label': 'Bus Turismo', 'icon': '🚌', 'maxPasajeros': 20},
  ];

  int get _maxPasajerosParaVehiculoActual {
    final opcion = _opcionesVehiculo.firstWhere(
      (o) => o['value'] == _tipoVehiculoSeleccionado,
      orElse: () => {'maxPasajeros': 4},
    );
    final dynamic max = opcion['maxPasajeros'];
    if (max is int) return max;
    if (max is num) return max.toInt();
    return 4;
  }

  /// Coerción segura de coordenadas: acepta double/int/String y descarta nulos o inválidos.
  static double? _coordDouble(dynamic v) {
    if (v is double) return v.isFinite ? v : null;
    if (v is int) return v.toDouble();
    if (v is num) {
      final double d = v.toDouble();
      return d.isFinite ? d : null;
    }
    final double? d = double.tryParse('$v');
    return (d != null && d.isFinite) ? d : null;
  }

  List<TurismoLugar> _catalogoBase = TurismoCatalogoRD.lugares;

  @override
  void initState() {
    super.initState();
    _tipoVehiculoSeleccionado = widget.tipoVehiculoInicial ?? 'carro';
    _organizarCatalogo(_catalogoBase, initTabs: true);
    _cargarDestinosFirestore();
  }

  Future<void> _resolverYAplicarTrasVoz(String texto) async {
    if (!mounted || texto.trim().length < 2) return;

    final res = await RaiAplicarDestinoDesdeVoz.resolver(
      textoReconocido: texto,
      biasLat: widget.latOrigen,
      biasLon: widget.lonOrigen,
      desdeVoz: true,
    );
    if (!mounted) return;

    final det = res.lugarConfiable ??
        (res.candidatos.isNotEmpty ? res.candidatos.first : null);
    if (det != null) {
      _searchCtrl.text = det.displayLabel;
      setState(() => _searchQuery = det.displayLabel);
      await _seleccionarDestinoGoogle(<String, dynamic>{
        'placeId': det.placeId,
        'nombre': det.name,
        'direccion': det.displayLabel,
        'lat': det.lat,
        'lon': det.lon,
      });
      return;
    }

    _onSearchChanged(texto);
    if (texto.trim().length >= 3) {
      await _buscarEnGoogle(texto.trim());
    }
  }

  Future<void> _toggleVoz() async {
    if (_buscandoGoogle) return;
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
        _searchCtrl.text = words;
        _onSearchChanged(words);
        if (isFinal) {
          final texto = words.trim();
          if (texto.length >= 2) {
            unawaited(_resolverYAplicarTrasVoz(texto));
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

  Future<void> _abrirBusquedaRai() async {
    final det = await RaiDireccionInteligenteSheet.mostrar(
      context,
      textoInicial: _searchQuery.trim(),
      biasLat: widget.latOrigen,
      biasLon: widget.lonOrigen,
    );
    if (det == null || !mounted) return;
    await _seleccionarDestinoGoogle(<String, dynamic>{
      'placeId': det.placeId,
      'nombre': det.name,
      'direccion': det.displayLabel,
      'lat': det.lat,
      'lon': det.lon,
    });
  }

  Future<void> _cargarDestinosFirestore() async {
    try {
      final fusion = await TurismoDestinosRepo.catalogoFusionado();
      if (!mounted) return;
      setState(() {
        _catalogoBase = fusion;
        _organizarCatalogo(fusion, reinitTabs: true);
      });
    } catch (_) {
      /* catálogo estático sigue funcionando */
    }
  }

  void _organizarCatalogo(
    List<TurismoLugar> lugares, {
    bool initTabs = false,
    bool reinitTabs = false,
  }) {
    _destinosPorSubtipo.clear();
    for (final lugar in lugares) {
      final subtipo = TurismoCatalogoRD.normalizarSubtipo(lugar.subtipo);
      final normalizado = lugar.subtipo == subtipo
          ? lugar
          : lugar.copyWith(subtipo: subtipo);
      _destinosPorSubtipo.putIfAbsent(subtipo, () => []).add(normalizado);
    }

    for (final lista in _destinosPorSubtipo.values) {
      lista.sort((a, b) {
        final pop = b.popularidad.compareTo(a.popularidad);
        if (pop != 0) return pop;
        return a.nombre.compareTo(b.nombre);
      });
    }

    final orden = [
      ...TurismoCatalogoRD.ordenSubtiposCatalogo
          .where((t) => _destinosPorSubtipo.containsKey(t)),
      ..._destinosPorSubtipo.keys.where(
        (t) => !TurismoCatalogoRD.ordenSubtiposCatalogo.contains(t),
      ),
    ];

    if (initTabs || reinitTabs || orden.length != _subtiposOrdenados.length) {
      final prevIndex = initTabs ? 0 : _tabController.index;
      // No desechar el controller viejo en medio del rebuild: el TabBar/TabBarView
      // aún dependen de él y dispararía «_dependents.isEmpty: is not true».
      // Se desecha tras el frame, cuando el subárbol ya se reconstruyó con el nuevo.
      final TabController? viejo = initTabs ? null : _tabController;
      _subtiposOrdenados = orden;
      _tabController = TabController(
        length: orden.isEmpty ? 1 : orden.length,
        vsync: this,
        initialIndex: orden.isEmpty
            ? 0
            : prevIndex.clamp(0, orden.length - 1),
      );
      if (viejo != null) {
        _tabControllersPendientesDispose.add(viejo);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_tabControllersPendientesDispose.remove(viejo)) {
            viejo.dispose();
          }
        });
      }
    } else {
      _subtiposOrdenados = orden;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    if (_voz.isListening) unawaited(_voz.stop());
    _searchCtrl.dispose();
    for (final TabController c in _tabControllersPendientesDispose) {
      c.dispose();
    }
    _tabControllersPendientesDispose.clear();
    _tabController.dispose();
    super.dispose();
  }

  List<TurismoLugar> get _destinosFiltrados {
    if (_searchQuery.isEmpty) return _catalogoBase;
    final query = _searchQuery.toLowerCase();
    return _catalogoBase.where((lugar) {
      return lugar.nombre.toLowerCase().contains(query) ||
          lugar.ciudad.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _buscarEnGoogle(String query) async {
    if (query.length < 3) {
      setState(() {
        _resultadosGoogle = [];
      });
      return;
    }
    setState(() {
      _buscandoGoogle = true;
    });
    try {
      final service = LugaresService.instance;
      final resultados = await service.autocompletar(query, country: 'DO');
      final detalles = <Map<String, dynamic>>[];

      final resultadosLimitados = resultados.take(5).toList();

      for (var pred in resultadosLimitados) {
        final detalle = await service.detalleDesdePrediccion(pred);
        if (detalle != null && mounted) {
          final double? lat = _coordDouble(detalle.lat);
          final double? lon = _coordDouble(detalle.lon);
          if (lat == null || lon == null) continue;
          final String nombre = detalle.name.trim();
          final String direccion = (detalle.address ?? '').trim();
          detalles.add({
            'nombre': nombre.isEmpty
                ? (direccion.isEmpty ? 'Lugar seleccionado' : direccion)
                : nombre,
            'direccion': direccion,
            'lat': lat,
            'lon': lon,
            'placeId': pred.placeId,
          });
        }
      }
      if (mounted) {
        setState(() {
          _resultadosGoogle = detalles;
          _buscandoGoogle = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _buscandoGoogle = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
    });
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (value.length >= 3) {
        _buscarEnGoogle(value);
      } else {
        setState(() {
          _resultadosGoogle = [];
        });
      }
    });
  }

  Future<void> _emitirDestinoSeleccionado({
    required TurismoLugar lugar,
  }) async {
    final ({double lat, double lon})? origen =
        await _resolverOrigenParaCotizar();
    if (!mounted) return;
    widget.onDestinoSeleccionado(
      DestinoSeleccionado(
        lugar: lugar,
        tipoVehiculo: _tipoVehiculoSeleccionado!,
        pasajeros: _pasajeros,
        latOrigen: origen?.lat,
        lonOrigen: origen?.lon,
      ),
    );
  }

  Future<void> _seleccionarDestinoGoogle(Map<String, dynamic> lugar) async {
    if (_pasajeros > _maxPasajerosParaVehiculoActual) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Máximo $_maxPasajerosParaVehiculoActual pasajeros para este vehículo'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final String nombre = (lugar['nombre'] ?? '').toString().trim();
    final String direccion = (lugar['direccion'] ?? '').toString().trim();
    final double? lat = _coordDouble(lugar['lat']);
    final double? lon = _coordDouble(lugar['lon']);

    if (lat == null || lon == null || (nombre.isEmpty && direccion.isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No pudimos usar este lugar. Elige otro destino.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final String nombreFinal = nombre.isEmpty ? direccion : nombre;
    final String ciudad = direccion.contains(',')
        ? direccion.split(',').first.trim()
        : (direccion.isEmpty ? nombreFinal : direccion);

    final lugarTemp = TurismoLugar(
      id: 'google_${(lugar['placeId'] ?? '').toString()}',
      nombre: nombreFinal,
      ciudad: ciudad.isEmpty ? nombreFinal : ciudad,
      lat: lat,
      lon: lon,
      subtipo: 'busqueda',
      descripcion: direccion.isEmpty ? nombreFinal : direccion,
      imagen: null,
      popularidad: 0,
    );

    await _emitirDestinoSeleccionado(lugar: lugarTemp);
  }

  Future<void> _seleccionarDestino(TurismoLugar destino) async {
    if (_pasajeros > _maxPasajerosParaVehiculoActual) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Máximo $_maxPasajerosParaVehiculoActual pasajeros para este vehículo'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_resolviendoDestino) return;
    setState(() {
      _destinoSeleccionado = destino;
      _resolviendoDestino = true;
    });

    TurismoLugar? cotizable = destino;
    if (!TurismoCatalogoRD.listoParaCotizar(destino)) {
      cotizable = await TurismoDestinosRepo.resolverLugarCotizable(destino);
    } else {
      final fixed =
          TurismoCatalogoRD.corregirCoordenadasRd(destino.lat, destino.lon);
      if (fixed != null &&
          (fixed.lat != destino.lat || fixed.lon != destino.lon)) {
        cotizable = destino.copyWith(lat: fixed.lat, lon: fixed.lon);
      }
    }

    if (!mounted) return;
    setState(() => _resolviendoDestino = false);

    if (cotizable == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo ubicar "${destino.nombre}" en el mapa. '
            'Prueba buscarlo arriba o elige otro destino.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _destinoSeleccionado = cotizable);
    await _emitirDestinoSeleccionado(lugar: cotizable);
  }

  /// Si el host aún no propagó coords, las obtiene aquí (con permiso si hace falta).
  Future<({double lat, double lon})?> _resolverOrigenParaCotizar() async {
    if (widget.latOrigen != null && widget.lonOrigen != null) {
      return (lat: widget.latOrigen!, lon: widget.lonOrigen!);
    }

    try {
      final Position? last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return (lat: last.latitude, lon: last.longitude);
      }
    } catch (_) {}

    try {
      final ({bool serviceEnabled, LocationPermission permission}) snap =
          await GpsService.readServiceAndPermissionStabilizedNoRequest(
        extendedAfterPriorGrant:
            await LocationPermissionService.ubicacionConcedidaAntesEnPrefs(),
      );
      if (!snap.serviceEnabled || !GpsService.permissionUsable(snap.permission)) {
        unawaited(RaiUbicacionClienteService.instance.refrescar());
        return null;
      }
      if (snap.serviceEnabled && GpsService.permissionUsable(snap.permission)) {
        final Position? pos = await GpsService.obtenerUbicacionActual(
          timeout: const Duration(seconds: 12),
          maxEdadUltima: const Duration(hours: 24),
        );
        if (pos != null) {
          return (lat: pos.latitude, lon: pos.longitude);
        }
      }
    } catch (_) {}

    try {
      final Position? last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return (lat: last.latitude, lon: last.longitude);
      }
    } catch (_) {}

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    // Tematización del sheet basada en el color de fondo personalizado
    // del cliente (CustomThemeService). Antes el sheet era 100% negro y
    // chocaba con cualquier color elegido (blanco, agua, rosado, amarillo).
    // Ahora el fondo del sheet usa cardOn(themedBg) y todos los textos /
    // bordes / chips se calculan por contraste WCAG sobre ese fondo, así
    // las opciones SIEMPRE son legibles. El púrpura se mantiene como
    // identidad visual de "Turismo".
    final Color themedBg = Theme.of(context).scaffoldBackgroundColor;
    final Color sheetBg = CustomThemeService.cardOn(themedBg);
    final Color textPrimary = CustomThemeService.textOn(sheetBg);
    final Color textMuted = CustomThemeService.textMutedOn(sheetBg);
    final Color textSubtle = CustomThemeService.textSubtleOn(sheetBg);
    final Color borderSoft = CustomThemeService.borderOn(sheetBg);
    // Superficie ligeramente elevada (chips, input, cards de resultados).
    final bool sheetIsDark =
        ThemeData.estimateBrightnessForColor(sheetBg) == Brightness.dark;
    final Color surfaceRaised = sheetIsDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    const Color accent = Colors.purple;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.85,
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: borderSoft, width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: textSubtle.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Destinos Turísticos',
                      style: TextStyle(
                          color: textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (widget.esViajeProgramado)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded,
                                color: accent, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Reserva programada: aquí eliges destino y vehículo. '
                                'Después definirás fecha, hora e ida y vuelta en el formulario.',
                                style: TextStyle(
                                  color: textMuted,
                                  fontSize: 12.5,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Selector de tipo de vehículo (chips). Las opciones AHORA
                  // son visibles sobre cualquier fondo: el fondo del chip
                  // usa surfaceRaised derivado del sheet, el texto usa
                  // textPrimary calculado por contraste WCAG.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tipo de vehículo:',
                            style:
                                TextStyle(color: textMuted, fontSize: 14)),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _opcionesVehiculo.map((opcion) {
                              final isSelected =
                                  _tipoVehiculoSeleccionado == opcion['value'];
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(
                                    opcion['label'] as String,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  avatar: Text(opcion['icon'] as String),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() {
                                        _tipoVehiculoSeleccionado =
                                            opcion['value'];
                                        if (_pasajeros >
                                            opcion['maxPasajeros']) {
                                          _pasajeros = opcion['maxPasajeros'];
                                        }
                                      });
                                    }
                                  },
                                  backgroundColor: surfaceRaised,
                                  selectedColor: accent.withAlpha(77),
                                  checkmarkColor: accent,
                                  side: BorderSide(
                                    color: isSelected
                                        ? accent.withValues(alpha: 0.7)
                                        : borderSoft,
                                    width: isSelected ? 1.4 : 0.8,
                                  ),
                                  labelStyle: TextStyle(
                                    color: isSelected ? accent : textPrimary,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Selector de pasajeros
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text('Pasajeros:',
                            style:
                                TextStyle(color: textMuted, fontSize: 14)),
                        const SizedBox(width: 16),
                        Container(
                          decoration: BoxDecoration(
                            color: surfaceRaised,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderSoft),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.remove,
                                    color: textPrimary),
                                onPressed: () {
                                  if (_pasajeros > 1) {
                                    setState(() => _pasajeros--);
                                  }
                                },
                              ),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  '$_pasajeros',
                                  style: TextStyle(
                                      color: textPrimary, fontSize: 16),
                                ),
                              ),
                              IconButton(
                                icon:
                                    Icon(Icons.add, color: textPrimary),
                                onPressed: () {
                                  if (_pasajeros <
                                      _maxPasajerosParaVehiculoActual) {
                                    setState(() => _pasajeros++);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Máximo $_maxPasajerosParaVehiculoActual pasajeros'),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Barra de búsqueda. Texto/hint/icons derivados del fondo
                  // del sheet para garantizar contraste con cualquier color.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _searchCtrl,
                      style: TextStyle(color: textPrimary),
                      scrollPadding: const EdgeInsets.fromLTRB(0, 0, 0, 280),
                      decoration: InputDecoration(
                        hintText: 'Buscar cualquier lugar en RD...',
                        hintStyle: TextStyle(color: textSubtle),
                        prefixIcon:
                            Icon(Icons.search, color: textSubtle),
                        suffixIcon: _buscandoGoogle || _resolviendoDestino
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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
                                  IconButton(
                                    tooltip: 'Búsqueda inteligente RAI',
                                    icon: const Icon(
                                      Icons.auto_awesome_rounded,
                                      color: accent,
                                      size: 22,
                                    ),
                                    onPressed: _abrirBusquedaRai,
                                  ),
                                  if (_searchQuery.isNotEmpty)
                                    IconButton(
                                      icon: Icon(Icons.clear,
                                          color: textSubtle),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        _onSearchChanged('');
                                        FocusScope.of(context).unfocus();
                                      },
                                    ),
                                ],
                              ),
                        filled: true,
                        fillColor: surfaceRaised,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: borderSoft),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: accent.withValues(alpha: 0.6)),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: borderSoft),
                        ),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Resultados
                  Expanded(
                    child: _buildResultados(
                      sheetBg: sheetBg,
                      surfaceRaised: surfaceRaised,
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                      textSubtle: textSubtle,
                      borderSoft: borderSoft,
                      accent: accent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultados({
    required Color sheetBg,
    required Color surfaceRaised,
    required Color textPrimary,
    required Color textMuted,
    required Color textSubtle,
    required Color borderSoft,
    required Color accent,
  }) {
    if (_searchQuery.isNotEmpty) {
      if (_resultadosGoogle.isNotEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Resultados de Google:',
                style: TextStyle(
                    color: accent, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _resultadosGoogle.length,
                itemBuilder: (context, index) {
                  final lugar = _resultadosGoogle[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: surfaceRaised,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: borderSoft),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: accent,
                        child: const Icon(Icons.location_on,
                            color: Colors.white),
                      ),
                      title: Text(
                        (lugar['nombre'] ?? 'Lugar').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        (lugar['direccion'] ?? '').toString(),
                        style: TextStyle(color: textSubtle),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(Icons.add_circle, color: accent),
                      onTap: () => _seleccionarDestinoGoogle(lugar),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      }

      final locales = _destinosFiltrados;
      if (locales.isNotEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Destinos turísticos:',
                style: TextStyle(
                    color: accent, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: _buildListaDestinos(
                locales,
                surfaceRaised: surfaceRaised,
                textPrimary: textPrimary,
                textSubtle: textSubtle,
                borderSoft: borderSoft,
                accent: accent,
              ),
            ),
          ],
        );
      }

      if (!_buscandoGoogle) {
        return Center(
          child: Text(
            'No se encontraron lugares',
            style: TextStyle(color: textSubtle),
          ),
        );
      }
    }

    // Vista normal con tabs.
    // El `key` ligado al controller fuerza un subárbol nuevo cuando el
    // controller se recrea (llegada de destinos Firestore), evitando que el
    // TabBar/TabBarView queden atados a un controller ya desechado.
    return Column(
      key: ValueKey<int>(identityHashCode(_tabController)),
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: accent,
          unselectedLabelColor: textMuted,
          indicatorColor: accent,
          dividerColor: Colors.transparent,
          tabs: _subtiposOrdenados.map((subtipo) {
            return Tab(
              icon: Icon(_iconos[subtipo] ?? Icons.place),
              text: _subtitulos[subtipo]?.split(' ').first ?? subtipo,
            );
          }).toList(),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _subtiposOrdenados.map((subtipo) {
              final destinos = _destinosPorSubtipo[subtipo] ?? [];
              return _buildListaDestinos(
                destinos,
                surfaceRaised: surfaceRaised,
                textPrimary: textPrimary,
                textSubtle: textSubtle,
                borderSoft: borderSoft,
                accent: accent,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildListaDestinos(
    List<TurismoLugar> destinos, {
    required Color surfaceRaised,
    required Color textPrimary,
    required Color textSubtle,
    required Color borderSoft,
    required Color accent,
  }) {
    if (destinos.isEmpty) {
      return Center(
        child: Text(
          'No hay destinos en esta categoría',
          style: TextStyle(color: textSubtle),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: destinos.length,
      itemBuilder: (context, index) {
        final destino = destinos[index];
        final isSelected = _destinoSeleccionado?.id == destino.id;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: isSelected ? accent.withAlpha(51) : surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? accent : borderSoft,
              width: isSelected ? 1.4 : 0.6,
            ),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: accent.withAlpha(77),
              child: Icon(
                _iconos[destino.subtipo] ?? Icons.place,
                color: accent,
              ),
            ),
            title: Text(
              destino.nombre,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: textPrimary),
            ),
            subtitle: Text(
              destino.ciudad,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: textSubtle),
            ),
            trailing: Icon(Icons.chevron_right, color: textSubtle),
            onTap: () => _seleccionarDestino(destino),
          ),
        );
      },
    );
  }
}
