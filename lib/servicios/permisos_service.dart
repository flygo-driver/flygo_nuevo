// lib/servicios/permisos_service.dart
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class PermisosService {
  /// Solicita y valida permisos de ubicación.
  /// Devuelve `true` si los servicios están activos y el permiso es válido.
  static Future<bool> ensureUbicacion(BuildContext context) async {
    // Captura segura (puede ser null si no hay Scaffold aún)
    final messenger = ScaffoldMessenger.maybeOf(context);

    // 1) Servicios de ubicación activos
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!context.mounted) return false;
      messenger?.showSnackBar(
        const SnackBar(content: Text('Activa el GPS para continuar')),
      );
      return false;
    }

    // 2) Estado del permiso
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      if (!context.mounted) return false;
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Permiso de ubicación denegado permanentemente. Ve a Ajustes.',
          ),
        ),
      );
      return false;
    }

    // 3) Resultado final
    final ok =
        permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;

    if (!ok) {
      if (!context.mounted) return false;
      messenger?.showSnackBar(
        const SnackBar(content: Text('No hay permiso de ubicación.')),
      );
    }
    return ok;
  }
}
