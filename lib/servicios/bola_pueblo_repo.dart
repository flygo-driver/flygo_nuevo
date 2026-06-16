import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/servicios/bola_pueblo_firestore_sync.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

class BolaPuebloRepo {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('bolas_pueblo');
  /// Tras acordar la bola puede pasar mucho tiempo hasta pickup + PIN; 20 min era demasiado corto.
  static const Duration vigenciaCodigoInicio = Duration(hours: 24);
  static const double baseBolaFactor = 0.50; // 50% de tarifa normal estimada.
  static const double ofertaMinFactorSobreBase = 0.80; // 80% de la base bola.
  static const double ofertaMaxFactorSobreNormal =
      1.10; // hasta 110% de tarifa normal.

  static const List<String> tipos = <String>['pedido', 'oferta'];
  static const List<String> estadosPublicacion = <String>[
    'abierta',
    'acordada',
    'en_curso',
    'finalizada',
    'cancelada',
  ];
  static const List<String> estadosOferta = <String>[
    'pendiente',
    'aceptada',
    'rechazada',
    'retirada',
  ];
  static const List<String> metodosPagoBola = <String>[
    'efectivo',
    'transferencia',
  ];

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamTablero() {
    return _col.orderBy('createdAt', descending: true).limit(200).snapshots();
  }

  /// Vista previa de tarifas (mismo criterio que [crearPublicacion]) para el formulario.
  static ({
    double tarifaNormalRd,
    double tarifaBaseBolaRd,
    double ofertaMinRd,
    double ofertaMaxRd,
  }) previewMontosPublicacion(double distanciaKm) {
    if (distanciaKm <= 0) {
      return (
        tarifaNormalRd: 0.0,
        tarifaBaseBolaRd: 0.0,
        ofertaMinRd: 0.0,
        ofertaMaxRd: 0.0,
      );
    }
    final double tarifaNormalRd = DistanciaService.calcularPrecio(distanciaKm);
    final double tarifaBaseBolaRd =
        double.parse((tarifaNormalRd * baseBolaFactor).toStringAsFixed(2));
    final double ofertaMinRd = double.parse(
        (tarifaBaseBolaRd * ofertaMinFactorSobreBase).toStringAsFixed(2));
    final double ofertaMaxRd = double.parse(
        (tarifaNormalRd * ofertaMaxFactorSobreNormal).toStringAsFixed(2));
    return (
      tarifaNormalRd: tarifaNormalRd,
      tarifaBaseBolaRd: tarifaBaseBolaRd,
      ofertaMinRd: ofertaMinRd,
      ofertaMaxRd: ofertaMaxRd,
    );
  }

