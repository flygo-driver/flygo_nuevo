import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/config/recarga_bancaria_config.dart';
import 'package:flygo_nuevo/utils/viaje_referencia_recaudo.dart';

/// Datos del recibo de pago con tarjeta (AZUL) para mostrar en factura.
class ReciboTarjetaAzul {
  const ReciboTarjetaAzul({
    required this.comercio,
    required this.rnc,
    required this.direccionComercio,
    required this.numeroOrden,
    required this.referenciaAzul,
    required this.montoRd,
    required this.moneda,
    required this.concepto,
    required this.viajeId,
    required this.metodoEtiqueta,
    required this.pagado,
    this.fecha,
    this.autorizacion,
    this.rrn,
  });

  final String comercio;
  final String rnc;
  final String direccionComercio;
  final String numeroOrden;
  final String referenciaAzul;
  final double montoRd;
  final String moneda;
  final String concepto;
  final String viajeId;
  final String metodoEtiqueta;
  final bool pagado;
  final DateTime? fecha;
  final String? autorizacion;
  final String? rrn;

  static ReciboTarjetaAzul fromViaje({
    required String viajeId,
    required Map<String, dynamic> data,
    required double montoRd,
  }) {
    final payment = data['payment'] is Map
        ? Map<String, dynamic>.from(data['payment'] as Map)
        : <String, dynamic>{};

    final estadoPago =
        (data['estadoPago'] ?? '').toString().trim().toLowerCase();
    final paymentStatus =
        (payment['status'] ?? '').toString().trim().toLowerCase();
    final pagado = estadoPago == 'verificado' || paymentStatus == 'captured';

    final refRecaudo = (data['referenciaRecaudo'] ?? '').toString().trim();
    final numeroOrden = refRecaudo.isNotEmpty
        ? refRecaudo
        : ViajeReferenciaRecaudo.generar(viajeId);

    final azulOrderId = (payment['azulOrderId'] ?? '').toString().trim();
    final pagoAzulId = (data['pagoAzulId'] ?? '').toString().trim();
    final referenciaAzul = azulOrderId.isNotEmpty
        ? azulOrderId
        : (pagoAzulId.isNotEmpty ? pagoAzulId : 'Pendiente');

    final auth = (payment['azulAuthCode'] ?? payment['authorizationCode'] ?? '')
        .toString()
        .trim();
    final brand = (payment['azulCardBrand'] ?? payment['cardBrand'] ?? '')
        .toString()
        .trim();
    final last4 = (payment['azulCardLast4'] ?? payment['cardLast4'] ?? '')
        .toString()
        .trim();
    final rrn =
        (payment['azulRrn'] ?? payment['rrn'] ?? '').toString().trim();

    String metodoEtiqueta = 'Tarjeta';
    if (brand.isNotEmpty && last4.length == 4) {
      metodoEtiqueta = '$brand · ****$last4';
    } else if (brand.isNotEmpty) {
      metodoEtiqueta = brand;
    } else if (last4.length == 4) {
      metodoEtiqueta = 'Tarjeta · ****$last4';
    }

    return ReciboTarjetaAzul(
      comercio: RecargaBancariaConfig.titular,
      rnc: RecargaBancariaConfig.rnc,
      direccionComercio: RecargaBancariaConfig.direccionUnaLinea,
      numeroOrden: numeroOrden,
      referenciaAzul: referenciaAzul,
      montoRd: montoRd,
      moneda: 'DOP',
      concepto: 'Servicio de transporte',
      viajeId: viajeId,
      metodoEtiqueta: metodoEtiqueta,
      pagado: pagado,
      fecha: _fechaDesde(data, payment),
      autorizacion: auth.isNotEmpty ? auth : null,
      rrn: rrn.isNotEmpty ? rrn : null,
    );
  }

  static DateTime? _fechaDesde(
    Map<String, dynamic> data,
    Map<String, dynamic> payment,
  ) {
    final candidates = <dynamic>[
      payment['azulCapturedAt'],
      payment['updatedAt'],
      data['finalizadoEn'],
      data['updatedAt'],
      data['actualizadoEn'],
      data['createdAt'],
    ];
    for (final raw in candidates) {
      final dt = _parseTs(raw);
      if (dt != null) return dt;
    }
    return null;
  }

  static DateTime? _parseTs(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.tryParse(raw.trim());
    }
    return null;
  }

  String get fechaLegible {
    final dt = fecha ?? DateTime.now();
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min AST';
  }

  String get montoLegible => 'RD\$ ${montoRd.toStringAsFixed(2)}';
}
