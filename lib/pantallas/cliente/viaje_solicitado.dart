// lib/pantallas/cliente/viaje_solicitado.dart
//
// Punto único de redirección cuando el cliente tiene un viaje activo
// (p. ej. tras matar la app o volver del home) hacia [ClientePantallaViajeActivo].
//
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';

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
    if (ActiveTripService.clienteSuprimirOverlayViajeActivo) {
      print(
        '[VIAJE_ACTIVO] ViajeSolicitadoActivoBootstrap omitido (cotización)',
      );
      return;
    }
    if (ActiveTripService.debeForzarInicioClienteShell) {
      print(
        '[VIAJE_ACTIVO] ViajeSolicitadoActivoBootstrap omitido (forzar inicio)',
      );
      return;
    }
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    print(
        '[VIAJE_ACTIVO] ViajeSolicitadoActivoBootstrap init uid=$uid → comprobar activo');
    try {
      final DocumentSnapshot<Map<String, dynamic>>? snap =
          await ActiveTripService.obtenerDocumentoViajeActivo(uid);
      if (snap == null || !snap.exists) return;
      if (ActiveTripService.viajeClienteDescartadoEnSesion(snap.id)) return;
      if (await ViajesRepo.viajeQueryMatchEsFantasmaParaCliente(snap.id)) {
        print(
          '[VIAJE_ACTIVO] ViajeSolicitadoActivoBootstrap → viaje fantasma ${snap.id}',
        );
        await ActiveTripService.liberarClienteTrasViajeEliminado(
          snap.id,
          uid: uid,
        );
        return;
      }
      final Map<String, dynamic> d = snap.data() ?? <String, dynamic>{};
      if (ViajePoolTaxistaGate.clienteDebeVerConfirmacionProgramado(d)) {
        print(
          '[VIAJE_ACTIVO] ViajeSolicitadoActivoBootstrap → reserva programada',
        );
        return;
      }
      if (!ActiveTripService.viajeDocCuentaComoSeguimientoParaUsuario(d, uid)) {
        print(
          '[VIAJE_ACTIVO] ViajeSolicitadoActivoBootstrap → doc sin overlay id=${snap.id} estado=${d['estado']}',
        );
        return;
      }
      final String st =
          EstadosViaje.normalizar((d['estado'] ?? '').toString());
      if (d['completado'] == true || EstadosViaje.esTerminal(st)) {
        return;
      }
      if (!mounted) return;
      // Ya tenemos el doc (incl. query fallback); no repetir tieneViajeActivo
      // que solo lee viajeActivoId + GET directo y falla con permission-denied.
      print(
          '[VIAJE_ACTIVO] ViajeSolicitadoActivoBootstrap → overlay shell vid=${snap.id}');
      ActiveTripService.cancelarForzarInicioClienteShell();
      ActiveTripService.registrarViajeOperativoCliente(snap.id);
      ActiveTripService.mantenerOverlayViajeEnShell(
        ActiveTripService.kOverlayClienteViajeActivo,
      );
      ActiveTripService.notificarRebuildShell();
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
    if (ActiveTripService.debeForzarInicioClienteShell) {
      print(
        '[VIAJE_ACTIVO] ViajeSolicitadoActivo omitido (forzar inicio)',
      );
      return;
    }
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
      final Map<String, dynamic> d = snap.data() ?? <String, dynamic>{};
      if (ViajePoolTaxistaGate.clienteDebeVerConfirmacionProgramado(d)) {
        print(
          '[VIAJE_ACTIVO] ViajeSolicitadoActivo → confirmación programado',
        );
        await NavigationService.abrirConfirmacionProgramadoEnShell(
          viajeId: snap.id,
          fechaHoraPickup: ViajePoolTaxistaGate.fechaHoraDeViaje(d),
          preNav: nav,
        );
        return;
      }
      if (!ActiveTripService.viajeDocCuentaComoSeguimientoParaUsuario(d, uid)) {
        return;
      }
      print('[VIAJE_ACTIVO] ViajeSolicitadoActivo → clearAndGoViajeEnCursoCliente');
      await NavigationService.clearAndGoViajeEnCursoCliente(preNav: nav);
    } catch (e) {
      print('[VIAJE_ACTIVO] ViajeSolicitadoActivo error: $e');
    }
  }
}
