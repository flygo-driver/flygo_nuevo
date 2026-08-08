// lib/servicios/rai_cambio_modo_sesion.dart
//
// Cambio in-app taxista ↔ pasajero (mismo correo, sin tocar `rol` en Firestore).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/auth/rai_identity_router.dart';
import 'package:flygo_nuevo/pantallas/taxista/entry_taxista.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/pool_timbre_session_guard.dart';
import 'package:flygo_nuevo/servicios/rai_modo_sesion_service.dart';
import 'package:flygo_nuevo/servicios/ubicacion_taxista.dart';
import 'package:flygo_nuevo/shell/cliente_shell.dart';
import 'package:flygo_nuevo/widgets/verify_email_gate.dart';

/// Color rojo chino para el control de cambio de modo.
const Color kRaiCambioModoRojoChino = Color(0xFFDE2910);

/// Separación extra de la barra sobre la navegación inferior.
const double kRaiCambioModoSesionMargenSobreNav = 20;

/// Altura aproximada de la barra (para padding del scroll en Cuenta).
const double kRaiCambioModoSesionBarAltura = 68;

/// Padding extra al final de la lista Cuenta cuando la barra está visible.
const double kRaiCambioModoSesionPaddingLista =
    kRaiCambioModoSesionBarAltura + kRaiCambioModoSesionMargenSobreNav + 12;

abstract final class RaiCambioModoSesion {
  RaiCambioModoSesion._();

  static Future<void> cambiarAPasajero(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final bloqueo = await _validarCambioAPasajero(uid);
    if (bloqueo != null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(bloqueo)),
      );
      return;
    }

    if (!context.mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usar como pasajero'),
        content: const Text(
          'Vas a cambiar a modo pasajero con la misma cuenta.\n\n'
          '• Se desactivará tu disponibilidad como conductor\n'
          '• Podrás pedir viajes como cliente\n'
          '• Podrás volver a conductor desde Cuenta',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kRaiCambioModoRojoChino,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cambiar a pasajero'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _ponerConductorOffline(uid);
      await RaiModoSesionService.activarModoPasajero(uid);
      PoolTimbreSessionGuard.activarSesionPasajero();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cambiar de modo: $e')),
      );
      return;
    }

    if (!context.mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const VerifyEmailGate(
          childWhenVerified: ClienteShellWithDeepLink(),
        ),
      ),
      (_) => false,
    );
  }

  static Future<void> cambiarAConductor(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final bloqueo = await _validarCambioAConductor(uid);
    if (bloqueo != null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(bloqueo)),
      );
      return;
    }

    if (!context.mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Volver a conductor'),
        content: const Text(
          'Vas a salir del modo pasajero y volver a operar como conductor '
          'con la misma cuenta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kRaiCambioModoRojoChino,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Volver a conductor'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await RaiModoSesionService.activarModoConductor(uid);
      PoolTimbreSessionGuard.activarSesionConductor();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cambiar de modo: $e')),
      );
      return;
    }

    if (!context.mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const RaiTaxistaAccessGate(child: TaxistaEntry()),
      ),
      (_) => false,
    );
  }

  static Future<String?> _validarCambioAPasajero(String uid) async {
    if (await ActiveTripService.tieneViajeActivo(uid)) {
      return 'Tienes un viaje activo como conductor. '
          'Finalízalo o ciérralo antes de cambiar a pasajero.';
    }

    final snap = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .get();
    final data = snap.data() ?? <String, dynamic>{};
    if (data['disponible'] == true) {
      // Se desactiva al cambiar; solo avisamos si hay viaje en pool aceptado.
      final vid = (data['viajeActivoId'] ?? '').toString().trim();
      if (vid.isNotEmpty) {
        return 'Tienes un viaje en curso. Resuélvelo antes de cambiar a pasajero.';
      }
    }
    return null;
  }

  static Future<String?> _validarCambioAConductor(String uid) async {
    if (await ActiveTripService.clienteTieneViajeEnSeguimiento(uid)) {
      return 'Tienes un viaje activo como pasajero. '
          'Finalízalo antes de volver a conductor.';
    }
    if (await ActiveTripService.tieneViajeActivo(uid)) {
      return 'Tienes un viaje activo. Finalízalo antes de volver a conductor.';
    }
    return null;
  }

  static Future<void> _ponerConductorOffline(String uid) async {
    await UbicacionTaxista.detenerActualizacion();
    await FirebaseFirestore.instance.collection('usuarios').doc(uid).set(
      <String, dynamic>{
        'disponible': false,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
