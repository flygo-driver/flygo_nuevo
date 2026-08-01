// lib/servicios/pagos_taxista_repo.dart
// ignore_for_file: avoid_print -- logs depuración taxistaEnviarRecargaComisionEfectivo

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/config/plataforma_economia.dart';
import '../modelo/pago_taxista.dart';
import '../modelo/recarga_comision_taxista.dart';
import 'pool_repo.dart';
import 'package:flygo_nuevo/servicios/comision_prepago_config_service.dart';
import 'finance_config_service.dart';
import 'taxista_billetera_gira_prepago.dart';
import 'taxista_prepago_ledger.dart';
import '../utils/liquidacion_semanal_viaje.dart';
import '../utils/metodo_pago_viaje.dart';
import '../utils/precio_viaje_doc.dart';

class PagosTaxistaRepo {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('pagos_taxistas');
  /// PR2: rechaza escritura legacy en `pagos_taxistas` cuando la autoridad es semanal.
  static Future<void> _assertEscrituraLegacyPagosTaxistas() async {
    await FinanceConfigService.ensureStarted();
    if (FinanceConfigService.useLiquidacionesSemanales &&
        !FinanceConfigService.escrituraPagosTaxistasLegacy) {
      debugPrint(
        '[PagosTaxistaRepo] pagos_taxistas legacy bloqueado: '
        'useLiquidacionesSemanales=true, escrituraPagosTaxistasLegacy=false',
      );
      throw Exception(
        'El flujo legacy pagos_taxistas está deshabilitado. Use liquidaciones semanales.',
      );
    }
  }

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

  /// Monto de prepago **reservado** para giras por cupos en curso (no disponible hasta devolución/cierre).
  static double saldoReservadoParaGirasDesdeBilletera(Map<String, dynamic>? data) =>
      TaxistaBilleteraGiraPrepago.saldoReservadoParaGiras(data);

  /// Comisión de giras ya descontada del prepago (acumulado contable).
  static double comisionesDescontadasDesdeBilletera(Map<String, dynamic>? data) =>
      TaxistaBilleteraGiraPrepago.comisionesDescontadas(data);

  /// Prepago libre para crear una nueva gira (prepago − reservado en giras).
  static double saldoDisponibleParaReservarGiraDesdeBilletera(
          Map<String, dynamic>? data) =>
      TaxistaBilleteraGiraPrepago.saldoDisponibleParaReservarGira(data);

  /// Saldo prepago **disponible** para operar (viajes en efectivo + nuevas giras).
  static double saldoDisponiblePrepagoComisionDesdeBilletera(
          Map<String, dynamic>? data) =>
      TaxistaBilleteraGiraPrepago.saldoDisponiblePrepagoComisionRd(data);

  /// Ratio máximo cancelaciones/creadas en el mes antes de bloquear nuevas giras.
  static const double giraAbusoRatioCancelacionesMax = 0.30;

  /// Mínimo de giras creadas en el mes para evaluar el ratio (evita bloqueo con 1–2 datos).
  static const int giraAbusoMinCreadasParaEvaluar = 3;

  static bool primerViajeComisionGratisConsumido(Map<String, dynamic>? data) {
    return data?['primerViajeComisionGratisConsumido'] == true;
  }

  /// Deuda legacy en billetera (ya no sube con viajes nuevos): mismo tope que Cloud Functions.
  static const double umbralComisionLegacyBloqueoRd = 500;

  /// Monto sugerido de recarga para operar con holgura (default; vivo en [ComisionPrepagoConfigService]).
  static double get minSaldoPrepagoComisionRd =>
      ComisionPrepagoConfigService.minimoOperativoRd;

  /// Alias histórico (UI que hablaba de “tope 500”): hoy es el tope solo de `comisionPendiente` legacy.
  static const double umbralBloqueoComisionEfectivoRd =
      umbralComisionLegacyBloqueoRd;

  /// Misma regla que [syncTienePagoPendiente] en `functions/src/finance.ts` (deuda comisión giras/pool).
  static const double umbralDeudaPoolComisionAdminRd = 500;

