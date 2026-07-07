import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/servicios/taxista_registro_perfil_data.dart';

/// Perfil mínimo pasajero tras teléfono/Google (nombre + teléfono RD).
abstract final class ClientePerfilOnboarding {
  ClientePerfilOnboarding._();

  static bool telefonoValido(String? raw) =>
      TaxistaRegistroPerfilData.telefonoRdValido(raw);

  static bool datosMinimosCompletos(Map<String, dynamic> data) {
    final nombre = (data['nombre'] ?? '').toString().trim();
    if (nombre.length < 2) return false;
    return telefonoValido((data['telefono'] ?? '').toString());
  }

  static bool debeCompletarPerfil(Map<String, dynamic> data) {
    if (data['registroClienteCompleto'] == true &&
        datosMinimosCompletos(data)) {
      return false;
    }
    return !datosMinimosCompletos(data);
  }

  static String telefonoDesdeUsuario(User? user, Map<String, dynamic> data) {
    final fs = (data['telefono'] ?? '').toString().trim();
    if (fs.isNotEmpty) return fs;
    final auth = (user?.phoneNumber ?? '').trim();
    if (auth.isNotEmpty) return auth;
    return '';
  }

  static String nombreDesdeUsuario(User? user, Map<String, dynamic> data) {
    final fs = (data['nombre'] ?? '').toString().trim();
    if (fs.length >= 2) return fs;
    final dn = (user?.displayName ?? '').trim();
    return dn;
  }

  static Future<void> guardarPerfilMinimo({
    required String uid,
    required String nombre,
    required String telefono,
  }) async {
    final telNorm = _normalizarTelRd(telefono);
    await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
      'uid': uid,
      'rol': 'cliente',
      'nombre': nombre.trim(),
      'telefono': telNorm,
      'registroClienteCompleto': true,
      'actualizadoEn': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.uid == uid) {
      try {
        await user.updateDisplayName(nombre.trim());
      } catch (_) {}
    }
  }

  static String _normalizarTelRd(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length == 11 && d.startsWith('1')) return '+$d';
    if (d.length == 10) return '+1$d';
    return raw.trim();
  }
}
