// lib/servicios/pool_repo.dart
// ignore_for_file: avoid_print -- logs operativos [GIRA_PREPAGO]

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/servicios/cliente_cuenta_real_policy.dart';
import 'package:flygo_nuevo/servicios/cliente_verificacion_identidad_service.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/servicios/analytics_rai.dart';
import 'package:flygo_nuevo/servicios/pool_gira_abuso.dart';
import 'package:flygo_nuevo/servicios/taxista_registro_perfil_data.dart';
import 'package:flygo_nuevo/utils/pool_gira_contenido.dart';
import 'package:flygo_nuevo/utils/pool_recaudo_central.dart';

class CrearPoolResult {
  const CrearPoolResult({required this.poolId, this.aviso});
  final String poolId;
  /// Solo si la reserva al publicar fue menor que la comisión objetivo (cupos mínimos).
  final String? aviso;
}

class PoolReservaResult {
  const PoolReservaResult({
    required this.poolId,
    required this.reservaId,
    this.recaudoCentral = false,
    this.referenciaRecaudo = '',
    this.montoEsperadoRecaudoRd = 0,
  });

  final String poolId;
  final String reservaId;
  final bool recaudoCentral;
  final String referenciaRecaudo;
  final double montoEsperadoRecaudoRd;

  factory PoolReservaResult.fromCallableData(Object? raw) {
    if (raw is! Map) {
      return const PoolReservaResult(poolId: '', reservaId: '');
    }
    final m = Map<String, dynamic>.from(raw);
    return PoolReservaResult(
      poolId: (m['poolId'] ?? '').toString(),
      reservaId: (m['reservaId'] ?? '').toString(),
      recaudoCentral: m['recaudoCentral'] == true,
      referenciaRecaudo: (m['referenciaRecaudo'] ?? '').toString(),
      montoEsperadoRecaudoRd:
          ((m['montoEsperadoRecaudoRd'] ?? 0) as num).toDouble(),
    );
  }
}

/// Vista previa de comisión al iniciar gira (cupos firmes en RAI).
class GiraInicioComisionPreview {
  const GiraInicioComisionPreview({
    required this.cuposFirmesRai,
    required this.comisionEstimadaRd,
    required this.comisionReservadaRd,
    required this.excesoDevolucionRd,
    required this.pctComision,
    this.recaudoCentral = false,
    this.asientosEfectivo = 0,
    this.comisionEfectivoRd = 0,
  });

  final int cuposFirmesRai;
  final double comisionEstimadaRd;
  final double comisionReservadaRd;
  final double excesoDevolucionRd;
  final double pctComision;
  final bool recaudoCentral;
  final int asientosEfectivo;
  final double comisionEfectivoRd;
}

/// Fila admin: reserva pool RAI con pago pendiente de verificar.
class PoolReservaRaiPendienteAdmin {
  const PoolReservaRaiPendienteAdmin({
    required this.poolId,
    required this.reservaId,
    required this.reserva,
    required this.pool,
  });

  final String poolId;
  final String reservaId;
  final Map<String, dynamic> reserva;
  final Map<String, dynamic> pool;
}

/// Reserva de gira del cliente (historial global Mis giras).
class PoolReservaClienteGira {
  const PoolReservaClienteGira({
    required this.poolId,
    required this.reservaId,
    required this.reserva,
    this.pool = const {},
  });

  final String poolId;
  final String reservaId;
  final Map<String, dynamic> reserva;
  final Map<String, dynamic> pool;
}

class PoolRepo {
  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get pools =>
      _db.collection('viajes_pool');

  /// Reserva pool central con transferencia aún no verificada por admin.
  static bool reservaEsPagoPendienteAdmin(Map<String, dynamic> r) {
    final est = (r['estado'] ?? '').toString().trim().toLowerCase();
    if (est != 'reservado') return false;
    final ep = (r['estadoPago'] ?? '').toString().trim().toLowerCase();
    return ep.isEmpty || ep == 'pendiente' || ep == 'comprobante_enviado';
  }

