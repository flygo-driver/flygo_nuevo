import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/servicios/viajes_repo.dart';

/// Mensajes cliente → operaciones RAI durante espera de conductor (panel admin).
class OperacionesMensajesAdmRepo {
  OperacionesMensajesAdmRepo._();

  static const String coleccionMensajes = 'operaciones_mensajes_adm';
  static const int maxMensajeChars = 500;
  static const int maxRespuestaChars = 700;

  /// Espera mínima entre mensajes del mismo cliente en un viaje.
  static const Duration esperaEntreMensajes = Duration(seconds: 30);

  /// Tope de mensajes por viaje: evita que un hilo se vuelva un buzón infinito.
  static const int maxMensajesPorViaje = 12;

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamMensajesClienteViaje(
    String viajeId,
  ) {
    final User? user = FirebaseAuth.instance.currentUser;
    final String uid = user?.uid.trim() ?? '';
    if (uid.isEmpty) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
    return _db
        .collection(coleccionMensajes)
        .where('viajeId', isEqualTo: viajeId.trim())
        .where('uidCliente', isEqualTo: uid)
        .orderBy('createdAt', descending: false)
        .limit(20)
        .snapshots();
  }

  static String tipoServicioParaAdm(Map<String, dynamic> viaje) {
    final String explicit =
        (viaje['tipoServicio'] ?? '').toString().trim().toLowerCase();
    if (explicit.isNotEmpty && explicit != 'normal') return explicit;
    final String tv = (viaje['tipoVehiculo'] ??
            viaje['tipoVehiculoOriginal'] ??
            '')
        .toString()
        .toLowerCase();
    if (tv.contains('motor') || tv.contains('🛵')) return 'motor';
    return explicit.isEmpty ? 'normal' : explicit;
  }

  /// Cliente autenticado: escribe a operaciones (sin alterar el flujo del viaje).
  static Future<void> enviarMensajeCliente({
    required String viajeId,
    required String mensaje,
    String origenPantalla = 'espera_conductor',
  }) async {
    try {
      await _enviarMensajeClienteDirecto(
        viajeId: viajeId,
        mensaje: mensaje,
        origenPantalla: origenPantalla,
      );
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      await _enviarMensajeClienteCallable(
        viajeId: viajeId,
        mensaje: mensaje,
        origenPantalla: origenPantalla,
      );
    }
  }

