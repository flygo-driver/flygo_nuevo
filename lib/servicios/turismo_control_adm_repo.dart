import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/servicios/asignacion_turismo_repo.dart';

/// Mensajes cliente → operaciones turismo ADM y consultas del radar en vivo.
class TurismoControlAdmRepo {
  TurismoControlAdmRepo._();

  static const String coleccionMensajes = 'turismo_mensajes_adm';
  static const int maxMensajeChars = 500;

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Pedidos turismo recientes (tiempo real). ADM lee todo; filtrar en UI.
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamViajesTurismo({
    int limit = 150,
  }) {
    return _db
        .collection('viajes')
        .where('tipoServicio', isEqualTo: 'turismo')
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamMensajesRecientes({
    int limit = 80,
    bool soloNoLeidos = false,
  }) {
    Query<Map<String, dynamic>> q =
        _db.collection(coleccionMensajes).orderBy('createdAt', descending: true);
    if (soloNoLeidos) {
      q = q.where('leidoPorAdm', isEqualTo: false);
    }
    return q.limit(limit).snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamMensajesViaje(
    String viajeId,
  ) {
    return _db
        .collection(coleccionMensajes)
        .where('viajeId', isEqualTo: viajeId.trim())
        .orderBy('createdAt', descending: false)
        .limit(40)
        .snapshots();
  }

  /// Cliente: historial de sus mensajes a operaciones en este viaje.
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

  static Stream<int> streamConteoMensajesNoLeidos() {
    return _db
        .collection(coleccionMensajes)
        .where('leidoPorAdm', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// Cliente autenticado: escribe a operaciones turismo (sin tocar flujo del viaje).
  static Future<void> enviarMensajeCliente({
    required String viajeId,
    required String mensaje,
    String origenPantalla = 'espera_asignacion',
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
    if ((v['tipoServicio'] ?? '').toString() != 'turismo') {
      throw StateError('Este viaje no es de turismo.');
    }

    final String uidCliente =
        (v['uidCliente'] ?? v['clienteId'] ?? '').toString().trim();
    if (uidCliente != user.uid) {
      throw StateError('No puedes enviar mensajes en este viaje.');
    }

    final String origen = (v['origen'] ?? '').toString();
    final String destino = (v['destino'] ?? '').toString();
    final String ruta = origen.isNotEmpty || destino.isNotEmpty
        ? '$origen → $destino'
        : 'Viaje turismo';

    String clienteNombre = (v['nombreCliente'] ?? '').toString().trim();
    if (clienteNombre.isEmpty) {
      final uSnap = await _db.collection('usuarios').doc(user.uid).get();
      clienteNombre = (uSnap.data()?['nombre'] ?? user.displayName ?? '')
          .toString()
          .trim();
    }

    await _db.collection(coleccionMensajes).add(<String, dynamic>{
      'viajeId': id,
      'uidCliente': user.uid,
      'clienteNombre': clienteNombre,
      'mensaje': texto,
      'ruta': ruta,
      'subtipoTurismo':
          (v['subtipoTurismo'] ?? '').toString().trim(),
      'vehiculoRequerido': AsignacionTurismoRepo
          .etiquetaVehiculoRequeridoDesdeViaje(v),
      'canalAsignacion': (v['canalAsignacion'] ?? 'admin').toString(),
      'origenPantalla': origenPantalla,
      'leidoPorAdm': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> marcarMensajeLeido(String mensajeId) async {
    if (mensajeId.trim().isEmpty) return;
    await _db.collection(coleccionMensajes).doc(mensajeId.trim()).update(
      <String, dynamic>{
        'leidoPorAdm': true,
        'leidoEn': FieldValue.serverTimestamp(),
      },
    );
  }

  static Future<void> marcarMensajesViajeLeidos(String viajeId) async {
    final String id = viajeId.trim();
    if (id.isEmpty) return;
    final QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection(coleccionMensajes)
        .where('viajeId', isEqualTo: id)
        .where('leidoPorAdm', isEqualTo: false)
        .limit(30)
        .get();
    if (snap.docs.isEmpty) return;
    final WriteBatch batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, <String, dynamic>{
        'leidoPorAdm': true,
        'leidoEn': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
