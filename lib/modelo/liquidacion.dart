// lib/modelo/liquidacion.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Liquidacion {
  final String id;
  final String uidTaxista;
  final double monto;
  final String estado; // 'pendiente' | 'aprobado' | 'rechazado'
  final DateTime? solicitadoEn;
  final DateTime? resueltoEn;
  final String? notaAdmin;

  Liquidacion({
    required this.id,
    required this.uidTaxista,
    required this.monto,
    required this.estado,
    this.solicitadoEn,
    this.resueltoEn,
    this.notaAdmin,
  });

  factory Liquidacion.fromMap(String id, Map<String, dynamic> data) {
    return Liquidacion(
      id: id,
      uidTaxista: (data['uidTaxista'] ?? '').toString(),
      monto: _asDouble(data['monto']),
      estado: (data['estado'] ?? 'pendiente').toString(),
      solicitadoEn: (data['solicitadoEn'] is Timestamp)
          ? (data['solicitadoEn'] as Timestamp).toDate()
          : null,
      resueltoEn: (data['resueltoEn'] is Timestamp)
          ? (data['resueltoEn'] as Timestamp).toDate()
          : null,
      notaAdmin: data['notaAdmin']?.toString(),
    );
  }

  static double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  Map<String, dynamic> toMap() {
    return {
      'uidTaxista': uidTaxista,
      'monto': monto,
      'estado': estado,
      if (solicitadoEn != null)
        'solicitadoEn': Timestamp.fromDate(solicitadoEn!),
      if (resueltoEn != null) 'resueltoEn': Timestamp.fromDate(resueltoEn!),
      if (notaAdmin != null) 'notaAdmin': notaAdmin,
    };
  }
}
