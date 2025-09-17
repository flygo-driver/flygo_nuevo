import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class TestGps extends StatefulWidget {
  const TestGps({super.key});

  @override
  State<TestGps> createState() => _TestGpsState();
}

class _TestGpsState extends State<TestGps> {
  String ubicacion = 'Presiona el botón para obtener tu ubicación';

  Future<void> obtenerUbicacion() async {
    final bool servicioHabilitado = await Geolocator.isLocationServiceEnabled();
    if (!servicioHabilitado) {
      setState(() {
        ubicacion = 'El GPS está desactivado.';
      });
      return;
    }

    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) {
        setState(() {
          ubicacion = 'Permiso denegado.';
        });
        return;
      }
    }

    if (permiso == LocationPermission.deniedForever) {
      setState(() {
        ubicacion = 'Permiso denegado permanentemente.';
      });
      return;
    }

    final Position posicion = await Geolocator.getCurrentPosition();
    setState(() {
      ubicacion = 'Lat: ${posicion.latitude}, Lon: ${posicion.longitude}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test GPS')),
      body: Center(child: Text(ubicacion)),
      floatingActionButton: FloatingActionButton(
        onPressed: obtenerUbicacion,
        child: const Icon(Icons.gps_fixed),
      ),
    );
  }
}
