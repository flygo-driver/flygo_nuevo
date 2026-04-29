// lib/servicios/pagos_taxista_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../modelo/pago_taxista.dart';
import '../modelo/recarga_comision_taxista.dart';
import 'pool_repo.dart';
import 'taxista_prepago_ledger.dart';

class PagosTaxistaRepo {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('pagos_taxistas');
  static const List<String> _estadosDeudaAbierta = <String>[
    'pendiente',
    'vencido',
    'pendiente_verificacion',
    'rechazado',
  ];

  /// Cierra o reabre `viajes_pool` del taxista según la bandera (misma regla que [TaxistaEntry]).
  /// Comisión efectivo acumulada (RD$) en `billeteras_taxista`.
  static double comisionPendienteDesdeBilletera(Map<String, dynamic>? data) {
    final v = data?['comisionPendiente'];
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static double saldoPrepagoComisionDesdeBilletera(Map<String, dynamic>? data) {
    final v = data?['saldoPrepagoComisionRd'];
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static bool primerViajeComisionGratisConsumido(Map<String, dynamic>? data) {
    return data?['primerViajeComisionGratisConsumido'] == true;
  }

  /// Deuda legacy en billetera (ya no sube con viajes nuevos): mismo tope que Cloud Functions.
  static const double umbralComisionLegacyBloqueoRd = 500;

  /// Tras el primer viaje en efectivo gratis, saldo prepago mínimo para pool / tomar viajes.
  static const double minSaldoPrepagoComisionRd = 200;

  /// Alias histórico (UI que hablaba de “tope 500”): hoy es el tope solo de `comisionPendiente` legacy.
  static const double umbralBloqueoComisionEfectivoRd =
      umbralComisionLegacyBloqueoRd;

  /// Textos UX (prepago + comisión 20% en efectivo).
  static const String mensajeRecargaTomarViajes =
      'Recarga crédito prepago (mín. RD\$200): el 20% de cada viaje en efectivo se descuenta de tu saldo. '
      'Sin saldo suficiente no puedes tomar viajes ni pool.';

  static const String mensajeRecargaActivarDisponible =
      'Sin el saldo prepago mínimo no puedes quedar disponible. Recarga desde Mis pagos; '
      'al verificar el admin, podrás activarte de nuevo.';

  static const String mensajeRecargaBannerLista =
      'Servicio cortado: falta crédito prepago para comisión en efectivo. Recarga desde Mis pagos.';

  static const String mensajeRecargaListaVacia =
      'No hay viajes disponibles hasta que regularices tu saldo prepago (comisión efectivo).';

  static String get mensajeRecargaAccesoPantallaCompleta =>
      'Tu acceso queda suspendido: necesitas al menos RD\$${minSaldoPrepagoComisionRd.toStringAsFixed(0)} '
      'de saldo prepago tras tu primer viaje en efectivo (el 20% de cada efectivo se descuenta del saldo), '
      'o regularizar comisión legacy ≥ RD\$${umbralComisionLegacyBloqueoRd.toStringAsFixed(0)}. '
      'Recarga desde Mis pagos; al verificar el admin, el servicio vuelve.';

  /// Misma regla que `bloqueoOperativoPrepago` en Cloud Functions.
  static bool bloqueoOperativoPorComisionEfectivo(
      Map<String, dynamic>? billeData) {
    final pend = comisionPendienteDesdeBilletera(billeData);
    if (pend >= umbralComisionLegacyBloqueoRd - 1e-6) return true;
    if (pend > 1e-6) return false;
    if (!primerViajeComisionGratisConsumido(billeData)) return false;
    return saldoPrepagoComisionDesdeBilletera(billeData) <
        minSaldoPrepagoComisionRd - 1e-6;
  }

  /// Una sola fuente para pool, reclamar viaje, encadenar siguiente y asignación turismo:
  /// [usuarios.tienePagoPendiente] + prepago mínimo / tope legacy en [billeteras_taxista].
  static bool taxistaSinBloqueoPrepagoOperativo(
    Map<String, dynamic>? uData,
    Map<String, dynamic>? billeData,
  ) {
    if (uData != null && uData['tienePagoPendiente'] == true) return false;
    if (bloqueoOperativoPorComisionEfectivo(billeData)) return false;
    return true;
  }

  /// Panel Mis pagos: mostrar recarga si aplica bloqueo operativo o aún hay deuda legacy > 0.
  static bool debeMostrarPanelRecargaComisionEfectivo(
      Map<String, dynamic>? billeData) {
    return bloqueoOperativoPorComisionEfectivo(billeData) ||
        comisionPendienteDesdeBilletera(billeData) > 1e-6;
  }

  static Future<bool> tieneBloqueoComisionEfectivo(String uidTaxista) async {
    if (uidTaxista.trim().isEmpty) return false;
    final b = await _db.collection('billeteras_taxista').doc(uidTaxista).get();
    return bloqueoOperativoPorComisionEfectivo(b.data());
  }

  /// Bloqueo operativo (pool, tomar viajes): saldo prepago bajo o comisión legacy ≥ tope.
  /// La deuda semanal abierta se gestiona en Mis pagos y no cierra el pool por sí sola.
  static Future<bool> tieneBloqueoOperativo(String uidTaxista) async {
    return tieneBloqueoComisionEfectivo(uidTaxista);
  }

  /// Sincroniza `usuarios.tienePagoPendiente` y pools según prepago / legacy (no deuda semanal).
  static Future<void> sincronizarBloqueoOperativo(String uidTaxista) =>
      _sincronizarBanderaPendiente(uidTaxista);

  /// Payload para bajar `comisionPendiente` (tope = saldo actual). Una sola fuente de verdad para liquidaciones.
  static Map<String, dynamic> _payloadLiquidarComisionPendiente({
    required Map<String, dynamic>? billeData,
    required double montoLiquidarRd,
    String? referenciaBanco,
  }) {
    final actual = comisionPendienteDesdeBilletera(billeData);
    if (actual <= 1e-9) {
      throw Exception('No hay comisión en efectivo pendiente que liquidar');
    }
    if (montoLiquidarRd <= 0) throw Exception('El monto debe ser mayor que 0');
    final liquidar = montoLiquidarRd > actual ? actual : montoLiquidarRd;
    final nuevo = (actual - liquidar).clamp(0.0, double.infinity);
    return <String, dynamic>{
      'comisionPendiente': double.parse(nuevo.toStringAsFixed(2)),
      'updatedAt': FieldValue.serverTimestamp(),
      'ultimaLiquidacionComisionEn': FieldValue.serverTimestamp(),
      'ultimaLiquidacionComisionMonto':
          double.parse(liquidar.toStringAsFixed(2)),
      if (referenciaBanco != null && referenciaBanco.trim().isNotEmpty)
        'ultimaLiquidacionComisionRef': referenciaBanco.trim(),
    };
  }

  static Map<String, dynamic> _payloadAcreditarSaldoPrepagoComision({
    required Map<String, dynamic>? billeData,
    required double montoAcreditarRd,
    String? referenciaBanco,
  }) {
    if (montoAcreditarRd <= 0) throw Exception('El monto debe ser mayor que 0');
    final actual = saldoPrepagoComisionDesdeBilletera(billeData);
    final nuevo = actual + montoAcreditarRd;
    return <String, dynamic>{
      'saldoPrepagoComisionRd': double.parse(nuevo.toStringAsFixed(2)),
      'updatedAt': FieldValue.serverTimestamp(),
      'ultimaRecargaPrepagoComisionEn': FieldValue.serverTimestamp(),
      'ultimaRecargaPrepagoComisionMonto':
          double.parse(montoAcreditarRd.toStringAsFixed(2)),
      if (referenciaBanco != null && referenciaBanco.trim().isNotEmpty)
        'ultimaRecargaPrepagoComisionRef': referenciaBanco.trim(),
    };
  }

  /// Admin: el taxista transfirió y tú verificaste el depósito. Baja `comisionPendiente` en
  /// `billeteras_taxista`, luego [sincronizarBloqueoOperativo] (bandera + pools). Si el monto
  /// excede lo pendiente, solo liquida hasta el saldo.
  static Future<void> adminLiquidarComisionEfectivoVerificado({
    required String uidTaxista,
    required double montoLiquidarRd,
    String? referenciaBanco,
  }) async {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) throw Exception('UID vacío');
    final bRef = _db.collection('billeteras_taxista').doc(uid);
    await _db.runTransaction((tx) async {
      final s = await tx.get(bRef);
      final pendAntes = comisionPendienteDesdeBilletera(s.data());
      final payload = _payloadLiquidarComisionPendiente(
        billeData: s.data(),
        montoLiquidarRd: montoLiquidarRd,
        referenciaBanco: referenciaBanco,
      );
      final pendDespuesRaw = payload['comisionPendiente'];
      final pendDespues = pendDespuesRaw is num
          ? pendDespuesRaw.toDouble()
          : double.tryParse('$pendDespuesRaw') ?? 0.0;
      final liquReal = payload['ultimaLiquidacionComisionMonto'];
      final double montoLiqReal =
          liquReal is num ? liquReal.toDouble() : montoLiquidarRd;
      await TaxistaPrepagoLedger.appendLiquidacionLegacy(
        tx: tx,
        uidTaxista: uid,
        pendienteAntes: pendAntes,
        pendienteDespues: pendDespues,
        montoLiquidarDeclaradoRd: montoLiqReal,
        referencia: referenciaBanco,
      );
      if (s.exists) {
        tx.update(bRef, payload);
      } else {
        tx.set(bRef, payload, SetOptions(merge: true));
      }
    });
    await sincronizarBloqueoOperativo(uid);
  }

  static Future<void> _syncPoolsTrasBandera(
    String uidTaxista,
    bool tienePagoPendiente,
  ) async {
    if (uidTaxista.trim().isEmpty) return;
    try {
      await PoolRepo.syncPoolsPorPagoSemanal(
        ownerTaxistaId: uidTaxista,
        tienePagoPendiente: tienePagoPendiente,
      );
    } catch (e) {
      debugPrint('[PagosTaxistaRepo] syncPoolsTrasBandera: $e');
    }
  }

  static Future<void> _sincronizarBanderaPendiente(String uidTaxista) async {
    if (uidTaxista.trim().isEmpty) return;
    final bille =
        await _db.collection('billeteras_taxista').doc(uidTaxista).get();
    final bool tienePagoPendiente =
        bloqueoOperativoPorComisionEfectivo(bille.data());
    await _db.collection('usuarios').doc(uidTaxista).set(
      {
        'tienePagoPendiente': tienePagoPendiente,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await _syncPoolsTrasBandera(uidTaxista, tienePagoPendiente);
  }

  // ==============================================================
  // RECARGAS COMISIÓN EFECTIVO (comprobante → admin verifica → billetera)
  // ==============================================================
  static CollectionReference<Map<String, dynamic>> get _recargasCol =>
      _db.collection('recargas_comision_taxista');

  static Stream<List<RecargaComisionTaxista>>
      streamRecargasComisionPendientesAdmin() {
    return _recargasCol
        .where('estado', isEqualTo: 'pendiente_verificacion')
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(RecargaComisionTaxista.fromDoc).toList();
      list.sort((a, b) {
        final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });
      return list;
    });
  }

  static Stream<List<RecargaComisionTaxista>> streamRecargasComisionPorTaxista(
      String uidTaxista) {
    final u = uidTaxista.trim();
    if (u.isEmpty) return Stream.value(<RecargaComisionTaxista>[]);
    return _recargasCol
        .where('uidTaxista', isEqualTo: u)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(RecargaComisionTaxista.fromDoc).toList();
      list.sort((a, b) {
        final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });
      return list;
    });
  }

  static Future<void> taxistaEnviarRecargaComisionEfectivo({
    required String uidTaxista,
    required String nombreTaxista,
    required double montoDeclaradoRd,
    required String comprobanteUrl,
    String metodoPago = 'transferencia',
  }) async {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) throw Exception('Sesión inválida');
    final url = comprobanteUrl.trim();
    if (url.isEmpty) throw Exception('Debes subir el comprobante');
    if (montoDeclaradoRd <= 0) {
      throw Exception('Indica el monto que transferiste');
    }
    final abierta = await _recargasCol
        .where('uidTaxista', isEqualTo: uid)
        .where('estado', isEqualTo: 'pendiente_verificacion')
        .limit(1)
        .get();
    if (abierta.docs.isNotEmpty) {
      throw Exception(
          'Ya tienes una recarga en revisión. Espera a que el administrador la verifique.');
    }
    final b = await _db.collection('billeteras_taxista').doc(uid).get();
    final bill = b.data();
    final pend = comisionPendienteDesdeBilletera(bill);
    final saldo = saldoPrepagoComisionDesdeBilletera(bill);
    await _recargasCol.add({
      'uidTaxista': uid,
      'nombreTaxista':
          nombreTaxista.trim().isEmpty ? 'Taxista' : nombreTaxista.trim(),
      'comisionPendienteAlEnviar': double.parse(pend.toStringAsFixed(2)),
      'saldoPrepagoAlEnviar': double.parse(saldo.toStringAsFixed(2)),
      'montoDeclaradoRd': double.parse(montoDeclaradoRd.toStringAsFixed(2)),
      'comprobanteUrl': url,
      'metodoPago':
          metodoPago.trim().isEmpty ? 'transferencia' : metodoPago.trim(),
      'estado': 'pendiente_verificacion',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> adminVerificarRecargaComisionEfectivo({
    required String recargaId,
    required bool aprobado,
    String? notaAdmin,
  }) async {
    final ref = _recargasCol.doc(recargaId.trim());
    if (aprobado) {
      /// Cobro + cierre de solicitud en **una** transacción: no puede quedar pagado en billetera
      /// y la recarga aún en revisión (evita doble aprobación y estados incoherentes).
      var uidParaSync = '';
      await _db.runTransaction((tx) async {
        final recSnap = await tx.get(ref);
        if (!recSnap.exists) throw Exception('Recarga no encontrada');
        final m = recSnap.data() ?? {};
        if ((m['estado'] ?? '').toString() != 'pendiente_verificacion') {
          throw Exception('Esta solicitud ya fue procesada');
        }
        final uid = (m['uidTaxista'] ?? '').toString();
        if (uid.isEmpty) throw Exception('Recarga sin taxista');
        final montoRaw = m['montoDeclaradoRd'];
        final monto = montoRaw is num
            ? montoRaw.toDouble()
            : double.tryParse('$montoRaw') ?? 0.0;
        if (monto <= 0) throw Exception('Monto inválido en la solicitud');
        uidParaSync = uid;
        final bRef = _db.collection('billeteras_taxista').doc(uid);
        final bSnap = await tx.get(bRef);
        final saldoAntes = saldoPrepagoComisionDesdeBilletera(bSnap.data());
        final pendAntes = comisionPendienteDesdeBilletera(bSnap.data());
        final payloadBille = _payloadAcreditarSaldoPrepagoComision(
          billeData: bSnap.data(),
          montoAcreditarRd: monto,
          referenciaBanco: 'recarga:${recargaId.trim()}',
        );
        final saldoDespuesRaw = payloadBille['saldoPrepagoComisionRd'];
        final saldoDespues = saldoDespuesRaw is num
            ? saldoDespuesRaw.toDouble()
            : double.tryParse('$saldoDespuesRaw') ?? saldoAntes;
        await TaxistaPrepagoLedger.appendRecargaPrepagoVerificada(
          tx: tx,
          uidTaxista: uid,
          recargaId: recargaId.trim(),
          saldoPrepagoAntes: saldoAntes,
          saldoPrepagoDespues: saldoDespues,
          comisionPendienteAntes: pendAntes,
          comisionPendienteDespues: pendAntes,
          montoAcreditadoRd: monto,
          referencia: 'recarga:${recargaId.trim()}',
        );
        if (bSnap.exists) {
          tx.update(bRef, payloadBille);
        } else {
          tx.set(bRef, payloadBille, SetOptions(merge: true));
        }
        tx.update(ref, {
          'estado': 'pagado',
          'notaAdmin': notaAdmin,
          'updatedAt': FieldValue.serverTimestamp(),
          'verificadoEn': FieldValue.serverTimestamp(),
        });
      });
      if (uidParaSync.isNotEmpty) {
        await sincronizarBloqueoOperativo(uidParaSync);
      }
    } else {
      final motivo = (notaAdmin ?? '').trim();
      if (motivo.isEmpty) throw Exception('Indica el motivo del rechazo');
      await _db.runTransaction((tx) async {
        final recSnap = await tx.get(ref);
        if (!recSnap.exists) throw Exception('Recarga no encontrada');
        final m = recSnap.data() ?? {};
        if ((m['estado'] ?? '').toString() != 'pendiente_verificacion') {
          throw Exception('Esta solicitud ya fue procesada');
        }
        tx.update(ref, {
          'estado': 'rechazado',
          'notaAdmin': motivo,
          'updatedAt': FieldValue.serverTimestamp(),
          'verificadoEn': FieldValue.serverTimestamp(),
        });
      });
    }
  }

  // ==============================================================
  // GENERAR PAGO SEMANAL (llamado por Cloud Function o manualmente)
  // ==============================================================
  static Future<void> generarPagoSemanal(String uidTaxista) async {
    try {
      // Calcular fechas de la semana actual
      final now = DateTime.now();
      final fechaFin = DateTime(now.year, now.month, now.day);
      final fechaInicio = fechaFin.subtract(const Duration(days: 7));

      // Número de semana
      final semanaStr = _getWeekString(now);

      final String pagoId = '${uidTaxista}_$semanaStr';
      final DocumentReference<Map<String, dynamic>> pagoRef = _col.doc(pagoId);

      // Obtener nombre del taxista
      final userDoc = await _db.collection('usuarios').doc(uidTaxista).get();
      final userData = userDoc.data() ?? {};
      final nombreTaxista = userData['nombre'] ?? 'Sin nombre';

      // Calcular viajes de la semana
      final viajes = await _db
          .collection('viajes')
          .where('uidTaxista', isEqualTo: uidTaxista)
          .where('completado', isEqualTo: true)
          .where('finalizadoEn',
              isGreaterThanOrEqualTo: Timestamp.fromDate(fechaInicio))
          .where('finalizadoEn',
              isLessThanOrEqualTo: Timestamp.fromDate(fechaFin))
          .get();

      double totalGanado = 0; // 80% para taxista
      double totalComision = 0; // 20% para admin

      for (var viaje in viajes.docs) {
        final data = viaje.data();
        // ✅ USAR LOS CAMPOS CORRECTOS
        totalGanado += (data['gananciaTaxista'] ?? 0).toDouble();
        totalComision += (data['comision'] ?? 0).toDouble();
      }

      final viajesSemana = viajes.docs.length;

      // Si no hay viajes, no generar pago
      if (viajesSemana == 0) return;

      // Crear documento de pago
      final pago = PagoTaxista(
        id: pagoId,
        uidTaxista: uidTaxista,
        nombreTaxista: nombreTaxista,
        semana: semanaStr,
        fechaInicio: fechaInicio,
        fechaFin: fechaFin,
        totalGanado: totalGanado,
        comision: totalComision,
        netoAPagar: totalGanado, // El taxista recibe el 80%
        estado: 'pendiente',
        viajesSemana: viajesSemana,
      );

      final bool insertado = await _db.runTransaction<bool>((tx) async {
        final pagoSnap = await tx.get(pagoRef);
        if (pagoSnap.exists) {
          return false;
        }
        tx.set(pagoRef, {
          ...pago.toMap(),
          'id': pagoId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.set(
            _db.collection('usuarios').doc(uidTaxista),
            {
              'semanaPendiente': semanaStr,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
        return true;
      });
      if (insertado) {
        await sincronizarBloqueoOperativo(uidTaxista);
      }
    } catch (e) {
      debugPrint('Error generando pago semanal: $e');
    }
  }

  // ==============================================================
  // GENERAR PAGOS PARA TODOS LOS TAXISTAS (ejecutar cada domingo)
  // ==============================================================
  static Future<void> generarPagosSemanales() async {
    try {
      // Obtener todos los taxistas
      final taxistas = await _db
          .collection('usuarios')
          .where('rol', isEqualTo: 'taxista')
          .get();

      for (var taxista in taxistas.docs) {
        await generarPagoSemanal(taxista.id);
      }
    } catch (e) {
      debugPrint('Error generando pagos semanales: $e');
    }
  }

  // ==============================================================
  // VERIFICAR SI TAXISTA PUEDE TRABAJAR
  // ==============================================================
  static Future<bool> puedeTrabajar(String uidTaxista) async {
    try {
      // Verificar si tiene pagos vencidos (más de 2 semanas)
      final now = DateTime.now();
      final dosSemanasAtras = now.subtract(const Duration(days: 14));

      final pagosVencidos = await _col
          .where('uidTaxista', isEqualTo: uidTaxista)
          .where('estado', whereIn: _estadosDeudaAbierta)
          .where('fechaFin', isLessThan: Timestamp.fromDate(dosSemanasAtras))
          .limit(1)
          .get();

      if (pagosVencidos.docs.isNotEmpty) {
        return false; // Bloqueado por deuda
      }

      return true;
    } catch (e) {
      debugPrint('Error verificando si puede trabajar: $e');
      return true; // Por seguridad, permitir trabajar si hay error
    }
  }

  /// `true` si hay documentos de pago semanal en estados abiertos (cobro/recordatorio en Mis pagos).
  /// No implica bloqueo operativo del pool; ver [tieneBloqueoOperativo].
  static Future<bool> tieneBloqueoSemanal(String uidTaxista) async {
    try {
      final pendientes = await _col
          .where('uidTaxista', isEqualTo: uidTaxista)
          .where('estado', whereIn: _estadosDeudaAbierta)
          .limit(1)
          .get();
      return pendientes.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error verificando bloqueo semanal: $e');
      // Fallback conservador para producción financiera.
      return true;
    }
  }

  // ==============================================================
  // SUBIR COMPROBANTE DE PAGO (Taxista)
  // ==============================================================
  static Future<void> subirComprobante({
    required String pagoId,
    required String comprobanteUrl,
    required String metodoPago,
  }) async {
    final ref = _col.doc(pagoId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Pago no encontrado');
      final data = snap.data() ?? {};
      final String estado =
          (data['estado'] ?? '').toString().trim().toLowerCase();
      if (estado == 'pagado') throw Exception('Este pago ya fue aprobado');
      if (estado == 'pendiente_verificacion') {
        final String prevUrl = (data['comprobanteUrl'] ?? '').toString();
        if (prevUrl == comprobanteUrl) return; // idempotencia
      }
      tx.update(ref, {
        'comprobanteUrl': comprobanteUrl,
        'metodoPago': metodoPago,
        'estado': 'pendiente_verificacion',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ==============================================================
  // VERIFICAR PAGO (Admin)
  // ==============================================================
  static Future<void> verificarPago({
    required String pagoId,
    required bool aprobado,
    String? notaAdmin,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final pagoRef = _col.doc(pagoId);

    await _db.runTransaction((tx) async {
      final pagoSnap = await tx.get(pagoRef);
      if (!pagoSnap.exists) throw 'Pago no encontrado';

      final pagoData = pagoSnap.data()!;
      final String uidTaxista = (pagoData['uidTaxista'] ?? '').toString();
      final String estadoActual =
          (pagoData['estado'] ?? '').toString().trim().toLowerCase();
      if (uidTaxista.isEmpty) throw 'Pago sin uidTaxista';
      if (estadoActual == 'pagado' || estadoActual == 'rechazado') {
        final bool coincideAccion = (aprobado && estadoActual == 'pagado') ||
            (!aprobado && estadoActual == 'rechazado');
        if (coincideAccion) return; // idempotente ante doble click/reintento
        throw 'Este pago ya fue procesado';
      }
      if (!(estadoActual == 'pendiente' ||
          estadoActual == 'pendiente_verificacion')) {
        throw 'Estado no válido para verificación: $estadoActual';
      }

      if (aprobado) {
        tx.update(pagoRef, {
          'estado': 'pagado',
          'fechaPago': FieldValue.serverTimestamp(),
          'verificadoPor': user?.uid,
          'verificadoEn': FieldValue.serverTimestamp(),
          'notaAdmin': notaAdmin,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        tx.set(
          _db.collection('usuarios').doc(uidTaxista),
          {
            'semanaPendiente': null,
            'ultimoPago': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } else {
        tx.update(pagoRef, {
          'estado': 'rechazado',
          'notaAdmin': notaAdmin ?? 'Comprobante no válido',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
    final snap = await pagoRef.get();
    final uidTaxista = (snap.data()?['uidTaxista'] ?? '').toString();
    if (uidTaxista.isNotEmpty) {
      await _sincronizarBanderaPendiente(uidTaxista);
    }
  }

  // ==============================================================
  // BLOQUEAR TAXISTA POR FALTA DE PAGO
  // ==============================================================
  static Future<void> bloquearPorFaltaPago(
      String uidTaxista, String semana) async {
    await _db.collection('usuarios').doc(uidTaxista).set({
      'bloqueado': true,
      'motivoBloqueo': 'Falta de pago semana $semana',
      'fechaBloqueo': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ==============================================================
  // STREAMS PARA ADMIN
  // ==============================================================
  static Stream<List<PagoTaxista>> streamPagosPendientes() {
    return _col
        .where('estado', whereIn: ['pendiente', 'pendiente_verificacion'])
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((doc) => PagoTaxista.fromMap(doc.id, doc.data()))
              .toList();
          list.sort((a, b) => b.fechaFin.compareTo(a.fechaFin));
          return list;
        });
  }

  static Stream<List<PagoTaxista>> streamPagosPorTaxista(String uidTaxista) {
    return _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((doc) => PagoTaxista.fromMap(doc.id, doc.data()))
          .toList();
      list.sort((a, b) => b.fechaFin.compareTo(a.fechaFin));
      return list;
    });
  }

  static Stream<List<PagoTaxista>> streamHistorialPagos({
    int limite = 50,
    String? uidTaxista,
  }) {
    Query<Map<String, dynamic>> query = _col;

    if (uidTaxista != null) {
      query = query.where('uidTaxista', isEqualTo: uidTaxista);
    }

    return query.snapshots().map((snap) {
      final list = snap.docs
          .map((doc) => PagoTaxista.fromMap(doc.id, doc.data()))
          .toList();
      list.sort((a, b) => b.fechaFin.compareTo(a.fechaFin));
      return list.take(limite).toList();
    });
  }

  // ==============================================================
  // ESTADÍSTICAS PARA ADMIN
  // ==============================================================
  static Future<Map<String, dynamic>> obtenerEstadisticas() async {
    try {
      final now = DateTime.now();
      final inicioMes = DateTime(now.year, now.month, 1);
      final finMes = DateTime(now.year, now.month + 1, 0);

      // Pagos del mes
      final pagosMes = await _col
          .where('fechaFin',
              isGreaterThanOrEqualTo: Timestamp.fromDate(inicioMes))
          .where('fechaFin', isLessThanOrEqualTo: Timestamp.fromDate(finMes))
          .get();

      double totalComisiones = 0;
      double totalPagado = 0;
      int taxistasActivos = 0;
      final taxistasSet = <String>{};

      for (var doc in pagosMes.docs) {
        final data = doc.data();
        final estado = data['estado'];
        final comision = (data['comision'] ?? 0).toDouble();
        final uidTaxista = data['uidTaxista'] ?? '';

        totalComisiones += comision;
        taxistasSet.add(uidTaxista);

        if (estado == 'pagado') {
          totalPagado += comision;
        }
      }

      taxistasActivos = taxistasSet.length;

      return {
        'totalComisiones': totalComisiones,
        'totalPagado': totalPagado,
        'totalPendiente': totalComisiones - totalPagado,
        'taxistasActivos': taxistasActivos,
        'porcentajeCobrado': totalComisiones > 0
            ? (totalPagado / totalComisiones * 100).toStringAsFixed(1)
            : '0',
      };
    } catch (e) {
      debugPrint('Error obteniendo estadísticas: $e');
      return {
        'totalComisiones': 0,
        'totalPagado': 0,
        'totalPendiente': 0,
        'taxistasActivos': 0,
        'porcentajeCobrado': '0',
      };
    }
  }

  // ==============================================================
  // HELPERS
  // ==============================================================
  static String _getWeekString(DateTime date) {
    final semana = _getWeekNumber(date);
    return '${date.year}-${semana.toString().padLeft(2, '0')}';
  }

  static int _getWeekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final days = date.difference(firstDayOfYear).inDays;
    return ((days - date.weekday + 10) / 7).floor();
  }
}
