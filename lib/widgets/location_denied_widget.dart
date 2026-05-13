import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/location_permission_service.dart';

/// Pantalla / panel cuando falta permiso de ubicación o GPS apagado.
class LocationDeniedWidget extends StatelessWidget {
  const LocationDeniedWidget({
    super.key,
    this.title = 'Ubicación necesaria',
    this.message =
        'RAI necesita tu ubicación y el GPS activo para calcular tarifas y mostrarte el mapa.',
    this.showOpenGps = true,
    this.showOpenAppSettings = true,
  });

  final String title;
  final String message;
  final bool showOpenGps;
  final bool showOpenAppSettings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_off_outlined, size: 56, color: cs.error),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 24),
          if (showOpenGps)
            FilledButton.tonalIcon(
              onPressed: () =>
                  LocationPermissionService.openSystemLocationSettings(),
              icon: const Icon(Icons.gps_fixed),
              label: const Text('Abrir ajustes de ubicación'),
            ),
          if (showOpenGps && showOpenAppSettings) const SizedBox(height: 10),
          if (showOpenAppSettings)
            OutlinedButton.icon(
              onPressed: () =>
                  LocationPermissionService.openAppSettingsPage(),
              icon: const Icon(Icons.app_settings_alt_outlined),
              label: const Text('Permisos de la app'),
            ),
        ],
      ),
    );
  }
}
