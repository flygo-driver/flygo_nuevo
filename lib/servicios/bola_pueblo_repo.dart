import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

class BolaPuebloRepo {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('bolas_pueblo');
  static const double comisionPct = 0.10; // 10% RAI por bola acordada.
  static const Duration vigenciaCodigoInicio = Duration(minutes: 20);
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

  static Future<void> crearPublicacion({
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
    // Viaje espejo en `viajes` (pool) para que el conductor abra detalle y oferte enlazado a esta bola.
    if (t == 'pedido' && coordsOk) {
      try {
        await ViajesRepo.crearViajePendiente(
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
        );
      } catch (_) {
        // La publicación en bolas_pueblo queda; el espejo es opcional si falla validación de viaje.
      }
    }
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

  /// Cliente o taxista: cancelar el acuerdo antes de confirmar abordo (sin viaje en curso).
  static Future<void> cancelarAcuerdoAntesDeAbordo({
    required String bolaId,
    required String uidActor,
  }) async {
    final ref = _col.doc(bolaId.trim());
    final s = await ref.get();
    if (!s.exists) throw Exception('Publicación no encontrada');
    final d = s.data() ?? <String, dynamic>{};
    final actor = uidActor.trim();
    final createdBy = (d['createdByUid'] ?? '').toString();
    final uidTx = (d['uidTaxista'] ?? '').toString();
    final uidCli = (d['uidCliente'] ?? '').toString();
    final estado = (d['estado'] ?? '').toString();
    if (estado != 'acordada') {
      throw Exception(
          'Solo se puede cancelar un acuerdo pendiente de iniciar.');
    }
    if (d['pickupConfirmadoTaxista'] == true) {
      throw Exception(
          'Ya se registró el abordo. No se puede cancelar desde aquí.');
    }
    if (d['codigoVerificado'] == true) {
      throw Exception('El traslado ya fue iniciado.');
    }
    if (actor != createdBy && actor != uidTx && actor != uidCli) {
      throw Exception('No podés cancelar este acuerdo.');
    }
    await ref.set(<String, dynamic>{
      'estado': 'cancelada',
      'estadoViajeBola': 'cancelada',
      'canceladaEn': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
    await ref.set(<String, dynamic>{
      'pickupConfirmadoTaxista': true,
      'pickupConfirmadoTaxistaEn': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
    final entered = codigoIngresado.trim();
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
    if (entered.isEmpty || entered != codigo) {
      throw Exception('Código incorrecto. Pide el código al cliente.');
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
