import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/servicios/taxista_registro_perfil_data.dart';

/// Perfil mínimo pasajero tras teléfono/Google (nombre + teléfono RD).
abstract final class ClientePerfilOnboarding {
  ClientePerfilOnboarding._();

  static bool telefonoValido(String? raw) =>
      TaxistaRegistroPerfilData.telefonoRdValido(raw);

  static bool _esGoogle(User? user, Map<String, dynamic> data) {
    final proveedor =
        (data['proveedor'] ?? '').toString().trim().toLowerCase();
    if (proveedor == 'google') return true;
    return user?.providerData.any((p) => p.providerId == 'google.com') ??
        false;
  }

  static bool datosMinimosCompletos(Map<String, dynamic> data) {
    final nombre = (data['nombre'] ?? '').toString().trim();
    if (nombre.length < 2) return false;
    return telefonoValido((data['telefono'] ?? '').toString());
  }

  /// `true` = hay que mostrar [CompletarPerfilCliente] y bloquear el shell.
  static bool debeCompletarPerfil(Map<String, dynamic> data) {
    final User? user = FirebaseAuth.instance.currentUser;
    final String nombreFs = (data['nombre'] ?? '').toString().trim();
    final String nombre = nombreFs.length >= 2
        ? nombreFs
        : (user?.displayName ?? '').trim();

    // Google con nombre: entrar sin exigir teléfono (web/laptop).
    if (_esGoogle(user, data) && nombre.length >= 2) {
      return false;
    }

    // Ya completó el onboarding antes: no volver a atrapar tras cancelar viaje.
    if (data['registroClienteCompleto'] == true && nombre.length >= 2) {
      return false;
    }

    final String telFs = (data['telefono'] ?? '').toString();
    final String telAuth = (user?.phoneNumber ?? '').toString();
    if (nombre.length >= 2 &&
        (telefonoValido(telFs) || telefonoValido(telAuth))) {
      return false;
    }

    return !datosMinimosCompletos(<String, dynamic>{
      ...data,
      if (nombre.isNotEmpty) 'nombre': nombre,
      if (!telefonoValido(telFs) && telefonoValido(telAuth))
        'telefono': telAuth,
    });
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
