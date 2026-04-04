// lib/debug/places_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

// Prefijos para evitar choques de tipos
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart' as places;

// Tu archivo con la API key (ajústalo si tu constante tiene otro nombre)
import 'package:flygo_nuevo/keys.dart' as app_keys;

class PlacesTestPage extends StatefulWidget {
  const PlacesTestPage({super.key});
  @override
  State<PlacesTestPage> createState() => _PlacesTestPageState();
}

class _PlacesTestPageState extends State<PlacesTestPage> {
  // ❗ En esta versión del plugin debes pasar la API key al constructor
  final places.FlutterGooglePlacesSdk _places =
      places.FlutterGooglePlacesSdk(app_keys.kGooglePlacesApiKey);

  final _queryCtrl = TextEditingController();
  final _focusNode = FocusNode();

  List<places.AutocompletePrediction> _predictions = [];
  bool _loadingPreds = false;
  bool _loadingDetails = false;
  String? _error;

  places.Place? _selectedPlace;
  Timer? _debounce;

  gmap.GoogleMapController? _mapCtrl;
  final Set<gmap.Marker> _markers = {};
  gmap.CameraPosition _camera = const gmap.CameraPosition(
    target: gmap.LatLng(18.4861, -69.9312), // Santo Domingo
    zoom: 12,
  );