  static Future<String> crearPublicacion({
    required String uid,
    required String rol,
    required String nombre,
    required String tipo,
    required String origen,
    required String destino,
    required double distanciaKm,
    required DateTime fechaSalida,
    String nota = '',
    double? origenLat,
    double? origenLon,
    double? destinoLat,
    double? destinoLon,
    int pasajeros = 1,

    /// Si viene en rango [ofertaMin,ofertaMax] se guarda como [montoSugeridoRd]; si no, usa la base bola.
    double? montoPropuestoRd,
  }) async {
    final t = tipo.trim().toLowerCase();
    if (!tipos.contains(t)) throw Exception('Tipo inválido');
    if (origen.trim().isEmpty || destino.trim().isEmpty) {
      throw Exception('Origen y destino son obligatorios');
    }
    if (uid.trim().isEmpty) throw Exception('Sesión inválida');
    if (distanciaKm <= 0) throw Exception('Distancia inválida');
    final int pax = pasajeros.clamp(1, 8);
    final double tarifaNormalRd = DistanciaService.calcularPrecio(distanciaKm);
    final double tarifaBaseBolaRd =
        double.parse((tarifaNormalRd * baseBolaFactor).toStringAsFixed(2));
    final double ofertaMinRd = double.parse(
        (tarifaBaseBolaRd * ofertaMinFactorSobreBase).toStringAsFixed(2));
    final double ofertaMaxRd = double.parse(
        (tarifaNormalRd * ofertaMaxFactorSobreNormal).toStringAsFixed(2));

    double montoSugeridoRd = tarifaBaseBolaRd;
    if (montoPropuestoRd != null &&
        montoPropuestoRd.isFinite &&
        montoPropuestoRd > 0) {
      final x = double.parse(montoPropuestoRd.toStringAsFixed(2));
      if (x >= ofertaMinRd && x <= ofertaMaxRd) {
        montoSugeridoRd = x;
      }
    }

    final doc = <String, dynamic>{
      'createdByUid': uid.trim(),
      'createdByRol': rol.trim().toLowerCase(),
      'createdByNombre': nombre.trim().isEmpty ? 'Usuario' : nombre.trim(),
      'tipo': t,
      'origen': origen.trim(),
      'destino': destino.trim(),
      'distanciaKm': double.parse(distanciaKm.toStringAsFixed(2)),
      'tarifaNormalRd': tarifaNormalRd,
      'tarifaBaseBolaRd': tarifaBaseBolaRd,
      'ofertaMinRd': ofertaMinRd,
      'ofertaMaxRd': ofertaMaxRd,
      'fechaSalida': Timestamp.fromDate(fechaSalida),
      'montoSugeridoRd': montoSugeridoRd,
      'nota': nota.trim(),
      'pasajeros': pax,
      'estado': 'abierta',
      'ofertaAceptadaId': '',
      'comisionPorcentaje': PlataformaEconomia.comisionViajePorcentaje,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final bool coordsOk = origenLat != null &&
        origenLon != null &&
        destinoLat != null &&
        destinoLon != null &&
        origenLat.isFinite &&
        origenLon.isFinite &&
        destinoLat.isFinite &&
        destinoLon.isFinite;
    if (coordsOk) {
      doc['origenLat'] = double.parse(origenLat.toStringAsFixed(6));
      doc['origenLon'] = double.parse(origenLon.toStringAsFixed(6));
      doc['destinoLat'] = double.parse(destinoLat.toStringAsFixed(6));
      doc['destinoLon'] = double.parse(destinoLon.toStringAsFixed(6));
    }
    final ref = await _col.add(doc);
    if (t == 'pedido' && coordsOk) {
      const int maxIntentos = 2;
      Object? lastErr;
      for (var intento = 1; intento <= maxIntentos; intento++) {
        try {
          debugPrint(
            '[BOLA_AHORRO] crearViajeEspejo intento=$intento/$maxIntentos bolaId=${ref.id}',
          );
          final String viajeIdEspejo = await ViajesRepo.crearViajePendiente(
            uidCliente: uid.trim(),
            origen: origen.trim(),
            destino: destino.trim(),
            latOrigen: origenLat,
            lonOrigen: origenLon,
            latDestino: destinoLat,
            lonDestino: destinoLon,
            fechaHora: fechaSalida,
            precio: montoSugeridoRd,
            metodoPago: 'Efectivo',
            tipoVehiculo: 'Bola Ahorro',
            idaYVuelta: false,
            distanciaKm: distanciaKm,
            tipoServicio: 'bola_ahorro',
            bolaPuebloId: ref.id,
            comisionPorcentajeViaje: PlataformaEconomia.comisionViajePorcentaje,
          );
          debugPrint(
            '[BOLA_AHORRO] crearViajeEspejo OK viajeId=$viajeIdEspejo bolaId=${ref.id}',
          );
          await ref.set(<String, dynamic>{
            'viajeEspejoId': viajeIdEspejo,
            'errorSync': false,
            'errorSyncViajeEspejo': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          lastErr = null;
          break;
        } catch (e, st) {
          lastErr = e;
          debugPrint(
            '[BOLA_AHORRO] crearViajeEspejo FAIL intento=$intento bolaId=${ref.id} err=$e\n$st',
          );
          if (intento < maxIntentos) {
            await Future<void>.delayed(const Duration(milliseconds: 600));
          }
        }
      }
      if (lastErr != null) {
        await BolaPuebloFirestoreSync.marcarErrorSyncViajeEspejo(
          bolaId: ref.id,
          error: lastErr,
        );
      }
    }
    return ref.id;
  }

  static CollectionReference<Map<String, dynamic>> _ofertasCol(String bolaId) =>
      _col.doc(bolaId).collection('ofertas');

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamOfertas(
      String bolaId) {
    return _ofertasCol(bolaId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Future<void> enviarOferta({
    required String bolaId,
    required String fromUid,
    required String fromNombre,
    required String fromRol,
    required double montoRd,
    String mensaje = '',
  }) async {
    if (bolaId.trim().isEmpty) throw Exception('Publicación inválida');
    if (fromUid.trim().isEmpty) throw Exception('Sesión inválida');
    if (montoRd <= 0) throw Exception('Monto inválido');
    final pubSnap = await _col.doc(bolaId).get();
    if (!pubSnap.exists) throw Exception('Publicación no encontrada');
    final pub = pubSnap.data() ?? <String, dynamic>{};
    final double minRd = ((pub['ofertaMinRd'] ?? 0) as num).toDouble();
    final double maxRd = ((pub['ofertaMaxRd'] ?? 0) as num).toDouble();
    if (minRd > 0 && maxRd > 0 && (montoRd < minRd || montoRd > maxRd)) {
      throw Exception(
        'Oferta fuera de rango. Debe estar entre RD\$${minRd.toStringAsFixed(0)} y RD\$${maxRd.toStringAsFixed(0)}.',
      );
    }

    await _ofertasCol(bolaId).add(<String, dynamic>{
      'fromUid': fromUid.trim(),
      'fromNombre': fromNombre.trim().isEmpty ? 'Usuario' : fromNombre.trim(),
      'fromRol': fromRol.trim().toLowerCase(),
      'montoRd': double.parse(montoRd.toStringAsFixed(2)),
      'mensaje': mensaje.trim(),
      'estado': 'pendiente',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // No actualizar el doc padre aquí: las reglas solo permiten merge al dueño/asignados;
    // un taxista ofertando no cumple eso y Firestore devolvía permission-denied.
  }

  /// Pedido publicado por el cliente: propone otro monto al conductor (quien ya envió una oferta).
  static Future<void> enviarContraofertaCliente({
    required String bolaId,
    required String clienteUid,
    required String clienteNombre,
    required String taxistaUid,
    String? respondiendoOfertaId,
    required double montoRd,
    String mensaje = '',
  }) async {
    if (bolaId.trim().isEmpty) throw Exception('Publicación inválida');
    if (clienteUid.trim().isEmpty) throw Exception('Sesión inválida');
    if (taxistaUid.trim().isEmpty) throw Exception('Conductor inválido');
    if (montoRd <= 0) throw Exception('Monto inválido');
    if (taxistaUid.trim() == clienteUid.trim()) {
      throw Exception('Contraoferta inválida.');
    }
    final pubSnap = await _col.doc(bolaId).get();
    if (!pubSnap.exists) throw Exception('Publicación no encontrada');
    final pub = pubSnap.data() ?? <String, dynamic>{};
    if ((pub['tipo'] ?? '').toString().trim().toLowerCase() != 'pedido') {
      throw Exception('Solo en pedidos del pasajero.');
    }
    if ((pub['createdByUid'] ?? '').toString() != clienteUid.trim()) {
      throw Exception('Solo quien publicó el pedido puede contraofertar.');
    }
    final double minRd = ((pub['ofertaMinRd'] ?? 0) as num).toDouble();
    final double maxRd = ((pub['ofertaMaxRd'] ?? 0) as num).toDouble();
    if (minRd > 0 && maxRd > 0 && (montoRd < minRd || montoRd > maxRd)) {
      throw Exception(
        'Monto fuera de rango. Entre RD\$${minRd.toStringAsFixed(0)} y RD\$${maxRd.toStringAsFixed(0)}.',
      );
    }

    await _ofertasCol(bolaId).add(<String, dynamic>{
      'fromUid': clienteUid.trim(),
      'fromNombre':
          clienteNombre.trim().isEmpty ? 'Pasajero' : clienteNombre.trim(),
      'fromRol': 'cliente',
      'montoRd': double.parse(montoRd.toStringAsFixed(2)),
      'mensaje': mensaje.trim(),
      'estado': 'pendiente',
      'esContraofertaCliente': true,
      'contraOfertaParaUid': taxistaUid.trim(),
      if (respondiendoOfertaId != null &&
          respondiendoOfertaId.trim().isNotEmpty)
        'respondiendoOfertaId': respondiendoOfertaId.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Conductor acepta el monto que propuso el pasajero (contraoferta).
  static Future<void> aceptarContraofertaClienteBola({
    required String bolaId,
    required String ofertaId,
  }) async {
    if (bolaId.trim().isEmpty || ofertaId.trim().isEmpty) {
      throw Exception('Datos inválidos');
    }
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('aceptarContraofertaClienteBola');
      await callable.call(<String, dynamic>{
        'bolaId': bolaId.trim(),
        'ofertaId': ofertaId.trim(),
      });
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) {
        throw Exception(msg);
      }
      throw Exception(e.code);
    }
  }

  /// Conductor no acepta la contraoferta; el pedido sigue abierto.
  static Future<void> rechazarContraofertaClienteBola({
    required String bolaId,
    required String ofertaId,
    String? motivo,
  }) async {
    if (bolaId.trim().isEmpty || ofertaId.trim().isEmpty) {
      throw Exception('Datos inválidos');
    }
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('rechazarContraofertaClienteBola');
      await callable.call(<String, dynamic>{
        'bolaId': bolaId.trim(),
        'ofertaId': ofertaId.trim(),
        if (motivo != null && motivo.trim().isNotEmpty) 'motivo': motivo.trim(),
      });
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) {
        throw Exception(msg);
      }
      throw Exception(e.code);
    }
  }

  /// Retirar una oferta o contraoferta propia pendiente.
  static Future<void> retirarMiOfertaPendiente({
    required String bolaId,
    required String ofertaId,
    required String uid,
  }) async {
    final ref = _ofertasCol(bolaId).doc(ofertaId.trim());
    final s = await ref.get();
    if (!s.exists) throw Exception('Oferta no encontrada');
    final m = s.data() ?? {};
    if ((m['fromUid'] ?? '').toString() != uid.trim()) {
      throw Exception('Solo podés retirar tus propias propuestas.');
    }
    if ((m['estado'] ?? '').toString() != 'pendiente') {
      throw Exception('Esta propuesta ya no está pendiente.');
    }
    await ref.update(<String, dynamic>{
      'estado': 'retirada',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Confirma el acuerdo vía Cloud Function (Admin SDK); el cliente no escribe el batch en Firestore.
  static Future<void> aceptarOferta({
    required String bolaId,
    required String ofertaId,
  }) async {
    if (bolaId.trim().isEmpty || ofertaId.trim().isEmpty) {
      throw Exception('Datos inválidos');
    }
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('aceptarOfertaBola');
      await callable.call(<String, dynamic>{
        'bolaId': bolaId.trim(),
        'ofertaId': ofertaId.trim(),
      });
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) {
        throw Exception(msg);
      }
      throw Exception(e.code);
    }
  }

  /// Dueño de la publicación descarta una propuesta pendiente (la bola sigue abierta; el ofertante puede reenviar).
  static Future<void> rechazarOfertaPublicador({
    required String bolaId,
    required String ofertaId,
  }) async {
    if (bolaId.trim().isEmpty || ofertaId.trim().isEmpty) {
      throw Exception('Datos inválidos');
    }
    final ref = _ofertasCol(bolaId).doc(ofertaId.trim());
    final s = await ref.get();
    if (!s.exists) throw Exception('Oferta no encontrada');
    final m = s.data() ?? {};
    if ((m['estado'] ?? '').toString() != 'pendiente') {
      throw Exception('Esta propuesta ya no está pendiente.');
    }
    await ref.update(<String, dynamic>{
      'estado': 'rechazada',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// ¿Se puede cancelar el acuerdo? (solo acordada, sin abordo ni PIN / en curso).
  static bool puedeCancelarAcuerdo(Map<String, dynamic> d) {
    final estado = (d['estado'] ?? '').toString().trim();
    if (estado != 'acordada') return false;
    if (d['pickupConfirmadoTaxista'] == true) return false;
    if (d['codigoVerificado'] == true) return false;
    return true;
  }

  /// Cliente o taxista: cancelar el acuerdo antes de confirmar abordo (sin viaje en curso).
  static Future<void> cancelarAcuerdoAntesDeAbordo({
    required String bolaId,
    required String uidActor,
  }) async {
    final ref = _col.doc(bolaId.trim());
    final s = await ref.get();
    if (!s.exists) throw Exception('Publicación no encontrada');
    final d = s.data() ?? <String, dynamic>{};
    if (!puedeCancelarAcuerdo(d)) {
      final estado = (d['estado'] ?? '').toString();
      if (estado == 'en_curso') {
        throw Exception(
            'El traslado ya va hacia el destino. No se puede cancelar.');
      }
      if (d['pickupConfirmadoTaxista'] == true) {
        throw Exception(
            'Ya se registró el abordo. No se puede cancelar.');
      }
      if (d['codigoVerificado'] == true) {
        throw Exception('El traslado ya fue iniciado.');
      }
      throw Exception(
          'Solo se puede cancelar un acuerdo pendiente de iniciar.');
    }
    final actor = uidActor.trim();
    final createdBy = (d['createdByUid'] ?? '').toString();
    final uidTx = (d['uidTaxista'] ?? '').toString();
    final uidCli = (d['uidCliente'] ?? '').toString();
    if (actor != createdBy && actor != uidTx && actor != uidCli) {
      throw Exception('No podés cancelar este acuerdo.');
    }

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('cancelarAcuerdoBolaPueblo');
      await callable.call(<String, dynamic>{'bolaId': bolaId.trim()});
      return;
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        debugPrint(
          '[BOLA_AHORRO] cancelarAcuerdo CF no disponible (${e.code}), fallback cliente',
        );
      } else {
        throw Exception(msg.isNotEmpty ? msg : e.code);
      }
    } catch (e) {
      debugPrint('[BOLA_AHORRO] cancelarAcuerdo CF error $e, fallback cliente');
    }

    await ref.set(<String, dynamic>{
      'estado': 'cancelada',
      'estadoViajeBola': 'cancelada',
      'canceladaEn': FieldValue.serverTimestamp(),
      'canceladaPor': actor,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final String viajeEspejoId = (d['viajeEspejoId'] ?? '').toString().trim();
    if (viajeEspejoId.isNotEmpty) {
      try {
        if (actor == uidTx) {
          await ViajesRepo.cancelarPorTaxista(
            viajeId: viajeEspejoId,
            uidTaxista: uidTx,
          );
        } else if (actor == uidCli) {
          await ViajesRepo.cancelarPorCliente(
            viajeId: viajeEspejoId,
            uidCliente: uidCli,
          );
        }
      } catch (e, st) {
        debugPrint(
          '[BOLA_AHORRO] cancelar espejo tras bola falló viaje=$viajeEspejoId $e $st',
        );
      }
    }
  }

  /// Taxista asignado: confirma en Firestore que el cliente ya subió (paso 2 del flujo).
  static Future<void> marcarPickupClienteAbordo({
    required String bolaId,
    required String uidTaxista,
  }) async {
    final ref = _col.doc(bolaId);
    final s = await ref.get();
    if (!s.exists) throw Exception('Publicación no encontrada');
    final d = s.data() ?? <String, dynamic>{};
    final String uidTx = (d['uidTaxista'] ?? '').toString();
    final String estado = (d['estado'] ?? '').toString();
    if (uidTx.isEmpty || uidTx != uidTaxista.trim()) {
      throw Exception('Solo el taxista asignado puede confirmar el abordo');
    }
    if (estado != 'acordada') {
      throw Exception(
          'Solo aplica mientras el acuerdo está pendiente de iniciar');
    }
    final String viajeEspejoId = (d['viajeEspejoId'] ?? '').toString().trim();
    debugPrint(
      '[BOLA_AHORRO] marcarPickupClienteAbordo bola=$bolaId espejo=$viajeEspejoId '
      'estadoBola=$estado uidTaxistaDoc=$uidTx callerUid=${uidTaxista.trim()}',
    );

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('confirmarPickupClienteAbordoBola');
      await callable.call(<String, dynamic>{'bolaId': bolaId.trim()});
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) {
        throw Exception(msg);
      }
      throw Exception(e.code);
    }

    if (viajeEspejoId.isNotEmpty) {
      try {
        final vs = await _db.collection('viajes').doc(viajeEspejoId).get();
        final vd = vs.data();
        debugPrint(
          '[BOLA_AHORRO] viaje espejo antes sync: existe=${vs.exists} '
          'estado=${vd?['estado']} uidTaxistaViaje=${vd?['uidTaxista']}',
        );
      } catch (e, st) {
        debugPrint('[BOLA_AHORRO] lectura espejo para log falló: $e $st');
      }
      try {
        await ViajesRepo.marcarEnCaminoPickup(
          viajeId: viajeEspejoId,
          uidTaxista: uidTaxista.trim(),
        );
      } catch (e, st) {
        debugPrint(
          '[BOLA_AHORRO] marcarEnCaminoPickup espejo (ignorado si ya avanzó): $e $st',
        );
      }
      try {
        await ViajesRepo.marcarClienteAbordo(
          viajeId: viajeEspejoId,
          uidTaxista: uidTaxista.trim(),
        );
      } catch (e, st) {
        debugPrint(
          '[BOLA_AHORRO] marcarClienteAbordo espejo (ignorado si ya a bordo): $e $st',
        );
      }
    }
  }

  /// Tras abrir navegación al pickup: alinea `en_camino_pickup` en el viaje espejo si aplica.
  static Future<void> syncViajeEspejoCaminoPickupSiAplica({
    required String bolaId,
    required String uidTaxista,
  }) async {
    final ref = _col.doc(bolaId.trim());
    final s = await ref.get();
    if (!s.exists) return;
    final d = s.data() ?? <String, dynamic>{};
    final String viajeEspejoId = (d['viajeEspejoId'] ?? '').toString().trim();
    if (viajeEspejoId.isEmpty) return;
    try {
      await ViajesRepo.marcarEnCaminoPickup(
        viajeId: viajeEspejoId,
        uidTaxista: uidTaxista.trim(),
      );
    } catch (e) {
      debugPrint(
        '[BOLA_AHORRO] syncViajeEspejoCaminoPickupSiAplica (ignorado): $e',
      );
    }
  }

  static Future<void> marcarEnCurso({
    required String bolaId,
    required String uidActor,
    required String codigoIngresado,
  }) async {
    final ref = _col.doc(bolaId);
    final s = await ref.get();
    if (!s.exists) throw Exception('Publicación no encontrada');
    final d = s.data() ?? <String, dynamic>{};
    final String uidTx = (d['uidTaxista'] ?? '').toString();
    final String estado = (d['estado'] ?? '').toString();
    final String codigo = (d['codigoVerificacionBola'] ?? '').toString().trim();
    final Timestamp? codigoTs = d['codigoGeneradoEn'] as Timestamp?;
    final enteredDigits =
        codigoIngresado.replaceAll(RegExp(r'\D'), '');
    final codigoDigits = codigo.replaceAll(RegExp(r'\D'), '');
    if (uidTx.isEmpty) throw Exception('No hay taxista definido en el acuerdo');
    if (uidTx != uidActor.trim()) {
      throw Exception('Solo el taxista puede iniciar');
    }
    if (estado != 'acordada') {
      throw Exception('Solo se puede iniciar desde acordada');
    }
    // Bolas nuevas guardan `pickupConfirmadoTaxista` al acordar; las antiguas no tienen la clave.
    if (d.containsKey('pickupConfirmadoTaxista') &&
        d['pickupConfirmadoTaxista'] != true) {
      throw Exception(
          'Primero confirma en la app que el cliente está a bordo (paso 2).');
    }
    if (codigo.isEmpty) throw Exception('Código de verificación no disponible');
    if (codigoTs == null) {
      throw Exception('Código inválido. Reacuerda la bola.');
    }
    final DateTime venceEn = codigoTs.toDate().add(vigenciaCodigoInicio);
    if (DateTime.now().isAfter(venceEn)) {
      throw Exception(
          'Código vencido. Reacuerda la bola para generar uno nuevo.');
    }
    if (enteredDigits.isEmpty || enteredDigits != codigoDigits) {
      throw Exception('Código incorrecto. Pide el código al cliente.');
    }

    final String viajeEspejoId = (d['viajeEspejoId'] ?? '').toString().trim();
    if (viajeEspejoId.isNotEmpty) {
      await ViajesRepo.iniciarViaje(
        viajeId: viajeEspejoId,
        uidTaxista: uidActor.trim(),
        pinVerificacion: enteredDigits,
      );
    }

    await ref.set(<String, dynamic>{
      'estado': 'en_curso',
      'estadoViajeBola': 'en_curso',
      'codigoVerificado': true,
      'codigoVerificadoEn': FieldValue.serverTimestamp(),
      'confirmacionTaxistaFinal': false,
      'confirmacionClienteFinal': false,
      'confirmacionTaxistaFinalEn': FieldValue.delete(),
      'confirmacionClienteFinalEn': FieldValue.delete(),
      'comisionAplicada': false,
      'inicioEn': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Cliente o taxista asignados: define cómo se pagará la bola al finalizar.
  /// Usa Cloud Function para evitar permission-denied por reglas de diff en Firestore.
  static Future<void> actualizarMetodoPagoBola({
    required String bolaId,
    required String uidActor,
    required String metodoPago,
  }) async {
    final String m = metodoPago.trim().toLowerCase();
    if (!metodosPagoBola.contains(m)) {
      throw Exception('Método de pago inválido');
    }
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (authUid.isEmpty || authUid != uidActor.trim()) {
      throw Exception('Sesión inválida para cambiar el pago');
    }
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('actualizarMetodoPagoBola');
      await callable.call(<String, dynamic>{
        'bolaId': bolaId.trim(),
        'metodoPago': m,
      });
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) throw Exception(msg);
      throw Exception(e.code);
    }
  }

  /// Cliente: reporta comprobante de transferencia tras cierre (CF servidor).
  static Future<void> reportarTransferenciaCliente({
    required String bolaId,
    required String comprobanteUrl,
  }) async {
    if (bolaId.trim().isEmpty || comprobanteUrl.trim().isEmpty) {
      throw Exception('Datos inválidos');
    }
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('reportarTransferenciaBolaClienteSeguro');
      await callable.call(<String, dynamic>{
        'bolaId': bolaId.trim(),
        'comprobanteUrl': comprobanteUrl.trim(),
      });
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) throw Exception(msg);
      throw Exception(e.code);
    }
  }

  /// Taxista: confirma que recibió la transferencia del pasajero.
  static Future<void> confirmarTransferenciaPorTaxista({
    required String bolaId,
  }) async {
    if (bolaId.trim().isEmpty) throw Exception('Publicación inválida');
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('confirmarTransferenciaBolaTaxistaSeguro');
      await callable.call(<String, dynamic>{'bolaId': bolaId.trim()});
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) throw Exception(msg);
      throw Exception(e.code);
    }
  }

  /// Confirmación de llegada: solo [Cloud Function finalizarBolaPueblo] (reglas bloquean cierre en cliente).
  static Future<void> confirmarFinalizacion({
    required String bolaId,
    required String uidActor,
  }) async {
    if (bolaId.trim().isEmpty) throw Exception('Publicación inválida');
    uidActor.trim(); // auth en servidor
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('finalizarBolaPueblo');
      await callable.call(<String, dynamic>{'bolaId': bolaId.trim()});
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) throw Exception(msg);
      throw Exception(e.code);
    }
  }

  static CollectionReference<Map<String, dynamic>> _mensajesBolaCol(
          String bolaId) =>
      _col.doc(bolaId).collection('mensajes_bola');

  /// Chat entre cliente y taxista asignados (no usa colección global `chats/` ligada a viajes).
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamMensajesBola(
      String bolaId) {
    return _mensajesBolaCol(bolaId)
        .orderBy('ts', descending: true)
        .limit(120)
        .snapshots();
  }

  static Future<void> enviarMensajeBola({
    required String bolaId,
    required String deUid,
    required String texto,
  }) async {
    final t = texto.trim();
    if (bolaId.trim().isEmpty || deUid.trim().isEmpty || t.isEmpty) return;
    if (t.length > 4000) {
      throw Exception('Mensaje demasiado largo (máx. 4000 caracteres).');
    }
    await _mensajesBolaCol(bolaId).add(<String, dynamic>{
      'de': deUid.trim(),
      'texto': t,
      'ts': FieldValue.serverTimestamp(),
    });
  }
}
