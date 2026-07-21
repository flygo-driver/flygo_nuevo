import 'package:flygo_nuevo/modelos/corporativo_models.dart';

/// Numeración estable de rutas corporativas por empresa (Ruta 1, Ruta 2, …).
abstract final class CorporativoRutaEnumeracion {
  CorporativoRutaEnumeracion._();

  static int _minutosHora(String hora) {
    final parts = hora.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return h * 60 + m;
  }

  /// Orden fijo: hora de recogida → nombre → id de plantilla.
  static List<CorporativoPlantilla> ordenar(List<CorporativoPlantilla> items) {
    final list = List<CorporativoPlantilla>.from(items);
    list.sort((a, b) {
      final hc = _minutosHora(a.horaRecogidaGrupo)
          .compareTo(_minutosHora(b.horaRecogidaGrupo));
      if (hc != 0) return hc;
      final nc = a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      if (nc != 0) return nc;
      return a.id.compareTo(b.id);
    });
    return list;
  }

  static Map<String, int> mapaNumeros(List<CorporativoPlantilla> plantillas) {
    final ordenadas = ordenar(plantillas);
    return {
      for (var i = 0; i < ordenadas.length; i++) ordenadas[i].id: i + 1,
    };
  }

  static int numeroDe(
    List<CorporativoPlantilla> plantillas,
    String plantillaId,
  ) {
    return mapaNumeros(plantillas)[plantillaId] ?? 0;
  }

  static String etiquetaNumero(int numero) {
    if (numero <= 0) return 'Ruta';
    return 'Ruta $numero';
  }

  /// Título principal: «Ruta 2 · Mañana» o solo «Ruta 2» si no hay nombre.
  static String titulo(CorporativoPlantilla pl, int numero) {
    final nom = pl.nombre.trim();
    if (numero <= 0) return nom.isEmpty ? 'Ruta' : nom;
    if (nom.isEmpty) return etiquetaNumero(numero);
    return '${etiquetaNumero(numero)} · $nom';
  }

  /// Subtítulo con nombre cuando el título ya lleva solo el número.
  static String? subtituloNombre(CorporativoPlantilla pl, int numero) {
    final nom = pl.nombre.trim();
    if (nom.isEmpty || numero <= 0) return null;
    return nom;
  }
}
