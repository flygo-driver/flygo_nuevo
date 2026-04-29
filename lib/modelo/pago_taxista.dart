// lib/modelo/pago_taxista.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart'; // ✅ IMPORTANTE: Agregar este import

class PagoTaxista {
  final String id;
  final String uidTaxista;
  final String nombreTaxista;
  final String semana; // Formato: 2025-11 (año-semana)
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final double totalGanado;
  final double comision; // 20% del total
  final double netoAPagar; // total - comision
  final String
      estado; // 'pendiente' | 'pagado' | 'vencido' | 'pendiente_verificacion'
  final DateTime? fechaPago;
  final String? metodoPago; // 'transferencia' | 'efectivo' | 'tarjeta'
  final String? comprobanteUrl; // Foto del comprobante
  final String? verificadoPor; // UID del admin que verificó
  final DateTime? verificadoEn;
  final String? notaAdmin;
  final int viajesSemana; // Cantidad de viajes en la semana

  PagoTaxista({
    required this.id,
    required this.uidTaxista,
    required this.nombreTaxista,
    required this.semana,
    required this.fechaInicio,
    required this.fechaFin,
    required this.totalGanado,
    required this.comision,
    required this.netoAPagar,
    required this.estado,
    this.fechaPago,
    this.metodoPago,
    this.comprobanteUrl,
    this.verificadoPor,
    this.verificadoEn,
    this.notaAdmin,
    required this.viajesSemana,
  });

  factory PagoTaxista.fromMap(String id, Map<String, dynamic> map) {
    return PagoTaxista(
      id: id,
      uidTaxista: map['uidTaxista'] ?? '',
      nombreTaxista: map['nombreTaxista'] ?? '',
      semana: map['semana'] ?? '',
      fechaInicio:
          (map['fechaInicio'] as Timestamp?)?.toDate() ?? DateTime.now(),
      fechaFin: (map['fechaFin'] as Timestamp?)?.toDate() ?? DateTime.now(),
      totalGanado: (map['totalGanado'] ?? 0).toDouble(),
      comision: (map['comision'] ?? 0).toDouble(),
      netoAPagar: (map['netoAPagar'] ?? 0).toDouble(),
      estado: map['estado'] ?? 'pendiente',
      fechaPago: (map['fechaPago'] as Timestamp?)?.toDate(),
      metodoPago: map['metodoPago'],
      comprobanteUrl: map['comprobanteUrl'],
      verificadoPor: map['verificadoPor'],
      verificadoEn: (map['verificadoEn'] as Timestamp?)?.toDate(),
      notaAdmin: map['notaAdmin'],
      viajesSemana: map['viajesSemana'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uidTaxista': uidTaxista,
      'nombreTaxista': nombreTaxista,
      'semana': semana,
      'fechaInicio': Timestamp.fromDate(fechaInicio),
      'fechaFin': Timestamp.fromDate(fechaFin),
      'totalGanado': totalGanado,
      'comision': comision,
      'netoAPagar': netoAPagar,
      'estado': estado,
      'fechaPago': fechaPago != null ? Timestamp.fromDate(fechaPago!) : null,
      'metodoPago': metodoPago,
      'comprobanteUrl': comprobanteUrl,
      'verificadoPor': verificadoPor,
      'verificadoEn':
          verificadoEn != null ? Timestamp.fromDate(verificadoEn!) : null,
      'notaAdmin': notaAdmin,
      'viajesSemana': viajesSemana,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  // Método helper para obtener color según estado
  Color get estadoColor {
    switch (estado) {
      case 'pagado':
        return Colors.green;
      case 'pendiente_verificacion':
        return Colors.orange;
      case 'pendiente':
        return Colors.red;
      case 'vencido':
        return Colors.red.shade900;
      default:
        return Colors.grey;
    }
  }

  // Método helper para obtener ícono según estado
  IconData get estadoIcon {
    switch (estado) {
      case 'pagado':
        return Icons.check_circle;
      case 'pendiente_verificacion':
        return Icons.hourglass_top;
      case 'pendiente':
        return Icons.warning;
      case 'vencido':
        return Icons.error;
      default:
        return Icons.help;
    }
  }

  // Método helper para obtener texto legible del estado
  String get estadoTexto {
    switch (estado) {
      case 'pagado':
        return 'Pagado';
      case 'pendiente_verificacion':
        return 'En revisión';
      case 'pendiente':
        return 'Pendiente';
      case 'vencido':
        return 'Vencido';
      default:
        return estado;
    }
  }
}