  /// Admin · Verificar pagos Giras RAI (sin collectionGroup → sin índice compuesto).
  static Stream<List<PoolReservaRaiPendienteAdmin>>
      streamReservasPoolRaiPagoPendienteAdmin({
    int poolLimit = 80,
  }) {
    return Stream<List<PoolReservaRaiPendienteAdmin>>.multi((multi) {
      final reservaSubs =
          <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
      var poolDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      final reservasByPool =
          <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};

      void publish() {
        final out = <PoolReservaRaiPendienteAdmin>[];
        for (final poolDoc in poolDocs) {
          final poolId = poolDoc.id;
          final pool = poolDoc.data();
          for (final r in reservasByPool[poolId] ?? const []) {
            if (!reservaEsPagoPendienteAdmin(r.data())) continue;
            out.add(PoolReservaRaiPendienteAdmin(
              poolId: poolId,
              reservaId: r.id,
              reserva: r.data(),
              pool: pool,
            ));
          }
        }
        out.sort((a, b) {
          final ta = a.reserva['createdAt'];
          final tb = b.reserva['createdAt'];
          final da = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
          final db = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
          return db.compareTo(da);
        });
        multi.add(out);
      }

      void bindPoolReservas(String poolId) {
        reservaSubs[poolId] = pools
            .doc(poolId)
            .collection('reservas')
            .where('estado', isEqualTo: 'reservado')
            .snapshots()
            .listen(
          (snap) {
            reservasByPool[poolId] = snap.docs;
            publish();
          },
          onError: multi.addError,
        );
      }

      final poolsSub = pools
          .where('recaudoModelo', isEqualTo: 'central')
          .limit(poolLimit)
          .snapshots()
          .listen(
        (snap) {
          poolDocs = snap.docs;
          final ids = snap.docs.map((d) => d.id).toSet();
          for (final id in reservaSubs.keys.toList()) {
            if (!ids.contains(id)) {
              reservaSubs.remove(id)?.cancel();
              reservasByPool.remove(id);
            }
          }
          for (final id in ids) {
            if (!reservaSubs.containsKey(id)) bindPoolReservas(id);
          }
          publish();
        },
        onError: multi.addError,
      );

      multi.onCancel = () async {
        await poolsSub.cancel();
        for (final s in reservaSubs.values) {
          await s.cancel();
        }
      };
    });
  }

  /// Cliente: todas sus reservas en giras (Mis giras · historial global).
  static Stream<List<PoolReservaClienteGira>> streamMisReservasGiraCliente(
    String uid, {
    int limit = 80,
  }) {
    final u = uid.trim();
    if (u.isEmpty) return Stream.value(const []);

    return _db
        .collectionGroup('reservas')
        .where('uidCliente', isEqualTo: u)
        .limit(limit)
        .snapshots()
        .asyncMap((snap) async {
          final items = snap.docs
              .map((doc) {
                final poolId = doc.reference.parent.parent?.id ?? '';
                if (poolId.isEmpty) return null;
                return PoolReservaClienteGira(
                  poolId: poolId,
                  reservaId: doc.id,
                  reserva: doc.data(),
                );
              })
              .whereType<PoolReservaClienteGira>()
              .toList();

          items.sort((a, b) {
            final ta = a.reserva['createdAt'];
            final tb = b.reserva['createdAt'];
            final da = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
            final db = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
            return db.compareTo(da);
          });

          final poolIds = items.map((e) => e.poolId).toSet();
          final poolMap = <String, Map<String, dynamic>>{};
          await Future.wait(poolIds.map((id) async {
            try {
              final p = await pools.doc(id).get();
              if (p.exists) poolMap[id] = p.data() ?? {};
            } catch (_) {}
          }));

          return items
              .map(
                (r) => PoolReservaClienteGira(
                  poolId: r.poolId,
                  reservaId: r.reservaId,
                  reserva: r.reserva,
                  pool: poolMap[r.poolId] ?? const {},
                ),
              )
              .toList();
        });
  }

  static const String _msgGiraLegacySinComisionEstimada =
      'Esta salida fue creada con una versión anterior del sistema. Por favor, cancélala y crea una nueva.';

  static double _round2(double v) =>
      double.parse(v.clamp(0, 1e12).toStringAsFixed(2));

  /// Default UI: min(5, mínimo confirmar) si mínimo > 5.
  static int defaultCuposComisionRai({
    required int capacidad,
    required int minParaConfirmar,
  }) {
    final int cap = capacidad > 0 ? capacidad : 1;
    final int minConf = minParaConfirmar > 0 ? minParaConfirmar : cap;
    if (minConf <= 5) return minConf.clamp(1, cap);
    return 5.clamp(1, cap);
  }

  /// Cupos usados para apartar prepago al publicar (tope RAI, no todo el bus).
  static int cuposReservaComision({
    required int cuposComisionRai,
    required int minParaConfirmar,
    required int capacidad,
  }) {
    final int cap = capacidad > 0 ? capacidad : 1;
    final int minConf = minParaConfirmar > 0 ? minParaConfirmar : cap;
    final int tope = cuposComisionRai.clamp(1, cap);
    return [tope, minConf, cap].reduce((int a, int b) => a < b ? a : b);
  }

  /// Pagado + efectivo reservado en app (igual que firmSeatsFromReservaDocs en CF).
  static int cuposFirmesRaiDesdeReservas(Iterable<Map<String, dynamic>> reservas) {
    var firm = 0;
    for (final r in reservas) {
      final e = (r['estado'] ?? '').toString().toLowerCase().trim();
      final m = (r['metodoPago'] ?? '').toString().toLowerCase().trim();
      final s = ((r['seats'] ?? 0) as num).toInt();
      if (s <= 0) continue;
      if (e == 'pagado') {
        firm += s;
      } else if (e == 'reservado' && m == 'efectivo') {
        firm += s;
      }
    }
    return firm;
  }

  /// Solo asientos efectivo firmes (recaudo central: comisión prepago al iniciar).
  static int cuposEfectivoFirmesDesdeReservas(
    Iterable<Map<String, dynamic>> reservas,
  ) {
    var n = 0;
    for (final r in reservas) {
      final e = (r['estado'] ?? '').toString().toLowerCase().trim();
      final m = (r['metodoPago'] ?? '').toString().toLowerCase().trim();
      final s = ((r['seats'] ?? 0) as num).toInt();
      if (s <= 0 || m != 'efectivo') continue;
      if (e == 'pagado' || e == 'reservado') n += s;
    }
    return n;
  }

  static double comisionRdDesdeCupos({
    required Map<String, dynamic> pool,
    required int cupos,
    required double pct,
  }) {
    return PoolRecaudoCentral.comisionRaiRd(
      pool: pool,
      asientos: cupos,
      pctComision: pct,
    );
  }

  /// Lectura pool + reservas para diálogo antes de iniciar.
  static Future<GiraInicioComisionPreview> previewComisionAlIniciar(
    String poolId,
  ) async {
    final poolSnap = await pools.doc(poolId).get();
    if (!poolSnap.exists) {
      throw 'Salida no encontrada';
    }
    final pool = poolSnap.data() ?? <String, dynamic>{};
    final resSnap = await pools.doc(poolId).collection('reservas').get();
    final reservasList = resSnap.docs.map((d) => d.data()).toList();
    final firm = cuposFirmesRaiDesdeReservas(reservasList);
    final cap = ((pool['capacidad'] ?? 0) as num).toInt();
    final cupos = cap > 0 ? firm.clamp(0, cap) : firm;
    final pct = ((pool['comisionGiraPctUsado'] as num?)?.toDouble() ??
            PlataformaEconomia.comisionViajePorcentaje)
        .clamp(0.0, 100.0);
    final recaudoCentral = PoolRecaudoCentral.esPoolCentral(pool);
    final asientosEfectivo = recaudoCentral
        ? (cap > 0
            ? cuposEfectivoFirmesDesdeReservas(reservasList).clamp(0, cap)
            : cuposEfectivoFirmesDesdeReservas(reservasList))
        : 0;
    final comisionEst = recaudoCentral
        ? comisionRdDesdeCupos(
            pool: pool,
            cupos: asientosEfectivo,
            pct: pct,
          )
        : comisionRdDesdeCupos(pool: pool, cupos: cupos, pct: pct);
    final reservada =
        _round2(((pool['comisionGiraEstimadaRd'] ?? 0) as num).toDouble());
    final exceso = recaudoCentral
        ? 0.0
        : _round2((reservada - comisionEst).clamp(0.0, 1e12));
    return GiraInicioComisionPreview(
      cuposFirmesRai: cupos,
      comisionEstimadaRd: comisionEst,
      comisionReservadaRd: reservada,
      excesoDevolucionRd: exceso,
      pctComision: pct,
      recaudoCentral: recaudoCentral,
      asientosEfectivo: asientosEfectivo,
      comisionEfectivoRd: recaudoCentral ? comisionEst : 0,
    );
  }

  /// Hay cupos reservados o pagos registrados (cancelar afecta pasajeros).
  static bool giraTieneReservasActivas(Map<String, dynamic> d) {
    final occ = ((d['asientosReservados'] ?? 0) as num).toInt();
    final pag = ((d['asientosPagados'] ?? 0) as num).toInt();
    return occ > 0 || pag > 0;
  }

  /// Antes de `en_ruta`: chofer/admin pueden cancelar la gira (devuelve prepago reservado vía CF).
  static bool giraPuedeCancelarseAntesDeIniciar(Map<String, dynamic> d) {
    final estado = (d['estado'] ?? '').toString().trim().toLowerCase();
    const bloqueados = <String>{
      'en_ruta',
      'finalizado',
      'cancelado',
      'cancelado_por_admin',
    };
    return !bloqueados.contains(estado);
  }

  /// Gira cerrada: no debe aparecer en catálogo cliente ni lista activa taxista.
  static bool giraEstadoOcultoEnListados(String raw) {
    final s = raw.trim().toLowerCase();
    return s == 'cancelado' ||
        s == 'cancelado_por_admin' ||
        s == 'finalizado' ||
        s == 'en_ruta';
  }

  /// Reserva de cupo aún vigente para el pasajero (no cancelada).
  static bool reservaPoolActivaParaCliente(String raw) {
    final e = raw.trim().toLowerCase();
    return e == 'reservado' || e == 'pagado';
  }

  /// Pool admite reservas / cancelación de cupos por clientes.
  static bool giraAdmiteReservasCliente(Map<String, dynamic> d) {
    final estado = (d['estado'] ?? '').toString().trim().toLowerCase();
    const permitidos = <String>{
      'abierto',
      'preconfirmado',
      'confirmado',
      'activo',
      'disponible',
      'buscando',
      'lleno',
    };
    return permitidos.contains(estado);
  }

  static Future<CrearPoolResult> crearPool({
    required String tipo,
    required String sentido,
    required String origenTown,
    required String destino,
    required DateTime fechaSalida,
    DateTime? fechaVuelta,
    required int capacidad,
    required int minParaConfirmar,
    required int cuposComisionRai,
    required double precioPorAsiento,
    List<String>? pickupPoints,
    double depositPct = 0.30,
    double feePct = 0.10,
    String? agenciaNombre,
    String? agenciaLogoUrl,
    String? bannerUrl,
    List<String>? bannerUrls,
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
    PoolGiraContenidoExtra? contenidoExtra,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw 'Debes iniciar sesión como taxista';

    final userPre = await _db.collection('usuarios').doc(u.uid).get();
    final udPre = userPre.data() ?? <String, dynamic>{};
    if (!TaxistaRegistroPerfilData.taxistaRegistroPerfilCompleto(udPre)) {
      throw 'Completá tu registro de conductor en RAI antes de publicar salidas por cupos.';
    }

    final int cap = capacidad > 0 ? capacidad : 1;
    if (cuposComisionRai < 1 || cuposComisionRai > cap) {
      throw 'Cupos RAI para comisión debe estar entre 1 y $cap.';
    }

    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    try {
      final callable = fx.httpsCallable('crearPoolGira');
      final res = await callable.call(<String, dynamic>{
        'tipo': tipo,
        'sentido': sentido,
        'origenTown': origenTown.trim(),
        'destino': destino.trim(),
        'fechaSalida': fechaSalida.millisecondsSinceEpoch,
        if (fechaVuelta != null)
          'fechaVuelta': fechaVuelta.millisecondsSinceEpoch,
        'capacidad': capacidad,
        'minParaConfirmar': minParaConfirmar,
        'cuposComisionRai': cuposComisionRai,
        'precioPorAsiento': precioPorAsiento,
        if (pickupPoints != null && pickupPoints.isNotEmpty)
          'pickupPoints': pickupPoints,
        'depositPct': depositPct,
        'feePct': feePct,
        if (agenciaNombre != null && agenciaNombre.trim().isNotEmpty)
          'agenciaNombre': agenciaNombre.trim(),
        if (agenciaLogoUrl != null && agenciaLogoUrl.trim().isNotEmpty)
          'agenciaLogoUrl': agenciaLogoUrl.trim(),
        if (bannerUrls != null && bannerUrls.isNotEmpty)
          'bannerUrls': bannerUrls
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .take(3)
              .toList(),
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
        ...?contenidoExtra?.toFirestore(),
      });

      final raw = res.data;
      if (raw is! Map) {
        throw 'Respuesta inválida al publicar la salida.';
      }
      final data = Map<String, dynamic>.from(raw);
      final poolId = (data['poolId'] ?? '').toString().trim();
      if (poolId.isEmpty) {
        throw 'No se recibió el identificador de la salida publicada.';
      }
      final avisoRaw = data['aviso'];
      final aviso = avisoRaw?.toString().trim();

      print('[GIRA_PREPAGO] crearPoolGira ok poolId=$poolId uid=${u.uid}');

      unawaited(
        AnalyticsRai.logGiraCreated(
          comisionEstimada: 0,
          capacidad: capacidad,
          precioPorAsiento: precioPorAsiento,
        ),
      );

      return CrearPoolResult(
        poolId: poolId,
        aviso: aviso != null && aviso.isNotEmpty ? aviso : null,
      );
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      if (details is Map &&
          (details['tipo'] ?? '').toString() == 'gira_abuso') {
        throw PoolGiraAbusoBloqueo(
          creadas: ((details['creadas'] ?? 0) as num).toInt(),
          canceladas: ((details['canceladas'] ?? 0) as num).toInt(),
          ratioMax: ((details['ratioMax'] ?? 0.5) as num).toDouble(),
          diasHastaReinicio: details['diasHastaReinicio'] == null
              ? null
              : ((details['diasHastaReinicio'] as num).toInt()),
        );
      }
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) throw msg;
      if (e.code == 'permission-denied') {
        throw 'No se pudo publicar la salida (permisos). '
            'Verifica que iniciaste sesión como conductor o contacta soporte.';
      }
      if (e.code == 'not-found' || e.code == 'unimplemented') {
        throw 'La función de publicación no está disponible. '
            'Actualiza la app o contacta soporte RAI.';
      }
      throw 'Error al publicar la salida (${e.code}).';
    }
  }

  /// Edita contenido de gira publicada (reservas y pagos se conservan).
  static Future<void> actualizarPoolGiraContenido({
    required String poolId,
    PoolGiraContenidoExtra? contenidoExtra,
    String? agenciaNombre,
    String? agenciaLogoUrl,
    String? bannerUrl,
    List<String>? bannerUrls,
    String? bannerVideoUrl,
    String? puntoSalida,
    String? destino,
    String? servicioBadge,
    String? descripcionViaje,
    List<String>? incluye,
    List<String>? pickupPoints,
    String? origenTown,
    String? bancoNombre,
    String? bancoCuenta,
    String? bancoTipoCuenta,
    String? bancoTitular,
    double? precioPorAsiento,
    int? capacidad,
    DateTime? fechaSalida,
    DateTime? fechaVuelta,
    bool clearFechaVuelta = false,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw 'Debes iniciar sesión';

    final payload = <String, dynamic>{
      'poolId': poolId.trim(),
      ...?contenidoExtra?.toFirestore(),
      if (agenciaNombre != null && agenciaNombre.trim().isNotEmpty)
        'agenciaNombre': agenciaNombre.trim(),
      if (agenciaLogoUrl != null && agenciaLogoUrl.trim().isNotEmpty)
        'agenciaLogoUrl': agenciaLogoUrl.trim(),
      if (bannerUrls != null && bannerUrls.isNotEmpty)
        'bannerUrls': bannerUrls
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .take(3)
            .toList(),
      if (bannerUrl != null && bannerUrl.trim().isNotEmpty)
        'bannerUrl': bannerUrl.trim(),
      if (bannerVideoUrl != null && bannerVideoUrl.trim().isNotEmpty)
        'bannerVideoUrl': bannerVideoUrl.trim(),
      if (puntoSalida != null && puntoSalida.trim().isNotEmpty)
        'puntoSalida': puntoSalida.trim(),
      if (destino != null && destino.trim().isNotEmpty)
        'destino': destino.trim(),
      if (servicioBadge != null && servicioBadge.trim().isNotEmpty)
        'servicioBadge': servicioBadge.trim(),
      if (descripcionViaje != null && descripcionViaje.trim().isNotEmpty)
        'descripcionViaje': descripcionViaje.trim(),
      if (incluye != null && incluye.isNotEmpty) 'incluye': incluye,
      if (pickupPoints != null && pickupPoints.isNotEmpty)
        'pickupPoints': pickupPoints,
      if (origenTown != null && origenTown.trim().isNotEmpty)
        'origenTown': origenTown.trim(),
      if (bancoNombre != null && bancoNombre.trim().isNotEmpty)
        'bancoNombre': bancoNombre.trim(),
      if (bancoCuenta != null && bancoCuenta.trim().isNotEmpty)
        'bancoCuenta': bancoCuenta.trim(),
      if (bancoTipoCuenta != null && bancoTipoCuenta.trim().isNotEmpty)
        'bancoTipoCuenta': bancoTipoCuenta.trim(),
      if (bancoTitular != null && bancoTitular.trim().isNotEmpty)
        'bancoTitular': bancoTitular.trim(),
      if (precioPorAsiento != null && precioPorAsiento > 0)
        'precioPorAsiento': precioPorAsiento,
      if (capacidad != null && capacidad > 0) 'capacidad': capacidad,
      if (fechaSalida != null)
        'fechaSalida': fechaSalida.millisecondsSinceEpoch,
      if (clearFechaVuelta) 'fechaVuelta': null,
      if (!clearFechaVuelta && fechaVuelta != null)
        'fechaVuelta': fechaVuelta.millisecondsSinceEpoch,
    };

    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = fx.httpsCallable('actualizarPoolGiraContenido');
    await callable.call(payload);
  }

  /// Ticket digital: genera token si falta (reserva pagada).
  static Future<String> ensurePoolReservaTicket({
    required String poolId,
    required String reservaId,
  }) async {
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    final res = await fx.httpsCallable('ensurePoolReservaTicket').call(<String, dynamic>{
      'poolId': poolId.trim(),
      'reservaId': reservaId.trim(),
    });
    final raw = res.data;
    if (raw is! Map) throw 'Respuesta inválida al obtener ticket';
    final token = (raw['tokenEntrada'] ?? '').toString().trim();
    if (token.isEmpty) throw 'No se pudo generar el ticket';
    return token;
  }

  /// Valida código QR / token en punto de salida (admin u operador).
  static Future<Map<String, dynamic>> validarTokenEntradaGira({
    required String token,
    String? poolId,
  }) async {
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    final res = await fx.httpsCallable('validarTokenEntradaGira').call(<String, dynamic>{
      'token': token.trim().toUpperCase(),
      if (poolId != null && poolId.trim().isNotEmpty) 'poolId': poolId.trim(),
    });
    final raw = res.data;
    if (raw is! Map) throw 'Respuesta inválida al validar ticket';
    return Map<String, dynamic>.from(raw);
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

  static Future<void> reportarComprobanteReservaSeguro({
    required String poolId,
    required String reservaId,
    required String comprobanteUrl,
    String? idempotencyKey,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw 'Debes iniciar sesión';
    final url = comprobanteUrl.trim();
    if (url.isEmpty) throw 'Falta comprobante';
    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : 'bauche_${poolId}_${reservaId}_${DateTime.now().millisecondsSinceEpoch}';
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    await fx.httpsCallable('reportPoolReservaComprobante').call(<String, dynamic>{
      'poolId': poolId,
      'reservaId': reservaId,
      'comprobanteUrl': url,
      'idempotencyKey': key,
    });
  }

  static Future<PoolReservaResult> reservarCupos({
    required String poolId,
    required int seats,
    required String metodoPago,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw 'Debes iniciar sesión';
    ClienteCuentaRealPolicy.exigirParaPedirViaje();
    await ClienteVerificacionIdentidadService.exigirParaPedirViaje();
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = fx.httpsCallable('reservePoolSeats');
    final resp = await callable.call(<String, dynamic>{
      'poolId': poolId,
      'seats': seats,
      'metodoPago': metodoPago,
      'idempotencyKey':
          '${poolId}_${u.uid}_${DateTime.now().millisecondsSinceEpoch}',
    });
    return PoolReservaResult.fromCallableData(resp.data);
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

  /// Admin: verifica transferencia del cliente en cuenta RAI (recaudo central).
  static Future<void> verifyPoolReservaRecaudoAdmin({
    required String poolId,
    required String reservaId,
    String? idempotencyKey,
  }) async {
    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : 'verify_${poolId}_${reservaId}_${DateTime.now().millisecondsSinceEpoch}';
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    await fx.httpsCallable('verifyPoolReservaRecaudo').call(<String, dynamic>{
      'poolId': poolId,
      'reservaId': reservaId,
      'idempotencyKey': key,
    });
  }

  /// Admin: revierte reserva pool verificada (reembolso manual al cliente).
  static Future<void> adminRevertPoolReservaPagada({
    required String poolId,
    required String reservaId,
    required String motivo,
    String? idempotencyKey,
  }) async {
    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : 'revert_${poolId}_${reservaId}_${DateTime.now().millisecondsSinceEpoch}';
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    await fx.httpsCallable('adminRevertPoolReservaPagada').call(<String, dynamic>{
      'poolId': poolId,
      'reservaId': reservaId,
      'motivo': motivo.trim(),
      'idempotencyKey': key,
    });
  }

  /// Admin: neto transferido al organizador tras cerrar gira central.
  static Future<void> approveLiquidacionPoolAdmin({
    required String liquidacionId,
    String? referenciaBanco,
    String? idempotencyKey,
  }) async {
    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : 'liq_${liquidacionId}_${DateTime.now().millisecondsSinceEpoch}';
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    await fx.httpsCallable('approveLiquidacionPool').call(<String, dynamic>{
      'liquidacionId': liquidacionId,
      if (referenciaBanco != null && referenciaBanco.trim().isNotEmpty)
        'referenciaBanco': referenciaBanco.trim(),
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
    if (!PoolRecaudoCentral.poolPuedeIniciarEnApp(poolSnap.data())) {
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

  /// Cliente cancela su reserva activa (solo `reservado`, antes de salida en ruta).
  static Future<Map<String, dynamic>> cancelarReservaClienteSeguro({
    required String poolId,
    required String reservaId,
    String? idempotencyKey,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw 'Debes iniciar sesión';

    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : 'cancel_res_${poolId}_${reservaId}_${DateTime.now().millisecondsSinceEpoch}';
    final fx = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = fx.httpsCallable('cancelPoolReservation');
    final res = await callable.call(<String, dynamic>{
      'poolId': poolId,
      'reservaId': reservaId,
      'idempotencyKey': key,
    });
    final raw = res.data;
    if (raw == null) return <String, dynamic>{};
    return raw is Map<String, dynamic>
        ? raw
        : Map<String, dynamic>.from(raw as Map);
  }
}
