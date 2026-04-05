// lib/data/pago_data.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/servicios/pagos/payment_gateway.dart' as pg;
import 'package:flygo_nuevo/modelo/viaje.dart';

/// Persistencia de pagos (cliente/taxista) + actualización de estado en viajes.
/// Solo efectivo y transferencia. Deja hooks listos para gateway real (opcional).
class PagoData {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Historial general de pagos (cliente y taxista)
  static final CollectionReference<Map<String, dynamic>> _pagos =
      _db.collection('pagos');

  /// Inyectable (mock por defecto). Si más adelante usas un gateway real,
  /// podrás asignarlo desde main: PagoData.gateway = TuGateway();
  static pg.PaymentGateway gateway = pg.MockPaymentGateway();

  // ----------------- Helpers -----------------
  static double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static double _round2(double v) => double.parse(v.toStringAsFixed(2));
  static int _toCents(double v) => (v * 100).round();
  static String _isoNow() => DateTime.now().toIso8601String();

  // ──────────────────────────────────────────────────────────────────────────
  // TARJETA (opcional/futuro) — lo dejamos por si luego activas gateway real
  // ──────────────────────────────────────────────────────────────────────────
  static Future<void> autorizarPago({
    required String viajeId,
    required String clienteId,
    required String paymentMethodId,
    required double montoDop,
    String? emailCliente,
  }) async {
    await gateway.autorizarPago(
      viajeId: viajeId,
      clienteId: clienteId,
      paymentMethodId: paymentMethodId,
      montoDop: montoDop,
    );

    final provider = gateway.providerId;
    final paymentIntentId = gateway.buildPaymentIntentId(viajeId);

    await _db.collection('viajes').doc(viajeId).update({
      'metodoPago': 'Tarjeta',
      'payment.status': 'authorized',
      'payment.provider': provider,
      'payment.paymentIntentId': paymentIntentId,
      'payment.updatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _pagos.add({
      'tipo': 'cliente',
      'viajeId': viajeId,
      'clienteId': clienteId,
      'emailCliente': emailCliente,
      'monto': _round2(montoDop),
      'metodo': 'Tarjeta',
      'estado': 'autorizado',
      'fecha': _isoNow(),
      'provider': provider,
      'paymentIntentId': paymentIntentId,
    });
  }

