import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/legal/terms_data.dart';

/// Aceptación digital del contrato corporativo (empresa / encargado).
///
/// Coherente con el modelo de negocio:
/// 1) El encargado **firma** el contrato B2B (esta función).
/// 2) RAI **activa** el servicio (`contratoActivo`) desde Admin.
/// Firmar NO publica rutas; sí permite entrar al hub y configurar.
abstract final class CorporativoContratoService {
  CorporativoContratoService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const _camposFirmaEmpresa = <String>[
    'contratoCorporativoAceptado',
    'contratoCorporativoVersion',
    'contratoCorporativoAceptadoEn',
    'contratoCorporativoAceptadoPorUid',
    'contratoCorporativoFirmaTipo',
    'actualizadoEn',
  ];

  static bool empresaContratoDigitalFirmado(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (data['contratoCorporativoAceptado'] != true) return false;
    return (data['contratoCorporativoVersion'] ?? '')
            .toString()
            .trim() ==
        kCorporativoContractVersion;
  }

  static Future<bool> encargadoDebeFirmar({
    required String empresaId,
    Map<String, dynamic>? empresaData,
  }) async {
    if (empresaData != null) {
      return !empresaContratoDigitalFirmado(empresaData);
    }
    final snap =
        await _db.collection('empresas_corporativas').doc(empresaId).get();
    return !empresaContratoDigitalFirmado(snap.data());
  }

  /// Firma el contrato en la empresa. El perfil de usuario es best-effort.
  static Future<void> firmarContrato({
    required String empresaId,
    required String encargadoUid,
  }) async {
    final empresaRef = _db.collection('empresas_corporativas').doc(empresaId);
    final patch = <String, dynamic>{
      'contratoCorporativoAceptado': true,
      'contratoCorporativoVersion': kCorporativoContractVersion,
      'contratoCorporativoAceptadoEn': FieldValue.serverTimestamp(),
      'contratoCorporativoAceptadoPorUid': encargadoUid,
      'contratoCorporativoFirmaTipo': 'check_digital',
      'actualizadoEn': FieldValue.serverTimestamp(),
    };

    // 1) Empresa primero (lo que abre el hub).
    await empresaRef.set(patch, SetOptions(merge: true));

    // 2) Verificar en servidor (evita cache local desactualizado).
    final verify = await empresaRef.get(
      const GetOptions(source: Source.server),
    );
    if (!empresaContratoDigitalFirmado(verify.data())) {
      throw StateError(
        'La firma no quedó guardada. Revisá permisos de encargado e intentá de nuevo.',
      );
    }

    // 3) Espejo en usuario (no bloquea la entrada al hub).
    try {
      await _db.collection('usuarios').doc(encargadoUid).set(
        {
          'contratoCorporativoAceptado': true,
          'contratoCorporativoVersion': kCorporativoContractVersion,
          'contratoCorporativoEmpresaId': empresaId,
          'contratoCorporativoAceptadoEn': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  static String? uidActual() => FirebaseAuth.instance.currentUser?.uid;

  /// Expuesto para tests / reglas documentadas.
  static List<String> get camposFirmaEmpresa =>
      List<String>.unmodifiable(_camposFirmaEmpresa);
}
