// lib/debug/map_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class MapTestPage extends StatefulWidget {
  const MapTestPage({super.key});

  @override
  State<MapTestPage> createState() => _MapTestPageState();
}

class _MapTestPageState extends State<MapTestPage> {
  final Completer<GoogleMapController> _controller = Completer();
  LatLng _center = const LatLng(18.4861, -69.9312); // Santo Domingo
  String _status = 'Cargando…';
  bool _hasLocation = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }

      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        );
        _center = LatLng(pos.latitude, pos.longitude);
        _hasLocation = true;
        _status = 'OK';
      } else {
        _status = 'Sin permisos de ubicación (usando SD).';
      }
    } catch (e) {
      _status = 'Error init: $e';
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final initial = CameraPosition(target: _center, zoom: 13);
    return Scaffold(
      appBar: AppBar(title: const Text('TEST Google Map')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.black12,
            padding: const EdgeInsets.all(8),
            child: Text('estado: $_status  |  hasLocation: $_hasLocation'),
          ),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: initial,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              onMapCreated: (c) => _controller.complete(c),
              markers: {
                Marker(
                  markerId: const MarkerId('m1'),
                  position: _center,
                  infoWindow: const InfoWindow(title: 'Centro'),
                )
              },
            ),
          ),
        ],
      ),
    );
  }
}
