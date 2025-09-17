// lib/servicios/admin_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../modelo/liquidacion.dart';

class AdminService {
  static final _db = FirebaseFirestore.instance;
  static final _liquidas = _db.collection('liquidaciones');

  /// Streams por estado (pendiente / aprobado / rechazado)
  static Stream<List<Liquidacion>> streamLiquidacionesPorEstado(
    String estado, {
    String? query,
  }) {
    final base = _liquidas
        .where('estado', isEqualTo: estado)
        .orderBy('solicitadoEn', descending: true);

    return base.snapshots().map((s) {
      final list = s.docs
          .map((d) => Liquidacion.fromMap(d.id, d.data()))
          .toList();
      if (query == null || query.trim().isEmpty) return list;

      final q = query.trim().toLowerCase();
      // filtro simple por uid (directo) o notaAdmin
      return list.where((l) {
        final nota = (l.notaAdmin ?? '').toLowerCase();
        return l.uidTaxista.toLowerCase().contains(q) || nota.contains(q);
      }).toList();
    });
  }

  /// Actualiza estado con nota y timestamp de resolución
  static Future<void> resolverLiquidacion({
    required String id,
    required String nuevoEstado, // 'aprobado' | 'rechazado'
    String? notaAdmin,
  }) async {
    assert(nuevoEstado == 'aprobado' || nuevoEstado == 'rechazado');
    final ref = _liquidas.doc(id);
    await ref.update({
      'estado': nuevoEstado,
      'resueltoEn': FieldValue.serverTimestamp(),
      if (notaAdmin != null && notaAdmin.trim().isNotEmpty)
        'notaAdmin': notaAdmin.trim(),
    });
  }

  /// (Opcional) revertir a pendiente si te equivocas
  static Future<void> marcarPendiente(String id, {String? notaAdmin}) async {
    final ref = _liquidas.doc(id);
    await ref.update({
      'estado': 'pendiente',
      'resueltoEn': null,
      if (notaAdmin != null && notaAdmin.trim().isNotEmpty)
        'notaAdmin': notaAdmin.trim(),
    });
  }
}
