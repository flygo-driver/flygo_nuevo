// lib/pantallas/cliente/programar_viaje_logic.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';

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
    final estadoInicial =
        (metodo == 'tarjeta') ? EstadosViaje.pendientePago : EstadosViaje.pendiente;

    // Flags de “ahora” vs “programado”
    final bool esAhora = viaje.fechaHora.isBefore(
      DateTime.now().add(const Duration(minutes: 15)),
    );
    final Timestamp publishAt = esAhora
        ? Timestamp.fromDate(DateTime.now())
        : Timestamp.fromDate(viaje.fechaHora.subtract(const Duration(minutes: 30)));

    final data = viaje
        .copyWith(
          uidCliente: viaje.uidCliente.isNotEmpty ? viaje.uidCliente : clienteId,
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
        'publishAt': publishAt,
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
