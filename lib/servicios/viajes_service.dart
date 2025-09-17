import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Servicio centralizado para mutar el estado de un Viaje
/// compatible con tus reglas de seguridad actuales.
class ViajesService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid {
    final u = _auth.currentUser;
    if (u == null) throw 'No hay usuario logueado';
    return u.uid;
  }

  /// ACEPTAR el viaje y dejarlo en "aceptado".
  Future<void> confirmarViaje(String viajeId, {String? nombreTaxista}) async {
    final ref = _db.collection('viajes').doc(viajeId);
    try {
      await ref.update({
        'estado': 'aceptado',
        'uidTaxista': _uid,
        'taxistaId': _uid,
        'aceptado': true,
        'rechazado': false,
        if (nombreTaxista != null && nombreTaxista.isNotEmpty)
          'nombreTaxista': nombreTaxista,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      debugPrint('Firestore error(confirmarViaje): ${e.code} - ${e.message}');
      rethrow;
    }
  }

  /// PASAR A: A BORDO
  Future<void> marcarABordo(String viajeId) async {
    try {
      await _db.collection('viajes').doc(viajeId).update({
        'estado': 'a_bordo',
        'pickupConfirmadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      debugPrint('Firestore error(marcarABordo): ${e.code} - ${e.message}');
      rethrow;
    }
  }

  /// PASAR A: EN CURSO (solo desde a_bordo)
  Future<void> marcarEnCurso(String viajeId) async {
    try {
      await _db.collection('viajes').doc(viajeId).update({
        'estado': 'en_curso',
        'inicioEnRutaEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      debugPrint('Firestore error(marcarEnCurso): ${e.code} - ${e.message}');
      rethrow;
    }
  }

  /// PASAR A: COMPLETADO.
  Future<void> marcarCompletado(
    String viajeId, {
    num? precioFinal,
    num? comision,
    num? gananciaTaxista,
  }) async {
    final data = <String, dynamic>{
      'estado': 'completado',
      'completado': true,
      'finalizadoEn': FieldValue.serverTimestamp(),
      'completadoEn': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (precioFinal != null) data['precioFinal'] = precioFinal;
    if (comision != null) data['comision'] = comision;
    if (gananciaTaxista != null) data['gananciaTaxista'] = gananciaTaxista;

    try {
      await _db.collection('viajes').doc(viajeId).update(data);
    } on FirebaseException catch (e) {
      debugPrint('Firestore error(marcarCompletado): ${e.code} - ${e.message}');
      rethrow;
    }
  }

  /// ACTUALIZAR POSICIÓN del taxista durante el viaje
  Future<void> actualizarPosicion(
    String viajeId, {
    required double lat,
    required double lon,
  }) async {
    try {
      await _db.collection('viajes').doc(viajeId).update({
        'latTaxista': lat,
        'lonTaxista': lon,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      debugPrint(
        'Firestore error(actualizarPosicion): ${e.code} - ${e.message}',
      );
      rethrow;
    }
  }
}
