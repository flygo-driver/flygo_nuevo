import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/modelos/corporativo_models.dart';

/// Construye el perfil visible del conductor para encargados corporativos.
abstract final class CorporativoChoferPerfilService {
  CorporativoChoferPerfilService._();

  static final _db = FirebaseFirestore.instance;

  static CorporativoChoferPerfil desdeUsuario(
    Map<String, dynamic> u, {
    required String uid,
    DateTime? asignadoEn,
  }) {
    final docsOk = u['documentosCompletos'] == true ||
        u['documentosAprobados'] == true ||
        (u['estadoDocumentos'] ?? '').toString().toLowerCase() == 'aprobado';
    final suma = (u['ratingSuma'] as num?)?.toDouble() ?? 0;
    final cnt = (u['ratingConteo'] as num?)?.toInt() ?? 0;
    final rating = cnt > 0 ? (suma / cnt).clamp(0, 5).toDouble() : 0.0;
    DateTime? reg;
    final fr = u['fechaRegistro'];
    if (fr is Timestamp) reg = fr.toDate();
    final anios = reg != null
        ? (DateTime.now().difference(reg).inDays / 365).floor().clamp(0, 40)
        : 0;

    return CorporativoChoferPerfil(
      uid: uid,
      nombre: (u['nombre'] ?? u['displayName'] ?? '').toString().trim(),
      telefono: (u['telefono'] ?? '').toString().trim(),
      email: (u['email'] ?? u['correo'] ?? '').toString().trim(),
      cedula: (u['ciTaxista'] ?? u['cedula'] ?? u['cedulaTaxista'] ?? '')
          .toString()
          .trim(),
      placa: (u['placa'] ?? '').toString().trim().toUpperCase(),
      marca: (u['vehiculoMarca'] ?? u['marca'] ?? '').toString().trim(),
      modelo: (u['vehiculoModelo'] ?? u['modelo'] ?? '').toString().trim(),
      color: (u['vehiculoColor'] ?? u['color'] ?? '').toString().trim(),
      anio: (u['anio'] ?? u['vehiculoAnio'] ?? '').toString().trim(),
      tipoVehiculo: (u['tipoVehiculo'] ?? u['vehiculoTipo'] ?? '')
          .toString()
          .trim(),
      documentosVerificados: docsOk,
      fotoUrl: (u['fotoUrl'] ?? u['photoURL'] ?? u['imagenPerfil'] ?? '')
          .toString()
          .trim(),
      asignadoEn: asignadoEn ?? DateTime.now(),
      calificacionPromedio: rating,
      aniosExperiencia: anios,
    );
  }

  static Future<CorporativoChoferPerfil?> cargarPorUid(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return null;
    final snap = await _db.collection('usuarios').doc(id).get();
    if (!snap.exists) return null;
    return desdeUsuario(snap.data() ?? {}, uid: id);
  }

  /// Perfil guardado en plantilla o lectura en vivo si falta snapshot.
  static Future<CorporativoChoferPerfil?> resolverParaPlantilla(
    CorporativoPlantilla plantilla,
  ) async {
    final guardado = plantilla.choferAsignadoPerfil;
    if (guardado != null && guardado.asignado) return guardado;
    final uid = plantilla.choferPreferidoUid?.trim();
    if (uid == null || uid.isEmpty) return null;
    return cargarPorUid(uid);
  }

  static Stream<CorporativoChoferPerfil?> streamPorUid(String uid) {
    final id = uid.trim();
    if (id.isEmpty) return Stream.value(null);
    return _db.collection('usuarios').doc(id).snapshots().map((snap) {
      if (!snap.exists) return null;
      return desdeUsuario(snap.data() ?? {}, uid: id);
    });
  }
}
