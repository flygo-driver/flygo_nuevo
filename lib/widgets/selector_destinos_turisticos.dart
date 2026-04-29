// selector_destinos_turisticos.dart - CORRECCIÓN COMPLETA

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:flygo_nuevo/servicios/turismo_catalogo_rd.dart';
import 'package:flygo_nuevo/servicios/tarifa_service_unificado.dart';
import 'package:flygo_nuevo/servicios/directions_service.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/servicios/lugares_service.dart';

class DestinoSeleccionado {
  final TurismoLugar lugar;
  final String tipoVehiculo;
  final int pasajeros;
  final double distanciaKm;
  final double precio;

  DestinoSeleccionado({
    required this.lugar,
    required this.tipoVehiculo,
    required this.pasajeros,
    required this.distanciaKm,
    required this.precio,
  });
}

class SelectorDestinosTuristicos extends StatefulWidget {
  final Function(DestinoSeleccionado) onDestinoSeleccionado;
  final double? latOrigen;
  final double? lonOrigen;
  final String? tipoVehiculoInicial;

  const SelectorDestinosTuristicos({
    super.key,
    required this.onDestinoSeleccionado,
    this.latOrigen,
    this.lonOrigen,
    this.tipoVehiculoInicial,
  });

  @override
  State<SelectorDestinosTuristicos> createState() =>
      _SelectorDestinosTuristicosState();
}

