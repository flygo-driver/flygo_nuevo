import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/calculos/estados.dart';

/// Modelo de Viaje usado en la app (cliente y taxista).
class Viaje {
  final String id;

  // Identidad (cliente/taxista)
  final String clienteId;   // legacy / compat
  final String uidCliente;  // preferido
  final String uidTaxista;
  final String taxistaId;   // compat
  final String nombreTaxista;

  // Direcciones y coords
  final String origen;
  final String destino;
  final double latCliente;
  final double lonCliente;
  final double latDestino;
  final double lonDestino;

  // Posición en vivo del taxista (ping)
  final double latTaxista;
  final double lonTaxista;

  // Precios
  final double precio;              // precio estimado
  final double precioFinal;         // precio final (si aplica)
  final double comision;            // info de UI / contable
  final double gananciaTaxista;     // info de UI / contable

  // Preferencias
  final String metodoPago;          // 'Efectivo' | 'Transferencia' | 'Tarjeta'
  final String tipoVehiculo;        // 'Carro' | 'Jeepeta' | etc.
  final String marca;
  final String modelo;
  final String color;
  final bool idaYVuelta;
  final String telefono;
  final String placa;

  // Estado
  final String estado;              // 'pendiente' | 'aceptado' | 'a_bordo' | 'en_curso' | 'completado' | 'cancelado'
  final bool aceptado;
  final bool rechazado;
  final bool completado;
  final bool calificado;

  // Rating/feedback
  final double calificacion;
  final String comentario;

  // Fecha/hora del servicio
  final DateTime fechaHora;

  Viaje({
    this.id = '',
    this.clienteId = '',
    this.uidCliente = '',
    this.uidTaxista = '',
    this.taxistaId = '',
    this.nombreTaxista = '',
    this.origen = '',
    this.destino = '',
    this.latCliente = 0.0,
    this.lonCliente = 0.0,
    this.latDestino = 0.0,
    this.lonDestino = 0.0,
    this.latTaxista = 0.0,
    this.lonTaxista = 0.0,
    this.precio = 0.0,
    this.precioFinal = 0.0,
    this.comision = 0.0,
    this.gananciaTaxista = 0.0,
    this.metodoPago = 'Efectivo',
    this.tipoVehiculo = 'Carro',
    this.marca = '',
    this.modelo = '',
    this.color = '',
    this.idaYVuelta = false,
    this.telefono = '',
    this.placa = '',
    this.estado = EstadosViaje.pendiente,
    this.aceptado = false,
    this.rechazado = false,
    this.completado = false,
    this.calificado = false,
    this.calificacion = 0.0,
    this.comentario = '',
    DateTime? fechaHora,
  }) : fechaHora = fechaHora ?? DateTime.now();

  // ---- Helpers ----
  static String _asString(dynamic v) => (v ?? '').toString();

