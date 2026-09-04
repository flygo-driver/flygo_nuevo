import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/app_flavor.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_hub_page.dart';
import 'package:flygo_nuevo/pantallas/taxista/mis_rutas_corporativas_page.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_encargado_deep_link.dart';
import 'package:flygo_nuevo/servicios/fcm_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/shell/cliente_pool_deep_link_bridge.dart';

/// Enrutado único de taps de push (remoto o local) — evita ciclos FCM↔Push.
abstract final class PushOpenRouter {
  PushOpenRouter._();

  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static bool _esTipoCorporativo(String type) =>
      type.startsWith('corporativo_');

  static bool _esEncargadoPush(Map<String, dynamic> data) =>
      (data['rol'] ?? '').toString().trim().toLowerCase() == 'encargado';

  static Future<User?> _usuarioTrasArranque() async {
    User? u = _auth.currentUser;
    if (u == null) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      u = _auth.currentUser;
    }
    return u;
  }

  static Future<void> handleOpenedPushData(Map<String, dynamic> data) async {
    final String type = (data['type'] ?? '').toString();
    if (type == 'trip_chat_message' || type == 'trip_call_attempt') {
      debugPrint('[FCM] opened: trip comms type=$type');
      await FcmService.openTripFromPushData(data);
      return;
    }
    if (type.startsWith('gira_cupos_recordatorio_') ||
        type == 'gira_cupos_actualizada' ||
        type == 'gira_cupos_catalogo') {
      if (!isPasajeroCapableFlavor) return;
      final poolId = (data['poolId'] ?? '').toString().trim();
      if (poolId.isEmpty ||
          type == 'gira_cupos_catalogo' ||
          poolId == 'giras_cupos_catalogo') {
        ClientePoolDeepLinkBridge.enqueueGirasLista();
        ClientePoolDeepLinkBridge.tryOpenGirasLista();
        return;
      }
      ClientePoolDeepLinkBridge.enqueuePoolId(poolId);
      ClientePoolDeepLinkBridge.tryOpenPool(poolId);
      return;
    }

    if (_esTipoCorporativo(type)) {
      // Encargado solo en portal web empresa. En APK conductor (o app unificada
      // como chofer) siempre vista taxista — evita sacar al chofer si la misma
      // cuenta también es encargado y le llegan dos pushes.
      if (_esEncargadoPush(data) && kIsWeb && _enRutaWebCorporativo()) {
        await _abrirCorporativoEncargado(data);
        return;
      }
      if (isTaxistaCapableFlavor) {
        await _abrirCorporativoChofer(type, data);
        return;
      }
      if (_esEncargadoPush(data)) {
        await _abrirCorporativoEncargado(data);
      }
      return;
    }

    if (type != 'scheduled_trip_pool_open') return;

    final String viajeId = (data['viajeId'] ?? '').toString().trim();
    if (viajeId.isEmpty) return;

    final NavigatorState? preNav = NavigationService.navigatorKey.currentState;
    final u = await _usuarioTrasArranque();
    if (u == null) return;

    final snap = await _db.collection('viajes').doc(viajeId).get();
    if (!snap.exists) return;
    final vd = snap.data()!;
    final String cid =
        (vd['uidCliente'] ?? vd['clienteId'] ?? '').toString().trim();
    if (cid != u.uid) return;

    await _db.collection('usuarios').doc(u.uid).set(
      {
        'viajeActivoId': viajeId,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    ActiveTripService.cancelarForzarInicioClienteShell();
    ActiveTripService.registrarViajeOperativoCliente(viajeId);

    await NavigationService.clearAndGoViajeEnCursoCliente(preNav: preNav);
  }

  /// Portal empresa en navegador (encargado).
  static bool _enRutaWebCorporativo() {
    final path = Uri.base.path.replaceAll(RegExp(r'/+$'), '');
    return path == '/empresas' ||
        path.startsWith('/empresas/') ||
        path == '/corporativo' ||
        path.startsWith('/corporativo/') ||
        path == '/login/corporativo' ||
        path.startsWith('/login/corporativo');
  }

  static Future<void> _abrirCorporativoEncargado(
    Map<String, dynamic> data,
  ) async {
    CorporativoEncargadoDeepLinkBridge.ingestPushData(data);

    if (kIsWeb) {
      CorporativoEncargadoDeepLinkBridge.tryFlush();
      return;
    }

    final nav = NavigationService.navigatorKey.currentState;
    if (nav == null) return;
    await nav.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const CorporativoHubPage(),
      ),
      (route) => false,
    );
    CorporativoEncargadoDeepLinkBridge.tryFlush();
  }

  static Future<void> _abrirCorporativoChofer(
    String type,
    Map<String, dynamic> data,
  ) async {
    if (type == 'corporativo_chofer_asignado') {
      await NavigationService.clearAndGo(const MisRutasCorporativasPage());
      return;
    }

    const soloMisRutas = <String>{
      'corporativo_feriado',
      'corporativo_feriado_calendario',
      'corporativo_pausa_total',
      'corporativo_reactivar',
      'corporativo_quitar_pasajero',
      'corporativo_agregar_pasajero',
      'corporativo_aviso_confirmar',
      'corporativo_sustituto',
    };

    final NavigatorState? preNav = NavigationService.navigatorKey.currentState;
    final u = await _usuarioTrasArranque();
    if (u == null) return;

    // Ruta operativa: abrir viaje si hay id; si no, Mis rutas sin matar el shell.
    if (type == 'corporativo_ruta_operativa') {
      final viajeId = (data['viajeId'] ?? '').toString().trim();
      if (viajeId.isNotEmpty) {
        await NavigationService.abrirViajeCorporativoTaxista(
          uidTaxista: u.uid,
          viajeId: viajeId,
          preNav: preNav,
        );
      } else {
        final nav = preNav ?? NavigationService.navigatorKey.currentState;
        if (nav != null && nav.mounted) {
          await nav.push(
            MaterialPageRoute<void>(
              builder: (_) => const MisRutasCorporativasPage(),
            ),
          );
        }
      }
      return;
    }

    if (soloMisRutas.contains(type)) {
      final nav = preNav ?? NavigationService.navigatorKey.currentState;
      if (nav != null && nav.mounted) {
        await nav.push(
          MaterialPageRoute<void>(
            builder: (_) => const MisRutasCorporativasPage(),
          ),
        );
      }
      return;
    }

    if (type == 'corporativo_cambio_hora') {
      final viajeId = (data['viajeId'] ?? '').toString().trim();
      if (viajeId.isNotEmpty) {
        await NavigationService.abrirViajeCorporativoTaxista(
          uidTaxista: u.uid,
          viajeId: viajeId,
          preNav: preNav,
        );
      } else {
        await NavigationService.clearAndGo(const MisRutasCorporativasPage());
      }
      return;
    }

    if (type == 'corporativo_asignado' || type == 'corporativo_ruta_fija') {
      final viajeId = (data['viajeId'] ?? '').toString().trim();
      await NavigationService.abrirViajeCorporativoTaxista(
        uidTaxista: u.uid,
        viajeId: viajeId.isNotEmpty ? viajeId : null,
        preNav: preNav,
      );
      return;
    }

    await NavigationService.clearAndGo(const MisRutasCorporativasPage());
  }
}