class _SelectorDestinosTuristicosState extends State<SelectorDestinosTuristicos>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  String? _tipoVehiculoSeleccionado;
  int _pasajeros = 1;
  TurismoLugar? _destinoSeleccionado;
  bool _calculando = false;

  List<Map<String, dynamic>> _resultadosGoogle = [];
  bool _buscandoGoogle = false;
  Timer? _debounceTimer;

  final Map<String, List<TurismoLugar>> _destinosPorSubtipo = {};

  // 🔥 CACHÉ para el contador de viajes
  int? _contadorViajesCache;
  DateTime? _contadorTimestamp;

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
    return opcion['maxPasajeros'] as int;
  }

  // 🔥 Obtener contador de viajes con caché
  Future<int> _obtenerContadorViajes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 1;

    if (_contadorViajesCache != null &&
        _contadorTimestamp != null &&
        DateTime.now().difference(_contadorTimestamp!) <
            const Duration(minutes: 5)) {
      return _contadorViajesCache!;
    }

    try {
      final snapshot = await fs.FirebaseFirestore.instance
          .collection('viajes')
          .where('uidCliente', isEqualTo: user.uid)
          .where('completado', isEqualTo: true)
          .count()
          .get();

      final int contador = snapshot.count ?? 0;
      _contadorViajesCache = contador;
      _contadorTimestamp = DateTime.now();

      return contador == 0 ? 1 : contador;
    } catch (e) {
      return 1;
    }
  }

  @override
  void initState() {
    super.initState();
    _tipoVehiculoSeleccionado = widget.tipoVehiculoInicial ?? 'carro';

    // Organizar destinos por subtipo
    for (var lugar in TurismoCatalogoRD.lugares) {
      _destinosPorSubtipo.putIfAbsent(lugar.subtipo, () => []).add(lugar);
    }

    // Ordenar subtipos
    final subtiposOrdenados = [
      TurismoCatalogoRD.aeropuerto,
      TurismoCatalogoRD.muelle,
      TurismoCatalogoRD.zonaColonial,
      TurismoCatalogoRD.playa,
      TurismoCatalogoRD.resort,
      TurismoCatalogoRD.ciudad,
      TurismoCatalogoRD.tour,
      TurismoCatalogoRD.montana,
      TurismoCatalogoRD.cascada,
      TurismoCatalogoRD.atraccion,
      TurismoCatalogoRD.parque,
      TurismoCatalogoRD.hotel,
      TurismoCatalogoRD.museo,
      TurismoCatalogoRD.lago,
    ].where((t) => _destinosPorSubtipo.containsKey(t)).toList();

    _tabController = TabController(
      length: subtiposOrdenados.length,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  List<TurismoLugar> get _destinosFiltrados {
    if (_searchQuery.isEmpty) return TurismoCatalogoRD.lugares;
    final query = _searchQuery.toLowerCase();
    return TurismoCatalogoRD.lugares.where((lugar) {
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
        final detalle = await service.detalle(pred.placeId);
        if (detalle != null && mounted) {
          detalles.add({
            'nombre': detalle.name,
            'direccion': detalle.address ?? '',
            'lat': detalle.lat,
            'lon': detalle.lon,
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

  Future<double> _calcularDistancia(double lat, double lon) async {
    if (widget.latOrigen == null || widget.lonOrigen == null) return 0.0;
    try {
      final result = await DirectionsService.drivingDistanceKm(
        originLat: widget.latOrigen!,
        originLon: widget.lonOrigen!,
        destLat: lat,
        destLon: lon,
        withTraffic: true,
        region: 'do',
      );
      return result?.km ??
          DistanciaService.calcularDistancia(
            widget.latOrigen!,
            widget.lonOrigen!,
            lat,
            lon,
          );
    } catch (e) {
      return DistanciaService.calcularDistancia(
        widget.latOrigen!,
        widget.lonOrigen!,
        lat,
        lon,
      );
    }
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
    if (widget.latOrigen == null || widget.lonOrigen == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esperando ubicación...')),
      );
      return;
    }

    setState(() {
      _calculando = true;
    });
    try {
      final distancia = await _calcularDistancia(lugar['lat'], lugar['lon']);
      final contadorViajes = await _obtenerContadorViajes();

      final precio = await TarifaServiceUnificado().calcularPrecio(
        tipoServicio: 'turismo',
        tipoVehiculo: _tipoVehiculoSeleccionado!,
        subtipoTurismo: 'busqueda',
        distanciaKm: distancia,
        idaVuelta: false,
        contadorViajes: contadorViajes, // ✅ AGREGADO
      );
      if (mounted) {
        setState(() {
          _calculando = false;
        });

        final lugarTemp = TurismoLugar(
          id: 'google_${lugar['placeId']}',
          nombre: lugar['nombre'],
          ciudad: lugar['direccion'].split(',').first.trim(),
          lat: lugar['lat'],
          lon: lugar['lon'],
          subtipo: 'busqueda',
          descripcion: lugar['direccion'],
          imagen: null,
          popularidad: 0,
        );

        widget.onDestinoSeleccionado(DestinoSeleccionado(
          lugar: lugarTemp,
          tipoVehiculo: _tipoVehiculoSeleccionado!,
          pasajeros: _pasajeros,
          distanciaKm: distancia,
          precio: precio,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _calculando = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al calcular: $e')),
        );
      }
    }
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
    if (widget.latOrigen == null || widget.lonOrigen == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esperando ubicación...')),
      );
      return;
    }

    setState(() {
      _destinoSeleccionado = destino;
      _calculando = true;
    });

    try {
      final distancia = await _calcularDistancia(destino.lat, destino.lon);
      final contadorViajes = await _obtenerContadorViajes();

      final precio = await TarifaServiceUnificado().calcularPrecio(
        tipoServicio: 'turismo',
        tipoVehiculo: _tipoVehiculoSeleccionado!,
        subtipoTurismo: destino.subtipo,
        distanciaKm: distancia,
        idaVuelta: false,
        contadorViajes: contadorViajes, // ✅ AGREGADO
      );
      if (mounted) {
        setState(() {
          _calculando = false;
        });
        widget.onDestinoSeleccionado(DestinoSeleccionado(
          lugar: destino,
          tipoVehiculo: _tipoVehiculoSeleccionado!,
          pasajeros: _pasajeros,
          distanciaKm: distancia,
          precio: precio,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _calculando = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al calcular: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Destinos Turísticos',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                  ),

                  // Selector de tipo de vehículo
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Tipo de vehículo:',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 14)),
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
                                  backgroundColor: Colors.grey[900],
                                  selectedColor: Colors.purple.withAlpha(77),
                                  checkmarkColor: Colors.white,
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? Colors.purple
                                        : Colors.white,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
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
                        const Text('Pasajeros:',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(width: 16),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove,
                                    color: Colors.white),
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
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 16),
                                ),
                              ),
                              IconButton(
                                icon:
                                    const Icon(Icons.add, color: Colors.white),
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

                  // Barra de búsqueda
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      style: const TextStyle(color: Colors.white),
                      scrollPadding: const EdgeInsets.fromLTRB(0, 0, 0, 280),
                      decoration: InputDecoration(
                        hintText: 'Buscar cualquier lugar en RD...',
                        hintStyle: const TextStyle(color: Colors.white54),
                        prefixIcon:
                            const Icon(Icons.search, color: Colors.white54),
                        suffixIcon: _buscandoGoogle
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : (_searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear,
                                        color: Colors.white54),
                                    onPressed: () {
                                      _onSearchChanged('');
                                      FocusScope.of(context).unfocus();
                                    },
                                  )
                                : null),
                        filled: true,
                        fillColor: Colors.grey[900],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Resultados
                  Expanded(
                    child: _buildResultados(),
                  ),
                ],
              ),
              if (_calculando)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: IgnorePointer(
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      color: const Color(0xFFBA68C8),
                      backgroundColor: Colors.purple.withValues(alpha: 0.18),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultados() {
    if (_searchQuery.isNotEmpty) {
      if (_resultadosGoogle.isNotEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Resultados de Google:',
                style: TextStyle(
                    color: Colors.purple, fontWeight: FontWeight.bold),
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
                    color: Colors.grey[900],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.purple,
                        child: Icon(Icons.location_on, color: Colors.white),
                      ),
                      title: Text(
                        lugar['nombre'],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        lugar['direccion'],
                        style: const TextStyle(color: Colors.white54),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing:
                          const Icon(Icons.add_circle, color: Colors.purple),
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Destinos turísticos:',
                style: TextStyle(
                    color: Colors.purple, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: _buildListaDestinos(locales),
            ),
          ],
        );
      }

      if (!_buscandoGoogle) {
        return const Center(
          child: Text(
            'No se encontraron lugares',
            style: TextStyle(color: Colors.white54),
          ),
        );
      }
    }

    // Vista normal con tabs
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: Colors.purple,
          unselectedLabelColor: Colors.white54,
          indicatorColor: Colors.purple,
          dividerColor: Colors.transparent,
          tabs: _destinosPorSubtipo.keys.map((subtipo) {
            return Tab(
              icon: Icon(_iconos[subtipo] ?? Icons.place),
              text: _subtitulos[subtipo]?.split(' ').first ?? subtipo,
            );
          }).toList(),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _destinosPorSubtipo.keys.map((subtipo) {
              final destinos = _destinosPorSubtipo[subtipo] ?? [];
              return _buildListaDestinos(destinos);
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildListaDestinos(List<TurismoLugar> destinos) {
    if (destinos.isEmpty) {
      return const Center(
        child: Text(
          'No hay destinos en esta categoría',
          style: TextStyle(color: Colors.white54),
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
          color: isSelected ? Colors.purple.withAlpha(51) : Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? Colors.purple : Colors.transparent,
              width: 1,
            ),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.purple.withAlpha(77),
              child: Icon(
                _iconos[destino.subtipo] ?? Icons.place,
                color: Colors.purple,
              ),
            ),
            title: Text(
              destino.nombre,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              destino.ciudad,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () => _seleccionarDestino(destino),
          ),
        );
      },
    );
  }
}
