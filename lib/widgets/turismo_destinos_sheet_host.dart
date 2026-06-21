import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flygo_nuevo/servicios/custom_theme_service.dart';
import 'package:flygo_nuevo/servicios/gps_service.dart';
import 'package:flygo_nuevo/servicios/location_permission_service.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_cliente_service.dart';
import 'package:flygo_nuevo/widgets/selector_destinos_turisticos.dart';

/// Abre el selector de turismo al instante; la ubicación se completa en segundo plano
/// sin banners que bloqueen la UI (falsos «permiso denegado» en algunos Android).
class TurismoDestinosSheetHost extends StatefulWidget {
  const TurismoDestinosSheetHost({
    super.key,
    required this.onDestinoSeleccionado,
    this.tipoVehiculoInicial = 'carro',
    this.seedLat,
    this.seedLon,
    this.showFloatingBack = true,
  });

  final void Function(DestinoSeleccionado seleccion) onDestinoSeleccionado;
  final String tipoVehiculoInicial;
  final double? seedLat;
  final double? seedLon;
  /// En pantalla completa con AppBar, usar `false`.
  final bool showFloatingBack;

  @override
  State<TurismoDestinosSheetHost> createState() =>
      _TurismoDestinosSheetHostState();
}

class _TurismoDestinosSheetHostState extends State<TurismoDestinosSheetHost> {
  double? _lat;
  double? _lon;

  @override
  void initState() {
    super.initState();
    if (widget.seedLat != null && widget.seedLon != null) {
      _lat = widget.seedLat;
      _lon = widget.seedLon;
    }
    unawaited(RaiUbicacionClienteService.instance.ensureStarted());
    unawaited(_cargarUbicacionEnSegundoPlano());
  }

  void _aplicarCoords(double lat, double lon) {
    if (!mounted) return;
    if (_lat == lat && _lon == lon) return;
    setState(() {
      _lat = lat;
      _lon = lon;
    });
  }

  Future<void> _cargarUbicacionEnSegundoPlano() async {
    if (_lat != null && _lon != null) return;

    try {
      final Position? last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        _aplicarCoords(last.latitude, last.longitude);
      }
    } catch (_) {}

    try {
      final ({bool serviceEnabled, LocationPermission permission}) snap =
          await GpsService.readServiceAndPermissionStabilizedNoRequest(
        extendedAfterPriorGrant:
            await LocationPermissionService.ubicacionConcedidaAntesEnPrefs(),
      );
      if (!mounted) return;
      if (!snap.serviceEnabled || !GpsService.permissionUsable(snap.permission)) {
        unawaited(RaiUbicacionClienteService.instance.refrescar());
        return;
      }

      final Position? pos = await GpsService.obtenerUbicacionActual(
        timeout: const Duration(seconds: 12),
        maxEdadUltima: const Duration(hours: 24),
      );
      if (pos != null) {
        _aplicarCoords(pos.latitude, pos.longitude);
      }
    } catch (_) {
      try {
        final Position? last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          _aplicarCoords(last.latitude, last.longitude);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color themedBg = Theme.of(context).scaffoldBackgroundColor;
    final Color sheetBg = CustomThemeService.cardOn(themedBg);
    final Color fg = CustomThemeService.textOn(sheetBg);
    final Color border = CustomThemeService.borderOn(sheetBg);
    final bool sheetDark =
        ThemeData.estimateBrightnessForColor(sheetBg) == Brightness.dark;
    final Color btnBg = sheetDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.07);

    return Stack(
      fit: StackFit.passthrough,
      children: [
        SelectorDestinosTuristicos(
          latOrigen: _lat,
          lonOrigen: _lon,
          tipoVehiculoInicial: widget.tipoVehiculoInicial,
          onDestinoSeleccionado: widget.onDestinoSeleccionado,
        ),
        if (widget.showFloatingBack)
          Positioned(
            top: 10,
            left: 12,
            child: SafeArea(
              bottom: false,
              child: Material(
                color: btnBg,
                shape: CircleBorder(
                  side: BorderSide(color: border),
                ),
                child: IconButton(
                  tooltip: 'Volver',
                  icon: Icon(Icons.arrow_back_rounded, color: fg),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
