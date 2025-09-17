// lib/servicios/logout.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

// Para navegar aunque no haya context montado
import 'package:flygo_nuevo/servicios/navigation_service.dart';

Future<void> cerrarSesion(BuildContext? context) async {
  // Feedback corto (si hay contexto vivo)
  try {
    if (context != null && context.mounted) {
      final m = ScaffoldMessenger.of(context);
      m.hideCurrentSnackBar();
      m.showSnackBar(const SnackBar(content: Text('Cerrando sesión...')));
    }
  } catch (_) {}

  try {
    // 1) Cerrar proveedores externos (best-effort)
    try { await GoogleSignIn().signOut(); } catch (_) {}
    try { await GoogleSignIn().disconnect(); } catch (_) {}

    // 2) Firebase sign out (bloqueante)
    await FirebaseAuth.instance.signOut();

    // 3) Esperar a que el auth se vuelva null (evita regresos raros)
    try {
      await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u == null)
          .timeout(const Duration(seconds: 2));
    } catch (_) {}

    // 4) Navegación FUERTE al gate de auth usando el navigator global
    final nav = NavigationService.navigatorKey.currentState;
    if (nav != null) {
      nav.pushNamedAndRemoveUntil('/auth_check', (route) => false);
      return;
    }

    // Fallback: si no hay navigatorKey, intenta con el context (root)
    if (context != null && context.mounted) {
      Navigator.of(context, rootNavigator: true)
          .pushNamedAndRemoveUntil('/auth_check', (route) => false);
    }
  } catch (e) {
    // Error visible si hay contexto
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cerrar sesión: $e')),
      );
    }
  }
}
