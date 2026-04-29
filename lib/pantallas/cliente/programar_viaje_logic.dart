// lib/pantallas/cliente/programar_viaje_logic.dart
//
// Nota de producción:
// Este archivo mantiene una implementación "logic" alternativa/legacy.
// El flujo principal debería preferir los controladores/servicios centrales
// (p.ej. `ViajesRepo`/widgets actuales) para evitar incoherencias.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/trip_publish_windows.dart';

class ProgramarViajeLogic {
  static Future<void> programar({
    required Viaje viaje,
    required String clienteId,
    required double kmEstimados,
    required double comision,
    required double gananciaTaxista,
  }) async {
    await RolesService.ensureUserDoc(clienteId, defaultRol: Roles.cliente);

    final metodo = viaje.metodoPago.toLowerCase().trim();
    final estadoInicial = (metodo == 'tarjeta')
        ? EstadosViaje.pendientePago
        : EstadosViaje.pendiente;

    // Flags de “ahora” vs “programado”
    final DateTime now = DateTime.now();
    final bool esAhora =
        TripPublishWindows.esAhoraPorFechaPickup(viaje.fechaHora, now);
    final DateTime publishInstant = esAhora
        ? now
        : ViajesRepo.poolOpensAtForScheduledPickup(viaje.fechaHora, now);
    final Timestamp publishAt = Timestamp.fromDate(publishInstant);

    final data = viaje
        .copyWith(
          uidCliente:
              viaje.uidCliente.isNotEmpty ? viaje.uidCliente : clienteId,
          clienteId: clienteId,
          estado: estadoInicial,
          aceptado: false,
          rechazado: false,
          completado: false,
        )
        .toCreateMap()
      ..addAll({
        'programado': !esAhora,
        'esAhora': esAhora,
        if (!esAhora) 'poolOpeningPushSent': false,
        'publishAt': publishAt,
        'acceptAfter': publishAt,
        // sin taxista asignado
        'uidTaxista': '',
        'taxistaId': '',
      })
      ..putIfAbsent('tomadoPor', () => null);

    // Validaciones defensivas
    bool _okLL(dynamic lat, dynamic lon) {
      if (lat is! num || lon is! num) return false;
      return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
    }

    if (!_okLL(data['latCliente'], data['lonCliente']) ||
        !_okLL(data['latDestino'], data['lonDestino'])) {
      throw Exception('Coordenadas inválidas.');
    }
    if (data['precio'] is! num || (data['precio'] as num) <= 0) {
      throw Exception('Precio inválido.');
    }

    await FirebaseFirestore.instance.collection('viajes').add(data);

    try {
      await FirebaseFirestore.instance.collection('logs_programacion').add({
        'clienteId': clienteId,
        'viajeCreadoEn': FieldValue.serverTimestamp(),
        'kmEstimados': kmEstimados,
        'comision': comision,
        'gananciaTaxista': gananciaTaxista,
        'metodoPago': viaje.metodoPago,
        'estadoInicial': estadoInicial,
        'programado': !esAhora,
      });
    } catch (_) {/* ignore */}
  }
}
