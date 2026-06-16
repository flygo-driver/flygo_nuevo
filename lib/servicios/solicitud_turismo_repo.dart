// lib/servicios/solicitud_turismo_repo.dart
//
// Solicitud de chofer turismo: taxista → solicitudes_turismo → ADM aprueba → choferes_turismo.

import 'dart:io';
import 'dart:typed_data';

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flygo_nuevo/modelo/vehiculo_turismo.dart';

class EstadoRegistroTurismo {
  const EstadoRegistroTurismo({
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

class SolicitudTurismoRepo {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  static const Map<String, String> _labelsTipo = <String, String>{
    'carro': 'Carro Turismo',
    'jeepeta': 'Jeepeta Turismo',
    'minivan': 'Minivan Turismo',
    'bus': 'Bus Turismo',
  };

  static int capacidadPorTipo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'jeepeta':
        return 6;
      case 'minivan':
        return 8;
      case 'bus':
        return 25;
      case 'carro':
      default:
        return 4;
    }
  }

  static List<Map<String, dynamic>> vehiculosParaFirestore(
    List<VehiculoTurismo> vehiculos,
  ) {
    return vehiculos.map((VehiculoTurismo v) {
      final Map<String, dynamic> m = Map<String, dynamic>.from(v.toMap());
      m['tipoLabel'] = _labelsTipo[v.tipo] ?? v.tipoLabel;
      m['capacidad'] = capacidadPorTipo(v.tipo);
      return m;
    }).toList();
  }

  static Future<String> _subirImagen({
    required String uid,
    required String nombre,
    required Uint8List bytes,
  }) async {
    if (bytes.length > 10 * 1024 * 1024) {
      throw Exception('El archivo excede 10 MB');
    }
    final int ts = DateTime.now().millisecondsSinceEpoch;
    final String path = 'taxistas/$uid/documentos/turismo/${nombre}_$ts.jpg';
    final Reference ref = _storage.ref(path);
    await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg', customMetadata: {'uid': uid}),
    );
    return ref.getDownloadURL();
  }

  static Future<String> subirBytesDocumento({
    required String uid,
    required String tipo,
    required Uint8List bytes,
  }) async {
    return _subirImagen(uid: uid, nombre: tipo, bytes: bytes);
  }

  static Future<String> subirArchivoDocumento({
    required String uid,
    required String tipo,
    required File file,
  }) async {
    if (!await file.exists()) {
      throw Exception(
        'El archivo ya no está disponible. Vuelve a seleccionar la foto.',
      );
    }
    final Uint8List bytes = await file.readAsBytes();
    return subirBytesDocumento(uid: uid, tipo: tipo, bytes: bytes);
  }