  /// Suma montos de comisión pendiente de validación admin en `viajes_pool`.
  static Future<double> sumarDeudaPoolComisionPendienteAdmin(
      String uidTaxista) async {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return 0;
    double total = 0;
    try {
      final snap = await _db
          .collection('viajes_pool')
          .where('ownerTaxistaId', isEqualTo: uid)
          .where('comisionPendientePagoAdmin', isEqualTo: true)
          .limit(500)
          .get();
      for (final doc in snap.docs) {
        final m = doc.data();
        final v = m['montoComisionPendienteAdmin'] ?? m['montoComision'];
        if (v is num && v.isFinite) {
          total += v.toDouble();
        } else if (v != null) {
          final n = double.tryParse(v.toString());
          if (n != null && n.isFinite) total += n;
        }
      }
    } catch (e) {
      debugPrint('[PagosTaxistaRepo] sumarDeudaPoolComisionPendienteAdmin: $e');
    }
    return double.parse(total.clamp(0, 1e9).toStringAsFixed(2));
  }

  /// Textos UX (prepago + comisión global en efectivo).
  static String get mensajeRecargaTomarViajes =>
      'Recarga crédito prepago (mín. RD\$200): el ${PlataformaEconomia.etiquetaPorcentajeComision()} '
      'de cada viaje en efectivo se descuenta de tu saldo. '
      'Sin saldo suficiente no puedes tomar viajes ni pool.';

  static const String mensajeRecargaActivarDisponible =
      'Sin el saldo prepago mínimo no puedes quedar disponible. Recarga desde Mis pagos; '
      'al verificar el admin, podrás activarte de nuevo.';

  static const String mensajeRecargaBannerLista =
      'Servicio cortado: falta crédito prepago para comisión en efectivo. Recarga desde Mis pagos.';

  static const String mensajeRecargaListaVacia =
      'No hay viajes disponibles hasta que regularices tu saldo prepago (comisión efectivo).';

  /// Bloqueo al abrir la app (prepago bajo), distinto del recordatorio largo.
  /// Coherente con la CF: una recarga aprobada paga primero [comisionPendiente] legacy y el resto suma prepago.
  static const String mensajeBloqueoAppSaldoRecargas =
      'Saldo prepago disponible para comisión en efectivo insuficiente (mín. RD\$200 tras el '
      'primer viaje en efectivo). Recarga en Mis pagos; al aprobar el admin se acredita. '
      'Si tenés comisión pendiente, ese mismo depósito primero baja esa deuda y el '
      'resto queda en prepago.';

  /// Cualquier comisión efectivo pendiente bloquea hasta regularizar con admin.
  static const String mensajeBloqueoComisionPendienteApp =
      'Tenés comisión en efectivo pendiente de pago a RAI. No podés tomar viajes ni publicar '
      'giras hasta depositar y que el administrador verifique tu comprobante en Mis pagos. '
      'El monto verificado paga primero esa deuda; el resto queda en tu prepago.';

  /// Legacy `comisionPendiente` ≥ tope (mismo bloqueo; mensaje con cifra de referencia).
  static const String mensajeBloqueoComisionLegacyTopeApp =
      'Tu comisión en efectivo pendiente superó el tope de referencia (RD\$500). El acceso '
      'está suspendido hasta que deposites y el administrador verifique el comprobante en '
      'Mis pagos. El monto verificado paga primero esa comisión pendiente y el resto suma '
      'a tu prepago.';

  /// Suma de comisiones de giras/pool marcadas pendientes de validación admin ≥ tope.
  static const String mensajeBloqueoDeudaPoolAdminApp =
      'Hay comisión de giras/pool pendiente de validación por el administrador que supera el '
      'tope permitido. Seguí las indicaciones en Mis pagos o soporte hasta que el equipo '
      'regularice esos viajes de gira.';

