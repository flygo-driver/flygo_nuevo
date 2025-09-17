import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Libro mayor por taxista:
/// Colección: billeteras/{uidTaxista}/movimientos/{idMovimiento}
/// Todos los montos en CENTAVOS (int), nunca double para cálculos.
///
/// Campos base por movimiento:
/// - id                : string (docId)
/// - type              : 'ride_income' | 'withdrawal' | 'adjustment'
/// - status            : 'posted' | 'pending' | 'approved' | 'rejected' (según type)
/// - amount_cents      : int (signado desde la perspectiva del CONDUCTOR)
///                       +creditos -> aumentan saldo (p.ej. ride_income)
///                       -débitos  -> reservan o descuentan saldo (p.ej. withdrawal)
/// - currency          : 'DOP'
/// - ref_type          : 'viaje' | 'liquidacion' | 'manual'
/// - ref_id            : id relacionado (viajeId | liquidacionId)
/// - note              : texto opcional
/// - created_at        : serverTimestamp
/// - created_by_uid    : quien generó (si aplica)
/// - created_by_name   : nombre/email (si aplica)
class LedgerService {
  LedgerService._();
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _movRef(String uidTaxista) =>
      _db.collection('billeteras').doc(uidTaxista).collection('movimientos');

  // ------------------------
  // STREAMS (tiempo real)
  // ------------------------

  /// Saldo "disponible" = suma de:
  /// - ride_income: SUM(amount_cents)  (posted)
  /// - withdrawal : SUM(amount_cents)  (pending o approved => ya reserva/desc)
  /// - adjustment : SUM(amount_cents)  (posted)
  ///
  /// NOTA: withdrawal 'rejected' NO cuenta. Por eso filtramos para excluirlos.
  static Stream<int> streamSaldoCents(String uidTaxista) {
    if (uidTaxista.trim().isEmpty) return Stream.value(0);

    final q = _movRef(uidTaxista)
        .where('status', whereIn: ['posted', 'pending', 'approved']);

    return q.snapshots().map((qs) {
      var sum = 0;
      for (final d in qs.docs) {
        final data = d.data();
        final v = data['amount_cents'];
        if (v is int) sum += v;
      }
      return sum;
    });
  }

  /// Devuelve todos los movimientos (últimos primero) para auditoría UI.
  static Stream<List<LedgerEntry>> streamMovimientos(String uidTaxista, {int limit = 500}) {
    if (uidTaxista.trim().isEmpty) return Stream.value(const <LedgerEntry>[]);
    return _movRef(uidTaxista)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((qs) => qs.docs.map((d) => LedgerEntry.fromMap(d.id, d.data())).toList());
  }

  // ------------------------
  // ESCRITURAS (idempotentes)
  // ------------------------

  /// Asentamiento de un viaje: CREDITAR ganancia del taxista.
  /// Usa docId determinístico para evitar duplicados: "ride_{viajeId}".
  static Future<void> postRideIncome({
    required String uidTaxista,
    required String viajeId,
    required int driverAmountCents, // 80% del viaje, por ejemplo
    String? createdByUid,
    String? createdByName,
    String? note,
  }) async {
    final id = 'ride_$viajeId';
    final ref = _movRef(uidTaxista).doc(id);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) return; // idempotencia

