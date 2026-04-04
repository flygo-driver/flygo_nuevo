// lib/servicios/ubicacion_taxista.dart
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UbicacionTaxista {
  static StreamSubscription<Position>? _subscription;
  static bool _isActive = false;

  /// Inicia la escucha de la ubicación en tiempo real.
  /// Si `soloCuandoDisponible` es true (por defecto), solo publicará la ubicación
  /// si el taxista está disponible (sin viaje activo). Debe llamarse en la pantalla
  /// de viajes disponibles (cuando el taxista está disponible).
  static void iniciarActualizacion({bool soloCuandoDisponible = true}) {
    if (_isActive) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _subscription = Geolocator.getPositionStream(locationSettings: settings).listen((Position pos) async {
      // Siempre actualizar la colección taxistas (para administración)
      await FirebaseFirestore.instance.collection('taxistas').doc(user.uid).set({
        'ubicacion': GeoPoint(pos.latitude, pos.longitude),
        'ultimaActualizacion': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // ✅ Determinar si el taxista tiene viaje activo
      bool tieneViajeActivo = false;
      if (soloCuandoDisponible) {
        final userDoc = await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get();
        tieneViajeActivo = (userDoc.data()?['viajeActivoId'] as String?)?.isNotEmpty == true;
      }

      // ✅ Siempre publicar en drivers_location con online = !tieneViajeActivo
      await FirebaseFirestore.instance.collection('drivers_location').doc(user.uid).set({
        'location': GeoPoint(pos.latitude, pos.longitude),
        'online': !tieneViajeActivo,   // true si libre, false si ocupado
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    _isActive = true;
  }

  /// Detiene la escucha de ubicación y elimina el registro de drivers_location
  /// (para que el taxista desaparezca del mapa de clientes).
  static Future<void> detenerActualizacion() async {
    if (_subscription != null) {
      await _subscription!.cancel();
      _subscription = null;
    }
    _isActive = false;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Marcar como offline en drivers_location
      await FirebaseFirestore.instance.collection('drivers_location').doc(user.uid).set({
        'online': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Marca al taxista como "no disponible" (oculta del mapa de clientes)
  /// sin detener la escucha de ubicación.
  static Future<void> marcarNoDisponible() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('drivers_location').doc(user.uid).set({
        'online': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Marca al taxista como "disponible" (visible en el mapa de clientes)
  static Future<void> marcarDisponible() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('drivers_location').doc(user.uid).set({
        'online': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Obtiene la ubicación actual una sola vez.
  static Future<Position> obtenerUbicacionActual() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Servicios de ubicación desactivados');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Permisos de ubicación denegados');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Permisos de ubicación denegados permanentemente');
    }

    return await Geolocator.getCurrentPosition();
  }

  /// Stream de la ubicación actual (solo datos, sin actualizar Firestore).
  static Stream<Position> obtenerStreamUbicacion() {
    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}