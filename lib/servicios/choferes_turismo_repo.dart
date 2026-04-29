// lib/servicios/choferes_turismo_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flygo_nuevo/modelo/chofer_turismo.dart';

class ChoferesTurismoRepo {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('choferes_turismo');

  // ==============================================================
  //                           CREATE
  // ==============================================================
  static Future<void> crearChofer(ChoferTurismo chofer) async {
    await _col.doc(chofer.uid).set(chofer.toMap());
  }

  // ==============================================================
  //                           READ
  // ==============================================================
  static Stream<List<ChoferTurismo>> streamChoferesDisponibles({
    String? tipoVehiculo,
    double? lat,
    double? lon,
    double radioKm = 30,
  }) {
    Query<Map<String, dynamic>> query = _col
        .where('estado', isEqualTo: 'aprobado')
        .where('disponible', isEqualTo: true);

    if (tipoVehiculo != null && tipoVehiculo.isNotEmpty) {
      // Filtro por tipo de vehículo en el array de vehiculos
      query = query.where('vehiculos', arrayContains: {'tipo': tipoVehiculo});
    }

    return query.snapshots().map((snapshot) {
      var choferes = snapshot.docs
          .map((doc) => ChoferTurismo.fromMap(doc.id, doc.data()))
          .toList();

      // Filtrar por distancia si hay coordenadas
      if (lat != null && lon != null) {
        choferes = choferes.where((c) {
          if (c.ultimaUbicacion == null) return true;
          final distancia = Geolocator.distanceBetween(
                lat,
                lon,
                c.ultimaUbicacion!.latitude,
                c.ultimaUbicacion!.longitude,
              ) /
              1000;
          return distancia <= radioKm;
        }).toList();

        // Ordenar por distancia
        choferes.sort((a, b) {
          if (a.ultimaUbicacion == null) return 1;
          if (b.ultimaUbicacion == null) return -1;
          final da = Geolocator.distanceBetween(
            lat,
            lon,
            a.ultimaUbicacion!.latitude,
            a.ultimaUbicacion!.longitude,
          );
          final db = Geolocator.distanceBetween(
            lat,
            lon,
            b.ultimaUbicacion!.latitude,
            b.ultimaUbicacion!.longitude,
          );
          return da.compareTo(db);
        });
      }

      return choferes;
    });
  }

  static Future<ChoferTurismo?> obtenerChofer(String uid) async {
    final doc = await _col.doc(uid).get();
    if (!doc.exists) return null;
    return ChoferTurismo.fromMap(doc.id, doc.data()!);
  }

  static Stream<ChoferTurismo?> streamChofer(String uid) {
    return _col.doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return ChoferTurismo.fromMap(doc.id, doc.data()!);
    });
  }

  // ==============================================================
  //                           UPDATE
  // ==============================================================
  static Future<void> actualizarDisponibilidad(
      String uid, bool disponible) async {
    await _col.doc(uid).update({
      'disponible': disponible,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> actualizarUbicacion(
      String uid, double lat, double lon) async {
    await _col.doc(uid).update({
      'ultimaUbicacion': GeoPoint(lat, lon),
      'ultimaUbicacionActualizada': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> incrementarViajes(String uid) async {
    await _col.doc(uid).update({
      'viajesCompletados': FieldValue.increment(1),
    });
  }

  static Future<void> actualizarCalificacion(
      String uid, double nuevaCalificacion) async {
    final chofer = await obtenerChofer(uid);
    if (chofer == null) return;

    final totalViajes = chofer.viajesCompletados + 1;
    final nuevaPromedio =
        ((chofer.calificacion * chofer.viajesCompletados) + nuevaCalificacion) /
            totalViajes;

    await _col.doc(uid).update({
      'calificacion': nuevaPromedio,
    });
  }

  static Future<void> actualizarEstado(String uid, String estado,
      {String? verificadoPor}) async {
    final Map<String, dynamic> update = {
      'estado': estado,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (verificadoPor != null) {
      update['verificadoPor'] = verificadoPor;
      update['verificadoEn'] = FieldValue.serverTimestamp();
    }
    await _col.doc(uid).update(update);
  }

  // ==============================================================
  //                           DELETE
  // ==============================================================
  static Future<void> eliminarChofer(String uid) async {
    await _col.doc(uid).delete();
  }
}
