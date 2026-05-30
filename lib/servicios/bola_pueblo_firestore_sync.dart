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

  /// Tras `marcarClienteAbordo` en el viaje espejo: alinea `bolas_pueblo` (paso «Subió el cliente»).
  static Future<void> syncBolaPickupConfirmadaDesdeViaje(String viajeId) async {
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
        'pickupConfirmadoTaxista': true,
        'pickupConfirmadoTaxistaEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('[BOLA_AHORRO] sync bola pickup desde viaje=$vid bola=$bolaId');
    } catch (e, st) {
      debugPrint('[BOLA_AHORRO] syncBolaPickupConfirmadaDesdeViaje $e $st');
    }
  }

  /// Tras `iniciarViajeSeguro` en el viaje espejo: alinea estado en tablero bola.
  static Future<void> syncBolaEnCursoDesdeViaje(String viajeId) async {
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
        'estado': 'en_curso',
        'estadoViajeBola': 'en_curso',
        'codigoVerificado': true,
        'codigoVerificadoEn': FieldValue.serverTimestamp(),
        'confirmacionTaxistaFinal': false,
        'confirmacionClienteFinal': false,
        'confirmacionTaxistaFinalEn': FieldValue.delete(),
        'confirmacionClienteFinalEn': FieldValue.delete(),
        'comisionAplicada': false,
        'inicioEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('[BOLA_AHORRO] sync bola en_curso desde viaje=$vid bola=$bolaId');
    } catch (e, st) {
      debugPrint('[BOLA_AHORRO] syncBolaEnCursoDesdeViaje $e $st');
    }
  }

  /// Tras callable completar viaje espejo bola: alinea tablero (mismo cierre que viaje estándar).
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

      final String metodo =
          (m['metodoPago'] ?? 'Efectivo').toString().trim().toLowerCase();
      final bool esEfectivo =
          metodo.isEmpty || metodo.contains('efectivo');

      final Map<String, dynamic> patch = <String, dynamic>{
        'estado': 'finalizada',
        'estadoViajeBola': 'finalizada',
        'finalizadaEn': FieldValue.serverTimestamp(),
        'comisionAplicada': true,
        'viajeCompletadoId': vid,
        'updatedAt': FieldValue.serverTimestamp(),
        'metodoPago': esEfectivo ? 'efectivo' : 'transferencia',
        'estadoPago': (m['estadoPago'] ?? (esEfectivo ? 'pagado' : 'pendiente'))
            .toString(),
      };

      final dynamic saldoFactura = m['facturaSaldoPrepagoComisionRd'];
      if (saldoFactura is num) {
        patch['facturaSaldoPrepagoComisionRd'] = saldoFactura;
      }
      final dynamic comp = m['comprobanteTransferenciaUrl'];
      if (comp is String && comp.trim().isNotEmpty) {
        patch['comprobanteTransferenciaUrl'] = comp.trim();
      }
      if (m['transferenciaConfirmada'] == true) {
        patch['transferenciaConfirmada'] = true;
      }

      await _bolas.doc(bolaId).set(patch, SetOptions(merge: true));
      debugPrint('[BOLA_AHORRO] postCompletar finalizada bolaId=$bolaId viaje=$vid');
    } catch (e, st) {
      debugPrint('[BOLA_AHORRO] postCompletarViajeEspejo error viaje=$vid $e $st');
    }
  }
}
