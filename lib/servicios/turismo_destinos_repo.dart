import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/servicios/lugares_service.dart';
import 'package:flygo_nuevo/servicios/turismo_catalogo_rd.dart';

/// Destinos turísticos extra en Firestore (ADM). Se fusionan con el catálogo estático.
class TurismoDestinosRepo {
  static final _col = FirebaseFirestore.instance.collection('turismo_destinos');

  static Stream<List<TurismoLugar>> streamDestinosActivos() {
    return _col
        .where('activo', isEqualTo: true)
        .limit(200)
        .snapshots()
        .map((s) => s.docs.map(_fromDoc).whereType<TurismoLugar>().toList()
          ..sort((a, b) => a.nombre.compareTo(b.nombre)));
  }

  static Future<List<TurismoLugar>> fetchTodos({int limit = 300}) async {
    final snap = await _col.orderBy('nombre').limit(limit).get();
    return snap.docs.map(_fromDoc).whereType<TurismoLugar>().toList();
  }

  static Future<List<TurismoLugar>> fetchActivos({int limit = 200}) async {
    final snap = await _col.where('activo', isEqualTo: true).limit(limit).get();
    final list = snap.docs.map(_fromDoc).whereType<TurismoLugar>().toList();
    list.sort((a, b) => a.nombre.compareTo(b.nombre));
    return list;
  }

  static TurismoLugar? _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final latRaw = (m['lat'] as num?)?.toDouble();
    final lonRaw = (m['lon'] as num?)?.toDouble();
    if (latRaw == null || lonRaw == null) return null;

    final coords = TurismoCatalogoRD.corregirCoordenadasRd(latRaw, lonRaw);
    if (coords == null) return null;

    final subtipo = TurismoCatalogoRD.normalizarSubtipo(
      (m['subtipo'] ?? TurismoCatalogoRD.ciudad).toString(),
    );

    return TurismoLugar(
      id: (m['id'] ?? d.id).toString(),
      nombre: (m['nombre'] ?? '').toString().trim(),
      ciudad: (m['ciudad'] ?? '').toString().trim(),
      subtipo: subtipo,
      lat: coords.lat,
      lon: coords.lon,
      descripcion: (m['descripcion'] as String?),
      imagen: (m['imagen'] as String?),
      popularidad: (m['popularidad'] as num?)?.toInt() ?? 0,
    );
  }

  /// Catálogo cliente: estático + extras Firestore activos (sin duplicar id).
  static Future<List<TurismoLugar>> catalogoFusionado() async {
    final extras = await fetchActivos();
    final ids = extras.map((e) => e.id).toSet();
    final base =
        TurismoCatalogoRD.lugares.where((l) => !ids.contains(l.id)).toList();
    return [...base, ...extras];
  }

  /// Resuelve coords válidas; geocodifica si el doc no las tiene bien guardadas.
  static Future<TurismoLugar?> resolverLugarCotizable(TurismoLugar lugar) async {
    final fixed = TurismoCatalogoRD.corregirCoordenadasRd(lugar.lat, lugar.lon);
    if (fixed != null) {
      if (fixed.lat == lugar.lat && fixed.lon == lugar.lon) return lugar;
      return lugar.copyWith(lat: fixed.lat, lon: fixed.lon);
    }

    final hint = lugar.ciudad.trim().isNotEmpty
        ? '${lugar.nombre}, ${lugar.ciudad}, República Dominicana'
        : '${lugar.nombre}, República Dominicana';

    final det = await LugaresService.instance.detalle(
      'geocoded:turismo_${lugar.id}',
      hintDireccion: hint,
    );
    if (det == null) return null;

    final geo = TurismoCatalogoRD.corregirCoordenadasRd(det.lat, det.lon);
    if (geo == null) return null;

    return lugar.copyWith(lat: geo.lat, lon: geo.lon);
  }

  static Future<void> guardar({
    String? docId,
    required TurismoLugar lugar,
    bool activo = true,
  }) async {
    final coords = TurismoCatalogoRD.corregirCoordenadasRd(lugar.lat, lugar.lon);
    if (coords == null) {
      throw ArgumentError(
        'Coordenadas inválidas para RD. Revisa lat/lon (¿invertidos?).',
      );
    }

    final subtipo = TurismoCatalogoRD.normalizarSubtipo(lugar.subtipo);
    final id = docId ?? _col.doc().id;

    await _col.doc(id).set({
      'id': lugar.id,
      'nombre': lugar.nombre.trim(),
      'ciudad': lugar.ciudad.trim(),
      'subtipo': subtipo,
      'lat': coords.lat,
      'lon': coords.lon,
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
