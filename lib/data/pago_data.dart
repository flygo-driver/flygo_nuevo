// lib/servicios/pago_data.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/servicios/pagos/payment_gateway.dart' as pg;
import 'package:flygo_nuevo/modelo/viaje.dart';

/// Persistencia de pagos (cliente/taxista) + actualización de estado en viajes.
/// 100% compatible con PaymentGateway (autorizar/capturar/cancelar) y
/// mantiene registrarMovimientoPorViaje para billetera del taxista.
class PagoData {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Historial general de pagos (cliente y taxista)
  static final CollectionReference<Map<String, dynamic>> _pagos =
      _db.collection('pagos');

  /// Inyectable (mock por defecto). Sustituye en runtime por tu gateway real.
  static pg.PaymentGateway gateway = pg.MockPaymentGateway();

  // ----------- Helpers -----------
  static double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static String _isoNow() => DateTime.now().toIso8601String();

  // ======================================================================
  // AUTORIZAR TARJETA (cliente)
  // ======================================================================
  static Future<void> autorizarPago({
    required String viajeId,
    required String clienteId,
    required String paymentMethodId,
    required double montoDop,
    String? emailCliente,
  }) async {
    // 1) Autorización en el gateway (mock/real)
    await gateway.autorizarPago(
      viajeId: viajeId,
      clienteId: clienteId,
      paymentMethodId: paymentMethodId,
      montoDop: montoDop,
    );

    // 2) Guardar estado de pago en el viaje
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

    // 3) Asiento del historial del cliente
    await _pagos.add({
      'tipo': 'cliente',
      'viajeId': viajeId,
      'clienteId': clienteId,
      'emailCliente': emailCliente,
      'monto': double.parse(montoDop.toStringAsFixed(2)),
      'metodo': 'Tarjeta',
      'estado': 'autorizado',
      'fecha': _isoNow(),
      'provider': provider,
      'paymentIntentId': paymentIntentId,
    });
  }

  // ======================================================================
  // CAPTURAR TARJETA (al completar)
  // ======================================================================
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
    // 1) Captura en el gateway
    await gateway.capturarPago(
      viajeId: viajeId,
      paymentIntentId: paymentIntentId,
      montoFinalDop: montoFinalDop,
    );

    // 2) Marcar el viaje como capturado y programar liquidación
    await _db.collection('viajes').doc(viajeId).update({
      'payment.status': 'captured',
      'payment.capturedAt': FieldValue.serverTimestamp(),
      'settlement.commission': double.parse(comision.toStringAsFixed(2)),
      'settlement.driverAmount':
          double.parse(gananciaTaxista.toStringAsFixed(2)),
      'settlement.status': 'scheduled', // la liquidación se hace luego
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 3) Asiento a favor del taxista (por liquidar)
    await _pagos.add({
      'tipo': 'taxista',
      'viajeId': viajeId,
      'uidTaxista': uidTaxista,
      'emailTaxista': emailTaxista,
      'monto': double.parse(gananciaTaxista.toStringAsFixed(2)),
      'metodo': metodoLiquidacion,
      'estado': 'por_liquidar',
      'fecha': _isoNow(),
      'provider': gateway.providerId,
      'paymentIntentId': paymentIntentId,
    });
  }

  // ======================================================================
  // CANCELAR PAGO (opcional)
  // ======================================================================
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

    // Asiento histórico (opcional)
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

  // ======================================================================
  // EFECTIVO: registrar comisión pendiente (cobrado al taxista luego)
  // ======================================================================
  static Future<void> registrarComisionCash({
    required String viajeId,
    required String taxistaId,
    required double comision,
  }) async {
    final billeteraRef = _db.collection('billeteras_taxista').doc(taxistaId);

    // 1) Acumular comisión pendiente en billetera_taxista
    await _db.runTransaction((tx) async {
      final snap = await tx.get(billeteraRef);
      final data = snap.data() ?? <String, dynamic>{};
      final double pendiente = _asDouble(data['comisionPendiente']);

      tx.set(billeteraRef, {
        'comisionPendiente': double.parse(
          (pendiente + comision.abs()).toStringAsFixed(2),
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    // 2) Marcar el viaje con estado de cobro cash
    await _db.collection('viajes').doc(viajeId).update({
      'payment.status': 'cash_collected',
      'settlement.commission': double.parse(comision.toStringAsFixed(2)),
      'settlement.driverAmount': null,
      'settlement.status': 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 3) Asiento histórico (negativo = deuda/retención)
    await _pagos.add({
      'tipo': 'taxista',
      'viajeId': viajeId,
      'uidTaxista': taxistaId,
      'monto': -double.parse(comision.abs().toStringAsFixed(2)),
      'metodo': 'efectivo',
      'estado': 'comision_pendiente',
      'fecha': _isoNow(),
      'provider': 'cash',
    });
  }

  // ======================================================================
  // HISTORIALES
  // ======================================================================
  /// Para "HistorialPagosCliente"
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

  /// Para "PagoTaxista"
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

  // ======================================================================
  // MOVIMIENTO EN BILLETERA DEL TAXISTA POR VIAJE (COMPAT)
  // ======================================================================
  /// Mantengo tu método previo para registrar movimiento del viaje en la
  /// billetera del taxista. Lo hago idempotente para no duplicar si ya existe.
  static Future<void> registrarMovimientoPorViaje(Viaje v) async {
    final total = (v.precio > 0)
        ? v.precio
        : (v.precioFinal > 0 ? v.precioFinal : 0.0);
    final comision = (v.comision > 0) ? v.comision : (total * 0.20);
    final ganancia =
        (v.gananciaTaxista > 0) ? v.gananciaTaxista : (total - comision);

    final String taxistaId = (v.uidTaxista.isNotEmpty)
        ? v.uidTaxista
        : (v.taxistaId.isNotEmpty ? v.taxistaId : '');

    if (taxistaId.isEmpty) return; // nada que abonar

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
        'montoTotal': double.parse(total.toStringAsFixed(2)),
        'comisionFlygo': double.parse(comision.toStringAsFixed(2)),
        'gananciaTaxista': double.parse(ganancia.toStringAsFixed(2)),
        'estado': 'pendiente_liquidacion',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2) Actualizar billetera del taxista
      final billeRef = _db.collection('billeteras_taxista').doc(taxistaId);
      tx.set(
        billeRef,
        {
          'saldoAcumulado': FieldValue.increment(
            double.parse(ganancia.toStringAsFixed(2)),
          ),
          'comisionPendiente': FieldValue.increment(
            double.parse(comision.toStringAsFixed(2)),
          ),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }
}