  static Future<void> _enviarMensajeClienteDirecto({
    required String viajeId,
    required String mensaje,
    String origenPantalla = 'espera_conductor',
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Inicia sesión para enviar el mensaje.');

    final String texto = mensaje.trim();
    if (texto.isEmpty) throw ArgumentError('Escribe un mensaje.');
    if (texto.length > maxMensajeChars) {
      throw ArgumentError('Máximo $maxMensajeChars caracteres.');
    }

    final String id = viajeId.trim();
    if (id.isEmpty) throw ArgumentError('Viaje inválido.');

    final DocumentSnapshot<Map<String, dynamic>> vSnap =
        await _db.collection('viajes').doc(id).get();
    if (!vSnap.exists) throw StateError('El viaje ya no existe.');

    final Map<String, dynamic> v = vSnap.data() ?? <String, dynamic>{};
    final String uidCliente = ViajesRepo.uidClienteDesdeDocViaje(v);
    if (uidCliente != user.uid) {
      throw StateError('No puedes enviar mensajes en este viaje.');
    }

    final String origen = (v['origen'] ?? '').toString();
    final String destino = (v['destino'] ?? '').toString();
    final String ruta = origen.isNotEmpty || destino.isNotEmpty
        ? '$origen → $destino'
        : 'Viaje RAI';

    String clienteNombre = (v['nombreCliente'] ?? '').toString().trim();
    if (clienteNombre.isEmpty) {
      final uSnap = await _db.collection('usuarios').doc(user.uid).get();
      clienteNombre = (uSnap.data()?['nombre'] ?? user.displayName ?? '')
          .toString()
          .trim();
    }

    await _verificarRitmoEnvio(viajeId: id, uidCliente: user.uid);

    await _db.collection(coleccionMensajes).add(<String, dynamic>{
      'viajeId': id,
      'uidCliente': user.uid,
      'clienteNombre': clienteNombre,
      'mensaje': texto,
      'ruta': ruta,
      'tipoServicio': tipoServicioParaAdm(v),
      'origenPantalla': origenPantalla,
      'leidoPorAdm': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Respaldo servidor (Admin SDK) si Firestore rules aún no están en prod.
  static Future<void> _enviarMensajeClienteCallable({
    required String viajeId,
    required String mensaje,
    String origenPantalla = 'espera_conductor',
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('enviarMensajeOperacionesAdm');
    try {
      await callable.call(<String, dynamic>{
        'viajeId': viajeId.trim(),
        'mensaje': mensaje.trim(),
        'origenPantalla': origenPantalla,
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') {
        throw StateError(
          'El servicio de mensajes a operaciones no está activo. '
          'Actualiza la app o intenta en unos minutos.',
        );
      }
      final String msg = (e.message ?? '').trim();
      if (e.code == 'failed-precondition' && msg.isNotEmpty) {
        throw StateError(msg);
      }
      if (e.code == 'unauthenticated') {
        throw StateError('Inicia sesión para enviar el mensaje.');
      }
      if (e.code == 'permission-denied') {
        throw StateError('No puedes enviar mensajes en este viaje.');
      }
      rethrow;
    }
  }

  /// Cada mensaje despierta a todo el equipo de operaciones (push + correo),
  /// así que el hilo tiene freno de mano.
  static Future<void> _verificarRitmoEnvio({
    required String viajeId,
    required String uidCliente,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> previos = await _db
        .collection(coleccionMensajes)
        .where('viajeId', isEqualTo: viajeId)
        .where('uidCliente', isEqualTo: uidCliente)
        .orderBy('createdAt', descending: true)
        .limit(maxMensajesPorViaje)
        .get();

    if (previos.docs.length >= maxMensajesPorViaje) {
      throw StateError(
        'Ya enviaste varios mensajes en este viaje. '
        'Operaciones los está viendo; espera la respuesta.',
      );
    }

    if (previos.docs.isEmpty) return;
    final dynamic ts = previos.docs.first.data()['createdAt'];
    if (ts is! Timestamp) return;
    final Duration desde = DateTime.now().difference(ts.toDate());
    if (desde < esperaEntreMensajes) {
      final int faltan = (esperaEntreMensajes - desde).inSeconds + 1;
      throw StateError('Espera $faltan segundos para enviar otro mensaje.');
    }
  }

  // ==============================================================
  //                            ADMIN
  // ==============================================================

  /// Bandeja de operaciones. [soloSinResponder] deja arriba lo pendiente.
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamMensajesAdmin({
    int limite = 100,
  }) {
    return _db
        .collection(coleccionMensajes)
        .orderBy('createdAt', descending: true)
        .limit(limite)
        .snapshots();
  }

  static Future<void> marcarLeidoPorAdm(String mensajeId) async {
    final String id = mensajeId.trim();
    if (id.isEmpty) return;
    await _db.collection(coleccionMensajes).doc(id).update(<String, dynamic>{
      'leidoPorAdm': true,
      'leidoEn': FieldValue.serverTimestamp(),
    });
  }

  /// Respuesta de operaciones al cliente (dispara aviso push desde backend).
  static Future<void> responderComoAdm({
    required String mensajeId,
    required String respuesta,
    String? nombreAdmin,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Inicia sesión como administrador.');

    final String id = mensajeId.trim();
    if (id.isEmpty) throw ArgumentError('Mensaje inválido.');

    final String texto = respuesta.trim();
    if (texto.isEmpty) throw ArgumentError('Escribe una respuesta.');
    if (texto.length > maxRespuestaChars) {
      throw ArgumentError('Máximo $maxRespuestaChars caracteres.');
    }

    await _db.collection(coleccionMensajes).doc(id).update(<String, dynamic>{
      'respuesta': texto,
      'respuestaEn': FieldValue.serverTimestamp(),
      'respondidoPor': user.uid,
      'respondidoPorNombre':
          (nombreAdmin ?? user.displayName ?? 'Operaciones RAI').trim(),
      'leidoPorAdm': true,
      'leidoEn': FieldValue.serverTimestamp(),
    });
  }
}
