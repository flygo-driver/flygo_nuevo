// lib/pantallas/taxista/viaje_en_curso_taxista_logic.dart
//
// Nota de producción:
// Implementación alternativa/legacy para "completar" y asentar pagos.
// El flujo principal actual debe ser el de las pantallas/controladores
// que usan `ViajesRepo`/`PagoData` directamente.
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data/pago_data.dart';
import '../../data/viaje_data.dart';
import '../../modelo/viaje.dart';

class ViajeEnCursoTaxistaLogic {
  /// Completa el viaje y asienta el pago:
  /// - Tarjeta: captura cargo (si estaba autorizado).
  /// - Efectivo: registra comisión pendiente para el taxista.
  static Future<void> completarYAsentar({
    required Viaje viaje,
    required String uidTaxista,
    String? emailTaxista,
  }) async {
    final db = FirebaseFirestore.instance;
    final docRef = db.collection('viajes').doc(viaje.id);
    final snap = await docRef.get();
    final data = snap.data() ?? {};

    final metodo = (data['metodoPago'] ?? viaje.metodoPago ?? 'Efectivo')
        .toString();
    final payment = (data['payment'] ?? {}) as Map<String, dynamic>;
    final paymentStatus = (payment['status'] ?? '').toString();
    final paymentIntentId = (payment['paymentIntentId'] ?? '').toString();

    final total = (data['precio'] ?? viaje.precio) as num;
    final comision = ((data['comision'] ?? 0) as num) > 0
        ? (data['comision'] as num).toDouble()
        : double.parse((total * 0.20).toStringAsFixed(2));
    final driverAmount = ((data['gananciaTaxista'] ?? 0) as num) > 0
        ? (data['gananciaTaxista'] as num).toDouble()
        : double.parse((total * 0.80).toStringAsFixed(2));

    if (metodo == 'Tarjeta') {
      if (paymentStatus != 'captured') {
        await PagoData.capturarPago(
          viajeId: viaje.id,
          paymentIntentId: paymentIntentId.isEmpty
              ? 'pi_mock_${viaje.id}'
              : paymentIntentId,
          montoFinalDop: total.toDouble(),
          comision: comision,
          gananciaTaxista: driverAmount,
          uidTaxista: uidTaxista,
          emailTaxista: emailTaxista,
        );
      }
      await ViajeData.completarViaje(viaje.id);
    } else {
      await PagoData.registrarComisionCash(
        viajeId: viaje.id,
        taxistaId: uidTaxista,
        comision: comision,
      );
      await ViajeData.completarViaje(viaje.id);
    }
  }
}