  /// Sincroniza `choferes_turismo.disponible` con el toggle general del taxista.
  static Future<void> sincronizarDisponibilidadChofer({
    required String uid,
    required bool disponible,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref =
        _db.collection('choferes_turismo').doc(uid);
    final DocumentSnapshot<Map<String, dynamic>> snap = await ref.get();
    if (!snap.exists) return;
    final Map<String, dynamic>? d = snap.data();
    if (d == null) return;
    final String est = (d['estado'] ?? '').toString().trim().toLowerCase();
    if (est != 'aprobado' && est != 'activo') return;
    if ((d['viajeActualId'] ?? '').toString().trim().isNotEmpty) return;
    await ref.set(
      {
        'disponible': disponible,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Publica ubicación en la red turística (auto-asignación ADM).
  static Future<void> sincronizarUbicacionChofer({
    required String uid,
    required double lat,
    required double lon,
  }) async {
    await _db.collection('choferes_turismo').doc(uid).set(
      {
        'ultimaUbicacion': GeoPoint(lat, lon),
        'ultimaUbicacionActualizada': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<bool> esChoferTurismoAprobado(String uid) async {
    final DocumentSnapshot<Map<String, dynamic>> snap =
        await _db.collection('choferes_turismo').doc(uid).get();
    if (!snap.exists) return false;
    final String est =
        (snap.data()?['estado'] ?? '').toString().trim().toLowerCase();
    return est == 'aprobado' || est == 'activo';
  }

  static Future<EstadoRegistroTurismo> estadoRegistro(String uid) async {
    final DocumentSnapshot<Map<String, dynamic>> choferSnap =
        await _db.collection('choferes_turismo').doc(uid).get();
    if (choferSnap.exists) {
      final String est = (choferSnap.data()?['estado'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (est == 'aprobado' || est == 'activo') {
        return const EstadoRegistroTurismo(
          fase: 'aprobado',
          choferAprobado: true,
        );
      }
    }

    final QuerySnapshot<Map<String, dynamic>> pend = await _db
        .collection('solicitudes_turismo')
        .where('uidChofer', isEqualTo: uid)
        .where('estado', isEqualTo: 'pendiente')
        .limit(1)
        .get();
    if (pend.docs.isNotEmpty) {
      return EstadoRegistroTurismo(
        fase: 'pendiente_adm',
        solicitudId: pend.docs.first.id,
      );
    }

    final QuerySnapshot<Map<String, dynamic>> rechazadas = await _db
        .collection('solicitudes_turismo')
        .where('uidChofer', isEqualTo: uid)
        .where('estado', isEqualTo: 'rechazado')
        .limit(10)
        .get();
    if (rechazadas.docs.isNotEmpty) {
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> sorted =
          List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
              rechazadas.docs);
      sorted.sort((a, b) {
        final Timestamp? ta = a.data()['fechaSolicitud'] as Timestamp?;
        final Timestamp? tb = b.data()['fechaSolicitud'] as Timestamp?;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
      final Map<String, dynamic> d = sorted.first.data();
      return EstadoRegistroTurismo(
        fase: 'rechazado',
        solicitudId: sorted.first.id,
        motivoRechazo: (d['motivoRechazo'] ?? '').toString().trim(),
      );
    }

    return const EstadoRegistroTurismo(fase: 'sin_solicitud');
  }

  static Stream<EstadoRegistroTurismo> streamEstadoRegistro(String uid) {
    final StreamController<EstadoRegistroTurismo> controller =
        StreamController<EstadoRegistroTurismo>.broadcast();
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? choferSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? solSub;

    Future<void> emit() async {
      if (controller.isClosed) return;
      controller.add(await estadoRegistro(uid));
    }

    controller.onListen = () {
      unawaited(emit());
      choferSub = _db
          .collection('choferes_turismo')
          .doc(uid)
          .snapshots()
          .listen((_) => unawaited(emit()), onError: (_) {});
      solSub = _db
          .collection('solicitudes_turismo')
          .where('uidChofer', isEqualTo: uid)
          .snapshots()
          .listen((_) => unawaited(emit()), onError: (_) {});
    };
    controller.onCancel = () async {
      await choferSub?.cancel();
      await solSub?.cancel();
      if (!controller.isClosed) {
        await controller.close();
      }
    };
    return controller.stream;
  }

  static Future<void> enviarSolicitud({
    required String nombre,
    required String email,
    required String telefono,
    required List<VehiculoTurismo> vehiculos,
    required Map<String, String> documentosUrls,
    String notas = '',
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('No hay sesión activa');

    await user.getIdToken(true);

    final EstadoRegistroTurismo estado = await estadoRegistro(user.uid);
    if (estado.fase == 'aprobado') {
      throw Exception('Tu cuenta ya está aprobada como chofer de turismo.');
    }
    if (estado.fase == 'pendiente_adm') {
      throw Exception(
        'Ya tienes una solicitud en revisión. El administrador la verá en «Aprobar Solicitudes».',
      );
    }
    if (vehiculos.isEmpty) {
      throw Exception('Agrega al menos un vehículo turístico.');
    }

    final List<Map<String, dynamic>> vehiculosMaps =
        vehiculosParaFirestore(vehiculos);

    await _db.collection('solicitudes_turismo').add({
      'uidChofer': user.uid,
      'nombre': nombre.trim(),
      'email': email.trim(),
      'telefono': telefono.trim(),
      'vehiculos': vehiculosMaps,
      'vehiculosSolicitados': vehiculos.map((VehiculoTurismo v) => v.tipo).toList(),
      'documentos': documentosUrls,
      'notas': notas.trim(),
      'estado': 'pendiente',
      'fechaSolicitud': FieldValue.serverTimestamp(),
    });
  }
}
