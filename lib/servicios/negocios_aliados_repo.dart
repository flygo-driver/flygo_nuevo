// lib/servicios/negocios_aliados_repo.dart

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/servicios/negocio_aliado_codigo.dart';
import 'package:flygo_nuevo/servicios/negocio_aliado_config.dart';

class NegocioAliado {
  const NegocioAliado({
    required this.codigo,
    required this.nombre,
    required this.ciudad,
    required this.telefonoContacto,
    required this.activo,
    this.notas = '',
    this.viajesReferidos = 0,
    this.clientesReferidos = 0,
  });

  final String codigo;
  final String nombre;
  final String ciudad;
  final String telefonoContacto;
  final bool activo;
  final String notas;
  final int viajesReferidos;
  final int clientesReferidos;

  factory NegocioAliado.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? <String, dynamic>{};
    return NegocioAliado(
      codigo: doc.id,
      nombre: (d['nombre'] ?? '').toString(),
      ciudad: (d['ciudad'] ?? '').toString(),
      telefonoContacto: (d['telefonoContacto'] ?? '').toString(),
      activo: d['activo'] == true,
      notas: (d['notas'] ?? '').toString(),
      viajesReferidos: _int(d['viajesReferidos']),
      clientesReferidos: _int(d['clientesReferidos']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'codigo': codigo,
      'nombre': nombre.trim(),
      'ciudad': ciudad.trim(),
      'telefonoContacto': telefonoContacto.trim(),
      'activo': activo,
      'notas': notas.trim(),
      'promoM': NegocioAliadoConfig.promoViajesM,
      'promoK': NegocioAliadoConfig.promoViajesK,
      'vigenciaDias': NegocioAliadoConfig.vigenciaDias,
      'pctComisionNegocio': NegocioAliadoConfig.pctComisionNegocio,
      'pctComisionTaxista': NegocioAliadoConfig.pctComisionTaxistaReferido,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }
}

abstract final class NegociosAliadosRepo {
  NegociosAliadosRepo._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(NegocioAliadoConfig.collection);

  static Stream<List<NegocioAliado>> streamTodos() {
    return _col
        .orderBy('nombre')
        .snapshots()
        .map((s) => s.docs.map(NegocioAliado.fromDoc).toList());
  }

  static Future<NegocioAliado?> obtenerPorCodigo(String codigo) async {
    final id = NegocioAliadoCodigo.normalizar(codigo);
    if (id.isEmpty) return null;
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    return NegocioAliado.fromDoc(snap);
  }

  static Future<String> codigoDisponible({
    required String nombre,
    required String ciudad,
    String? preferido,
  }) async {
    var base = NegocioAliadoCodigo.normalizar(
      preferido?.trim().isNotEmpty == true
          ? preferido!
          : NegocioAliadoCodigo.generarDesdeNombreCiudad(
              nombre: nombre,
              ciudad: ciudad,
            ),
    );
    if (base.isEmpty) base = 'NEGOCIO';
    var candidato = base;
    var n = 2;
    while (await _col.doc(candidato).get().then((s) => s.exists)) {
      candidato = '$base-$n';
      n++;
      if (n > 99) break;
    }
    return candidato;
  }

  static Future<NegocioAliado> crear({
    required String nombre,
    required String ciudad,
    String telefonoContacto = '',
    String notas = '',
    String? codigoPreferido,
  }) async {
    final codigo = await codigoDisponible(
      nombre: nombre,
      ciudad: ciudad,
      preferido: codigoPreferido,
    );
    final negocio = NegocioAliado(
      codigo: codigo,
      nombre: nombre.trim(),
      ciudad: ciudad.trim(),
      telefonoContacto: telefonoContacto.trim(),
      activo: true,
      notas: notas.trim(),
    );
    await _col.doc(codigo).set(<String, dynamic>{
      ...negocio.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
      'viajesReferidos': 0,
      'clientesReferidos': 0,
    });
    return negocio;
  }

  static Future<void> actualizar(NegocioAliado negocio) async {
    await _col.doc(negocio.codigo).set(negocio.toFirestore(), SetOptions(merge: true));
  }

  static Future<void> setActivo(String codigo, bool activo) async {
    await _col.doc(codigo).set(<String, dynamic>{
      'activo': activo,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
