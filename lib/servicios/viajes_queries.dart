// lib/servicios/viajes_queries.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';

class ViajesQueries {
  static Query<Map<String, dynamic>> basePendientes() {
    return FirebaseFirestore.instance
        .collection('viajes')
        .where('estado', isEqualTo: EstadosViaje.pendiente)
        .where('aceptado', isEqualTo: false)
        .where('rechazado', isEqualTo: false)
        .where('completado', isEqualTo: false)
        .where('uidTaxista', isEqualTo: '');
  }

  /// Umbral de 10 min: <= AHORA, > PROGRAMADOS
  static ({Query<Map<String, dynamic>> ahora, Query<Map<String, dynamic>> programados})
      splitAhoraProgramados() {
    final now = DateTime.now();
    final threshold = Timestamp.fromDate(now.add(const Duration(minutes: 10)));

    final ahora = basePendientes()
        .where('fechaHora', isLessThanOrEqualTo: threshold)
        .orderBy('fechaHora', descending: true)
        .limit(50);

    final programados = basePendientes()
        .where('fechaHora', isGreaterThan: threshold)
        .orderBy('fechaHora', descending: true)
        .limit(50);

    return (ahora: ahora, programados: programados);
  }
}