  @override
  void initState() {
    super.initState();
    _queryCtrl.addListener(() {
      _error = null;
      _selectedPlace = null;
      _markers.clear();
      _debouncedSearch(_queryCtrl.text.trim());
      setState(() {});
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.dispose();
    _focusNode.dispose();
    _mapCtrl?.dispose();
    super.dispose();
  }

  void _debouncedSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _searchPredictions(q);
    });
  }

  String _readStructured(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    try {
      final t = v.text;
      if (t is String) return t;
    } catch (_) {}
    return v.toString();
  }

  Future<void> _searchPredictions(String query) async {
    if (query.length < 2) {
      setState(() => _predictions = []);
      return;
    }
    setState(() {
      _loadingPreds = true;
      _error = null;
    });
    try {
      final result = await _places.findAutocompletePredictions(
        query,
        countries: const ['DO'],
        newSessionToken: true,
      );
      setState(() {
        _predictions = result.predictions;
      });
    } on PlatformException catch (e) {
      setState(() {
        _error = 'Autocomplete error: ${e.code} ${e.message}';
        _predictions = [];
      });
    } catch (e) {
      setState(() {
        _error = 'Error buscando sugerencias: $e';
        _predictions = [];
      });
    } finally {
      if (mounted) setState(() => _loadingPreds = false);
    }
  }

  // Devuelve la lista de PlaceField compatible con tu versión del plugin:
  // usa LatLng si existe; si no, usa Location.
  List<places.PlaceField> _compatibleFields() {
    const values = places.PlaceField.values; // ✅ CORREGIDO: ahora es const
    
    places.PlaceField? _byName(String n) {
      try {
        return values.firstWhere(
          (f) => f.name == n,
          orElse: () => values.firstWhere(
            (f) => f.toString().split('.').last == n,
            orElse: () => values.first,
          ),
        );
      } catch (_) {
        return null;
      }
    }

    final id = _byName('Id');
    final name = _byName('Name');
    final address = _byName('Address');
    final types = _byName('Types');
    final latLng = _byName('LatLng') ?? _byName('Location');

    final out = <places.PlaceField>[];
    if (id != null) out.add(id);
    if (name != null) out.add(name);
    if (address != null) out.add(address);
    if (latLng != null) out.add(latLng);
    if (types != null) out.add(types);
    return out;
  }

  Future<void> _selectPrediction(places.AutocompletePrediction p) async {
    setState(() {
      _loadingDetails = true;
      _error = null;
      _selectedPlace = null;
      _markers.clear();
    });
    try {
      final fields = _compatibleFields();
      final details = await _places.fetchPlace(p.placeId, fields: fields);
      final place = details.place;

      // Toma lat/lng soportando LatLng o Location, sin referenciar miembros inexistentes
      double? lat;
      double? lng;
      try {
        final ll = place?.latLng;
        if (ll != null) {
          lat = ll.lat;
          lng = ll.lng;
        }
      } catch (_) {}

      if ((lat == null || lng == null) && place != null) {
        try {
          final loc = (place as dynamic).location;
          lat = (loc?.lat as num?)?.toDouble();
          lng = (loc?.lng as num?)?.toDouble();
        } catch (_) {}
      }

      if (place == null || lat == null || lng == null) {
        setState(() {
          _error = 'No se pudo obtener lat/lng del lugar seleccionado';
        });
        return;
      }

      final pos = gmap.LatLng(lat, lng);

      _camera = gmap.CameraPosition(target: pos, zoom: 16);
      _markers.add(
        gmap.Marker(
          markerId: gmap.MarkerId(place.id ?? pos.toString()),
          position: pos,
          infoWindow: gmap.InfoWindow(
            title: place.name ?? 'Lugar',
            snippet: place.address ?? '',
          ),
        ),
      );
      if (_mapCtrl != null) {
        await _mapCtrl!.animateCamera(
          gmap.CameraUpdate.newCameraPosition(_camera),
        );
      }

      setState(() {
        _selectedPlace = place;
        _focusNode.unfocus();
      });
    } on PlatformException catch (e) {
      setState(() {
        _error = 'fetchPlace error: ${e.code} ${e.message}';
        _selectedPlace = null;
      });
    } catch (e) {
      setState(() {
        _error = 'Error trayendo detalles: $e';
        _selectedPlace = null;
      });
    } finally {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  Future<void> _abrirGoogleMapsExternamente() async {
    // Intentamos leer lat/lng de ambas formas sin romper
    double? lat, lng;
    try {
      lat = _selectedPlace?.latLng?.lat;
      lng = _selectedPlace?.latLng?.lng;
    } catch (_) {}
    if ((lat == null || lng == null) && _selectedPlace != null) {
      try {
        final loc = (_selectedPlace as dynamic).location;
        lat = (loc?.lat as num?)?.toDouble();
        lng = (loc?.lng as num?)?.toDouble();
      } catch (_) {}
    }
    if (lat == null || lng == null) return;

    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Test: Google Places + Map'),
        backgroundColor: Colors.black,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Campo de búsqueda
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: TextField(
                controller: _queryCtrl,
                focusNode: _focusNode,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Busca un lugar…',
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.search, color: Colors.greenAccent),
                  filled: true,
                  fillColor: const Color(0xFF121212),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.greenAccent),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.greenAccent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.greenAccent, width: 2),
                  ),
                  suffixIcon: _loadingPreds
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : (_queryCtrl.text.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _queryCtrl.clear();
                                setState(() => _predictions = []);
                              },
                              icon: const Icon(Icons.clear, color: Colors.white70),
                            )
                          : null),
                ),
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ),

            // Lista de sugerencias
            if (_predictions.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  itemBuilder: (ctx, i) {
                    final p = _predictions[i];
                    final primary = _readStructured(p.primaryText);
                    final secondary = _readStructured(p.secondaryText);
                    return InkWell(
                      onTap: () => _selectPrediction(p),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121212),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.place, color: Colors.greenAccent),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    primary,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (secondary.isNotEmpty)
                                    Text(
                                      secondary,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: Colors.white54),
                          ],
                        ),
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemCount: _predictions.length,
                ),
              )
            else
              const SizedBox.shrink(),

            // Detalles + Mapa
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              decoration: const BoxDecoration(
                color: Colors.black,
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Column(
                children: [
                  if (_loadingDetails)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (!_loadingDetails && _selectedPlace != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PlaceDetailsCard(place: _selectedPlace!),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 260,
                          child: gmap.GoogleMap(
                            initialCameraPosition: _camera,
                            markers: _markers,
                            myLocationButtonEnabled: false,
                            myLocationEnabled: false,
                            onMapCreated: (c) => _mapCtrl = c,
                            compassEnabled: true,
                            mapToolbarEnabled: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: _abrirGoogleMapsExternamente,
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Abrir en Google Maps'),
                        ),
                      ],
                    ),
                  if (!_loadingDetails && _selectedPlace == null && _predictions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Escribe para buscar…',
                          style: TextStyle(color: Colors.white54)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceDetailsCard extends StatelessWidget {
  const _PlaceDetailsCard({required this.place});
  final places.Place place;

  String _typeToString(dynamic t) {
    if (t == null) return '';
    if (t is String) return t;
    try {
      final n = t.name;
      if (n is String) return n;
    } catch (_) {}
    final s = t.toString();
    final i = s.lastIndexOf('.');
    return i >= 0 ? s.substring(i + 1) : s;
  }

  @override
  Widget build(BuildContext context) {
    double? lat, lng;
    try {
      lat = place.latLng?.lat;
      lng = place.latLng?.lng;
    } catch (_) {}
    if (lat == null || lng == null) {
      try {
        final loc = (place as dynamic).location;
        lat = (loc?.lat as num?)?.toDouble();
        lng = (loc?.lng as num?)?.toDouble();
      } catch (_) {}
    }

    final types = (place.types ?? [])
        .map((t) => _typeToString(t))
        .where((s) => s.isNotEmpty)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(12),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(place.name ?? 'Sin nombre',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (place.address != null)
              Text(place.address!, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            Text('placeId: ${place.id}', style: const TextStyle(fontSize: 12)),
            if (lat != null && lng != null) ...[
              const SizedBox(height: 6),
              Text('Lat: $lat, Lng: $lng'),
            ],
            if (types.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: -6,
                children: types
                    .map((t) => Chip(
                          label: Text(t,
                              style:
                                  const TextStyle(color: Colors.black, fontSize: 12)),
                          backgroundColor: Colors.greenAccent,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}