      tx.set(ref, {
        'id': id,
        'type': 'ride_income',
        'status': 'posted',
        'amount_cents': driverAmountCents, // POSITIVO
        'currency': 'DOP',
        'ref_type': 'viaje',
        'ref_id': viajeId,
        'note': note ?? '',
        'created_at': FieldValue.serverTimestamp(),
        'created_by_uid': createdByUid ?? '',
        'created_by_name': createdByName ?? '',
      });
    });
  }

  /// Solicitud de retiro: DEBITAR (reserva) en el momento de la solicitud.
  /// DocId determinístico: "wdreq_{liquidacionId}" si lo tienes; si no, genera con add().
  static Future<String> requestWithdrawal({
    required String uidTaxista,
    required int amountCents,        // POSITIVO en argumento; internamente se guarda NEGATIVO
    String? liquidacionId,           // si ya creaste el doc en /liquidaciones
    String? createdByUid,
    String? createdByName,
    String? note,
  }) async {
    final ref = (liquidacionId == null || liquidacionId.isEmpty)
        ? _movRef(uidTaxista).doc()                           // auto-id
        : _movRef(uidTaxista).doc('wdreq_$liquidacionId');     // idempotente

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) return;

      tx.set(ref, {
        'id': ref.id,
        'type': 'withdrawal',
        'status': 'pending',                 // reserva activa
        'amount_cents': -amountCents,        // NEGATIVO (reserva)
        'currency': 'DOP',
        'ref_type': 'liquidacion',
        'ref_id': liquidacionId ?? '',
        'note': note ?? '',
        'created_at': FieldValue.serverTimestamp(),
        'created_by_uid': createdByUid ?? '',
        'created_by_name': createdByName ?? '',
      });
    });

    return ref.id;
  }

  /// Marcar retiro como APROBADO (no cambia saldo porque ya estaba reservado).
  static Future<void> approveWithdrawal({
    required String uidTaxista,
    required String liquidacionId,
    String? note,
  }) async {
    final ref = _movRef(uidTaxista).doc('wdreq_$liquidacionId');
    await ref.update({
      'status': 'approved',
      if (note != null) 'note': note,
    });
  }

  /// Rechazar retiro: liberar la reserva agregando un AJUSTE positivo.
  static Future<void> rejectWithdrawal({
    required String uidTaxista,
    required String liquidacionId,
    required int originalAmountCents, // mismo monto que se reservó
    String? note,
  }) async {
    final reqRef = _movRef(uidTaxista).doc('wdreq_$liquidacionId');
    final adjRef = _movRef(uidTaxista).doc('wdrel_$liquidacionId'); // release

    await _db.runTransaction((tx) async {
      final reqSnap = await tx.get(reqRef);
      if (reqSnap.exists) {
        tx.update(reqRef, {'status': 'rejected', if (note != null) 'note': note});
      }
      final relSnap = await tx.get(adjRef);
      if (!relSnap.exists) {
        tx.set(adjRef, {
          'id': adjRef.id,
          'type': 'adjustment',
          'status': 'posted',
          'amount_cents': originalAmountCents, // POSITIVO (libera reserva)
          'currency': 'DOP',
          'ref_type': 'liquidacion',
          'ref_id': liquidacionId,
          'note': note ?? 'Liberación por rechazo de retiro',
          'created_at': FieldValue.serverTimestamp(),
          'created_by_uid': '',
          'created_by_name': '',
        });
      }
    });
  }
}

/// Modelo simple para UI/Auditoría
class LedgerEntry {
  final String id;
  final String type;    // ride_income | withdrawal | adjustment
  final String status;  // posted | pending | approved | rejected
  final int amountCents;
  final String currency;
  final String refType;
  final String refId;
  final String note;
  final DateTime? createdAt;
  final String createdByUid;
  final String createdByName;

  LedgerEntry({
    required this.id,
    required this.type,
    required this.status,
    required this.amountCents,
    required this.currency,
    required this.refType,
    required this.refId,
    required this.note,
    required this.createdAt,
    required this.createdByUid,
    required this.createdByName,
  });

  factory LedgerEntry.fromMap(String id, Map<String, dynamic> m) {
    final ts = m['created_at'];
    DateTime? t;
    if (ts is Timestamp) t = ts.toDate();

    return LedgerEntry(
      id: id,
      type: (m['type'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      amountCents: (m['amount_cents'] is int) ? m['amount_cents'] as int : 0,
      currency: (m['currency'] ?? 'DOP').toString(),
      refType: (m['ref_type'] ?? '').toString(),
      refId: (m['ref_id'] ?? '').toString(),
      note: (m['note'] ?? '').toString(),
      createdAt: t,
      createdByUid: (m['created_by_uid'] ?? '').toString(),
      createdByName: (m['created_by_name'] ?? '').toString(),
    );
  }
}