  /// Cuota semanal de servicio vencida (>14 días) sin regularizar.
  static const String mensajeBloqueoDeudaSemanalApp =
      'Tenés pagos semanales del servicio vencidos. Regularizá en Mis pagos para volver a operar.';

  static String get mensajeRecargaAccesoPantallaCompleta =>
      'Tu acceso queda suspendido: sin saldo prepago suficiente o con comisión en efectivo '
      'pendiente. Recarga (sugerido RD\$${minSaldoPrepagoComisionRd.toStringAsFixed(0)} o más) '
      'en Mis pagos; al verificar el admin, el monto paga primero cualquier comisión pendiente '
      'y el resto queda en prepago para seguir operando.';

  /// `true` si la deuda legacy alcanzó el tope (bloquea aunque el prepago bruto sea alto).
  static bool bloqueoPorComisionLegacyTope(Map<String, dynamic>? billeData) {
    return comisionPendienteDesdeBilletera(billeData) >=
        umbralComisionLegacyBloqueoRd - 1e-6;
  }

  /// Con bloqueo estricto: cualquier [comisionPendiente] > 0 exige liquidar toda la deuda legacy.
  static double montoMinimoRecargaParaSalirBloqueoLegacyRd(
    double comisionPendienteRd,
  ) {
    return montoParaLiquidarLegacyCompletoRd(comisionPendienteRd);
  }

  /// Monto que, si entero en recarga aprobada y va todo a legacy, deja `comisionPendiente` en 0.
  static double montoParaLiquidarLegacyCompletoRd(double comisionPendienteRd) {
    if (comisionPendienteRd <= 1e-9) return 0;
    return double.parse(comisionPendienteRd.clamp(0, 1e9).toStringAsFixed(2));
  }

