import 'package:flygo_nuevo/servicios/lugares_service.dart';
import 'package:flygo_nuevo/servicios/rai_asistente_service.dart';
import 'package:flygo_nuevo/utils/rai_destino_desde_voz.dart';

/// Resultado de resolver texto dictado/escrito → lugares con coordenadas.
class RaiAplicarDestinoDesdeVozResult {
  const RaiAplicarDestinoDesdeVozResult({
    required this.consultaPlaces,
    required this.candidatos,
    this.lugarConfiable,
  });

  final String consultaPlaces;
  final List<DetalleLugar> candidatos;
  /// Lugar para aplicar sin overlay si la confianza es alta (misma regla que el asistente FAB).
  final DetalleLugar? lugarConfiable;

  bool get encontroAlgo => candidatos.isNotEmpty;
}

/// Resolución compartida: voz del buscador, sheet inteligente y asistente RAI.
class RaiAplicarDestinoDesdeVoz {
  RaiAplicarDestinoDesdeVoz._();

  static Future<RaiAplicarDestinoDesdeVozResult> resolver({
    required String textoReconocido,
    double? biasLat,
    double? biasLon,
    bool desdeVoz = false,
  }) async {
    final raw = textoReconocido.trim();
    if (raw.length < 2) {
      return const RaiAplicarDestinoDesdeVozResult(
        consultaPlaces: '',
        candidatos: [],
      );
    }

    final analisis = RaiDestinoDesdeVoz.analizar(raw);
    final buscarDestino = analisis.tieneDestinoParaBuscar ||
        analisis.esDireccionDirecta ||
        analisis.esPedidoDestino;
    final consulta = buscarDestino ? analisis.consultaPlaces : raw;

    if (consulta.length < 2) {
      return RaiAplicarDestinoDesdeVozResult(
        consultaPlaces: raw,
        candidatos: const [],
      );
    }

    final res = await RaiAsistenteService.instance.resolverDireccionCompleja(
      descripcion: consulta,
      biasLat: biasLat,
      biasLon: biasLon,
    );

    final mejor =
        res.mejor ?? (res.lugares.isNotEmpty ? res.lugares.first : null);
    DetalleLugar? confiable;
    if (mejor != null) {
      final bool confianzaAlta = RaiDestinoDesdeVoz.confianzaAltaEnPrimerResultado(
        consulta: consulta,
        displayLabel: mejor.displayLabel,
        totalResultados: res.lugares.length,
      );
      // Voz: un solo resultado o frase larga con buen match → aplicar sin paso extra.
      if (confianzaAlta ||
          (desdeVoz &&
              res.lugares.length == 1 &&
              consulta.length >= 8) ||
          (desdeVoz &&
              consulta.length >= 20 &&
              confianzaAltaEnPrimerResultadoRelajada(
                consulta: consulta,
                displayLabel: mejor.displayLabel,
              ))) {
        confiable = mejor;
      }
    }

    return RaiAplicarDestinoDesdeVozResult(
      consultaPlaces: consulta,
      candidatos: res.lugares,
      lugarConfiable: confiable,
    );
  }

  /// Dictado: acepta match si comparte palabras clave aunque el label sea más largo.
  static bool confianzaAltaEnPrimerResultadoRelajada({
    required String consulta,
    required String displayLabel,
  }) {
    final q = consulta.toLowerCase().trim();
    final label = displayLabel.toLowerCase();
    if (q.length < 12 || label.length < 8) return false;
    final tokens = q
        .split(RegExp(r'[^a-záéíóúñ0-9]+', unicode: true))
        .where((w) => w.length > 3)
        .take(10)
        .toList();
    if (tokens.isEmpty) return false;
    var hits = 0;
    for (final t in tokens) {
      if (label.contains(t)) hits++;
    }
    return hits >= (tokens.length <= 3 ? 1 : 2);
  }
}
