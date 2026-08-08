// lib/servicios/negocio_aliado_admin_repo.dart
// Consultas ADM: clientes referidos y viajes con comisión 3%.

import 'package:cloud_firestore/cloud_firestore.dart';

class NegocioAliadoClienteRef {
  const NegocioAliadoClienteRef({
    required this.uid,
    required this.nombre,
    required this.telefono,
    required this.contadorPromo,
    required this.promoVenceAt,
    required this.registradoAt,
  });

  final String uid;
  final String nombre;
  final String telefono;
  final int contadorPromo;
  final DateTime? promoVenceAt;
  final DateTime? registradoAt;
}

class NegocioAliadoViajeComision {
  const NegocioAliadoViajeComision({
    required this.viajeId,
    required this.origen,
    required this.destino,
    required this.precioNominalRd,
    required this.comisionNegocioRd,
    required this.comisionTaxistaRd,
    required this.comisionTaxistaPct,
    required this.metodoPago,
    required this.esGratis,
    required this.finalizadoAt,
    required this.pagada,
  });

  final String viajeId;
  final String origen;
  final String destino;
  final double precioNominalRd;
  final double comisionNegocioRd;
  final double comisionTaxistaRd;
  final double comisionTaxistaPct;
  final String metodoPago;
  final bool esGratis;
  final DateTime? finalizadoAt;
  final bool pagada;
}

abstract final class NegocioAliadoAdminRepo {
  NegocioAliadoAdminRepo._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<List<NegocioAliadoClienteRef>> clientesReferidos(
    String codigo,
  ) async {
    final c = codigo.trim().toUpperCase();
    if (c.isEmpty) return <NegocioAliadoClienteRef>[];

    final snap = await _db
        .collection('usuarios')
        .where('negocioReferidoCodigo', isEqualTo: c)
        .limit(200)
        .get();

    final lista = snap.docs.map((doc) {
      final d = doc.data();
      return NegocioAliadoClienteRef(
        uid: doc.id,
        nombre: (d['nombre'] ?? '').toString(),
        telefono: (d['telefono'] ?? '').toString(),
        contadorPromo: _int(d['negocioPromoContador']),
        promoVenceAt: _ts(d['negocioPromoVenceAt']),
        registradoAt: _ts(d['negocioReferidoAt'] ?? d['fechaRegistro']),
      );
    }).toList();
    lista.sort((a, b) => (b.registradoAt ?? DateTime(1970))
        .compareTo(a.registradoAt ?? DateTime(1970)));
    return lista;
  }

  static Future<List<NegocioAliadoViajeComision>> viajesConComision(
    String codigo,
  ) async {
    final c = codigo.trim().toUpperCase();
    if (c.isEmpty) return <NegocioAliadoViajeComision>[];

    final snap = await _db
        .collection('viajes')
        .where('negocioAliadoCodigo', isEqualTo: c)
        .where('completado', isEqualTo: true)
        .limit(300)
        .get();

    final lista = <NegocioAliadoViajeComision>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      if (d['negocioAliadoPromoContabilizado'] != true) continue;
      final comCents = _int(d['negocioAliadoComisionNegocioCents']);
      final nominalCents = _int(d['precioNominalCents'] ?? d['precio_cents']);
      final taxistaCents = _int(d['comision_cents']);
      final pctTaxista = _dbl(
        d['negocioAliadoPctComisionTaxista'] ?? d['comisionPorcentaje'] ?? 15,
      );
      lista.add(
        NegocioAliadoViajeComision(
          viajeId: doc.id,
          origen: (d['origen'] ?? '').toString(),
          destino: (d['destino'] ?? '').toString(),
          precioNominalRd: nominalCents / 100.0,
          comisionNegocioRd: comCents > 0
              ? comCents / 100.0
              : _dbl(d['negocioAliadoComisionNegocioRd']),
          comisionTaxistaRd: taxistaCents / 100.0,
          comisionTaxistaPct: pctTaxista,
          metodoPago: (d['metodoPago'] ?? '').toString(),
          esGratis: d['negocioAliadoPromoGratis'] == true,
          finalizadoAt: _ts(d['finalizadoEn']),
          pagada: d['negocioAliadoComisionPagada'] == true,
        ),
      );
    }
    lista.sort((a, b) => (b.finalizadoAt ?? DateTime(1970))
        .compareTo(a.finalizadoAt ?? DateTime(1970)));
    return lista;
  }

  static Future<void> marcarComisionPagada(String viajeId) async {
    await _db.collection('viajes').doc(viajeId).set(<String, dynamic>{
      'negocioAliadoComisionPagada': true,
      'negocioAliadoComisionPagadaEn': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  static double _dbl(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }
}
