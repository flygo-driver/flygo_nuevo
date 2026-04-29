import 'package:cloud_firestore/cloud_firestore.dart';

/// Solicitud de recarga por comisión de viajes en efectivo (comprobante + monto).
class RecargaComisionTaxista {
  final String id;
  final String uidTaxista;
  final String nombreTaxista;
  final double comisionPendienteAlEnviar;
  final double saldoPrepagoAlEnviar;
  final double montoDeclaradoRd;
  final String comprobanteUrl;
  final String metodoPago;
  final String estado;
  final DateTime? createdAt;
  final String? notaAdmin;

  const RecargaComisionTaxista({
    required this.id,
    required this.uidTaxista,
    required this.nombreTaxista,
    required this.comisionPendienteAlEnviar,
    required this.saldoPrepagoAlEnviar,
    required this.montoDeclaradoRd,
    required this.comprobanteUrl,
    required this.metodoPago,
    required this.estado,
    this.createdAt,
    this.notaAdmin,
  });

  static RecargaComisionTaxista fromDoc(
      DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    final created = m['createdAt'];
    return RecargaComisionTaxista(
      id: d.id,
      uidTaxista: (m['uidTaxista'] ?? '').toString(),
      nombreTaxista: (m['nombreTaxista'] ?? '').toString(),
      comisionPendienteAlEnviar: _asDouble(m['comisionPendienteAlEnviar']),
      saldoPrepagoAlEnviar: _asDouble(m['saldoPrepagoAlEnviar']),
      montoDeclaradoRd: _asDouble(m['montoDeclaradoRd']),
      comprobanteUrl: (m['comprobanteUrl'] ?? '').toString(),
      metodoPago: (m['metodoPago'] ?? 'transferencia').toString(),
      estado: (m['estado'] ?? '').toString(),
      createdAt: created is Timestamp ? created.toDate() : null,
      notaAdmin: m['notaAdmin']?.toString(),
    );
  }

  static double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
