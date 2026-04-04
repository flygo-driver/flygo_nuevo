import 'package:cloud_firestore/cloud_firestore.dart';

class ReportesViajeData {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> crearReporte({
    required String viajeId,
    required String uidCliente,
    required String uidTaxista,
    required String motivo,
    required String comentario,
    String estado = 'pendiente',
  }) async {
    final ref = _db.collection('reportes_viaje').doc();
    await ref.set({
      'id': ref.id,
      'viajeId': viajeId,
      'uidCliente': uidCliente,
      'uidTaxista': uidTaxista,
      'motivo': motivo.trim(),
      'comentario': comentario.trim(),
      'estado': estado,
      'creadoEn': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    });

    await _db.collection('viajes').doc(viajeId).set({
      'reportado': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
