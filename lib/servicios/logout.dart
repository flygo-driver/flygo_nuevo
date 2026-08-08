// lib/servicios/logout.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flygo_nuevo/servicios/google_auth.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/rai_modo_sesion_service.dart';

/// Cierra Google + Firebase Auth y espera a que `currentUser` quede null.
Future<void> cerrarSesionAuthOnly() async {
  try {
    await GoogleAuthService.clearGoogleSignInSession();
  } catch (_) {}

  await FirebaseAuth.instance.signOut();
  RaiModoSesionService.limpiarAlCerrarSesion();

  try {
    await FirebaseAuth.instance
        .authStateChanges()
        .firstWhere((u) => u == null)
        .timeout(const Duration(seconds: 3));
  } catch (_) {}
}

/// Cierra sesión y navega al gate raíz → [SeleccionUsuario] si no hay usuario.
/// Usar desde cliente, taxista y pantallas de bloqueo (mismo flujo coherente).
Future<void> cerrarSesion(BuildContext? context) async {
  try {
    if (context != null && context.mounted) {
      final m = ScaffoldMessenger.of(context);
      m.hideCurrentSnackBar();
      m.showSnackBar(const SnackBar(content: Text('Cerrando sesión...')));
    }
  } catch (_) {}

  try {
    await cerrarSesionAuthOnly();

    final nav = NavigationService.navigatorKey.currentState;
    if (nav != null && nav.mounted) {
      await nav.pushNamedAndRemoveUntil('/auth_check', (route) => false);
      return;
    }

    if (context != null && context.mounted) {
      await Navigator.of(context, rootNavigator: true)
          .pushNamedAndRemoveUntil('/auth_check', (route) => false);
    }
  } catch (e) {
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cerrar sesión: $e')),
      );
    }
  }
}
