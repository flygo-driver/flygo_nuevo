import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PoolRepo {
  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get pools =>
      _db.collection('viajes_pool');

  static Future<String> crearPool({
    required String tipo, // "consular" | "tour"
    required String sentido, // "ida" | "vuelta" | "ida_y_vuelta"
    required String origenTown,
    required String destino,
    required DateTime fechaSalida,
    DateTime? fechaVuelta,
    required int capacidad,
    required int minParaConfirmar,
    required double precioPorAsiento,
    List<String>? pickupPoints,
    double depositPct = 0.30,
    double feePct = 0.12,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw 'Debes iniciar sesión como taxista';

    final data = <String, dynamic>{
      'tipo': tipo,
      'sentido': sentido,
      'origenTown': origenTown.trim(),
      'destino': destino.trim(),
      'fechaSalida': Timestamp.fromDate(fechaSalida),
      if (fechaVuelta != null) 'fechaVuelta': Timestamp.fromDate(fechaVuelta),
      'capacidad': capacidad,
      'minParaConfirmar': minParaConfirmar,
      'precioPorAsiento': precioPorAsiento,
      'pickupPoints': (pickupPoints != null && pickupPoints.isNotEmpty)
          ? pickupPoints
          : ['Parque Central de $origenTown'],
      'depositPct': depositPct,
      'feePct': feePct,
      'asientosReservados': 0,
      'asientosPagados': 0,
      'montoReservado': 0.0,
      'montoPagado': 0.0,
      'estado': 'abierto', // abierto | preconfirmado | confirmado | lleno | cancelado | finalizado
      'ownerTaxistaId': u.uid,
      'taxistaNombre': u.displayName ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    };

    final doc = await pools.add(data);
    return doc.id;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPoolsCliente({
    required String tipo,
    required String origenTown,
    DateTime? desde,
  }) {
    final now = desde ?? DateTime.now();
    return pools
        .where('tipo', isEqualTo: tipo)
        .where('origenTown', isEqualTo: origenTown)
        .where('estado', whereIn: ['abierto', 'preconfirmado', 'confirmado'])
        .where('fechaSalida', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .orderBy('fechaSalida')
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPoolsTaxista({
    required String ownerTaxistaId,
  }) {
    return pools
        .where('ownerTaxistaId', isEqualTo: ownerTaxistaId)
        .orderBy('fechaSalida')
        .snapshots();
  }

  static Future<void> reservarCupos({
    required String poolId,
    required int seats,
    required String metodoPago,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw 'Debes iniciar sesión';

    final poolRef = pools.doc(poolId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(poolRef);
      if (!snap.exists) throw 'Viaje no existe';
      final d = snap.data()!;
      final cap = (d['capacidad'] ?? 0) as int;
      final occ = (d['asientosReservados'] ?? 0) as int;
      final minConf = (d['minParaConfirmar'] ?? 0) as int;
      final precio = (d['precioPorAsiento'] as num).toDouble();
      final mult = (d['sentido'] == 'ida_y_vuelta') ? 2 : 1;
      final depositPct = ((d['depositPct'] ?? 0.0) as num).toDouble();

      if (seats <= 0) throw 'Asientos inválidos';
      if (occ + seats > cap) throw 'No hay suficientes cupos';

      final total = precio * seats * mult;
      final deposit = total * depositPct;
      final expiresAt = Timestamp.fromDate(DateTime.now().add(const Duration(hours: 2)));

      tx.update(poolRef, {
        'asientosReservados': occ + seats,
        'montoReservado': ((d['montoReservado'] ?? 0.0) as num).toDouble() + total,
        if ((occ + seats) >= cap) 'estado': 'lleno',
        if ((occ + seats) >= minConf && (d['estado'] == 'abierto')) 'estado': 'preconfirmado',
      });

      final resRef = poolRef.collection('reservas').doc();
      tx.set(resRef, {
        'uidCliente': u.uid,
        'seats': seats,
        'estado': 'reservado', // reservado | pagado | cancelado
        'metodoPago': metodoPago,
        'total': total,
        'deposit': deposit,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': expiresAt,
      });
    });
  }

  static Future<void> marcarReservaPagada({
    required String poolId,
    required String reservaId,
  }) async {
    final poolRef = pools.doc(poolId);
    final resRef = poolRef.collection('reservas').doc(reservaId);

    await _db.runTransaction((tx) async {
      final resSnap = await tx.get(resRef);
      if (!resSnap.exists) throw 'Reserva no encontrada';
      final r = resSnap.data()!;
      if (r['estado'] == 'pagado') return;

      final seats = (r['seats'] ?? 0) as int;
      final total = ((r['total'] ?? 0.0) as num).toDouble();

      final poolSnap = await tx.get(poolRef);
      final p = poolSnap.data()!;
      final minConf = (p['minParaConfirmar'] ?? 0) as int;
      final pag = (p['asientosPagados'] ?? 0) as int;

      tx.update(poolRef, {
        'asientosPagados': pag + seats,
        'montoPagado': ((p['montoPagado'] ?? 0.0) as num).toDouble() + total,
        if ((pag + seats) >= minConf && (p['estado'] != 'confirmado')) 'estado': 'confirmado',
      });
      tx.update(resRef, {'estado': 'pagado'});
    });
  }

  static Future<int> limpiarReservasVencidas(String poolId) async {
    final poolRef = pools.doc(poolId);
    final now = Timestamp.fromDate(DateTime.now());
    final q = await poolRef
        .collection('reservas')
        .where('estado', isEqualTo: 'reservado')
        .where('expiresAt', isLessThan: now)
        .get();

    int canceladas = 0;
    for (final doc in q.docs) {
      await _db.runTransaction((tx) async {
        final resSnap = await tx.get(doc.reference);
        if (!resSnap.exists) return;
        final r = resSnap.data()!;
        if (r['estado'] != 'reservado') return;

        final seats = (r['seats'] ?? 0) as int;
        final total = ((r['total'] ?? 0.0) as num).toDouble();

        final poolSnap = await tx.get(poolRef);
        final p = poolSnap.data()!;
        final occ = (p['asientosReservados'] ?? 0) as int;
        final newOcc = (occ - seats).clamp(0, 1 << 30);

        tx.update(poolRef, {
          'asientosReservados': newOcc,
          'montoReservado': ((p['montoReservado'] ?? 0.0) as num).toDouble() - total,
          if (p['estado'] == 'lleno') 'estado': 'abierto',
        });
        tx.update(doc.reference, {'estado': 'cancelado'});
      });
      canceladas++;
    }
    return canceladas;
  }
}
