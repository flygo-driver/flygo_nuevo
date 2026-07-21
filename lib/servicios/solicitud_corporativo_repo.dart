// Solicitud chofer corporativo: taxista → solicitudes_corporativo → ADM aprueba → choferes_corporativos.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EstadoRegistroCorporativo {
  const EstadoRegistroCorporativo({
    required this.fase,
    this.solicitudId,
    this.motivoRechazo,
    this.choferAprobado = false,
  });

  /// `sin_solicitud` | `pendiente_adm` | `rechazado` | `aprobado`
  final String fase;
  final String? solicitudId;
  final String? motivoRechazo;
  final bool choferAprobado;
}

abstract final class SolicitudCorporativoRepo {
  SolicitudCorporativoRepo._();

  static final _db = FirebaseFirestore.instance;

  static Future<bool> esChoferCorporativoAprobado(String uid) async {
    final snap = await _db.collection('choferes_corporativos').doc(uid).get();
    if (!snap.exists) return false;
    final est = (snap.data()?['estado'] ?? '').toString().trim().toLowerCase();
    if (est != 'aprobado' && est != 'activo') return false;
    return snap.data()?['activo'] != false;
  }

  static Future<EstadoRegistroCorporativo> estadoRegistro(String uid) async {
    final choferSnap = await _db.collection('choferes_corporativos').doc(uid).get();
    if (choferSnap.exists) {
      final est = (choferSnap.data()?['estado'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (est == 'aprobado' || est == 'activo') {
        if (choferSnap.data()?['activo'] != false) {
          return const EstadoRegistroCorporativo(
            fase: 'aprobado',
            choferAprobado: true,
          );
        }
      }
    }

    final pend = await _db
        .collection('solicitudes_corporativo')
        .where('uidChofer', isEqualTo: uid)
        .where('estado', isEqualTo: 'pendiente')
        .limit(1)
        .get();
    if (pend.docs.isNotEmpty) {
      return EstadoRegistroCorporativo(
        fase: 'pendiente_adm',
        solicitudId: pend.docs.first.id,
      );
    }

    final rechazadas = await _db
        .collection('solicitudes_corporativo')
        .where('uidChofer', isEqualTo: uid)
        .where('estado', isEqualTo: 'rechazado')
        .limit(5)
        .get();
    if (rechazadas.docs.isNotEmpty) {
      final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
        rechazadas.docs,
      )..sort((a, b) {
          final ta = a.data()['fechaSolicitud'] as Timestamp?;
          final tb = b.data()['fechaSolicitud'] as Timestamp?;
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });
      return EstadoRegistroCorporativo(
        fase: 'rechazado',
        solicitudId: sorted.first.id,
        motivoRechazo: (sorted.first.data()['motivoRechazo'] ?? '').toString(),
      );
    }

    return const EstadoRegistroCorporativo(fase: 'sin_solicitud');
  }

  static Stream<EstadoRegistroCorporativo> streamEstadoRegistro(String uid) {
    final controller = StreamController<EstadoRegistroCorporativo>.broadcast();
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? choferSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? solSub;

    Future<void> emit() async {
      if (controller.isClosed) return;
      controller.add(await estadoRegistro(uid));
    }

    choferSub = _db.collection('choferes_corporativos').doc(uid).snapshots().listen(
      (_) => emit(),
      onError: (_) {},
    );
    solSub = _db
        .collection('solicitudes_corporativo')
        .where('uidChofer', isEqualTo: uid)
        .snapshots()
        .listen((_) => emit(), onError: (_) {});

    emit();
    controller.onCancel = () async {
      await choferSub?.cancel();
      await solSub?.cancel();
      if (!controller.isClosed) await controller.close();
    };
    return controller.stream;
  }

  static Future<void> enviarSolicitud({
    String nota = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Inicia sesión como taxista');

    final uid = user.uid;
    final estado = await estadoRegistro(uid);
    if (estado.fase == 'aprobado') {
      throw Exception('Ya estás habilitado como chofer corporativo');
    }
    if (estado.fase == 'pendiente_adm') {
      throw Exception('Tu solicitud ya está en revisión');
    }

    final uSnap = await _db.collection('usuarios').doc(uid).get();
    final u = uSnap.data() ?? {};
    final rol = (u['rol'] ?? '').toString().toLowerCase();
    if (rol != 'taxista' && rol != 'driver') {
      throw Exception('Solo taxistas RAI pueden solicitar corporativo');
    }

    await _db.collection('solicitudes_corporativo').add({
      'uidChofer': uid,
      'nombre': (u['nombre'] ?? u['displayName'] ?? user.displayName ?? '').toString(),
      'email': (u['email'] ?? user.email ?? '').toString(),
      'telefono': (u['telefono'] ?? '').toString(),
      'cedula': (u['ciTaxista'] ?? u['cedula'] ?? u['cedulaTaxista'] ?? '').toString(),
      'placa': (u['placa'] ?? '').toString(),
      'marca': (u['vehiculoMarca'] ?? u['marca'] ?? '').toString(),
      'modelo': (u['vehiculoModelo'] ?? u['modelo'] ?? '').toString(),
      'color': (u['vehiculoColor'] ?? u['color'] ?? '').toString(),
      'notaChofer': nota.trim(),
      'estado': 'pendiente',
      'fechaSolicitud': FieldValue.serverTimestamp(),
      'creadoEn': FieldValue.serverTimestamp(),
    });
  }
}
