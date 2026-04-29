// lib/modelo/chofer_turismo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'vehiculo_turismo.dart';

class ChoferTurismo {
  final String uid;
  final String nombre;
  final String email;
  final String telefono;
  final List<VehiculoTurismo> vehiculos;
  final String estado; // 'aprobado' | 'rechazado' | 'pendiente'
  final bool disponible;
  final double calificacion;
  final int viajesCompletados;
  final List<String> zonas;
  final DateTime fechaRegistro;
  final Map<String, dynamic> documentos;
  final String? verificadoPor;
  final DateTime? verificadoEn;
  final String? notaAdmin;
  final GeoPoint? ultimaUbicacion;
  final DateTime? ultimaUbicacionActualizada;

  ChoferTurismo({
    required this.uid,
    required this.nombre,
    required this.email,
    required this.telefono,
    required this.vehiculos,
    required this.estado,
    required this.disponible,
    required this.calificacion,
    required this.viajesCompletados,
    required this.zonas,
    required this.fechaRegistro,
    required this.documentos,
    this.verificadoPor,
    this.verificadoEn,
    this.notaAdmin,
    this.ultimaUbicacion,
    this.ultimaUbicacionActualizada,
  });

  factory ChoferTurismo.fromMap(String uid, Map<String, dynamic> map) {
    return ChoferTurismo(
      uid: uid,
      nombre: map['nombre'] ?? '',
      email: map['email'] ?? '',
      telefono: map['telefono'] ?? '',
      vehiculos: (map['vehiculos'] as List? ?? [])
          .map((v) => VehiculoTurismo.fromMap(v as Map<String, dynamic>))
          .toList(),
      estado: map['estado'] ?? 'pendiente',
      disponible: map['disponible'] ?? false,
      calificacion: (map['calificacion'] ?? 0.0).toDouble(),
      viajesCompletados: map['viajesCompletados'] ?? 0,
      zonas: List<String>.from(map['zonas'] ?? []),
      fechaRegistro:
          (map['fechaRegistro'] as Timestamp?)?.toDate() ?? DateTime.now(),
      documentos: map['documentos'] ?? {},
      verificadoPor: map['verificadoPor']?.toString(),
      verificadoEn: (map['verificadoEn'] as Timestamp?)?.toDate(),
      notaAdmin: map['notaAdmin']?.toString(),
      ultimaUbicacion: map['ultimaUbicacion'] as GeoPoint?,
      ultimaUbicacionActualizada:
          (map['ultimaUbicacionActualizada'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'nombre': nombre,
      'email': email,
      'telefono': telefono,
      'vehiculos': vehiculos.map((v) => v.toMap()).toList(),
      'estado': estado,
      'disponible': disponible,
      'calificacion': calificacion,
      'viajesCompletados': viajesCompletados,
      'zonas': zonas,
      'fechaRegistro': Timestamp.fromDate(fechaRegistro),
      'documentos': documentos,
      'verificadoPor': verificadoPor,
      'verificadoEn':
          verificadoEn != null ? Timestamp.fromDate(verificadoEn!) : null,
      'notaAdmin': notaAdmin,
      'ultimaUbicacion': ultimaUbicacion,
      'ultimaUbicacionActualizada': ultimaUbicacionActualizada != null
          ? Timestamp.fromDate(ultimaUbicacionActualizada!)
          : null,
    };
  }
}