  static double deudaPoolPendienteRdDesdeUsuario(Map<String, dynamic>? usuarioData) {
    final v = usuarioData?['deudaPoolPendienteRd'];
    if (v is num && v.isFinite) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// Misma regla que [sumarDeudaPoolComisionPendienteAdmin] + umbral, usando snapshot en `usuarios`.
  static bool bloqueoPorDeudaPoolAdminDesdeUsuario(
      Map<String, dynamic>? usuarioData) {
    return deudaPoolPendienteRdDesdeUsuario(usuarioData) + 1e-9 >=
        umbralDeudaPoolComisionAdminRd;
  }

  /// Texto principal de pantalla “cuenta bloqueada”: prioridad semanal → legacy → prepago → pool → genérico.
  static String mensajeCuentaBloqueadaOperativo({
    required bool deudaSemanalVencida,
    required Map<String, dynamic>? billeData,
    required Map<String, dynamic>? usuarioData,
  }) {
    if (deudaSemanalVencida) return mensajeBloqueoDeudaSemanalApp;
    final pend = comisionPendienteDesdeBilletera(billeData);
    if (pend > 1e-6) {
      if (pend >= umbralComisionLegacyBloqueoRd - 1e-6) {
        return mensajeBloqueoComisionLegacyTopeApp;
      }
      return mensajeBloqueoComisionPendienteApp;
    }
    if (bloqueoOperativoPorComisionEfectivo(billeData)) {
      return mensajeBloqueoAppSaldoRecargas;
    }
    if (bloqueoPorDeudaPoolAdminDesdeUsuario(usuarioData)) {
      return mensajeBloqueoDeudaPoolAdminApp;
    }
    if (usuarioData?['tienePagoPendiente'] == true) {
      return mensajeBloqueoDeudaPoolAdminApp;
    }
    return mensajeRecargaAccesoPantallaCompleta;
  }

  /// Evalúa desbloqueo prepago/comisión desde snapshots (tiempo real tras aprobación ADM).
  /// No incluye deuda semanal vencida; combinar con [tieneDeudaSemanalVencida].
  static bool puedeOperarPrepagoDesdeSnapshots({
    Map<String, dynamic>? usuarioData,
    Map<String, dynamic>? billeData,
  }) {
    if (usuarioData == null) return false;
    if (usuarioData['bloqueado'] == true) return false;
    if (usuarioData['tienePagoPendiente'] == true) return false;
    if (bloqueoOperativoPorComisionEfectivo(billeData)) return false;
    if (bloqueoPorDeudaPoolAdminDesdeUsuario(usuarioData)) return false;
    return true;
  }

  /// Misma regla que `bloqueoOperativoPrepago` en Cloud Functions.
  static bool bloqueoOperativoPorComisionEfectivo(
    Map<String, dynamic>? billeData, {
    double? minimoOperativoRd,
    bool? permitirViajeConPrepagoParcial,
  }) {
    final pend = comisionPendienteDesdeBilletera(billeData);
    if (pend > 1e-6) return true;
    if (!primerViajeComisionGratisConsumido(billeData)) return false;
    final disp = saldoDisponiblePrepagoComisionDesdeBilletera(billeData);
    final partial = permitirViajeConPrepagoParcial ??
        ComisionPrepagoConfigService.permitirViajeConPrepagoParcial;
    if (partial) {
      return disp <= 1e-9;
    }
    final minimo = minimoOperativoRd ?? minSaldoPrepagoComisionRd;
    return disp + 1e-9 < minimo;
  }

  /// Solo **efectivo**: comisión RAI desde prepago. Digital → liquidación semanal.
  static bool viajeAplicaComisionPrepago(Map<String, dynamic> viajeData) {
    if (viajeData['corporativo'] == true) return false;
    if ((viajeData['recaudoDestino'] ?? '').toString() ==
        'empresa_corporativa') {
      return false;
    }
    if ((viajeData['canalAsignacion'] ?? '').toString() ==
        'corporativo_fijo') {
      return false;
    }
    if (viajeData['exentoBloqueoPrepago'] == true) return false;
    final String tipo =
        (viajeData['tipoServicio'] ?? 'normal').toString().trim().toLowerCase();
    if (tipo == 'bola_ahorro') return false;
    final String? metodo = viajeData['metodoPago']?.toString();
    if (MetodoPagoViaje.esEfectivo(metodo)) return true;
    return (metodo ?? '').trim().isEmpty;
  }

  static bool viajeEsEfectivoParaComisionPrepago(
    Map<String, dynamic> viajeData,
  ) {
    return viajeAplicaComisionPrepago(viajeData);
  }

  /// Descuenta comisión del prepago (1.er viaje gratis) dentro de una transacción Firestore.
  static Future<void> aplicarDescuentoComisionPrepagoEnTransaccion({
    required Transaction tx,
    required String taxistaId,
    required String viajeId,
    required double comisionRd,
    required String fuenteLedger,
  }) async {
    final billeRef = _db.collection('billeteras_taxista').doc(taxistaId);
    final billeSnap = await tx.get(billeRef);
    final b = billeSnap.data() ?? <String, dynamic>{};
    final pend = comisionPendienteDesdeBilletera(b);
    final flag = primerViajeComisionGratisConsumido(b);
    final saldoIni = saldoPrepagoComisionDesdeBilletera(b);
    final comision = double.parse(comisionRd.abs().toStringAsFixed(2));
    final Map<String, dynamic> bPatch = {
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!flag && pend < 1e-6) {
      bPatch['primerViajeComisionGratisConsumido'] = true;
      await TaxistaPrepagoLedger.appendComisionViajeEfectivo(
        tx: tx,
        uidTaxista: taxistaId,
        viajeId: viajeId,
        fuente: fuenteLedger,
        comisionTotalRd: comision,
        pendienteAntes: pend,
        saldoPrepagoAntes: saldoIni,
        pendienteDespues: pend,
        saldoPrepagoDespues: saldoIni,
        primerEfectivoSinDescuento: true,
      );
    } else {
      var p = pend;
      var saldo = saldoIni;
      final fromPend = p < comision ? p : comision;
      p = double.parse((p - fromPend).toStringAsFixed(2));
      final rem = double.parse((comision - fromPend).toStringAsFixed(2));
      final prepagoLibreIni = saldoDisponiblePrepagoComisionDesdeBilletera(b);
      final cubiertoPrepago = rem <= prepagoLibreIni ? rem : prepagoLibreIni;
      final faltantePrepago =
          double.parse((rem - cubiertoPrepago).toStringAsFixed(2));
      saldo = double.parse((saldo - cubiertoPrepago).toStringAsFixed(2));
      p = double.parse((p + faltantePrepago).toStringAsFixed(2));
      bPatch['comisionPendiente'] = p;
      bPatch['saldoPrepagoComisionRd'] = saldo;
      bPatch['primerViajeComisionGratisConsumido'] = true;
      await TaxistaPrepagoLedger.appendComisionViajeEfectivo(
        tx: tx,
        uidTaxista: taxistaId,
        viajeId: viajeId,
        fuente: fuenteLedger,
        comisionTotalRd: comision,
        pendienteAntes: pend,
        saldoPrepagoAntes: saldoIni,
        pendienteDespues: p,
        saldoPrepagoDespues: saldo,
        primerEfectivoSinDescuento: false,
      );
    }
    tx.set(billeRef, bPatch, SetOptions(merge: true));
  }

  static double pctComisionDesdeViaje(
    Map<String, dynamic> viajeData,
    double globalPct,
  ) {
    final dynamic raw = viajeData['comisionPorcentaje'];
    if (raw is num && raw.isFinite && raw > 0) {
      final double v = raw.toDouble();
      return v <= 1 ? v * 100 : v;
    }
    return globalPct;
  }

  static double comisionEstimadaRdDesdeViaje(
    Map<String, dynamic> viajeData, {
    double? pctComision,
  }) {
    final double total = totalRdDesdeDocViaje(viajeData);
    if (total <= 0) return 0;
    final double pct = pctComision ??
        pctComisionDesdeViaje(
          viajeData,
          PlataformaEconomia.comisionViajePorcentaje,
        );
    return double.parse((total * (pct / 100)).toStringAsFixed(2));
  }

  /// Código de rechazo al aceptar viaje en efectivo sin prepago para la comisión estimada.
  static String? codigoRechazoPrepagoInsuficienteComisionViaje({
    required Map<String, dynamic>? billeData,
    required Map<String, dynamic> viajeData,
    double? pctComision,
  }) {
    if (ComisionPrepagoConfigService.permitirViajeConPrepagoParcial) {
      return null;
    }
    if (!viajeAplicaComisionPrepago(viajeData)) return null;
    final double pend = comisionPendienteDesdeBilletera(billeData);
    if (!primerViajeComisionGratisConsumido(billeData) && pend <= 1e-6) {
      return null;
    }
    final double comision = comisionEstimadaRdDesdeViaje(
      viajeData,
      pctComision: pctComision,
    );
    if (comision <= 1e-6) return null;
    final double disp = saldoDisponiblePrepagoComisionDesdeBilletera(billeData);
    if (disp + 1e-9 >= comision) return null;
    return 'prepago-insuficiente-comision-viaje';
  }

  static String mensajePrepagoInsuficienteComisionViaje({
    required Map<String, dynamic> viajeData,
    required Map<String, dynamic>? billeData,
    double? pctComision,
  }) {
    final double comision = comisionEstimadaRdDesdeViaje(
      viajeData,
      pctComision: pctComision,
    );
    final double disp = saldoDisponiblePrepagoComisionDesdeBilletera(billeData);
    return 'Este viaje requiere RD\$${comision.toStringAsFixed(0)} de prepago '
        'disponible para la comisión RAI (${PlataformaEconomia.etiquetaPorcentajeComision()}). '
        'Tenés RD\$${disp.toStringAsFixed(0)} disponible. Recarga en Mis pagos antes de aceptar.';
  }

  static const String mensajePrepagoInsuficienteComisionViajeGenerico =
      'Tu prepago disponible no alcanza para la comisión de este viaje. '
      'Recarga en Mis pagos antes de aceptar.';

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

  /// Bloqueo operativo (pool, tomar viajes): saldo prepago bajo o cualquier comisión pendiente.
  /// La deuda semanal abierta se gestiona en Mis pagos y no cierra el pool por sí sola.
  static Future<bool> tieneBloqueoOperativo(String uidTaxista) async {
    return tieneBloqueoComisionEfectivo(uidTaxista);
  }

  /// Sincroniza `usuarios.tienePagoPendiente` y pools vía Cloud Function (Admin SDK).
  /// No hay fallback en cliente: Firestore rules no permiten escribir esa bandera.
  static Future<void> sincronizarBloqueoOperativo(String uidTaxista) async {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return;
    try {
      final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
      await fx.httpsCallable('sincronizarBloqueoOperativoTaxista').call(
        <String, dynamic>{'uidTaxista': uid},
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[PagosTaxistaRepo] sincronizarBloqueoOperativo CF ${e.code}: ${e.message}',
      );
    } catch (e) {
      debugPrint('[PagosTaxistaRepo] sincronizarBloqueoOperativo: $e');
    }
  }

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

  /// Fallback local si la CF no está disponible. **Solo funciona con Admin SDK**:
  /// las reglas de Firestore no permiten que el taxista escriba `tienePagoPendiente`.
  static Future<void> _sincronizarBanderaPendiente(String uidTaxista) async {
    if (uidTaxista.trim().isEmpty) return;
    final bille =
        await _db.collection('billeteras_taxista').doc(uidTaxista).get();
    final bool bloqueoComision =
        bloqueoOperativoPorComisionEfectivo(bille.data());
    final double deudaPoolRd =
        await sumarDeudaPoolComisionPendienteAdmin(uidTaxista);
    final bool bloqueoPool =
        deudaPoolRd + 1e-9 >= umbralDeudaPoolComisionAdminRd;
    final bool tienePagoPendiente = bloqueoComision || bloqueoPool;
    await _db.collection('usuarios').doc(uidTaxista).set(
      {
        'tienePagoPendiente': tienePagoPendiente,
        'deudaPoolPendienteRd': deudaPoolRd,
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
    double? montoElegidoRd,
    String? paqueteRecarga,
    String metodoPago = 'transferencia',
  }) async {
    final uid = uidTaxista.trim();
    print(
        '[PagosTaxistaRepo] taxistaEnviarRecargaComisionEfectivo start uid=$uid montoDeclarado=$montoDeclaradoRd montoElegido=$montoElegidoRd paquete=$paqueteRecarga');
    if (uid.isEmpty) throw Exception('Sesión inválida');
    final url = comprobanteUrl.trim();
    if (url.isEmpty) throw Exception('Debes subir el comprobante');
    if (montoDeclaradoRd <= 0) {
      throw Exception('Indica el monto que transferiste');
    }
    final abierta = await _recargasCol
        .where('uidTaxista', isEqualTo: uid)
        .where('estado', whereIn: ['pendiente_verificacion', 'pendiente_pago_azul'])
        .limit(1)
        .get();
    if (abierta.docs.isNotEmpty) {
      final estado = (abierta.docs.first.data()['estado'] ?? '').toString();
      print(
          '[PagosTaxistaRepo] taxistaEnviarRecargaComisionEfectivo rechazado: recarga abierta estado=$estado');
      throw Exception(
        estado == 'pendiente_pago_azul'
            ? 'Ya tienes una recarga con tarjeta en curso. Complétala en AZUL o esperá.'
            : 'Ya tienes una recarga en revisión. Espera a que el administrador la verifique.',
      );
    }
    final b = await _db.collection('billeteras_taxista').doc(uid).get();
    final bill = b.data();
    final pend = comisionPendienteDesdeBilletera(bill);
    final saldo = saldoPrepagoComisionDesdeBilletera(bill);
    final resG = saldoReservadoParaGirasDesdeBilletera(bill);
    final disp = saldoDisponiblePrepagoComisionDesdeBilletera(bill);
    print(
      '[PRE_TEST] recarga solicitud uid=$uid saldoPrepagoBruto=$saldo '
      'reservadoGiras=$resG disponibleOperar=$disp comisionPendiente=$pend '
      'montoDeclaradoRd=$montoDeclaradoRd',
    );
    await _recargasCol.add({
      'uidTaxista': uid,
      'nombreTaxista':
          nombreTaxista.trim().isEmpty ? 'Taxista' : nombreTaxista.trim(),
      'comisionPendienteAlEnviar': double.parse(pend.toStringAsFixed(2)),
      'saldoPrepagoAlEnviar': double.parse(saldo.toStringAsFixed(2)),
      'montoDeclaradoRd': double.parse(montoDeclaradoRd.toStringAsFixed(2)),
      if (montoElegidoRd != null && montoElegidoRd > 0)
        'montoElegidoRd': double.parse(montoElegidoRd.toStringAsFixed(2)),
      if ((paqueteRecarga ?? '').trim().isNotEmpty)
        'paqueteRecarga': paqueteRecarga!.trim(),
      'comprobanteUrl': url,
      'metodoPago':
          metodoPago.trim().isEmpty ? 'transferencia' : metodoPago.trim(),
      'estado': 'pendiente_verificacion',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // Bandera visible en ADM (Gestionar usuarios → Bloqueados prepago).
    await sincronizarBloqueoOperativo(uid);
    print(
        '[PRE_TEST] recarga documento creado uid=$uid (saldo sin cambio hasta aprobación admin; snapshot prepago=$saldo)');
    print(
        '[PagosTaxistaRepo] taxistaEnviarRecargaComisionEfectivo documento creado en recargas_comision_taxista');
  }

  static Future<void> adminVerificarRecargaComisionEfectivo({
    required String recargaId,
    required bool aprobado,
    String? notaAdmin,
  }) async {
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    if (aprobado) {
      final HttpsCallable callable =
          fx.httpsCallable('approveRecargaComision');
      final HttpsCallableResult<dynamic> res =
          await callable.call(<String, dynamic>{
        'recargaId': recargaId.trim(),
        'notaAdmin': (notaAdmin ?? '').trim(),
      });
      final Object? data = res.data;
      if (data is! Map || data['ok'] != true) {
        throw Exception(
          'approveRecargaComision no confirmó ok. Respuesta: $data',
        );
      }
    } else {
      final motivo = (notaAdmin ?? '').trim();
      if (motivo.isEmpty) throw Exception('Indica el motivo del rechazo');
      final HttpsCallable callable =
          fx.httpsCallable('rejectRecargaComision');
      final HttpsCallableResult<dynamic> res =
          await callable.call(<String, dynamic>{
        'recargaId': recargaId.trim(),
        'notaAdmin': motivo,
      });
      final Object? data = res.data;
      if (data is! Map || data['ok'] != true) {
        throw Exception(
          'rejectRecargaComision no confirmó ok. Respuesta: $data',
        );
      }
    }
  }

  // ==============================================================
  // GENERAR PAGO SEMANAL (llamado por Cloud Function o manualmente)
  // ==============================================================
  static Future<void> generarPagoSemanal(String uidTaxista) async {
    try {
      await FinanceConfigService.ensureStarted();
      if (FinanceConfigService.useLiquidacionesSemanales &&
          !FinanceConfigService.escrituraPagosTaxistasLegacy) {
        return;
      }
      final bool excluirEfectivo =
          FinanceConfigService.excluirEfectivoDePagoSemanal;

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
      int viajesEfectivoExcluidos = 0;

      for (final viaje in viajes.docs) {
        final data = viaje.data();
        if (excluirEfectivo && !LiquidacionSemanalViaje.esElegible(data)) {
          if (MetodoPagoViaje.esEfectivo(data['metodoPago']?.toString())) {
            viajesEfectivoExcluidos++;
          }
          continue;
        }
        totalGanado += (data['gananciaTaxista'] ?? 0).toDouble();
        totalComision += (data['comision'] ?? 0).toDouble();
      }

      final viajesSemana = excluirEfectivo
          ? viajes.docs
              .where((v) => LiquidacionSemanalViaje.esElegible(v.data()))
              .length
          : viajes.docs.length;

      // Si no hay viajes liquidables, no generar pago
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
        final Map<String, dynamic> pagoDoc = {
          ...pago.toMap(),
          'id': pagoId,
          'createdAt': FieldValue.serverTimestamp(),
        };
        if (excluirEfectivo) {
          pagoDoc['incluyeSoloMetodos'] = const ['transferencia', 'tarjeta'];
          pagoDoc['viajesEfectivoExcluidosCount'] = viajesEfectivoExcluidos;
        }
        tx.set(pagoRef, pagoDoc);
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

  /// Misma regla que la primera parte de [puedeTrabajar] (deuda semanal >14 días).
  static Future<bool> tieneDeudaSemanalVencida(String uidTaxista) async {
    if (uidTaxista.trim().isEmpty) return false;
    try {
      final now = DateTime.now();
      final dosSemanasAtras = now.subtract(const Duration(days: 14));
      final pagosVencidos = await _col
          .where('uidTaxista', isEqualTo: uidTaxista)
          .where('estado', whereIn: _estadosDeudaAbierta)
          .where('fechaFin', isLessThan: Timestamp.fromDate(dosSemanasAtras))
          .limit(1)
          .get();
      return pagosVencidos.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error tieneDeudaSemanalVencida: $e');
      return false;
    }
  }

  /// Banco + cuenta + titular en `usuarios` (cliente transfiere al taxista en viajes transferencia).
  static bool perfilBancarioTransferenciaCompleto(
      Map<String, dynamic>? usuarioData) {
    if (usuarioData == null) return false;
    final String banco = (usuarioData['banco'] ?? '').toString().trim();
    final String cuenta =
        (usuarioData['numeroCuenta'] ?? '').toString().trim();
    final String titular = (usuarioData['titularCuenta'] ??
            usuarioData['titular'] ??
            '')
        .toString()
        .trim();
    return banco.isNotEmpty && cuenta.isNotEmpty && titular.isNotEmpty;
  }

  static Future<bool> puedeTrabajar(String uidTaxista) async {
    try {
      if (await tieneDeudaSemanalVencida(uidTaxista)) {
        return false;
      }

      final usr =
          await _db.collection('usuarios').doc(uidTaxista).get();
      final ud = usr.data();
      if (ud != null && ud['tienePagoPendiente'] == true) {
        return false;
      }

      final bille =
          await _db.collection('billeteras_taxista').doc(uidTaxista).get();
      if (bloqueoOperativoPorComisionEfectivo(bille.data())) {
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Error verificando si puede trabajar: $e');
      // Onboarding: sin deuda explícita no bloquear por fallo transitorio de lectura.
      try {
        final usr =
            await _db.collection('usuarios').doc(uidTaxista.trim()).get();
        if (usr.data()?['tienePagoPendiente'] != true) return true;
      } catch (_) {}
      return false;
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
    await _assertEscrituraLegacyPagosTaxistas();
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
    await _assertEscrituraLegacyPagosTaxistas();
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

  /// Lectura puntual (sin stream) para pantallas de bloqueo — evita parpadeos.
  static Future<List<PagoTaxista>> obtenerPagosAbiertosTaxista(
      String uidTaxista) async {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return const [];
    try {
      final snap = await _col.where('uidTaxista', isEqualTo: uid).get();
      final list = snap.docs
          .map((doc) => PagoTaxista.fromMap(doc.id, doc.data()))
          .toList();
      list.sort((a, b) => b.fechaFin.compareTo(a.fechaFin));
      return list;
    } catch (e) {
      debugPrint('[PagosTaxistaRepo] obtenerPagosAbiertosTaxista: $e');
      return const [];
    }
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
