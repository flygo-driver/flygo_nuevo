import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/servicios/notification_service.dart';

class DisponibilidadService {
  static const Duration tiempoMaximo = Duration(hours: 12);

  static Future<void> verificar(String uid) async {
    final doc =
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();

    final data = doc.data() ?? <String, dynamic>{};
    final bool disponible = (data['disponible'] == true);

    DateTime? ultimaActivacion;
    final dynamic rawUltima = data['ultimaActivacion'];
    if (rawUltima is Timestamp) {
      ultimaActivacion = rawUltima.toDate();
    } else if (rawUltima is DateTime) {
      ultimaActivacion = rawUltima;
    }

    if (!disponible || ultimaActivacion == null) return;

    if (DateTime.now().difference(ultimaActivacion) >= tiempoMaximo) {
      final ref = FirebaseFirestore.instance.collection('usuarios').doc(uid);
      try {
        await ref.update({
          'disponible': false,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (e) {
        if (e.code == 'not-found') {
          await ref.set({
            'disponible': false,
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else {
          rethrow;
        }
      }

      await NotificationService.I.notifyNuevoViaje(
        viajeId: 'disponibilidad_timeout_$uid',
        titulo: 'Disponibilidad desactivada',
        cuerpo: 'Han pasado 12 horas. Activa nuevamente para recibir viajes.',
      );
    }
  }

  static Future<void> activar(String uid) async {
    final ref = FirebaseFirestore.instance.collection('usuarios').doc(uid);
    final data = <String, dynamic>{
      'ultimaActivacion': FieldValue.serverTimestamp(),
      'disponible': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    };
    try {
      await ref.update(data);
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        await ref.set(data, SetOptions(merge: true));
      } else {
        rethrow;
      }
    }
  }
}
