import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
    double feePct = 0.10,
    String? agenciaNombre,
    String? agenciaLogoUrl,
    String? bannerUrl,
    String? bannerVideoUrl,
    String? puntoSalida,
    double? puntoSalidaLat,
    double? puntoSalidaLon,
    String? destinoPlaceId,
    double? destinoLat,
    double? destinoLon,
    String? choferTelefono,
    String? choferWhatsApp,
    String? bancoNombre,
    String? bancoCuenta,
    String? bancoTipoCuenta,
    String? bancoTitular,
    String? servicioBadge,
    String? tipoPersonalizado,
    List<String>? incluye,
    String? descripcionViaje,
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
      if (agenciaNombre != null && agenciaNombre.trim().isNotEmpty)
        'agenciaNombre': agenciaNombre.trim(),
      if (agenciaLogoUrl != null && agenciaLogoUrl.trim().isNotEmpty)
        'agenciaLogoUrl': agenciaLogoUrl.trim(),
      if (bannerUrl != null && bannerUrl.trim().isNotEmpty)
        'bannerUrl': bannerUrl.trim(),
      if (bannerVideoUrl != null && bannerVideoUrl.trim().isNotEmpty)
        'bannerVideoUrl': bannerVideoUrl.trim(),
      if (puntoSalida != null && puntoSalida.trim().isNotEmpty)
        'puntoSalida': puntoSalida.trim(),
      if (puntoSalidaLat != null && puntoSalidaLon != null) ...{
        'puntoSalidaLat': puntoSalidaLat,
        'puntoSalidaLon': puntoSalidaLon,
      },
      if (destinoPlaceId != null && destinoPlaceId.trim().isNotEmpty)
        'destinoPlaceId': destinoPlaceId.trim(),
      if (destinoLat != null && destinoLon != null) ...{
        'destinoLat': destinoLat,
        'destinoLon': destinoLon,
      },
      if (choferTelefono != null && choferTelefono.trim().isNotEmpty)
        'choferTelefono': choferTelefono.trim(),
      if (choferWhatsApp != null && choferWhatsApp.trim().isNotEmpty)
        'choferWhatsApp': choferWhatsApp.trim(),
      if (bancoNombre != null && bancoNombre.trim().isNotEmpty)
        'bancoNombre': bancoNombre.trim(),
      if (bancoCuenta != null && bancoCuenta.trim().isNotEmpty)
        'bancoCuenta': bancoCuenta.trim(),
      if (bancoTipoCuenta != null && bancoTipoCuenta.trim().isNotEmpty)
        'bancoTipoCuenta': bancoTipoCuenta.trim(),
      if (bancoTitular != null && bancoTitular.trim().isNotEmpty)
        'bancoTitular': bancoTitular.trim(),
      if (servicioBadge != null && servicioBadge.trim().isNotEmpty)
        'servicioBadge': servicioBadge.trim(),
      if (tipoPersonalizado != null && tipoPersonalizado.trim().isNotEmpty)
        'tipoPersonalizado': tipoPersonalizado.trim(),
      if (incluye != null && incluye.isNotEmpty)
        'incluye': incluye
            .where((e) => e.trim().isNotEmpty)
            .map((e) => e.trim())
            .toList(),
      if (descripcionViaje != null && descripcionViaje.trim().isNotEmpty)
        'descripcionViaje': descripcionViaje.trim(),
      'asientosReservados': 0,
      'asientosPagados': 0,
      'montoReservado': 0.0,
      'montoPagado': 0.0,
      'estado':
          'abierto', // abierto | preconfirmado | confirmado | lleno | cancelado | finalizado
      'ownerTaxistaId': u.uid,
      'taxistaNombre': u.displayName ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    };

    final doc = await pools.add(data);
    return doc.id;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPoolsCliente({
    String? tipo,
    String? origenTown,
    DateTime? desde,
  }) {
    // Consulta tolerante para compatibilidad con documentos legacy de agencias:
    // el filtrado fino (estado/fecha/tipo) se aplica en cliente.
    Query<Map<String, dynamic>> q = pools;

    final town = (origenTown ?? '').trim().toLowerCase();
    if (town.isNotEmpty && town != 'todos') {
      q = q.where('origenTown', isEqualTo: origenTown!.trim());
    }

    final tipoFiltro = (tipo ?? '').trim().toLowerCase();
    if (tipoFiltro.isNotEmpty && tipoFiltro != 'todos') {
      if (tipoFiltro == 'excursion' || tipoFiltro == 'excursiones') {
        q = q.where('tipo', whereIn: ['excursion', 'excursiones']);
      } else if (tipoFiltro == 'tour' || tipoFiltro == 'tours') {
        // Incluye alias legacy / admin (gira, giras) para que el cliente vea el catálogo completo.
        q = q.where('tipo', whereIn: [
          'tour',
          'tours',
          'gira',
          'giras',
          'Gira',
          'Giras',
        ]);
      } else if (tipoFiltro == 'consular' || tipoFiltro == 'consulares') {
        q = q.where('tipo', whereIn: ['consular', 'consulares']);
      } else {
        q = q.where('tipo', isEqualTo: tipoFiltro);
      }
    }

    return q.snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPoolsTaxista({
    required String ownerTaxistaId,
  }) {
    return pools.where('ownerTaxistaId', isEqualTo: ownerTaxistaId).snapshots();
  }

  /// Refuerzo de consistencia:
  /// Si el taxista tiene `usuarios.{uid}.tienePagoPendiente == true` (comisión efectivo ≥ tope),
  /// cerramos sus pools (estado => 'cancelado') para que el cliente no pueda reservar.
  ///
  /// Si luego paga y `tienePagoPendiente` pasa a false, se reabre usando
  /// `estadoPrevioPorPagoSemanal` SOLO si el pool fue cerrado por este motivo.
  static Future<void> syncPoolsPorPagoSemanal({
    required String ownerTaxistaId,
    required bool tienePagoPendiente,
  }) async {
    if (ownerTaxistaId.trim().isEmpty) return;

    final snap =
        await pools.where('ownerTaxistaId', isEqualTo: ownerTaxistaId).get();
    if (snap.docs.isEmpty) return;

    // Batch por chunks para no exceder límite de Firestore.
    const int chunkSize = 450; // < 500 (batch operations limit)
    for (var i = 0; i < snap.docs.length; i += chunkSize) {
      final docsChunk = snap.docs.skip(i).take(chunkSize).toList();
      final batch = _db.batch();

      for (final doc in docsChunk) {
        final d = doc.data();
        final String estadoActual = (d['estado'] ?? 'abierto').toString();
        final bool canceladoPorPagoSemanal =
            (d['canceladoPorPagoSemanal'] ?? false) == true;
        final String estadoPrevio =
            (d['estadoPrevioPorPagoSemanal'] ?? estadoActual).toString();

        if (tienePagoPendiente) {
          // Si ya está cancelado y fue por pago, no repetimos writes.
          if (estadoActual == 'cancelado' && canceladoPorPagoSemanal) continue;

          // Si ya está cancelado pero NO fue por pago, no tocamos (otra razón).
          if (estadoActual == 'cancelado' && !canceladoPorPagoSemanal) continue;

          batch.update(doc.reference, {
            'estado': 'cancelado',
            'canceladoPorPagoSemanal': true,
            'estadoPrevioPorPagoSemanal': estadoActual,
            'canceladoPorPagoSemanalEn': FieldValue.serverTimestamp(),
          });
        } else {
          // Reabrir solo lo que nosotros cerramos por este motivo.
          if (estadoActual == 'cancelado' && canceladoPorPagoSemanal) {
            batch.update(doc.reference, {
              'estado': estadoPrevio.isNotEmpty ? estadoPrevio : 'abierto',
              'canceladoPorPagoSemanal': false,
              'estadoPrevioPorPagoSemanal': FieldValue.delete(),
              'canceladoPorPagoSemanalEn': FieldValue.delete(),
            });
          }
        }
      }

      await batch.commit();
    }
  }

  static Future<void> reservarCupos({
    required String poolId,
    required int seats,
    required String metodoPago,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw 'Debes iniciar sesión';
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = fx.httpsCallable('reservePoolSeats');
    await callable.call(<String, dynamic>{
      'poolId': poolId,
      'seats': seats,
      'metodoPago': metodoPago,
      'idempotencyKey':
          '${poolId}_${u.uid}_${DateTime.now().millisecondsSinceEpoch}',
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
        if ((pag + seats) >= minConf && (p['estado'] != 'confirmado'))
          'estado': 'confirmado',
      });
      tx.update(resRef, {'estado': 'pagado'});
    });
  }

  static Future<void> marcarReservaPagadaSegura({
    required String poolId,
    required String reservaId,
    String? idempotencyKey,
  }) async {
    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : '${poolId}_${reservaId}_${DateTime.now().millisecondsSinceEpoch}';
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = fx.httpsCallable('confirmPoolReservationPayment');
    await callable.call(<String, dynamic>{
      'poolId': poolId,
      'reservaId': reservaId,
      'idempotencyKey': key,
    });
  }

  static Future<void> iniciarViajePoolSeguro({
    required String poolId,
    String? idempotencyKey,
  }) async {
    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : 'start_${poolId}_${DateTime.now().millisecondsSinceEpoch}';
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = fx.httpsCallable('startPoolTrip');
    await callable.call(<String, dynamic>{
      'poolId': poolId,
      'idempotencyKey': key,
    });
  }

  static Future<void> finalizarViajePoolSeguro({
    required String poolId,
    String? idempotencyKey,
  }) async {
    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : 'finish_${poolId}_${DateTime.now().millisecondsSinceEpoch}';
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = fx.httpsCallable('finalizePoolTrip');
    await callable.call(<String, dynamic>{
      'poolId': poolId,
      'idempotencyKey': key,
    });
  }

  static Future<void> cancelarViajePoolSeguro({
    required String poolId,
    String motivo = '',
    String? idempotencyKey,
  }) async {
    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : 'cancel_${poolId}_${DateTime.now().millisecondsSinceEpoch}';
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = fx.httpsCallable('cancelPoolTrip');
    await callable.call(<String, dynamic>{
      'poolId': poolId,
      'motivo': motivo,
      'idempotencyKey': key,
    });
  }

  /// Solo admin (Cloud Function valida rol): anula una gira ya **finalizada** y limpia comisión pendiente en panel.
  static Future<void> anularGiraFinalizadaAdmin({
    required String poolId,
    String motivo = '',
    String? idempotencyKey,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw 'Debes iniciar sesión';
    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : 'voidfin_${poolId}_${DateTime.now().millisecondsSinceEpoch}';
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = fx.httpsCallable('adminVoidFinalizedPool');
    await callable.call(<String, dynamic>{
      'poolId': poolId,
      'motivo': motivo,
      'idempotencyKey': key,
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

        final seats = ((r['seats'] ?? 0) as num).toInt();
        final total = ((r['total'] ?? 0.0) as num).toDouble();

        final poolSnap = await tx.get(poolRef);
        final p = poolSnap.data()!;

        final occ = ((p['asientosReservados'] ?? 0) as num).toInt();
        final newOcc = (occ - seats).clamp(0, 1 << 30);

        final metodo = (r['metodoPago'] ?? '').toString().toLowerCase().trim();
        final poolPatch = <String, dynamic>{
          'asientosReservados': newOcc,
          'montoReservado':
              ((p['montoReservado'] ?? 0.0) as num).toDouble() - total,
          if (p['estado'] == 'lleno') 'estado': 'abierto',
        };
        // En cliente no hay query en transacción; si ya existe el contador, ajustamos efectivo.
        // El job `scheduledCleanupExpiredPoolReservations` recalcula firmeza con todas las reservas.
        if (metodo == 'efectivo' && p['asientosFirmesSalida'] != null) {
          poolPatch['asientosFirmesSalida'] = FieldValue.increment(-seats);
        }

        tx.update(poolRef, poolPatch);
        tx.update(doc.reference, {'estado': 'cancelado'});
      });
      canceladas++;
    }
    return canceladas;
  }
}
