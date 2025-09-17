import 'package:cloud_firestore/cloud_firestore.dart';

class Pago {
  final String id;
  final String clienteId;
  final double monto;
  final String metodo;
  final DateTime fecha;

  Pago({
    required this.id,
    required this.clienteId,
    required this.monto,
    required this.metodo,
    required this.fecha,
  });

  factory Pago.fromMap(String id, Map<String, dynamic> data) {
    return Pago(
      id: id,
      clienteId: data['clienteId'],
      monto: (data['monto'] ?? 0).toDouble(),
      metodo: data['metodo'] ?? '',
      fecha: (data['fecha'] as Timestamp)
          .toDate(), // ✅ Aquí usamos Timestamp de Firestore
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'clienteId': clienteId,
      'monto': monto,
      'metodo': metodo,
      'fecha': fecha,
    };
  }
}
