// lib/servicios/pool_repo.dart
// ignore_for_file: avoid_print -- logs operativos [GIRA_PREPAGO]

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/servicios/analytics_rai.dart';
import 'package:flygo_nuevo/servicios/comision_viaje_pct_service.dart';
import 'package:flygo_nuevo/servicios/configuracion_globals_service.dart';
import 'package:flygo_nuevo/servicios/taxista_billetera_gira_prepago.dart';

class PoolRepo {
  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get pools =>
      _db.collection('viajes_pool');

  static const String _msgGiraLegacySinComisionEstimada =
      'Esta gira fue creada con una versión anterior del sistema. Por favor, cancélala y crea una nueva.';

  static bool _poolTieneComisionGiraEstimada(Map<String, dynamic>? p) {
    final v = p?['comisionGiraEstimadaRd'];
    if (v is num && v.isFinite && v > 1e-9) return true;
    if (v is String) {
      final d = double.tryParse(v);
      return d != null && d.isFinite && d > 1e-9;
    }
    return false;
  }

  static double _round2(double v) =>
      double.parse(v.clamp(0, 1e12).toStringAsFixed(2));

  static Future<String> crearPool({
    required String tipo,
    required String sentido,
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

    await ComisionViajePctService.refresh(force: true);
    await ConfiguracionGlobalsService.refreshGiraComision(force: true);
    final abuso = await ConfiguracionGlobalsService.fetchGiraAbusoUmbral();

    final double pct = PlataformaEconomia.comisionGiraPorcentaje;
    final double factor = pct / 100.0;
    final double comisionEstimada = _round2(
      capacidad.toDouble() * precioPorAsiento * factor,
    );

    print(
      '[PRE_TEST] crearPool inicio uid=${u.uid} comisionEstimada=$comisionEstimada pct=$pct '
      'abuso_ratioMax=${abuso.ratioMax} abuso_minCreadas=${abuso.minCreadas} abuso_disabled=${abuso.disabled}',
    );

    final poolRef = pools.doc();
    final poolId = poolRef.id;
    final billeRef = _db.collection('billeteras_taxista').doc(u.uid);
    final userRef = _db.collection('usuarios').doc(u.uid);

    await _db.runTransaction((tx) async {
      final billeSnap = await tx.get(billeRef);
      final userSnap = await tx.get(userRef);
      final bille = billeSnap.data();
      final prep = TaxistaBilleteraGiraPrepago.saldoPrepagoComisionRd(bille);
      final res = TaxistaBilleteraGiraPrepago.saldoReservadoParaGiras(bille);
      final disponible = TaxistaBilleteraGiraPrepago.saldoDisponiblePrepagoComisionRd(bille);
      if (disponible + 1e-9 < comisionEstimada) {
        throw 'No tienes saldo prepago suficiente para crear esta gira. Recarga desde Mis Pagos.';
      }

      final ud = userSnap.data() ?? <String, dynamic>{};
      final Timestamp? ultimoTs = ud['ultimoReinicioContadorGiras'] as Timestamp?;
      final now = DateTime.now();
      bool resetVentana = false;
      if (ultimoTs == null) {
        resetVentana = true;
      } else {
        final diff = now.difference(ultimoTs.toDate()).inDays;
        if (diff >= 30) resetVentana = true;
      }

      int creadas = (ud['girasCreadasUltimoMes'] as num?)?.toInt() ?? 0;
      int canceladas = (ud['girasCanceladasAntesDeIniciar'] as num?)?.toInt() ?? 0;
      if (resetVentana) {
        creadas = 0;
        canceladas = 0;
      } else {
        if (!abuso.disabled && creadas >= abuso.minCreadas) {
          final ratio = canceladas / (creadas > 0 ? creadas : 1);
          if (ratio > abuso.ratioMax + 1e-9) {
            throw 'Has cancelado muchas giras sin iniciar. Contacta a soporte para regularizar.';
          }
        }
      }

      if (resetVentana) {
        tx.set(
          userRef,
          <String, dynamic>{
            'girasCreadasUltimoMes': 1,
            'girasCanceladasAntesDeIniciar': 0,
            'ultimoReinicioContadorGiras': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } else {
        tx.set(
          userRef,
          <String, dynamic>{
            'girasCreadasUltimoMes': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      print(
        '[PRE_TEST] crearPool saldos en tx uid=${u.uid} poolId=$poolId prepAntes=$prep '
        'reservAntes=$res disponibleAntes=$disponible',
      );

      final prepNuevo = _round2(prep - comisionEstimada);
      final resNuevo = _round2(res + comisionEstimada);
      tx.set(
        billeRef,
        <String, dynamic>{
          'saldoPrepagoComisionRd': prepNuevo,
          'saldoReservadoParaGiras': resNuevo,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

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
        'estado': 'abierto',
        'ownerTaxistaId': u.uid,
        'taxistaNombre': u.displayName ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'comisionGiraEstimadaRd': comisionEstimada,
        'comisionGiraPctUsado': pct,
        'prepagoComisionEtapa': 'reservada_creacion',
      };

      tx.set(poolRef, data);

      print(
        '[PRE_TEST] crearPool saldos post-reserva uid=${u.uid} poolId=$poolId prep=$prepNuevo '
        'reserv=$resNuevo',
      );
      print(
        '[GIRA_PREPAGO] crearPool tx ok poolId=$poolId comisionEstimada=$comisionEstimada',
      );
    });

    try {
      final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
      await fx.httpsCallable('appendLedgerGiraReserva').call(<String, dynamic>{
        'poolId': poolId,
        'idempotencyKey': 'ledger_reserva_$poolId',
      });
      print('[PRE_TEST] appendLedgerGiraReserva ok poolId=$poolId uid=${u.uid}');
    } catch (e, st) {
      print(
        '[PRE_TEST][ERROR] appendLedgerGiraReserva poolId=$poolId uid=${u.uid} err=$e',
      );
      print('[PRE_TEST][ERROR] stack=$st');
    }

    unawaited(
      AnalyticsRai.logGiraCreated(
        comisionEstimada: comisionEstimada,
        capacidad: capacidad,
        precioPorAsiento: precioPorAsiento,
      ),
    );
    return poolId;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPoolsCliente({
    String? tipo,
    String? origenTown,
    DateTime? desde,
  }) {
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

  static Future<void> _refundGiraReservaTrasCierrePagoSemanal(String poolId) async {
    try {
      final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = fx.httpsCallable('refundGiraReservaPagoSemanal');
      await callable.call(<String, dynamic>{
        'poolId': poolId,
        'idempotencyKey': 'ps_refund_$poolId',
      });
      print('[PRE_TEST] refundGiraReservaPagoSemanal ok poolId=$poolId');
    } catch (e) {
      print('[PRE_TEST][ERROR] refundGiraReservaPagoSemanal poolId=$poolId err=$e');
    }
  }

  static Future<void> syncPoolsPorPagoSemanal({
    required String ownerTaxistaId,
    required bool tienePagoPendiente,
  }) async {
    if (ownerTaxistaId.trim().isEmpty) return;

    final snap =
        await pools.where('ownerTaxistaId', isEqualTo: ownerTaxistaId).get();
    if (snap.docs.isEmpty) return;

    const int chunkSize = 450;
    final List<String> refundPoolIds = [];

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
          if (estadoActual == 'cancelado' && canceladoPorPagoSemanal) continue;
          if (estadoActual == 'cancelado' && !canceladoPorPagoSemanal) continue;

          batch.update(doc.reference, {
            'estado': 'cancelado',
            'canceladoPorPagoSemanal': true,
            'estadoPrevioPorPagoSemanal': estadoActual,
            'canceladoPorPagoSemanalEn': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          refundPoolIds.add(doc.id);
        } else {
          if (estadoActual == 'cancelado' && canceladoPorPagoSemanal) {
            batch.update(doc.reference, {
              'estado': estadoPrevio.isNotEmpty ? estadoPrevio : 'abierto',
              'canceladoPorPagoSemanal': false,
              'estadoPrevioPorPagoSemanal': FieldValue.delete(),
              'canceladoPorPagoSemanalEn': FieldValue.delete(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      }

      await batch.commit();
    }

    if (tienePagoPendiente) {
      for (final id in refundPoolIds) {
        await _refundGiraReservaTrasCierrePagoSemanal(id);
      }
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

  static Future<Map<String, dynamic>> iniciarViajePoolSeguro({
    required String poolId,
    String? idempotencyKey,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw 'Debes iniciar sesión como taxista';

    final poolSnap = await pools.doc(poolId).get();
    if (!_poolTieneComisionGiraEstimada(poolSnap.data())) {
      throw _msgGiraLegacySinComisionEstimada;
    }

    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : 'start_${poolId}_${DateTime.now().millisecondsSinceEpoch}';
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    print('[PRE_TEST] iniciarViajePoolSeguro uid=${u.uid} poolId=$poolId');
    final callable = fx.httpsCallable('startPoolTrip');
    final res = await callable.call(<String, dynamic>{
      'poolId': poolId,
      'idempotencyKey': key,
    });
    final raw = res.data;
    if (raw == null) return <String, dynamic>{};
    final map =
        raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw as Map);
    print('[PRE_TEST] iniciarViajePoolSeguro resultado uid=${u.uid} poolId=$poolId map=$map');
    print('[GIRA_PREPAGO] iniciarViajePoolSeguro poolId=$poolId result=$map');
    return map;
  }

  static Future<Map<String, dynamic>> finalizarViajePoolSeguro({
    required String poolId,
    String? idempotencyKey,
  }) async {
    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : 'finish_${poolId}_${DateTime.now().millisecondsSinceEpoch}';
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = fx.httpsCallable('finalizePoolTrip');
    final res = await callable.call(<String, dynamic>{
      'poolId': poolId,
      'idempotencyKey': key,
    });
    final raw = res.data;
    if (raw == null) return <String, dynamic>{};
    final map =
        raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw as Map);
    print('[GIRA_PREPAGO] finalizarViajePoolSeguro poolId=$poolId result=$map');
    return map;
  }

  static Future<Map<String, dynamic>> cancelarViajePoolSeguro({
    required String poolId,
    String motivo = '',
    String? idempotencyKey,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw 'Debes iniciar sesión como taxista';

    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : 'cancel_${poolId}_${DateTime.now().millisecondsSinceEpoch}';
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    print('[PRE_TEST] cancelarViajePoolSeguro uid=${u.uid} poolId=$poolId');
    final callable = fx.httpsCallable('cancelPoolTrip');
    final res = await callable.call(<String, dynamic>{
      'poolId': poolId,
      'motivo': motivo,
      'idempotencyKey': key,
    });
    final raw = res.data;
    if (raw == null) return <String, dynamic>{};
    final map =
        raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw as Map);
    print('[PRE_TEST] cancelarViajePoolSeguro resultado uid=${u.uid} poolId=$poolId map=$map');
    print('[GIRA_PREPAGO] cancelarViajePoolSeguro poolId=$poolId result=$map');
    return map;
  }

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

  static Future<Map<String, dynamic>> adminReleaseGiraReservation({
    required String poolId,
    String? idempotencyKey,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw 'Debes iniciar sesión';
    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : 'admrel_${poolId}_${DateTime.now().millisecondsSinceEpoch}';
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = fx.httpsCallable('adminReleaseGiraReservation');
    final res = await callable.call(<String, dynamic>{
      'poolId': poolId,
      'idempotencyKey': key,
    });
    final raw = res.data;
    if (raw == null) return <String, dynamic>{};
    return raw is Map<String, dynamic>
        ? raw
        : Map<String, dynamic>.from(raw as Map);
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
