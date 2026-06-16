// lib/pantallas/cliente/viaje_solicitado.dart
//
// Punto único de redirección cuando el cliente tiene un viaje activo
// (p. ej. tras matar la app o volver del home) hacia [ClientePantallaViajeActivo].
//
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';

/// Al montar [child] (p. ej. [ClienteHome] en la pestaña Inicio), redirige a
/// [ClientePantallaViajeActivo] si el servidor reporta un viaje activo.
class ViajeSolicitadoActivoBootstrap extends StatefulWidget {
  const ViajeSolicitadoActivoBootstrap({super.key, required this.child});

  final Widget child;

  @override
  State<ViajeSolicitadoActivoBootstrap> createState() =>
      _ViajeSolicitadoActivoBootstrapState();
}

class _ViajeSolicitadoActivoBootstrapState
    extends State<ViajeSolicitadoActivoBootstrap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_redirigirSiCorresponde());
    });
  }

  Future<void> _redirigirSiCorresponde() async {
    if (!mounted) return;
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    NavigatorState? preNav = NavigationService.navigatorKey.currentState;
    if (preNav == null && mounted) {
      preNav = Navigator.of(context, rootNavigator: true);
    }
    print(
        '[VIAJE_ACTIVO] ViajeSolicitadoActivoBootstrap init uid=$uid → comprobar activo');
    try {
      final bool ok = await ActiveTripService.tieneViajeActivo(uid);
      if (!mounted || !ok) return;
      print(
          '[VIAJE_ACTIVO] ViajeSolicitadoActivoBootstrap → clearAndGoViajeEnCursoCliente');
      await NavigationService.clearAndGoViajeEnCursoCliente(preNav: preNav);
    } catch (e) {
      print('[VIAJE_ACTIVO] ViajeSolicitadoActivoBootstrap error: $e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class ViajeSolicitadoActivo {
  ViajeSolicitadoActivo._();

  /// Si hay viaje activo para el usuario autenticado, reemplaza la ruta actual
  /// por la pantalla de viaje en curso (usa [addPostFrameCallback] desde el caller).
  static Future<void> redirigirSiHayViajeActivo(
    BuildContext context, {
    NavigatorState? preNav,
  }) async {
    if (!context.mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    NavigatorState? nav = preNav ?? NavigationService.navigatorKey.currentState;
    if (nav == null && context.mounted) {
      nav = Navigator.of(context, rootNavigator: true);
    }
    print('[VIAJE_ACTIVO] ViajeSolicitadoActivo.redirigirSiHayViajeActivo uid=$uid');
    try {
      final snap = await ActiveTripService.obtenerDocumentoViajeActivo(uid);
      if (snap == null || !snap.exists) return;
      print('[VIAJE_ACTIVO] ViajeSolicitadoActivo → clearAndGoViajeEnCursoCliente');
      await NavigationService.clearAndGoViajeEnCursoCliente(preNav: nav);
    } catch (e) {
      print('[VIAJE_ACTIVO] ViajeSolicitadoActivo error: $e');
    }
  }
}
