import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class PermisosService {
  static Future<bool> ensureUbicacion(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      messenger?.showSnackBar(const SnackBar(content: Text('Activa el GPS para continuar')));
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      messenger?.showSnackBar(const SnackBar(
        content: Text('Permiso de ubicación denegado permanentemente. Ve a Ajustes.'),
      ));
      return false;
    }

    final ok = permission == LocationPermission.always || permission == LocationPermission.whileInUse;
    if (!ok) messenger?.showSnackBar(const SnackBar(content: Text('No hay permiso de ubicación.')));
    return ok;
  }
}