  static double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase().trim();
      return s == 'true' || s == '1' || s == 'yes' || s == 'si' || s == 'sí';
    }
    return false;
  }

  static DateTime _asDate(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ---- Factory/serialización ----
  factory Viaje.fromMap(String id, Map<String, dynamic> data) {
    return Viaje(
      id: id,
      clienteId: _asString(data['clienteId']),
      uidCliente: _asString(data['uidCliente']),
      uidTaxista: _asString(data['uidTaxista']),
      taxistaId: _asString(data['taxistaId']),
      nombreTaxista: _asString(data['nombreTaxista']),
      origen: _asString(data['origen']),
      destino: _asString(data['destino']),
      latCliente: _asDouble(data['latCliente']),
      lonCliente: _asDouble(data['lonCliente']),
      latDestino: _asDouble(data['latDestino']),
      lonDestino: _asDouble(data['lonDestino']),
      latTaxista: _asDouble(data['latTaxista']),
      lonTaxista: _asDouble(data['lonTaxista']),
      precio: _asDouble(data['precio']),
      precioFinal: _asDouble(data['precioFinal']),
      comision: _asDouble(data['comision']),
      gananciaTaxista: _asDouble(data['gananciaTaxista']),
      metodoPago: _asString(data['metodoPago']).isEmpty
          ? 'Efectivo'
          : _asString(data['metodoPago']),
      tipoVehiculo: _asString(data['tipoVehiculo']).isEmpty
          ? 'Carro'
          : _asString(data['tipoVehiculo']),
      marca: _asString(data['marca']),
      modelo: _asString(data['modelo']),
      color: _asString(data['color']),
      idaYVuelta: _asBool(data['idaYVuelta']),
      telefono: _asString(data['telefono']),
      placa: _asString(data['placa']),
      estado: EstadosViaje.normalizar(
        _asString(data['estado']).isEmpty
            ? (_asBool(data['completado'])
                ? EstadosViaje.completado
                : (_asBool(data['aceptado'])
                    ? EstadosViaje.aceptado
                    : EstadosViaje.pendiente))
            : _asString(data['estado']),
      ),
      aceptado: _asBool(data['aceptado']),
      rechazado: _asBool(data['rechazado']),
      completado: _asBool(data['completado']),
      calificado: _asBool(data['calificado']),
      calificacion: _asDouble(data['calificacion']),
      comentario: _asString(data['comentario']),
      fechaHora: _asDate(data['fechaHora']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'clienteId': clienteId,
      'uidCliente': uidCliente,
      'uidTaxista': uidTaxista,
      'taxistaId': taxistaId,
      'nombreTaxista': nombreTaxista,
      'origen': origen,
      'destino': destino,
      'latCliente': latCliente,
      'lonCliente': lonCliente,
      'latDestino': latDestino,
      'lonDestino': lonDestino,
      'latTaxista': latTaxista,
      'lonTaxista': lonTaxista,
      'precio': precio,
      'precioFinal': precioFinal,
      'comision': comision,
      'gananciaTaxista': gananciaTaxista,
      'metodoPago': metodoPago,
      'tipoVehiculo': tipoVehiculo,
      'marca': marca,
      'modelo': modelo,
      'color': color,
      'idaYVuelta': idaYVuelta,
      'telefono': telefono,
      'placa': placa,
      'estado': estado,
      'aceptado': aceptado,
      'rechazado': rechazado,
      'completado': completado,
      'calificado': calificado,
      'calificacion': calificacion,
      'comentario': comentario,
      'fechaHora': Timestamp.fromDate(fechaHora),
    };
  }

  /// Mapa recomendado para **CREAR** en Firestore
  Map<String, dynamic> toCreateMap() {
    return {
      'uidCliente': uidCliente.isNotEmpty ? uidCliente : clienteId,
      'clienteId': clienteId.isNotEmpty ? clienteId : uidCliente,
      'estado': EstadosViaje.pendiente,
      'aceptado': false,
      'rechazado': false,
      'origen': origen,
      'destino': destino,
      'latCliente': latCliente,
      'lonCliente': lonCliente,
      'latDestino': latDestino,
      'lonDestino': lonDestino,
      'fechaHora': Timestamp.fromDate(fechaHora),
      'precio': precio,
      'metodoPago': metodoPago,
      'tipoVehiculo': tipoVehiculo,
      if (marca.isNotEmpty) 'marca': marca,
      if (modelo.isNotEmpty) 'modelo': modelo,
      if (color.isNotEmpty) 'color': color,
      'idaYVuelta': idaYVuelta,
      'uidTaxista': '',
      'taxistaId': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'creadoEn': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
      'latOrigen': latCliente,
      'lonOrigen': lonCliente,
    };
  }

  Viaje copyWith({
    String? id,
    String? clienteId,
    String? uidCliente,
    String? uidTaxista,
    String? taxistaId,
    String? nombreTaxista,
    String? origen,
    String? destino,
    double? latCliente,
    double? lonCliente,
    double? latDestino,
    double? lonDestino,
    double? latTaxista,
    double? lonTaxista,
    double? precio,
    double? precioFinal,
    double? comision,
    double? gananciaTaxista,
    String? metodoPago,
    String? tipoVehiculo,
    String? marca,
    String? modelo,
    String? color,
    bool? idaYVuelta,
    String? telefono,
    String? placa,
    String? estado,
    bool? aceptado,
    bool? rechazado,
    bool? completado,
    bool? calificado,
    double? calificacion,
    String? comentario,
    DateTime? fechaHora,
  }) {
    return Viaje(
      id: id ?? this.id,
      clienteId: clienteId ?? this.clienteId,
      uidCliente: uidCliente ?? this.uidCliente,
      uidTaxista: uidTaxista ?? this.uidTaxista,
      taxistaId: taxistaId ?? this.taxistaId,
      nombreTaxista: nombreTaxista ?? this.nombreTaxista,
      origen: origen ?? this.origen,
      destino: destino ?? this.destino,
      latCliente: latCliente ?? this.latCliente,
      lonCliente: lonCliente ?? this.lonCliente,
      latDestino: latDestino ?? this.latDestino,
      lonDestino: lonDestino ?? this.lonDestino,
      latTaxista: latTaxista ?? this.latTaxista,
      lonTaxista: lonTaxista ?? this.lonTaxista,
      precio: precio ?? this.precio,
      precioFinal: precioFinal ?? this.precioFinal,
      comision: comision ?? this.comision,
      gananciaTaxista: gananciaTaxista ?? this.gananciaTaxista,
      metodoPago: metodoPago ?? this.metodoPago,
      tipoVehiculo: tipoVehiculo ?? this.tipoVehiculo,
      marca: marca ?? this.marca,
      modelo: modelo ?? this.modelo,
      color: color ?? this.color,
      idaYVuelta: idaYVuelta ?? this.idaYVuelta,
      telefono: telefono ?? this.telefono,
      placa: placa ?? this.placa,
      estado: estado ?? this.estado,
      aceptado: aceptado ?? this.aceptado,
      rechazado: rechazado ?? this.rechazado,
      completado: completado ?? this.completado,
      calificado: calificado ?? this.calificado,
      calificacion: calificacion ?? this.calificacion,
      comentario: comentario ?? this.comentario,
      fechaHora: fechaHora ?? this.fechaHora,
    );
  }
}
