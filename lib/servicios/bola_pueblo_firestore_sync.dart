import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Sincronización cliente `bolas_pueblo` ↔ viaje espejo (sin importar [ViajesRepo]).
class BolaPuebloFirestoreSync {
  BolaPuebloFirestoreSync._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _bolas =>
      _db.collection('bolas_pueblo');
  static CollectionReference<Map<String, dynamic>> get _viajes =>
      _db.collection('viajes');

  static Future<void> marcarErrorSyncViajeEspejo({
    required String bolaId,
    required Object error,
  }) async {
    final id = bolaId.trim();
    if (id.isEmpty) return;
    try {
      await _bolas.doc(id).set(<String, dynamic>{
        'errorSync': true,
        'errorSyncViajeEspejo': error.toString(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('[BOLA_AHORRO] errorSync bolaId=$id err=$error');
    } catch (e, st) {
      debugPrint('[BOLA_AHORRO] marcarErrorSyncViajeEspejo falló bolaId=$id $e $st');
    }
  }

  /// Tras claim exitoso del viaje espejo: cierra negociación en bola y enlaza id.
  static Future<void> postClaimViajeEspejo(String viajeId) async {
    final vid = viajeId.trim();
    if (vid.isEmpty) return;
    try {
      final vSnap = await _viajes.doc(vid).get();
      if (!vSnap.exists) return;
      final m = vSnap.data() ?? <String, dynamic>{};
      if ((m['tipoServicio'] ?? '').toString().trim() != 'bola_ahorro') {
        return;
      }
      final bolaId =
          (m['bolaPuebloId'] ?? m['bolaId'] ?? '').toString().trim();
      if (bolaId.isEmpty) return;
      await _bolas.doc(bolaId).set(<String, dynamic>{
        'negociacionCerrada': true,
        'viajeEspejoId': vid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('[BOLA_AHORRO] postClaim negociacionCerrada bolaId=$bolaId viaje=$vid');
    } catch (e, st) {
      debugPrint('[BOLA_AHORRO] postClaimViajeEspejo error viaje=$vid $e $st');
    }
  }

  /// Tras callable completar viaje espejo bola: estado en tablero para el cliente.
  static Future<void> postCompletarViajeEspejo(String viajeId) async {
    final vid = viajeId.trim();
    if (vid.isEmpty) return;
    try {
      final vSnap = await _viajes.doc(vid).get();
      if (!vSnap.exists) return;
      final m = vSnap.data() ?? <String, dynamic>{};
      if ((m['tipoServicio'] ?? '').toString().trim() != 'bola_ahorro') {
        return;
      }
      final bolaId =
          (m['bolaPuebloId'] ?? m['bolaId'] ?? '').toString().trim();
      if (bolaId.isEmpty) return;
      await _bolas.doc(bolaId).set(<String, dynamic>{
        'estado': 'completado',
        'viajeCompletadoId': vid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('[BOLA_AHORRO] postCompletar bolaId=$bolaId viaje=$vid');
    } catch (e, st) {
      debugPrint('[BOLA_AHORRO] postCompletarViajeEspejo error viaje=$vid $e $st');
    }
  }
}
