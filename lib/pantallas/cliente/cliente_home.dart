// lib/pantallas/cliente/cliente_home.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

// Rol del usuario para decidir si auto-navegar
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/widgets/cliente_drawer.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/widgets/auto_trip_router.dart';

class ClienteHome extends StatefulWidget {
  const ClienteHome({super.key});
  @override
  State<ClienteHome> createState() => _ClienteHomeState();
}

class _ClienteHomeState extends State<ClienteHome> {
  bool _navegueAProgramar = false;

  bool _esTaxista(Map<String, dynamic>? userData) {
    if (userData == null) return false;
    final rol = (userData['rol'] ?? userData['role'] ?? '').toString().toLowerCase();
    final esTx = userData['esTaxista'] == true || userData['isDriver'] == true;
    return rol == 'taxista' || rol == 'driver' || esTx;
  }

  void _irAProgramarAhora() {
    if (!mounted || _navegueAProgramar) return;
    _navegueAProgramar = true;

    // Envolvemos ProgramarViaje con ClienteTripRouter para que
    // al crear el viaje, navegue solo a "Viaje en curso".
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const ClienteTripRouter(
          child: ProgramarViaje(modoAhora: true),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return ClienteTripRouter( // router pasivo SIEMPRE activo en Home
      child: Scaffold(
        backgroundColor: Colors.black,
        drawer: const ClienteDrawer(),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          centerTitle: true,
          title: Image.asset(
            'assets/icon/logo_flygo.png',
            height: 28,
            filterQuality: FilterQuality.high,
          ),
          leading: Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              tooltip: 'Menú',
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
        ),
        // Mapa siempre visible de fondo. Si es cliente, navega a Programar.
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: (user == null)
              ? const Stream.empty()
              : FirebaseFirestore.instance.collection('usuarios').doc(user.uid).snapshots(),
          builder: (context, snap) {
            // Mientras carga o no hay user ⇒ sólo mapa
            if (user == null ||
                snap.connectionState == ConnectionState.waiting ||
                !snap.hasData ||
                !snap.data!.exists) {
              return const MapaTiempoReal();
            }

            final data = Map<String, dynamic>.from(snap.data!.data() ?? <String, dynamic>{});
            final esTaxista = _esTaxista(data);

            // Si es cliente ⇒ navegar a ProgramarViaje UNA sola vez
            if (!esTaxista) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _irAProgramarAhora());
            }

            // Siempre dejamos el mapa de fondo
            return const MapaTiempoReal();
          },
        ),
      ),
    );
  }
}

/* ======================  MAPA EN TIEMPO REAL  ====================== */

class MapaTiempoReal extends StatefulWidget {
  const MapaTiempoReal({super.key});
  @override
  State<MapaTiempoReal> createState() => _MapaTiempoRealState();
}

class _MapaTiempoRealState extends State<MapaTiempoReal> {
  GoogleMapController? _map;
  StreamSubscription<Position>? _posSub;

  static const LatLng _fallback = LatLng(18.4861, -69.9312); // SDQ
  final Set<Marker> _markers = <Marker>{};
  bool _myLocEnabled = false;
  bool _movingCamera = false;

  @override
  void initState() {
    super.initState();
    _iniciarUbicacion();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _iniciarUbicacion() async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activa la ubicación del dispositivo')),
      );
    }

    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (!mounted) return;

    final denied = p == LocationPermission.denied || p == LocationPermission.deniedForever;
    setState(() => _myLocEnabled = !denied);
    if (denied) return;

    final last = await Geolocator.getLastKnownPosition();
    if (!mounted) return;
    if (last != null) {
      final here = LatLng(last.latitude, last.longitude);
      _putMarker(here);
      _moverCamara(here, zoom: 15);
    }

    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      final here = LatLng(pos.latitude, pos.longitude);
      _putMarker(here);
      if (!_movingCamera) _moverCamara(here, zoom: 16);
    });
  }

  void _putMarker(LatLng p) {
    _markers
      ..removeWhere((m) => m.markerId == const MarkerId('yo'))
      ..add(Marker(
        markerId: const MarkerId('yo'),
        position: p,
        infoWindow: const InfoWindow(title: 'Mi ubicación'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        // evita deprecated zIndex (double)
        zIndexInt: 2,
      ));
    if (mounted) setState(() {});
  }

  Future<void> _moverCamara(LatLng p, {double zoom = 15}) async {
    final c = _map;
    if (c == null) return;
    _movingCamera = true;
    try {
      await c.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: p, zoom: zoom)),
      );
    } catch (_) {
      try {
        c.moveCamera(CameraUpdate.newLatLngZoom(p, zoom));
      } catch (_) {}
    } finally {
      _movingCamera = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox.expand(
          child: GoogleMap(
            initialCameraPosition: const CameraPosition(target: _fallback, zoom: 12),
            onMapCreated: (ctrl) => _map = ctrl,
            myLocationEnabled: _myLocEnabled,
            myLocationButtonEnabled: false,
            compassEnabled: true,
            zoomControlsEnabled: false,
            markers: _markers,
            onCameraMoveStarted: () => _movingCamera = true,
            onCameraIdle: () => _movingCamera = false,
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            onPressed: () async {
              if (!_myLocEnabled) return;
              final pos = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.bestForNavigation,
              );
              if (!mounted) return;
              final here = LatLng(pos.latitude, pos.longitude);
              _putMarker(here);
              _moverCamara(here, zoom: 16);
            },
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }
}
