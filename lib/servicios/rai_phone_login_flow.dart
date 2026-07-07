import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/auth/cliente_entrada_rapida.dart';
import 'package:flygo_nuevo/servicios/phone_auth_service.dart';
import 'package:flygo_nuevo/servicios/rai_phone_auth_sync.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

/// Flujo SMS compartido (bienvenida y pantalla dedicada).
abstract final class RaiPhoneLoginFlow {
  RaiPhoneLoginFlow._();

  static String normalizarTelRd(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('1') && d.length == 11) return '+$d';
    if (d.length == 10) return '+1$d';
    return '+1$d';
  }

  /// Firebase puede abrir reCAPTCHA en segundo plano; no interrumpimos al usuario.
  static Future<bool> confirmarVerificacionSeguridad(BuildContext context) async {
    return true;
  }

  static Future<String> solicitarCodigoSms({
    required String telefonoE164,
    Future<void> Function(PhoneAuthCredential cred)? onAutoVerificado,
  }) {
    return PhoneAuthService.sendCode(
      phoneNumber: telefonoE164,
      onInstantVerification: onAutoVerificado,
    );
  }

  static Future<void> entrarConCredencial({
    required BuildContext context,
    required PhoneAuthCredential cred,
    required String telE164,
    required String entradaRol,
  }) async {
    UserCredential userCred;
    try {
      userCred = await FirebaseAuth.instance.signInWithCredential(cred);
    } on FirebaseAuthException {
      rethrow;
    }

    final user = userCred.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'No se pudo iniciar sesión con el teléfono.',
      );
    }

    await RaiPhoneAuthSync.syncAfterPhoneLogin(
      user: user,
      telE164: telE164,
      entradaRol: entradaRol,
    );

    if (entradaRol.trim().toLowerCase() == 'taxista') {
      await ViajesRepo.reconciliarActivosTaxista(user.uid);
    }

    if (!context.mounted) return;
    ClienteEntradaRapida.irTrasLogin(context);
  }
}
