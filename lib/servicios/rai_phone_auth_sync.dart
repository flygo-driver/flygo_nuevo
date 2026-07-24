import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/servicios/app_flavor_rol_guard.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';

/// Sincroniza Firestore tras login por SMS (cliente o taxista).
abstract final class RaiPhoneAuthSync {
  RaiPhoneAuthSync._();

  static Future<void> syncAfterPhoneLogin({
    required User user,
    required String telE164,
    required String entradaRol,
  }) async {
    final rolEntrada =
        entradaRol.trim().toLowerCase() == 'taxista' ? 'taxista' : 'cliente';
    final uid = user.uid;
    final db = FirebaseFirestore.instance;
    final ref = db.collection('usuarios').doc(uid);
    final rolesRef = db.collection('roles').doc(uid);

    final snap = await ref.get();
    final rolesSnap = await rolesRef.get();
    final data = snap.data() ?? <String, dynamic>{};
    final rolesData = rolesSnap.data();
    final rolUsuarios =
        AppFlavorRolGuard.rolCanonicoDesdeMaps(usuario: data);
    final rolRoles = AppFlavorRolGuard.rolCanonicoDesdeMaps(roles: rolesData);
    final rolActual = rolUsuarios.isNotEmpty ? rolUsuarios : rolRoles;
    final nowTs = FieldValue.serverTimestamp();

    final bool esAdmin = RolesService.esRolAdmin(rolUsuarios) ||
        RolesService.esRolAdmin(rolRoles);

    if (!esAdmin && AppFlavorRolGuard.esRolOperativo(rolActual)) {
      try {
        AppFlavorRolGuard.assertRolEntradaPermitida(
          rolFirestore: rolActual,
          entradaRol: rolEntrada,
          email: user.email,
          telefono: telE164,
        );
      } on FirebaseAuthException {
        await AppFlavorRolGuard.cerrarSesionTrasRechazo();
        rethrow;
      }
    }

    if (!esAdmin &&
        !AppFlavorRolGuard.rolCompatibleConFlavor(rolActual) &&
        rolActual.isNotEmpty) {
      final msg = AppFlavorRolGuard.mensajeMismatch(
        rolFirestore: rolActual,
        email: user.email,
        telefono: telE164,
      );
      AppFlavorRolGuard.guardarMotivoRechazo(msg);
      await AppFlavorRolGuard.cerrarSesionTrasRechazo();
      throw FirebaseAuthException(
        code: 'role-mismatch',
        message: msg,
      );
    }

    if (!snap.exists) {
      if (rolEntrada == 'cliente') {
        await ref.set({
          'uid': uid,
          'rol': 'cliente',
          'telefono': telE164,
          'proveedor': 'phone',
          'registroClienteCompleto': false,
          'fechaRegistro': nowTs,
          'lastLogin': nowTs,
          'updatedAt': nowTs,
          'actualizadoEn': nowTs,
        }, SetOptions(merge: true));
      } else {
        await ref.set({
          'uid': uid,
          'rol': 'taxista',
          'telefono': telE164,
          'proveedor': 'phone',
          'nombre': '',
          'disponible': false,
          'docsEstado': 'pendiente',
          'estadoDocumentos': 'pendiente',
          'documentosCompletos': false,
          'puedeRecibirViajes': false,
          'registroTaxistaCompleto': false,
          'fechaRegistro': nowTs,
          'lastLogin': nowTs,
          'updatedAt': nowTs,
          'actualizadoEn': nowTs,
        }, SetOptions(merge: true));
      }
      return;
    }

    final patch = <String, dynamic>{
      'telefono': telE164,
      'proveedor': 'phone',
      'lastLogin': nowTs,
      'updatedAt': nowTs,
      'actualizadoEn': nowTs,
    };
    if (rolActual.isEmpty) {
      patch['rol'] = rolEntrada;
      if (rolEntrada == 'cliente') {
        patch['registroClienteCompleto'] = false;
      } else {
        patch['registroTaxistaCompleto'] = false;
      }
    }
    await ref.set(patch, SetOptions(merge: true));
  }
}
