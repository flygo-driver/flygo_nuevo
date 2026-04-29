// lib/servicios/taxista_prepago_ledger.dart
// Libro auxiliar en paralelo a `billeteras_taxista`: auditoría sin alterar saldos ni bloqueos.
import 'package:cloud_firestore/cloud_firestore.dart';

abstract final class TaxistaPrepagoLedger {
  static const String subcoleccion = 'movimientos_prepago';
  static const int schemaVersion = 1;

  static DocumentReference<Map<String, dynamic>> refDoc(
      String uidTaxista, String movId) {
    return FirebaseFirestore.instance
        .collection('billeteras_taxista')
        .doc(uidTaxista.trim())
        .collection(subcoleccion)
        .doc(_safeId(movId));
  }

  /// IDs de Firestore no deben contener `/`.
  static String _safeId(String raw) => raw.trim().replaceAll('/', '_');

  static Future<void> _crearSiNoExiste(
    Transaction tx,
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> campos,
  ) async {
    final s = await tx.get(ref);
    if (s.exists) return;
    tx.set(ref, {
      ...campos,
      'schemaVersion': schemaVersion,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Comisión efectivo al cerrar viaje (o primer efectivo sin cargo).
  static Future<void> appendComisionViajeEfectivo({
    required Transaction tx,
    required String uidTaxista,
    required String viajeId,
    required String fuente,
    required double comisionTotalRd,
    required double pendienteAntes,
    required double saldoPrepagoAntes,
    required double pendienteDespues,
    required double saldoPrepagoDespues,
    required bool primerEfectivoSinDescuento,
  }) async {
    final uid = uidTaxista.trim();
    final vid = viajeId.trim();
    if (uid.isEmpty || vid.isEmpty) return;

    final ref = refDoc(uid, 'comision_viaje_$vid');
    final desdeLegacy =
        (pendienteAntes - pendienteDespues).clamp(0.0, double.infinity);
    final desdePrepago =
        (saldoPrepagoAntes - saldoPrepagoDespues).clamp(0.0, double.infinity);

    await _crearSiNoExiste(tx, ref, {
      'tipo': primerEfectivoSinDescuento
          ? 'primer_efectivo_sin_descuento'
          : 'comision_viaje_efectivo',
      'fuente': fuente,
      'uidTaxista': uid,
      'viajeId': vid,
      'comisionTotalRd': double.parse(comisionTotalRd.toStringAsFixed(2)),
      'comisionPendienteAntes': double.parse(pendienteAntes.toStringAsFixed(2)),
      'saldoPrepagoAntes': double.parse(saldoPrepagoAntes.toStringAsFixed(2)),
      'comisionPendienteDespues':
          double.parse(pendienteDespues.toStringAsFixed(2)),
      'saldoPrepagoDespues':
          double.parse(saldoPrepagoDespues.toStringAsFixed(2)),
      'desdeLegacyRd': double.parse(desdeLegacy.toStringAsFixed(2)),
      'desdePrepagoRd': double.parse(desdePrepago.toStringAsFixed(2)),
    });
  }

  /// Recarga verificada por admin (sube prepago).
  static Future<void> appendRecargaPrepagoVerificada({
    required Transaction tx,
    required String uidTaxista,
    required String recargaId,
    required double saldoPrepagoAntes,
    required double saldoPrepagoDespues,
    required double comisionPendienteAntes,
    required double comisionPendienteDespues,
    required double montoAcreditadoRd,
    String? referencia,
  }) async {
    final uid = uidTaxista.trim();
    final rid = recargaId.trim();
    if (uid.isEmpty || rid.isEmpty) return;

    final ref = refDoc(uid, 'recarga_prepago_$rid');
    await _crearSiNoExiste(tx, ref, {
      'tipo': 'recarga_prepago',
      'fuente': 'admin_verificar_recarga_comision',
      'uidTaxista': uid,
      'recargaId': rid,
      'montoAcreditadoRd': double.parse(montoAcreditadoRd.toStringAsFixed(2)),
      'saldoPrepagoAntes': double.parse(saldoPrepagoAntes.toStringAsFixed(2)),
      'saldoPrepagoDespues':
          double.parse(saldoPrepagoDespues.toStringAsFixed(2)),
      'comisionPendienteAntes':
          double.parse(comisionPendienteAntes.toStringAsFixed(2)),
      'comisionPendienteDespues':
          double.parse(comisionPendienteDespues.toStringAsFixed(2)),
      if (referencia != null && referencia.trim().isNotEmpty)
        'referencia': referencia.trim(),
    });
  }

  /// Liquidación administrativa sobre `comisionPendiente` legacy.
  static Future<void> appendLiquidacionLegacy({
    required Transaction tx,
    required String uidTaxista,
    required double pendienteAntes,
    required double pendienteDespues,
    required double montoLiquidarDeclaradoRd,
    String? referencia,
  }) async {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return;

    final mid =
        'liquidacion_legacy_${uid}_${pendienteAntes.toStringAsFixed(2)}_${montoLiquidarDeclaradoRd.toStringAsFixed(2)}';
    final ref = refDoc(uid, mid);

    await _crearSiNoExiste(tx, ref, {
      'tipo': 'liquidacion_legacy',
      'fuente': 'admin_liquidar_comision_efectivo',
      'uidTaxista': uid,
      'comisionPendienteAntes': double.parse(pendienteAntes.toStringAsFixed(2)),
      'comisionPendienteDespues':
          double.parse(pendienteDespues.toStringAsFixed(2)),
      'montoLiquidarDeclaradoRd':
          double.parse(montoLiquidarDeclaradoRd.toStringAsFixed(2)),
      if (referencia != null && referencia.trim().isNotEmpty)
        'referencia': referencia.trim(),
    });
  }

  /// Comisión bola pueblo (misma lógica que viaje efectivo).
  static Future<void> appendComisionBolaPueblo({
    required Transaction tx,
    required String uidTaxista,
    required String bolaId,
    required String fuente,
    required double comisionTotalRd,
    required double pendienteAntes,
    required double saldoPrepagoAntes,
    required double pendienteDespues,
    required double saldoPrepagoDespues,
    required bool primerEfectivoSinDescuento,
  }) async {
    final uid = uidTaxista.trim();
    final bid = bolaId.trim();
    if (uid.isEmpty || bid.isEmpty) return;

    final ref = refDoc(uid, 'comision_bola_$bid');
    final desdeLegacy =
        (pendienteAntes - pendienteDespues).clamp(0.0, double.infinity);
    final desdePrepago =
        (saldoPrepagoAntes - saldoPrepagoDespues).clamp(0.0, double.infinity);

    await _crearSiNoExiste(tx, ref, {
      'tipo': primerEfectivoSinDescuento
          ? 'primer_efectivo_sin_descuento'
          : 'comision_bola_pueblo',
      'fuente': fuente,
      'uidTaxista': uid,
      'bolaId': bid,
      'comisionTotalRd': double.parse(comisionTotalRd.toStringAsFixed(2)),
      'comisionPendienteAntes': double.parse(pendienteAntes.toStringAsFixed(2)),
      'saldoPrepagoAntes': double.parse(saldoPrepagoAntes.toStringAsFixed(2)),
      'comisionPendienteDespues':
          double.parse(pendienteDespues.toStringAsFixed(2)),
      'saldoPrepagoDespues':
          double.parse(saldoPrepagoDespues.toStringAsFixed(2)),
      'desdeLegacyRd': double.parse(desdeLegacy.toStringAsFixed(2)),
      'desdePrepagoRd': double.parse(desdePrepago.toStringAsFixed(2)),
    });
  }
}
