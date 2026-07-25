import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/cuenta_rol_perfil_guard.dart';
import 'package:flygo_nuevo/servicios/google_auth.dart';
import 'package:flygo_nuevo/servicios/post_auth_navigation.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

/// Entrada cliente sin tocar flujos taxista/admin.
abstract final class ClienteEntradaRapida {
  ClienteEntradaRapida._();

  /// RAI: sin visitante anónimo en producción.
  static const bool invitadoEnProduccion = false;

  static void irTrasLogin(BuildContext context, {String? route}) {
    if (!context.mounted) return;
    PostAuthNavigation.go(context, route: route);
  }

  static Future<void> irTrasLoginGuardandoRuta(
    BuildContext context, {
    String? route,
  }) async {
    if ((route ?? '').trim().isNotEmpty) {
      await PostAuthNavigation.saveRoute(route!.trim());
    }
    if (!context.mounted) return;
    await PostAuthNavigation.goAfterStoredRoute(context);
  }

  static Future<void> upsertUsuarioCliente({
    required String uid,
    required String email,
    bool includeNombreTelefono = false,
    String nombre = '',
    bool proveedorGoogle = false,
  }) async {
    try {
      final ref = FirebaseFirestore.instance.collection('usuarios').doc(uid);
      final snap = await ref.get();
      final nowTs = FieldValue.serverTimestamp();

      if (!snap.exists) {
        final nombreOk = nombre.trim().length >= 2;
        await ref.set({
          'uid': uid,
          'email': email.trim(),
          'rol': 'cliente',
          'registroClienteCompleto': proveedorGoogle && nombreOk,
          if (nombreOk) 'nombre': nombre.trim(),
          if (proveedorGoogle) 'proveedor': 'google',
          if (includeNombreTelefono) ...{'nombre': '', 'telefono': ''},
          'fechaRegistro': nowTs,
          'lastLogin': nowTs,
          'updatedAt': nowTs,
          'actualizadoEn': nowTs,
        }, SetOptions(merge: true));
      } else {
        final existing = snap.data();
        final patch = <String, dynamic>{
          'email': email.trim(),
          'lastLogin': nowTs,
          'updatedAt': nowTs,
          'actualizadoEn': nowTs,
        };
        if (proveedorGoogle) patch['proveedor'] = 'google';
        if (nombre.trim().length >= 2) {
          patch['nombre'] = nombre.trim();
          if (proveedorGoogle) patch['registroClienteCompleto'] = true;
        }
        final rolSeguro = CuentaRolPerfilGuard.rolClienteSeguroDesdeUsuario(
          existing ?? <String, dynamic>{},
        );
        if (rolSeguro != null) {
          final r = (existing?['rol'] ?? '').toString().trim();
          if (r.isEmpty) {
            patch['rol'] = rolSeguro;
            patch['registroClienteCompleto'] = false;
          }
        }
        await ref.set(patch, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  static Future<void> loginGoogle(
    BuildContext context, {
    required void Function(String msg) onMensaje,
    String entradaRol = 'cliente',
    String? postLoginRoute,
  }) async {
    final route = (postLoginRoute ?? '').trim();
    if (route == '/corporativo') {
      try {
        await GoogleAuthService.signInCorporativoLaptop();
        if (!context.mounted) return;
        await PostAuthNavigation.saveRoute('/corporativo');
        if (!context.mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/corporativo', (r) => false);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'aborted-by-user' || e.code == 'redirect-pending') {
          if (e.code == 'aborted-by-user') {
            onMensaje('Cancelaste Google. Podés intentar de nuevo u otro método.');
          }
          return;
        }
        onMensaje(GoogleAuthService.friendlyAuthError(e, rol: 'cliente'));
      } catch (e) {
        onMensaje(GoogleAuthService.friendlyAuthError(e, rol: 'cliente'));
      }
      return;
    }

    final rol = entradaRol.trim().toLowerCase() == 'taxista' ? 'taxista' : 'cliente';
    try {
      await GoogleAuthService.signInWithGoogleStrict(
        entradaRol: rol,
        postAuthRoute: postLoginRoute,
      );
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      final email = (user?.email ?? '').trim();
      if (uid != null && rol == 'cliente') {
        final user = FirebaseAuth.instance.currentUser;
        await upsertUsuarioCliente(
          uid: uid,
          email: email,
          nombre: (user?.displayName ?? '').trim(),
          proveedorGoogle: user?.providerData
                  .any((p) => p.providerId == 'google.com') ==
              true,
        );
      }
      if (uid != null && rol == 'taxista') {
        await ViajesRepo.reconciliarActivosTaxista(uid);
      }
      if (!context.mounted) return;
      if ((postLoginRoute ?? '').trim().isNotEmpty) {
        await PostAuthNavigation.saveRoute(postLoginRoute!.trim());
        Navigator.of(context).pushNamedAndRemoveUntil(
          postLoginRoute!.trim(),
          (r) => false,
        );
        return;
      }
      await PostAuthNavigation.goAfterStoredRoute(context);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'aborted-by-user' || e.code == 'redirect-pending') {
        if (e.code == 'aborted-by-user') {
          onMensaje('Cancelaste Google. Podés intentar de nuevo u otro método.');
        }
        return;
      }
      onMensaje(GoogleAuthService.friendlyAuthError(e, rol: rol));
    } catch (e) {
      onMensaje(GoogleAuthService.friendlyAuthError(e, rol: rol));
    }
  }

  static Future<void> loginInvitado(
    BuildContext context, {
    required void Function(String msg) onMensaje,
  }) async {
    try {
      final cred = await FirebaseAuth.instance.signInAnonymously();
      final uid = cred.user?.uid;
      if (uid == null) {
        onMensaje('No se pudo iniciar sesión. Inténtalo de nuevo.');
        return;
      }
      await upsertUsuarioCliente(
        uid: uid,
        email: '',
        includeNombreTelefono: true,
      );
      if (!context.mounted) return;
      irTrasLogin(context);
    } on FirebaseAuthException catch (e) {
      onMensaje(
        e.message ??
            'Acceso rápido no disponible. Usa Google o correo.',
      );
    } catch (_) {
      onMensaje('No se pudo entrar sin cuenta. Prueba con Google.');
    }
  }
}
