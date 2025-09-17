// lib/servicios/pool_reservas_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class PoolReservasService {
  static final _pools = FirebaseFirestore.instance.collection('pools');

  /// Crea una reserva del cliente con verificación de cupo.
  /// Devuelve el ID de la reserva.
  static Future<String> crearReserva({
    required String poolId,
    required String uidCliente,
    required int seats,
    required String metodoPago,      // 'transferencia' | 'efectivo'
    required double total,
    required double deposit,         // si transferencia, el depósito esperado
    required String referencia,      // referencia sugerida
  }) async {
    return FirebaseFirestore.instance.runTransaction((tx) async {
      final poolRef = _pools.doc(poolId);
      final poolSnap = await tx.get(poolRef);
      if (!poolSnap.exists) {
        throw 'El viaje no existe.';
      }
      final data = poolSnap.data()!;
      final cap = (data['capacidad'] ?? 0) as int;
      final occ = (data['asientosReservados'] ?? 0) as int;

      if (seats <= 0) throw 'Asientos inválidos.';
      if (occ + seats > cap) throw 'No hay cupos suficientes.';

      final reservasRef = poolRef.collection('reservas').doc();

      final estado = (metodoPago.toLowerCase() == 'efectivo')
          ? 'reservado_efectivo'   // paga al abordar
          : 'pendiente_pago';       // subirá comprobante y validamos

      tx.set(reservasRef, {
        'uidCliente': uidCliente,
        'seats': seats,
        'metodoPago': metodoPago.toLowerCase(),
        'total': total,
        'deposit': deposit,
        'referencia': referencia,
        'estado': estado,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Actualiza ocupación y monto reservado (solo transferencia suma depósito como "reservado")
      tx.update(poolRef, {
        'asientosReservados': FieldValue.increment(seats),
        if (metodoPago.toLowerCase() == 'transferencia')
          'montoReservado': FieldValue.increment(deposit),
      });

      return reservasRef.id;
    });
  }
}
