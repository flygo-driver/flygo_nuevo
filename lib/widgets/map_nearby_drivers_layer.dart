import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:flygo_nuevo/servicios/drivers_location_nearby_repo.dart';
import 'package:flygo_nuevo/widgets/rai_live_driver_map_animator.dart';
import 'package:flygo_nuevo/widgets/rai_map_vehicle_icons.dart';

/// Conductores con GPS activo cerca del punto indicado (mapa booking / origen).
class MapNearbyDriversLayer extends StatefulWidget {
  const MapNearbyDriversLayer({
    super.key,
    required this.center,
    this.tipoServicio,
    this.enabled = true,
    this.radiusKm = 25,
    required this.onMarkersChanged,
  });

  final LatLng? center;
  final String? tipoServicio;
  final bool enabled;
  final double radiusKm;
  final void Function(Set<Marker> markers) onMarkersChanged;

  @override
  State<MapNearbyDriversLayer> createState() => _MapNearbyDriversLayerState();
}

class _MapNearbyDriversLayerState extends State<MapNearbyDriversLayer>
    with SingleTickerProviderStateMixin {
  DriversLocationNearbySession? _session;
  late final RaiLiveDriverMapAnimator _anim;
  List<RaiLiveDriverPoint> _conductores = const <RaiLiveDriverPoint>[];

  @override
  void initState() {
    super.initState();
    _anim = RaiLiveDriverMapAnimator(vsync: this)
      ..onFrame = _emitMarkers;
    unawaited(RaiMapVehicleIcons.ensureLoaded());
    _syncSession();
  }

  @override
  void didUpdateWidget(MapNearbyDriversLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.center != widget.center ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.tipoServicio != widget.tipoServicio) {
      _syncSession();
    }
  }

  @override
  void dispose() {
    _session?.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _syncSession() {
    _session?.dispose();
    _session = null;
    _conductores = const <RaiLiveDriverPoint>[];
    _anim.syncTargets(const <RaiLiveDriverPoint>[]);

    final LatLng? center = widget.center;
    if (!widget.enabled || center == null) {
      widget.onMarkersChanged(const <Marker>{});
      return;
    }

    _session = DriversLocationNearbyRepo.createSession(
      initialCenter: center,
      uidCliente: FirebaseAuth.instance.currentUser?.uid,
      tipoServicioViaje: widget.tipoServicio,
      radiusKm: widget.radiusKm,
      maxResultados: 40,
      onUpdate: (DriversLocationNearbyUpdate update) {
        _conductores = update.conductores;
        _anim.syncTargets(update.conductores);
        _emitMarkers();
      },
    );
  }

  void _emitMarkers() {
    if (!mounted) return;
    final Set<Marker> out = <Marker>{};
    for (final RaiLiveDriverPoint d in _conductores) {
      final LatLng pos = _anim.displayPositions[d.uid] ?? d.position;
      final double bearing = _anim.bearingFor(d.uid);
      final BitmapDescriptor? icon = RaiMapVehicleIcons.iconoVistaCliente(
        esMiConductor: false,
        faseRecogida: false,
      );
      out.add(
        Marker(
          markerId: MarkerId('drv_${d.uid}'),
          position: pos,
          icon: icon ??
              BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueOrange,
              ),
          rotation: icon != null
              ? RaiMapVehicleIcons.rotationTaxiCliente(bearing)
              : 0,
          flat: icon != null,
          anchor: icon != null
              ? const Offset(0.5, 0.5)
              : const Offset(0.5, 1.0),
          zIndexInt: 3,
        ),
      );
    }
    widget.onMarkersChanged(out);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
