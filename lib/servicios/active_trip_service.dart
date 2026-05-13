// lib/servicios/active_trip_service.dart
//
// Fuente única para saber si taxista o cliente tienen un viaje operativo activo
// (misma semántica que [ViajesRepo.getViajeActivoParaUsuario]).
//
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/servicios/rai_local_read_cache.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

/// Servicio central para shells y pantallas de “solicitud / home”.
class ActiveTripService {
  ActiveTripService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Evita que el shell quite [ViajeEnCursoCliente] en el instante en que
  /// `viajeActivoId` ya se limpió pero aún corre factura / post-viaje.
  static int _mantenerOverlayViajeHastaMs = 0;

  /// Mantiene el overlay de “viaje en curso” en el shell aunque el stream diga
  /// `false` (p. ej. transición a factura).
  static void mantenerOverlayViajeEnShell(Duration duracion) {
    final int hasta =
        DateTime.now().add(duracion).millisecondsSinceEpoch;
    if (hasta > _mantenerOverlayViajeHastaMs) {
      _mantenerOverlayViajeHastaMs = hasta;
      print(
          '[VIAJE_ACTIVO] ActiveTripService.mantenerOverlayViajeEnShell ${duracion.inSeconds}s');
    }
  }

  static bool get debeMantenerOverlayViajeEnShell =>
      DateTime.now().millisecondsSinceEpoch < _mantenerOverlayViajeHastaMs;

  /// Documento del viaje activo, o `null`.
  static Future<DocumentSnapshot<Map<String, dynamic>>?> obtenerDocumentoViajeActivo(
      String uid) {
    return ViajesRepo.getViajeActivoParaUsuario(uid);
  }

  /// `true` si hay un viaje activo verificado en servidor.
  static Future<bool> tieneViajeActivo(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return false;
    final snap = await obtenerDocumentoViajeActivo(u);
    final ok = snap != null && snap.exists;
    print('[VIAJE_ACTIVO] ActiveTripService.tieneViajeActivo($u) → $ok');
    return ok;
  }

  /// Emite `true`/`false` al cambiar `usuarios/{uid}` o el propio viaje enlazado
  /// (vía nueva lectura con [ViajesRepo.getViajeActivoParaUsuario]).
  static Stream<bool> streamTieneViajeActivo(String uid) {
    final u = uid.trim();
    if (u.isEmpty) return Stream<bool>.value(false);
    // Reduce lecturas a [getViajeActivoParaUsuario] cuando solo cambian campos
    // irrelevantes del perfil (misma huella de viaje activo).
    return _db
        .collection('usuarios')
        .doc(u)
        .snapshots()
        .map((DocumentSnapshot<Map<String, dynamic>> s) {
          final d = s.data();
          final vid = (d?['viajeActivoId'] ?? '').toString().trim();
          final ts = d?['updatedAt'] ?? d?['actualizadoEn'];
          return '$vid|${ts?.toString() ?? ''}';
        })
        .distinct()
        .asyncMap((_) async {
          final snap = await ViajesRepo.getViajeActivoParaUsuario(u);
          final ok = snap != null && snap.exists;
          print(
              '[VIAJE_ACTIVO] ActiveTripService.streamTieneViajeActivo($u) → $ok');
          if (ok) {
            unawaited(RaiLocalReadCache.rememberActiveTripId(u, snap.id));
          }
          return ok;
        });
  }
}
