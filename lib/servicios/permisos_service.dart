import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/location_permission_service.dart';

/// Compatibilidad: delega en [LocationPermissionService] con mensajes claros.
class PermisosService {
  static Future<bool> ensureUbicacion(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);

    final r = await LocationPermissionService.checkAndRequestBasicPermission();
    if (!r.serviceEnabled) {
      messenger?.showSnackBar(
        SnackBar(
          content: const Text('Activa el GPS para continuar.'),
          action: SnackBarAction(
            label: 'Ajustes de ubicación',
            onPressed: () =>
                LocationPermissionService.openSystemLocationSettings(),
          ),
        ),
      );
      return false;
    }

    if (r.deniedForever) {
      messenger?.showSnackBar(
        SnackBar(
          content: const Text(
            'Permiso de ubicación bloqueado. Ábrelo en Ajustes de la app.',
          ),
          action: SnackBarAction(
            label: 'Ajustes',
            onPressed: () => LocationPermissionService.openAppSettingsPage(),
          ),
        ),
      );
      return false;
    }

    if (!r.canUseLocation) {
      messenger?.showSnackBar(
        SnackBar(
          content: const Text('RAI necesita permiso de ubicación para continuar.'),
          action: SnackBarAction(
            label: 'Ajustes',
            onPressed: () => LocationPermissionService.openAppSettingsPage(),
          ),
        ),
      );
      return false;
    }

    return true;
  }
}
