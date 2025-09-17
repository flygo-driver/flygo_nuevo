import 'package:firebase_auth/firebase_auth.dart';

class PhoneAuthService {
  static final _auth = FirebaseAuth.instance;

  /// Inicia flujo de verificación y devuelve el verificationId.
  static Future<String> sendCode({
    required String phoneNumber, // E.164, ej: +1829XXXXXXX
    Duration timeout = const Duration(seconds: 60),
    void Function(PhoneAuthCredential cred)? onInstantVerification,
  }) async {
    late String verificationId;

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: timeout,
      verificationCompleted: (credential) async {
        // En algunos dispositivos Google resuelve automáticamente.
        if (onInstantVerification != null) onInstantVerification(credential);
      },
      verificationFailed: (e) {
        throw Exception(e.message ?? 'Fallo de verificación');
      },
      codeSent: (vId, _token) {
        verificationId = vId;
      },
      codeAutoRetrievalTimeout: (vId) {
        verificationId = vId; // por si expira el autosolve
      },
    );

    return verificationId;
  }

  /// Vincula el teléfono a la cuenta actual (primera vez).
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

  /// Reautentica la sesión actual por SMS (para step-up / cada N días).
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
