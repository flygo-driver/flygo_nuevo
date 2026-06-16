import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/servicios/configuracion_globals_service.dart';

/// Cola ADM: taxistas bloqueados por cancelar muchas salidas por cupos.
abstract final class GirasAbusoAdminService {
  GirasAbusoAdminService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String kCampoBloqueado = 'girasAbusoBloqueado';
  static const String kCampoBloqueadoEn = 'girasAbusoBloqueadoEn';

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamColaBloqueados({
    int limite = 80,
  }) {
    return _db
        .collection('usuarios')
        .where(kCampoBloqueado, isEqualTo: true)
        .orderBy(kCampoBloqueadoEn, descending: true)
        .limit(limite)
        .snapshots();
  }

  static Future<void> marcarBloqueado(String uidTaxista) async {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return;
    await _db.collection('usuarios').doc(uid).set(
      <String, dynamic>{
        kCampoBloqueado: true,
        kCampoBloqueadoEn: FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> limpiarBloqueado(String uidTaxista) async {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return;
    await _db.collection('usuarios').doc(uid).set(
      <String, dynamic>{
        kCampoBloqueado: false,
        kCampoBloqueadoEn: FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static bool bloqueadoPorRatioEnDatos(
    Map<String, dynamic> data,
    GiraAbusoRemote abuso,
  ) {
    if (abuso.disabled) return false;
    final c = (data['girasCreadasUltimoMes'] as num?)?.toInt() ?? 0;
    final x = (data['girasCanceladasAntesDeIniciar'] as num?)?.toInt() ?? 0;
    if (c < abuso.minCreadas || x <= 0) return false;
    return x / c > abuso.ratioMax + 1e-9;
  }
}