  static Future<void> capturarPago({
    required String viajeId,
    required String paymentIntentId,
    required double montoFinalDop,
    required double comision, // 20%
    required double gananciaTaxista, // 80%
    required String uidTaxista,
    String? emailTaxista,
    String metodoLiquidacion = 'transfer',
  }) async {
    await gateway.capturarPago(
      viajeId: viajeId,
      paymentIntentId: paymentIntentId,
      montoFinalDop: montoFinalDop,
    );

    await _db.collection('viajes').doc(viajeId).update({
      'payment.status': 'captured',
      'payment.capturedAt': FieldValue.serverTimestamp(),
      'settlement.commission': _round2(comision),
      'settlement.driverAmount': _round2(gananciaTaxista),
      'settlement.status': 'scheduled',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _pagos.add({
      'tipo': 'taxista',
      'viajeId': viajeId,
      'uidTaxista': uidTaxista,
      'emailTaxista': emailTaxista,
      'monto': _round2(gananciaTaxista),
      'metodo': metodoLiquidacion,
      'estado': 'por_liquidar',
      'fecha': _isoNow(),
      'provider': gateway.providerId,
      'paymentIntentId': paymentIntentId,
    });
  }

  static Future<void> cancelarPago({
    required String viajeId,
    required String paymentIntentId,
  }) async {
    await gateway.cancelarPago(
      viajeId: viajeId,
      paymentIntentId: paymentIntentId,
    );

    await _db.collection('viajes').doc(viajeId).update({
      'payment.status': 'canceled',
      'payment.canceledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _pagos.add({
      'tipo': 'cliente',
      'viajeId': viajeId,
      'monto': 0.0,
      'metodo': 'Tarjeta',
      'estado': 'cancelado',
      'fecha': _isoNow(),
      'provider': gateway.providerId,
      'paymentIntentId': paymentIntentId,
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // EFECTIVO: cliente paga al taxista; el taxista nos debe la comisión (20%)
  // ──────────────────────────────────────────────────────────────────────────
  static Future<void> registrarComisionCash({
    required String viajeId,
    required String taxistaId,
    required double comision,
  }) async {
    final viajeRef = _db.collection('viajes').doc(viajeId);

    // Hacemos todo en transacción + idempotencia (si ya está pagoRegistrado, salimos)
    final bool actualizado = await _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(viajeRef);
      final m = snap.data() ?? <String, dynamic>{};

      if (m['pagoRegistrado'] == true) {
        // Ya registrado → no duplicar
        return false;
      }

      double total = _asDouble(m['precioFinal'] ?? m['precio']);
      if (total <= 0) {
        // Si no tenemos total en el documento, derivamos desde la comisión (20%)
        total = (comision > 0) ? (comision / 0.20) : 0.0;
      }

      final totalCents = _toCents(total);
      final comisionCents = _toCents(comision);
      final ganancia = (total - comision).clamp(0.0, double.infinity);
      final gananciaCents = _toCents(ganancia);

      // 1) Actualizar billetera del taxista: comisionPendiente
      final billeteraRef = _db.collection('billeteras_taxista').doc(taxistaId);
      final billeSnap = await tx.get(billeteraRef);
      final b = billeSnap.data() ?? <String, dynamic>{};
      final double pendiente = _asDouble(b['comisionPendiente']);

      tx.set(
        billeteraRef,
        {
          'comisionPendiente': _round2(pendiente + comision.abs()),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // 2) Marcar el viaje con método efectivo + partidas + flags
      tx.update(viajeRef, {
        'metodoPago': 'Efectivo',
        'payment.status': 'cash_collected',
        'payment.provider': 'cash',
        'payment.updatedAt': FieldValue.serverTimestamp(),

        // Partidas "en dólares" (double)
        'total': _round2(total),
        'comision': _round2(comision),
        'comisionFlygo': _round2(comision),
        'gananciaTaxista': _round2(ganancia),

        // Partidas en centavos (para cálculos exactos)
        'total_cents': totalCents,
        'comision_cents': comisionCents,
        'ganancia_cents': gananciaCents,

        // Estado de liquidación a la empresa: aún NO liquidado
        'pagoRegistrado': true,
        'liquidado': false,

        // Info extra
        'pagoDetalle': {
          'taxistaId': taxistaId,
          'metodo': 'efectivo',
          'total_cents': totalCents,
          'comision_cents': comisionCents,
          'ganancia_cents': gananciaCents,
          'createdAt': FieldValue.serverTimestamp(),
        },

        // Compat con settlement existente
        'settlement.commission': _round2(comision),
        'settlement.driverAmount': _round2(ganancia),
        'settlement.status': 'pending',

        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    });

    // 3) Mismo doc que ViajesRepo (`pagos/viaje_*_asiento`) para admin y reporting unificado.
    if (actualizado) {
      final post = await viajeRef.get();
      final pm = post.data() ?? <String, dynamic>{};
      final int tc = (pm['total_cents'] is int)
          ? pm['total_cents'] as int
          : _toCents(_asDouble(pm['total'] ?? pm['precioFinal'] ?? pm['precio']));
      final int cc = (pm['comision_cents'] is int)
          ? pm['comision_cents'] as int
          : _toCents(_asDouble(pm['comision'] ?? pm['comisionFlygo']));
      final int gc = (pm['ganancia_cents'] is int)
          ? pm['ganancia_cents'] as int
          : (tc > cc ? tc - cc : 0);

      await _pagos.doc('viaje_${viajeId}_asiento').set(
            {
              'tipo': 'taxista',
              'viajeId': viajeId,
              'uidTaxista': taxistaId,
              'monto': -_round2(comision.abs()),
              'totalCents': tc,
              'comisionCents': cc,
              'gananciaCents': gc,
              'comisionPlataformaPct': 20,
              'fuenteAsiento': 'registrar_comision_cash',
              'metodo': 'efectivo',
              'estado': 'comision_pendiente',
              'fecha': _isoNow(),
              'provider': 'cash',
              'createdAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TRANSFERENCIA: cliente transfiere al taxista; marcamos partidas del viaje
  // ──────────────────────────────────────────────────────────────────────────
  static Future<void> registrarTransferenciaCliente({
    required String viajeId,
    required String uidTaxista,
    required double montoFinalDop,
    required double comision,
    required double gananciaTaxista,
    String metodoLiquidacion = 'transferencia',
  }) async {
    final viajeRef = _db.collection('viajes').doc(viajeId);

    final bool actualizado = await _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(viajeRef);
      final m = snap.data() ?? <String, dynamic>{};

      if (m['pagoRegistrado'] == true) {
        return false; // idempotencia
      }

      final total = (montoFinalDop > 0) ? montoFinalDop : _asDouble(m['precioFinal'] ?? m['precio']);
      final totalCents = _toCents(total);
      final comisionCents = _toCents(comision);
      final gananciaCents = _toCents(gananciaTaxista);

      // OJO: para transferencia NO tocamos billetera.comisionPendiente.
      // La "pendiente" se calcula desde los viajes con liquidado==false.

      tx.update(viajeRef, {
        'metodoPago': 'Transferencia',
        'payment.status': 'bank_transfer_received',
        'payment.provider': 'transfer',
        'payment.updatedAt': FieldValue.serverTimestamp(),

        // Partidas double
        'total': _round2(total),
        'comision': _round2(comision),
        'comisionFlygo': _round2(comision),
        'gananciaTaxista': _round2(gananciaTaxista),

        // Partidas en centavos
        'total_cents': totalCents,
        'comision_cents': comisionCents,
        'ganancia_cents': gananciaCents,

        // Flags
        'pagoRegistrado': true,
        'liquidado': false,

        'pagoDetalle': {
          'taxistaId': uidTaxista,
          'metodo': 'transferencia',
          'total_cents': totalCents,
          'comision_cents': comisionCents,
          'ganancia_cents': gananciaCents,
          'createdAt': FieldValue.serverTimestamp(),
        },

        // Compat settlement
        'settlement.commission': _round2(comision),
        'settlement.driverAmount': _round2(gananciaTaxista),
        'settlement.status': 'scheduled',

        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    });

    if (actualizado) {
      // Asiento histórico a favor del taxista (por liquidar)
      await _pagos.add({
        'tipo': 'taxista',
        'viajeId': viajeId,
        'uidTaxista': uidTaxista,
        'monto': _round2(gananciaTaxista),
        'metodo': metodoLiquidacion,
        'estado': 'por_liquidar',
        'fecha': _isoNow(),
        'provider': 'transfer',
      });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HISTORIALES
  // ──────────────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> obtenerPagosPorCliente(
    String emailCliente,
  ) async {
    final snap = await _pagos
        .where('tipo', isEqualTo: 'cliente')
        .where('emailCliente', isEqualTo: emailCliente)
        .orderBy('fecha', descending: true)
        .get();

    return snap.docs.map((d) => d.data()).toList();
  }

  static Future<List<Map<String, dynamic>>> obtenerPagosTaxista(
    String emailTaxista,
  ) async {
    final snap = await _pagos
        .where('tipo', isEqualTo: 'taxista')
        .where('emailTaxista', isEqualTo: emailTaxista)
        .orderBy('fecha', descending: true)
        .get();

    return snap.docs.map((d) => d.data()).toList();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // COMPAT: movimiento por viaje en billetera (tu método previo)
  // ──────────────────────────────────────────────────────────────────────────
  static Future<void> registrarMovimientoPorViaje(Viaje v) async {
    final total = (v.precio > 0) ? v.precio : (v.precioFinal > 0 ? v.precioFinal : 0.0);
    final comision = (v.comision > 0) ? v.comision : (total * 0.20);
    final ganancia = (v.gananciaTaxista > 0) ? v.gananciaTaxista : (total - comision);

    final String taxistaId = (v.uidTaxista.isNotEmpty)
        ? v.uidTaxista
        : (v.taxistaId.isNotEmpty ? v.taxistaId : '');

    if (taxistaId.isEmpty) return;

    // Idempotencia: ¿ya existe algún pago para este viaje y taxista?
    final ya = await _db
        .collection('pagos_taxista')
        .where('viajeId', isEqualTo: v.id)
        .where('taxistaId', isEqualTo: taxistaId)
        .limit(1)
        .get();
    if (ya.docs.isNotEmpty) return;

    await _db.runTransaction((tx) async {
      // 1) Asiento en pagos_taxista
      final movRef = _db.collection('pagos_taxista').doc();
      tx.set(movRef, {
        'id': movRef.id,
        'viajeId': v.id,
        'taxistaId': taxistaId,
        'uidTaxista': taxistaId,
        'montoTotal': _round2(total),
        'comisionFlygo': _round2(comision),
        'gananciaTaxista': _round2(ganancia),
        'estado': 'pendiente_liquidacion',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2) Actualizar billetera del taxista
      final billeRef = _db.collection('billeteras_taxista').doc(taxistaId);
      tx.set(
        billeRef,
        {
          'saldoAcumulado': FieldValue.increment(_round2(ganancia)),
          'comisionPendiente': FieldValue.increment(_round2(comision)),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }
}
