// lib/servicios/google_auth.dart
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flygo_nuevo/keys.dart';
import 'package:flygo_nuevo/servicios/cuenta_rol_perfil_guard.dart';
import 'package:flygo_nuevo/servicios/app_flavor_rol_guard.dart';
import 'package:flygo_nuevo/servicios/taxista_registro_perfil_data.dart';
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
    final rawLower = error.toString().toLowerCase();
    if (rawLower.contains('signinwithidp are blocked') ||
        rawLower.contains('identitytoolkit') ||
        rawLower.contains('api_key_service_blocked')) {
      return 'Google Sign-In bloqueado por configuración de Firebase (API key). '
          'En Google Cloud → flygo-rd → Credenciales, la clave Android de Firebase '
          'debe permitir Identity Toolkit API y Token Service API. '
          'No cambia la firma de Play Store.';
    }
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'aborted-by-user':
        case 'popup-closed-by-user':
        case 'cancelled-popup-request':
          return 'Inicio con Google cancelado.';
        case 'redirect-pending':
          return 'Elige tu Gmail. Si ya está en Chrome, entra con un toque.';
        case 'unauthorized-domain':
          return 'Dominio no autorizado en Firebase. Usa https://flygo-rd.web.app';
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
              'Esta cuenta no corresponde al perfil $rolTxt. '
                  'Si eres pasajero, usa la app/pestaña Pasajero; '
                  'si eres conductor, usa Conductor.';
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

  static const String _kWebGoogleRolKey = 'rai_google_entrada_rol';
  static const String _kWebPostAuthRouteKey = 'rai_post_auth_route';

  static bool _googlePerfilListo(User user) =>
      (user.displayName ?? '').trim().length >= 2;

  static Future<void> _persistWebGoogleSession({
    required String rolEntrada,
    String? postAuthRoute,
  }) async {
    if (!kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWebGoogleRolKey, rolEntrada);
    final route = (postAuthRoute ?? '').trim();
    if (route.isNotEmpty) {
      await prefs.setString(_kWebPostAuthRouteKey, route);
    }
  }

  /// Login corporativo laptop/web.
  /// Popup con selector de cuentas; si el navegador bloquea, redirect.
  static Future<User> signInCorporativoLaptop() async {
    if (kIsWeb) {
      final cred = await _signInGoogleWeb(
        rolEntrada: 'cliente',
        postAuthRoute: '/corporativo',
      );
      final user = cred.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'no-user',
          message: 'Google no devolvió usuario.',
        );
      }
      await syncCorporativoMinimal(user);
      return user;
    }

    final cred = await _signInNativeRobust();
    final user = cred.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'Google no devolvió usuario.',
      );
    }
    await syncCorporativoMinimal(user);
    return user;
  }

  /// Correo + contraseña para corporativo web (misma cuenta cliente / encargado).
  static Future<User> signInCorporativoEmail({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    final user = cred.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'No se obtuvo usuario.',
      );
    }
    await syncCorporativoMinimal(user);
    return user;
  }

  /// Perfil mínimo para corporativo: nunca lanza role-mismatch ni cierra sesión.
  static Future<void> syncCorporativoMinimal(User user) async {
    final uid = user.uid;
    final nowTs = FieldValue.serverTimestamp();
    final ref = _db.collection('usuarios').doc(uid);
    try {
      final snap = await ref.get();
      final existing = snap.data() ?? <String, dynamic>{};
      final rolActual =
          (existing['rol'] ?? '').toString().trim().toLowerCase();
      final nombreFs = (existing['nombre'] ?? '').toString().trim();
      final nombreGoogle = (user.displayName ?? '').toString().trim();

      final patch = <String, dynamic>{
        'uid': uid,
        'email': (user.email ?? existing['email'] ?? '').toString().trim().toLowerCase(),
        'nombre': nombreFs.length >= 2 ? nombreFs : nombreGoogle,
        'fotoUrl': (existing['fotoUrl'] ?? user.photoURL ?? '').toString(),
        'proveedor': 'google',
        'lastLogin': nowTs,
        'updatedAt': nowTs,
        'actualizadoEn': nowTs,
      };
      if (rolActual.isEmpty) {
        patch['rol'] = 'cliente';
        patch['fechaRegistro'] = nowTs;
      }
      if (_googlePerfilListo(user)) {
        patch['registroClienteCompleto'] = true;
      }
      await ref.set(patch, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[GoogleAuth] syncCorporativoMinimal: $e');
    }
  }

  /// Tras `signInWithRedirect` en web, completar sesión al volver a la app.
  static Future<bool> completeWebRedirectIfAny() async {
    if (!kIsWeb) return false;
    try {
      final result = await _auth.getRedirectResult();
      final user = result.user;
      if (user == null) return false;

      final prefs = await SharedPreferences.getInstance();
      final rol = prefs.getString(_kWebGoogleRolKey) ?? 'cliente';
      final postRoute = prefs.getString(_kWebPostAuthRouteKey) ?? '';
      await prefs.remove(_kWebGoogleRolKey);

      _pendingEntradaRol = rol;
      try {
        if (postRoute.trim() == '/corporativo') {
          await syncCorporativoMinimal(user);
        } else {
          await _syncUsuarioFirestoreAfterGoogle(
            user: user,
            rolEntrada: rol,
          );
        }
      } on FirebaseAuthException catch (e) {
        debugPrint('[GoogleAuth] redirect sync auth error: ${e.code} ${e.message}');
      } catch (e) {
        debugPrint('[GoogleAuth] redirect sync omitido: $e');
      } finally {
        _pendingEntradaRol = null;
      }
      return true;
    } catch (e) {
      debugPrint('[GoogleAuth] completeWebRedirectIfAny: $e');
      return _auth.currentUser != null;
    }
  }

  static Future<UserCredential> signInWithGoogleStrict({
    required String entradaRol,
    String? postAuthRoute,
  }) async {
    final String rolEntrada =
        (entradaRol.trim().toLowerCase() == 'taxista') ? 'taxista' : 'cliente';

    try {
      _pendingEntradaRol = rolEntrada;

      final UserCredential cred;
      if (kIsWeb) {
        cred = await _signInGoogleWeb(
          rolEntrada: rolEntrada,
          postAuthRoute: postAuthRoute,
        );
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
      } on FirebaseAuthException catch (e) {
        _pendingEntradaRol = null;
        if (e.code == 'role-mismatch') {
          AppFlavorRolGuard.guardarMotivoRechazo(
            e.message ?? 'Esta cuenta no corresponde a este perfil.',
          );
          if (!kIsWeb) {
            await AppFlavorRolGuard.cerrarSesionTrasRechazo();
          }
        }
        rethrow;
      } catch (e) {
        debugPrint('GoogleAuth Firestore sync omitido: $e');
      }

      return cred;
    } on FirebaseAuthException catch (e) {
      _pendingEntradaRol = null;
      if (e.code == 'role-mismatch') {
        AppFlavorRolGuard.guardarMotivoRechazo(
          e.message ?? 'Esta cuenta no corresponde a este perfil.',
        );
        if (!kIsWeb) {
          await AppFlavorRolGuard.cerrarSesionTrasRechazo();
        }
      }
      rethrow;
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

    // Sin esto Google reutiliza la última cuenta y no muestra el resto.
    await _prepararPickerCuentasGoogle();

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

    // Reintento: limpiar otra vez y pedir cuenta.
    try {
      await _prepararPickerCuentasGoogle();
    } catch (_) {}

    gUser = await _googleSignInNativo().signIn();
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
    // Mapa Play: open07service=pasajero, ventasopenask=conductor.
    AppFlavorRolGuard.assertEntradaRespetaEmailFijo(
      email: user.email,
      entradaRol: rolEntrada,
    );
    final fijo = AppFlavorRolGuard.rolFijoPorEmail(user.email);
    final String rolEfectivo = fijo ??
        ((rolEntrada.trim().toLowerCase() == 'taxista') ? 'taxista' : 'cliente');

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
      if (!esAdmin && rolEfectivo == 'cliente') {
        await refUsuario.set({
          'uid': uid,
          'email': (user.email ?? '').toString(),
          'nombre': (user.displayName ?? '').toString(),
          'fotoUrl': (user.photoURL ?? '').toString(),
          'telefono': '',
          'registroClienteCompleto': _googlePerfilListo(user),
          'proveedor': 'google',
          'rol': 'cliente',
          'fechaRegistro': nowTs,
          'actualizadoEn': nowTs,
          'updatedAt': nowTs,
        }, SetOptions(merge: true));
        await refRol.set({
          'rol': 'cliente',
          'updatedAt': nowTs,
          'actualizadoEn': nowTs,
        }, SetOptions(merge: true));
      } else if (!esAdmin && rolEfectivo == 'taxista') {
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
          'registroTaxistaCompleto': false,
          'fechaRegistro': nowTs,
          'actualizadoEn': nowTs,
          'updatedAt': nowTs,
        }, SetOptions(merge: true));
        await refRol.set({
          'rol': 'taxista',
          'updatedAt': nowTs,
          'actualizadoEn': nowTs,
        }, SetOptions(merge: true));
      } else {
        await refUsuario.set({
          'uid': uid,
          'email': (user.email ?? '').toString(),
          'nombre': (user.displayName ?? '').toString(),
          'telefono': (user.phoneNumber ?? '').toString(),
          'fotoUrl': (user.photoURL ?? '').toString(),
          'proveedor': 'google',
          'rol': esAdmin ? 'admin' : rolEfectivo,
          'fechaRegistro': nowTs,
          'actualizadoEn': nowTs,
          'updatedAt': nowTs,
        }, SetOptions(merge: true));
      }
      return;
    }

    // Si el correo tiene rol fijo y el doc está mal, corregir (como Play).
    if (!esAdmin && fijo != null) {
      final actual = AppFlavorRolGuard.rolCanonicoDesdeMaps(
        usuario: dataUsuario,
        roles: dataRol,
      );
      if (actual != fijo) {
        await refUsuario.set({
          'rol': fijo,
          'isAdmin': false,
          'admin': false,
          if (fijo == 'cliente') ...{
            'disponible': false,
            'puedeRecibirViajes': false,
            'registroClienteCompleto': true,
          },
          'updatedAt': nowTs,
          'actualizadoEn': nowTs,
        }, SetOptions(merge: true));
        await refRol.set({
          'rol': fijo,
          'updatedAt': nowTs,
          'actualizadoEn': nowTs,
        }, SetOptions(merge: true));
        dataUsuario['rol'] = fijo;
        dataRol['rol'] = fijo;
      }
    }

    final rolActual = AppFlavorRolGuard.rolCanonicoDesdeMaps(
      usuario: dataUsuario,
      roles: dataRol,
    );

    if (!esAdmin && AppFlavorRolGuard.esRolOperativo(rolActual)) {
      AppFlavorRolGuard.assertRolEntradaPermitida(
        rolFirestore: rolActual,
        entradaRol: rolEfectivo,
        email: user.email,
        telefono: user.phoneNumber,
      );
      if (!AppFlavorRolGuard.rolCompatibleConFlavor(rolActual)) {
        final msg = AppFlavorRolGuard.mensajeMismatch(
          rolFirestore: rolActual,
          email: user.email,
          telefono: user.phoneNumber,
        );
        AppFlavorRolGuard.guardarMotivoRechazo(msg);
        throw FirebaseAuthException(
          code: 'role-mismatch',
          message: msg,
        );
      }
    }

    if (!esAdmin && rolActual.isEmpty) {
      final rolInicial =
          rolEfectivo == 'cliente' &&
                  CuentaRolPerfilGuard.cuentaPareceTaxista(dataUsuario)
              ? 'taxista'
              : rolEfectivo;
      await refUsuario.set(
        {'rol': rolInicial, 'updatedAt': nowTs, 'actualizadoEn': nowTs},
        SetOptions(merge: true),
      );
    }

    String preferirFirestore(String? firestoreVal, String? googleVal) {
      final raw = (firestoreVal ?? '').toString();
      if (raw.trim().isNotEmpty) return raw;
      return (googleVal ?? '').toString();
    }

    final patch = <String, dynamic>{
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
    };
    if (!esAdmin &&
        rolEfectivo == 'taxista' &&
        !TaxistaRegistroPerfilData.taxistaRegistroPerfilCompleto(dataUsuario)) {
      patch['registroTaxistaCompleto'] = false;
    }
    if (!esAdmin &&
        rolEfectivo == 'cliente' &&
        _googlePerfilListo(user) &&
        dataUsuario['registroClienteCompleto'] != true) {
      patch['registroClienteCompleto'] = true;
    }
    await refUsuario.set(patch, SetOptions(merge: true));
  }

  static Future<void> signOut() async {
    try {
      if (!kIsWeb) {
        await _googleSignInNativo().signOut();
      }
      // Web: no llamar GoogleSignIn.signOut — borra sesiones de Chrome y
      // obliga a escribir contraseña la próxima vez.
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
  }

  static Future<void> clearGoogleSignInSession() async {
    if (kIsWeb) {
      // En web no tocamos la sesión de Google en Chrome: si la cerramos,
      // el usuario tiene que volver a escribir correo y contraseña.
      try {
        await _auth.signOut();
      } catch (_) {}
      return;
    }
    try {
      await _googleSignInNativo().signOut();
    } catch (_) {
      try {
        await GoogleSignIn(scopes: const ['email', 'profile']).signOut();
      } catch (_) {}
    }
  }

  /// Solo cierra Firebase Auth. Mantiene cookies Google de Chrome (entrada directa).
  static Future<void> _prepararPickerWebSuave() async {
    try {
      if (_auth.currentUser != null) await _auth.signOut();
    } catch (_) {}
  }

  /// Nativo: sí limpia GoogleSignIn para que salga el selector de cuentas.
  static Future<void> _prepararPickerCuentasGoogle() async {
    try {
      await clearGoogleSignInSession();
    } catch (_) {}
    try {
      await _auth.signOut();
    } catch (_) {}
  }

  static GoogleAuthProvider _googleAuthProviderConPicker() {
    return GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile')
      ..setCustomParameters(const {
        'prompt': 'select_account',
      });
  }

  /// Web: popup con `select_account` (si cerrás el selector, se cancela limpio).
  /// Si el navegador bloquea el popup → redirect (la página se va a Google).
  static Future<UserCredential> _signInGoogleWeb({
    required String rolEntrada,
    String? postAuthRoute,
  }) async {
    await _prepararPickerWebSuave();
    final provider = _googleAuthProviderConPicker();
    await _persistWebGoogleSession(
      rolEntrada: rolEntrada,
      postAuthRoute: postAuthRoute,
    );

    try {
      return await _auth.signInWithPopup(provider);
    } on FirebaseAuthException catch (e) {
      final code = e.code;
      if (code == 'popup-closed-by-user' ||
          code == 'cancelled-popup-request' ||
          code == 'aborted-by-user') {
        throw FirebaseAuthException(
          code: 'aborted-by-user',
          message: 'Inicio con Google cancelado.',
        );
      }
      if (code == 'popup-blocked' ||
          code == 'operation-not-supported-in-this-environment') {
        await _iniciarGoogleWebAccountChooser(
          rolEntrada: rolEntrada,
          postAuthRoute: postAuthRoute,
        );
      }
      rethrow;
    }
  }

  /// Fallback redirect (solo si el popup está bloqueado).
  static Future<Never> _iniciarGoogleWebAccountChooser({
    required String rolEntrada,
    String? postAuthRoute,
  }) async {
    await _prepararPickerWebSuave();
    final provider = _googleAuthProviderConPicker();
    await _persistWebGoogleSession(
      rolEntrada: rolEntrada,
      postAuthRoute: postAuthRoute,
    );
    await _auth.signInWithRedirect(provider);
    throw FirebaseAuthException(
      code: 'redirect-pending',
      message:
          'Elige tu Gmail. Si la página no cambia, permite ventanas emergentes.',
    );
  }
}
