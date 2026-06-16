import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/servicios/turismo_catalogo_rd.dart';

/// Destinos turísticos extra en Firestore (ADM). Se fusionan con el catálogo estático.
class TurismoDestinosRepo {
  static final _col = FirebaseFirestore.instance.collection('turismo_destinos');

  static Stream<List<TurismoLugar>> streamDestinosActivos() {
    return _col
        .where('activo', isEqualTo: true)
        .limit(200)
        .snapshots()
        .map((s) => s.docs.map(_fromDoc).whereType<TurismoLugar>().toList());
  }

  static Future<List<TurismoLugar>> fetchTodos({int limit = 300}) async {
    final snap = await _col.orderBy('nombre').limit(limit).get();
    return snap.docs.map(_fromDoc).whereType<TurismoLugar>().toList();
  }

  static TurismoLugar? _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final lat = (m['lat'] as num?)?.toDouble();
    final lon = (m['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    return TurismoLugar(
      id: (m['id'] ?? d.id).toString(),
      nombre: (m['nombre'] ?? '').toString(),
      ciudad: (m['ciudad'] ?? '').toString(),
      subtipo: (m['subtipo'] ?? TurismoCatalogoRD.ciudad).toString(),
      lat: lat,
      lon: lon,
      descripcion: (m['descripcion'] as String?),
      imagen: (m['imagen'] as String?),
      popularidad: (m['popularidad'] as num?)?.toInt() ?? 0,
    );
  }

  /// Catálogo completo: estático + extras Firestore (sin duplicar id).
  static Future<List<TurismoLugar>> catalogoFusionado() async {
    final extras = await fetchTodos();
    final ids = extras.map((e) => e.id).toSet();
    final base =
        TurismoCatalogoRD.lugares.where((l) => !ids.contains(l.id)).toList();
    return [...base, ...extras];
  }

  static Future<void> guardar({
    String? docId,
    required TurismoLugar lugar,
    bool activo = true,
  }) async {
    final id = docId ?? _col.doc().id;
    await _col.doc(id).set({
      'id': lugar.id,
      'nombre': lugar.nombre,
      'ciudad': lugar.ciudad,
      'subtipo': lugar.subtipo,
      'lat': lugar.lat,
      'lon': lugar.lon,
      if (lugar.descripcion != null) 'descripcion': lugar.descripcion,
      if (lugar.imagen != null) 'imagen': lugar.imagen,
      'popularidad': lugar.popularidad,
      'activo': activo,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> setActivo(String docId, bool activo) async {
    await _col.doc(docId).set({
      'activo': activo,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
