// lib/servicios/google_auth.dart
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:flygo_nuevo/keys.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';

class GoogleAuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Pantalla desde la que entró con Google (`cliente` / `taxista`). [AuthCheck] lo consume
  /// si aún no hay doc en Firestore (p. ej. sync falló tras Auth).
  static String? _pendingEntradaRol;

  static String? consumePendingGoogleEntradaRol() {
    final v = _pendingEntradaRol;
    _pendingEntradaRol = null;
    return v;
  }

  static GoogleSignIn? _googleSignInMobile;

  static GoogleSignIn _googleSignInNativo() {
    if (_googleSignInMobile != null) return _googleSignInMobile!;
    final wid = AppKeys.googleOAuthWebClientId.trim();
    // Sin serverClientId la app usa el OAuth client de Android (google-services.json),
    // igual que versiones anteriores; con wid se pide idToken para Firebase Auth.
    _googleSignInMobile = wid.isNotEmpty
        ? GoogleSignIn(
            scopes: const ['email', 'profile'],
            serverClientId: wid,
          )
        : GoogleSignIn(
            scopes: const ['email', 'profile'],
          );
    return _googleSignInMobile!;
  }

  static String friendlyAuthError(Object error, {required String rol}) {
    final rolTxt = rol == 'taxista' ? 'taxista' : 'cliente';
    if (error is PlatformException) {
      final detail = '${error.code} ${error.message ?? ''}'.toLowerCase();
      if (detail.contains('10') ||
          detail.contains('developer_error') ||
          detail.contains('sign_in_failed')) {
        return 'Google Sign-In: revisa SHA-1 en Firebase flygo-rd, app Android '
            'com.flygo.rd2, y google-services.json en android/app.';
      }
    }
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'aborted-by-user':
        case 'popup-closed-by-user':
        case 'cancelled-popup-request':
          return 'Inicio con Google cancelado.';
        case 'google-token-null':
          return 'Google no devolvió credenciales válidas. Inténtalo de nuevo.';
        case 'google-config-missing':
          return 'Configuración de Google incompleta en la app.';
        case 'network-request-failed':
          return 'Sin conexión. Verifica internet e inténtalo de nuevo.';
        case 'too-many-requests':
          return 'Demasiados intentos. Espera un momento.';
        case 'invalid-credential':
          return 'Credencial de Google inválida. Reintenta.';
        case 'account-exists-with-different-credential':
          return 'Esa cuenta ya existe con otro método de acceso.';
        case 'role-mismatch':
          return error.message ??
              'Esta cuenta no corresponde al perfil $rolTxt.';
        default:
          if ((error.message ?? '')
              .toLowerCase()
              .contains('apiexception: 10')) {
            return 'Google Sign-In no está autorizado para esta app (SHA-1/SHA-256).';
          }
          return error.message ?? 'No se pudo iniciar con Google.';
      }
    }
    final raw = error.toString().toLowerCase();
    if (raw.contains('apiexception: 10')) {
      return 'Google Sign-In no está autorizado para esta app (SHA-1/SHA-256).';
    }
    if (raw.contains('network') || raw.contains('socket')) {
      return 'Sin conexión. Verifica internet e inténtalo de nuevo.';
    }
    if (error is FirebaseException) {
      return 'No se pudo guardar el perfil (${error.code}). Ya entraste: reabre la app.';
    }
    return 'No se pudo iniciar con Google para $rolTxt.';
  }

  static Future<UserCredential> signInWithGoogleStrict({
    required String entradaRol,
  }) async {
    final String rolEntrada =
        (entradaRol.trim().toLowerCase() == 'taxista') ? 'taxista' : 'cliente';

    UserCredential cred;

    try {
      _pendingEntradaRol = rolEntrada;
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile');
        cred = await _auth.signInWithPopup(provider);
      } else {
        cred = await _signInNativeRobust();
      }

      final user = cred.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'no-user',
          message: 'No se obtuvo usuario de Google.',
        );
      }

      try {
        await _syncUsuarioFirestoreAfterGoogle(
          user: user,
          rolEntrada: rolEntrada,
        );
        _pendingEntradaRol = null;
      } catch (e) {
        debugPrint('GoogleAuth Firestore sync omitido: $e');
      }

      return cred;
    } catch (e) {
      _pendingEntradaRol = null;
      if (kDebugMode) {
        debugPrint('GOOGLE AUTH ERROR => $e');
      }
      rethrow;
    }
  }

  static Future<UserCredential> _signInNativeRobust() async {
    GoogleSignInAccount? gUser;
    GoogleSignInAuthentication? gAuth;
    Object? firstError;

    try {
      gUser = await _googleSignInNativo().signIn();
      if (gUser == null) {
        throw FirebaseAuthException(
          code: 'aborted-by-user',
          message: 'Inicio de sesión cancelado.',
        );
      }
      gAuth = await gUser.authentication;
      if (gAuth.idToken == null && gAuth.accessToken == null) {
        throw FirebaseAuthException(
          code: 'google-token-null',
          message: 'Google no devolvió tokens.',
        );
      }
      final oauth = GoogleAuthProvider.credential(
        idToken: gAuth.idToken,
        accessToken: gAuth.accessToken,
      );
      return await _auth.signInWithCredential(oauth);
    } catch (e) {
      firstError = e;
      if (kDebugMode) debugPrint('Google native first attempt failed: $e');
    }

    // Reintento "como antes": limpiar sesión Google y pedir cuenta otra vez.
    try {
      await clearGoogleSignInSession();
    } catch (_) {}

    gUser = await GoogleSignIn(scopes: const ['email', 'profile']).signIn();
    if (gUser == null) {
      if (firstError is FirebaseAuthException &&
          firstError.code == 'aborted-by-user') {
        throw firstError;
      }
      throw FirebaseAuthException(
        code: 'aborted-by-user',
        message: 'Inicio de sesión cancelado.',
      );
    }
    gAuth = await gUser.authentication;
    if (gAuth.idToken == null && gAuth.accessToken == null) {
      throw FirebaseAuthException(
        code: 'google-token-null',
        message: 'Google no devolvió tokens.',
      );
    }

    final oauth = GoogleAuthProvider.credential(
      idToken: gAuth.idToken,
      accessToken: gAuth.accessToken,
    );
    return await _auth.signInWithCredential(oauth);
  }

  static Future<void> _syncUsuarioFirestoreAfterGoogle({
    required User user,
    required String rolEntrada,
  }) async {
    final uid = user.uid;
    final nowTs = FieldValue.serverTimestamp();

    final refUsuario = _db.collection('usuarios').doc(uid);
    final refRol = _db.collection('roles').doc(uid);

    final snapUsuario = await refUsuario.get();
    final snapRol = await refRol.get();

    final dataUsuario = snapUsuario.data() ?? <String, dynamic>{};
    final dataRol = snapRol.data() ?? <String, dynamic>{};

    final rolUsuarios =
        (dataUsuario['rol'] ?? '').toString().trim().toLowerCase();
    final rolRoles = (dataRol['rol'] ?? '').toString().trim().toLowerCase();

    final bool esAdmin = RolesService.esRolAdmin(rolUsuarios) ||
        RolesService.esRolAdmin(rolRoles);

    if (!snapUsuario.exists) {
      if (!esAdmin && rolEntrada == 'cliente') {
        await refUsuario.set({
          'uid': uid,
          'email': (user.email ?? '').toString(),
          'nombre': (user.displayName ?? '').toString(),
          'fotoUrl': (user.photoURL ?? '').toString(),
          'telefono': '',
          'registroClienteCompleto': false,
          'proveedor': 'google',
          'rol': rolEntrada,
          'fechaRegistro': nowTs,
          'actualizadoEn': nowTs,
          'updatedAt': nowTs,
        }, SetOptions(merge: true));
      } else if (!esAdmin && rolEntrada == 'taxista') {
        await refUsuario.set({
          'uid': uid,
          'email': (user.email ?? '').toString(),
          'nombre': (user.displayName ?? '').toString(),
          'fotoUrl': (user.photoURL ?? '').toString(),
          'telefono': '',
          'rol': 'taxista',
          'proveedor': 'google',
          'disponible': false,
          'docsEstado': 'pendiente',
          'estadoDocumentos': 'pendiente',
          'documentosCompletos': false,
          'puedeRecibirViajes': false,
          'fechaRegistro': nowTs,
          'actualizadoEn': nowTs,
          'updatedAt': nowTs,
        }, SetOptions(merge: true));
      } else {
        await refUsuario.set({
          'uid': uid,
          'email': (user.email ?? '').toString(),
          'nombre': (user.displayName ?? '').toString(),
          'telefono': (user.phoneNumber ?? '').toString(),
          'fotoUrl': (user.photoURL ?? '').toString(),
          'proveedor': 'google',
          'rol': esAdmin ? 'admin' : rolEntrada,
          'fechaRegistro': nowTs,
          'actualizadoEn': nowTs,
          'updatedAt': nowTs,
        }, SetOptions(merge: true));
      }
      return;
    }

    if (!esAdmin) {
      final rolActual = rolUsuarios;
      if (rolActual.isEmpty) {
        await refUsuario.set(
          {'rol': rolEntrada, 'updatedAt': nowTs, 'actualizadoEn': nowTs},
          SetOptions(merge: true),
        );
      }
    }

    String preferirFirestore(String? firestoreVal, String? googleVal) {
      final raw = (firestoreVal ?? '').toString();
      if (raw.trim().isNotEmpty) return raw;
      return (googleVal ?? '').toString();
    }

    await refUsuario.set(
      {
        'email': (user.email ?? (dataUsuario['email'] ?? '')).toString(),
        'nombre': preferirFirestore(
          dataUsuario['nombre']?.toString(),
          user.displayName,
        ),
        'telefono': preferirFirestore(
          dataUsuario['telefono']?.toString(),
          user.phoneNumber,
        ),
        'fotoUrl': preferirFirestore(
          dataUsuario['fotoUrl']?.toString(),
          user.photoURL,
        ),
        'proveedor': 'google',
        'updatedAt': nowTs,
        'actualizadoEn': nowTs,
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> signOut() async {
    try {
      if (!kIsWeb) {
        await _googleSignInNativo().signOut();
      } else {
        await GoogleSignIn().signOut();
      }
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
  }

  static Future<void> clearGoogleSignInSession() async {
    if (kIsWeb) {
      try {
        await GoogleSignIn().signOut();
      } catch (_) {}
      return;
    }
    try {
      await _googleSignInNativo().disconnect();
    } catch (_) {}
    try {
      await _googleSignInNativo().signOut();
    } catch (_) {}
  }
}
