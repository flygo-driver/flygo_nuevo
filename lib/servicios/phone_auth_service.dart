import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/servicios/phone_auth_config.dart';
import 'package:flygo_nuevo/servicios/phone_auth_error_es.dart';

class PhoneAuthService {
  PhoneAuthService._();

  static final _auth = FirebaseAuth.instance;
  static bool _sendInFlight = false;
  static DateTime? _lastSendAt;
  static const Duration _cooldownEntreEnvios = Duration(seconds: 50);

  /// Espera a [codeSent] o error (no devuelve antes del SMS).
  /// Si el dispositivo auto-verifica, llama [onInstantVerification] y devuelve ''.
  static Future<String> sendCode({
    required String phoneNumber,
    Duration timeout = const Duration(seconds: 120),
    Future<void> Function(PhoneAuthCredential cred)? onInstantVerification,
    bool ignorarCooldown = false,
  }) async {
    if (_sendInFlight) {
      throw FirebaseAuthException(
        code: 'operation-in-progress',
        message: 'Ya estamos enviando un SMS. Esperá un momento.',
      );
    }

    if (!ignorarCooldown && _lastSendAt != null) {
      final restante = _cooldownEntreEnvios - DateTime.now().difference(_lastSendAt!);
      if (restante > Duration.zero) {
        final seg = restante.inSeconds.clamp(1, 999);
        throw FirebaseAuthException(
          code: 'too-many-requests',
          message:
              'Esperá $seg segundos antes de pedir otro SMS (evita bloqueo de Firebase).',
        );
      }
    }

    _sendInFlight = true;
    final completer = Completer<String>();
    var instantHandled = false;

    void finishOk(String vId) {
      _lastSendAt = DateTime.now();
      _sendInFlight = false;
      if (!completer.isCompleted) completer.complete(vId);
    }

    void finishErr(Object e, [StackTrace? st]) {
      _sendInFlight = false;
      if (!completer.isCompleted) completer.completeError(e, st);
    }

    try {
      await PhoneAuthConfig.aplicarAntesDeEnviarSms();
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: timeout,
        verificationCompleted: (credential) {
          if (instantHandled || completer.isCompleted) return;
          if (onInstantVerification != null) {
            instantHandled = true;
            onInstantVerification(credential).then((_) {
              finishOk('');
            }).catchError((Object e, StackTrace st) {
              finishErr(e, st);
            });
            return;
          }
          finishOk('');
        },
        verificationFailed: (e) {
          finishErr(
            FirebaseAuthException(
              code: normalizarCodigoPhoneAuth(e.code, e.message),
              message: e.message ?? 'No se pudo verificar el teléfono.',
            ),
          );
        },
        codeSent: (vId, _) {
          if (instantHandled) return;
          finishOk(vId);
        },
        codeAutoRetrievalTimeout: (vId) {
          if (instantHandled || completer.isCompleted) return;
          if (vId.isNotEmpty) finishOk(vId);
        },
      );
    } catch (e, st) {
      finishErr(e, st);
    }

    return completer.future.timeout(
      timeout + const Duration(seconds: 15),
      onTimeout: () {
        _sendInFlight = false;
        throw FirebaseAuthException(
          code: 'captcha-check-failed',
          message:
              'La verificación de Google no terminó. Cerrá la pantalla blanca con '
              'el botón Atrás, actualizá «Android System WebView» en Play Store '
              'e intentá de nuevo. También podés entrar con Google.',
        );
      },
    );
  }

  static Future<void> linkWithSms({
    required String verificationId,
    required String smsCode,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay sesión activa');
    final cred = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    await user.linkWithCredential(cred);
  }

  static Future<void> reauthWithSms({
    required String verificationId,
    required String smsCode,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay sesión activa');
    final cred = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    await user.reauthenticateWithCredential(cred);
  }
}
