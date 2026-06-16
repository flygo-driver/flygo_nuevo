import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// `config/finance` — flags de comportamiento financiero sin redeploy.
class FinanceConfigService {
  FinanceConfigService._();

  /// Por defecto activo: excluir efectivo del pago semanal (Fase 1).
  static bool excluirEfectivoDePagoSemanal = true;

  /// PR2: nueva colección `liquidaciones_semanales` (default off = PR1).
  static bool useLiquidacionesSemanales = false;

  /// Si false con useLiquidacionesSemanales, no escribe en pagos_taxistas.
  static bool escrituraPagosTaxistasLegacy = true;

  /// Fase 5: cliente paga transferencia a cuenta RAI con [referenciaRecaudo] (default off).
  static bool transferenciaRecaudoEnCuentaRai = false;

  /// Fase 4: job/callable propone matches movimiento ↔ viaje (default off).
  static bool conciliacionAutomaticaHabilitada = false;

  /// Fase 4: bloquea finalizar transferencia RAI sin estadoPago verificado (default off).
  static bool transferenciaExigeVerificadoParaFinalizar = false;

  /// Fase 5c: muestra QR recaudo Popular en panel/factura (default off).
  static bool qrRecaudoPopularHabilitado = false;

  /// Fase 6: tarjeta AZUL en UI + callables (default off).
  static bool pagosConTarjetaAzulHabilitados = false;

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  static bool _started = false;

  static Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('config')
          .doc('finance')
          .get();
      _apply(snap.data());
    } catch (_) {}
    _sub = FirebaseFirestore.instance
        .collection('config')
        .doc('finance')
        .snapshots()
        .listen((snap) => _apply(snap.data()));
  }

  static void _apply(Map<String, dynamic>? data) {
    if (data == null) return;
    excluirEfectivoDePagoSemanal =
        _boolOr(data['excluirEfectivoDePagoSemanal'], true);
    useLiquidacionesSemanales =
        _boolOr(data['useLiquidacionesSemanales'], false);
    escrituraPagosTaxistasLegacy =
        _boolOr(data['escrituraPagosTaxistasLegacy'], true);
    transferenciaRecaudoEnCuentaRai =
        _boolOr(data['transferenciaRecaudoEnCuentaRai'], false);
    conciliacionAutomaticaHabilitada =
        _boolOr(data['conciliacionAutomaticaHabilitada'], false);
    transferenciaExigeVerificadoParaFinalizar =
        _boolOr(data['transferenciaExigeVerificadoParaFinalizar'], false);
    qrRecaudoPopularHabilitado =
        _boolOr(data['qrRecaudoPopularHabilitado'], false);
    pagosConTarjetaAzulHabilitados =
        _boolOr(data['pagosConTarjetaAzulHabilitados'], false);
  }

  static bool _boolOr(dynamic raw, bool defaultValue) {
    if (raw == null) return defaultValue;
    if (raw is bool) return raw;
    return defaultValue;
  }

  static void disposeService() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
