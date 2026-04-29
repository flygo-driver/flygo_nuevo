import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flygo_nuevo/widgets/selector_destinos_turisticos.dart';

/// Abre el selector de turismo de inmediato y completa origen en segundo plano
/// (última posición conocida + GPS baja precisión con límite de tiempo).
class TurismoDestinosSheetHost extends StatefulWidget {
  const TurismoDestinosSheetHost({
    super.key,
    required this.onDestinoSeleccionado,
    this.tipoVehiculoInicial = 'carro',
    this.seedLat,
    this.seedLon,
  });

  final void Function(DestinoSeleccionado seleccion) onDestinoSeleccionado;
  final String tipoVehiculoInicial;
  final double? seedLat;
  final double? seedLon;

  @override
  State<TurismoDestinosSheetHost> createState() =>
      _TurismoDestinosSheetHostState();
}

class _TurismoDestinosSheetHostState extends State<TurismoDestinosSheetHost> {
  double? _lat;
  double? _lon;
  bool _permDenied = false;

  @override
  void initState() {
    super.initState();
    if (widget.seedLat != null && widget.seedLon != null) {
      _lat = widget.seedLat;
      _lon = widget.seedLon;
    }
    unawaited(_mejorarUbicacionSiHaceFalta());
  }

  Future<void> _mejorarUbicacionSiHaceFalta() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (!mounted) return;
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _permDenied = true);
        return;
      }

      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        setState(() {
          _lat = last.latitude;
          _lon = last.longitude;
        });
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 10),
        );
        if (mounted) {
          setState(() {
            _lat = position.latitude;
            _lon = position.longitude;
          });
        }
      } on TimeoutException {
        // Mantener última conocida o semilla
      }
    } catch (_) {
      if (mounted && _lat == null && _lon == null && !_permDenied) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        SelectorDestinosTuristicos(
          latOrigen: _lat,
          lonOrigen: _lon,
          tipoVehiculoInicial: widget.tipoVehiculoInicial,
          onDestinoSeleccionado: widget.onDestinoSeleccionado,
        ),
        Positioned(
          top: 10,
          right: 12,
          child: SafeArea(
            bottom: false,
            child: Material(
              color: Colors.black.withValues(alpha: 0.72),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Volver',
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ),
        if (_permDenied)
          Positioned(
            left: 12,
            right: 12,
            top: 10,
            child: Material(
              color: Colors.orange.shade900.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  'Ubicación desactivada: activala para ver distancia y precio al elegir destino.',
                  style: TextStyle(color: Colors.white, fontSize: 12.5),
                ),
              ),
            ),
          )
        else if (_lat == null || _lon == null)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              child: LinearProgressIndicator(
                minHeight: 3,
                color: Colors.purpleAccent,
                backgroundColor: Colors.purple.withValues(alpha: 0.15),
              ),
            ),
          ),
      ],
    );
  }
}
