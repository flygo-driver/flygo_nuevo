import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/google_auth.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

/// Entrada cliente sin tocar flujos taxista/admin.
abstract final class ClienteEntradaRapida {
  ClienteEntradaRapida._();

  /// RAI: sin visitante anónimo en producción.
  static const bool invitadoEnProduccion = false;

  static void irTrasLogin(BuildContext context) {
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/auth_check', (r) => false);
  }

  static Future<void> upsertUsuarioCliente({
    required String uid,
    required String email,
    bool includeNombreTelefono = false,
  }) async {
    try {
      final ref = FirebaseFirestore.instance.collection('usuarios').doc(uid);
      final snap = await ref.get();
      final nowTs = FieldValue.serverTimestamp();

      if (!snap.exists) {
        await ref.set({
          'uid': uid,
          'email': email.trim(),
          'rol': 'cliente',
          'registroClienteCompleto': false,
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
        final r = (existing?['rol'] ?? '').toString().trim();
        if (r.isEmpty) {
          patch['rol'] = 'cliente';
          patch['registroClienteCompleto'] = false;
        }
        await ref.set(patch, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  static Future<void> loginGoogle(
    BuildContext context, {
    required void Function(String msg) onMensaje,
    String entradaRol = 'cliente',
  }) async {
    final rol = entradaRol.trim().toLowerCase() == 'taxista' ? 'taxista' : 'cliente';
    try {
      await GoogleAuthService.signInWithGoogleStrict(entradaRol: rol);
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      final email = (user?.email ?? '').trim();
      if (uid != null && rol == 'cliente') {
        await upsertUsuarioCliente(uid: uid, email: email);
      }
      if (uid != null && rol == 'taxista') {
        await ViajesRepo.reconciliarActivosTaxista(uid);
      }
      if (!context.mounted) return;
      irTrasLogin(context);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'aborted-by-user') return;
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
