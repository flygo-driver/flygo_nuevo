/// Configuración admin de tarifas por tramos de distancia (`config/tarifas_tramos`).
class TarifasTramosConfig {
  const TarifasTramosConfig({
    required this.activo,
    required this.tramosKm,
    required this.minimoLargaDistanciaRd,
    required this.promoAplicaSoloTramoLocal,
    required this.porVehiculo,
    required this.distanciaMaximaCotizableKm,
  });

  final bool activo;
  final List<double> tramosKm;
  final double minimoLargaDistanciaRd;
  final bool promoAplicaSoloTramoLocal;
  /// Tope de seguridad RD (carretera); no es tope comercial — tramo 140+ sigue sin límite inferior.
  final double distanciaMaximaCotizableKm;

  /// Clave vehículo → lista RD$/km por tramo (longitud = tramosKm.length + 1).
  final Map<String, List<double>> porVehiculo;

  static const List<double> tramosKmDefault = <double>[40, 80, 140];
  static const double distanciaMaximaDefaultKm = 800;

  static TarifasTramosConfig inactiva() => const TarifasTramosConfig(
        activo: false,
        tramosKm: tramosKmDefault,
        minimoLargaDistanciaRd: 1200,
        promoAplicaSoloTramoLocal: true,
        porVehiculo: <String, List<double>>{},
        distanciaMaximaCotizableKm: distanciaMaximaDefaultKm,
      );

  /// Defaults listos para pruebas reales (activar tramos en ADM).
  static TarifasTramosConfig defaultsPrueba() => const TarifasTramosConfig(
        activo: false,
        tramosKm: tramosKmDefault,
        minimoLargaDistanciaRd: 1200,
        promoAplicaSoloTramoLocal: true,
        distanciaMaximaCotizableKm: distanciaMaximaDefaultKm,
        porVehiculo: <String, List<double>>{
          'Carro': <double>[22, 40, 53, 63],
          'Jeepeta': <double>[30, 50, 65, 80],
          'Minivan': <double>[32, 52, 68, 82],
          'Minibús': <double>[35, 55, 70, 85],
          'AutobusGuagua': <double>[45, 65, 80, 95],
          'motor': <double>[12, 22, 35, 42],
          'carro': <double>[22, 40, 53, 63],
          'jeepeta': <double>[30, 50, 65, 80],
          'minivan': <double>[35, 55, 70, 85],
          'bus': <double>[45, 65, 80, 95],
        },
      );

  static TarifasTramosConfig fromFirestore(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return inactiva();

    final tramosRaw = data['tramosKm'];
    final List<double> tramos = <double>[];
    if (tramosRaw is List) {
      for (final v in tramosRaw) {
        if (v is num && v.isFinite && v > 0) tramos.add(v.toDouble());
      }
      tramos.sort();
    }
    if (tramos.isEmpty) tramos.addAll(tramosKmDefault);

    final porVehiculo = <String, List<double>>{};
    final pv = data['porVehiculo'];
    if (pv is Map) {
      for (final entry in pv.entries) {
        final key = entry.key.toString().trim();
        if (key.isEmpty) continue;
        final rates = _parseRates(entry.value, tramos.length + 1);
        if (rates != null) porVehiculo[key] = rates;
      }
    }

    final minLarga = (data['minimoLargaDistanciaRd'] as num?)?.toDouble();
    final maxKm = (data['distanciaMaximaCotizableKm'] as num?)?.toDouble();
    return TarifasTramosConfig(
      activo: data['activo'] == true,
      tramosKm: tramos,
      minimoLargaDistanciaRd:
          (minLarga != null && minLarga > 0) ? minLarga : 1200,
      promoAplicaSoloTramoLocal: data['promoAplicaSoloTramoLocal'] != false,
      porVehiculo: porVehiculo,
      distanciaMaximaCotizableKm: (maxKm != null && maxKm >= 100)
          ? maxKm
          : distanciaMaximaDefaultKm,
    );
  }

  Map<String, dynamic> toFirestore() {
    final porVehiculoMap = <String, dynamic>{};
    for (final e in porVehiculo.entries) {
      porVehiculoMap[e.key] = <String, dynamic>{'porKmPorTramo': e.value};
    }
    return <String, dynamic>{
      'activo': activo,
      'tramosKm': tramosKm,
      'minimoLargaDistanciaRd': minimoLargaDistanciaRd,
      'promoAplicaSoloTramoLocal': promoAplicaSoloTramoLocal,
      'distanciaMaximaCotizableKm': distanciaMaximaCotizableKm,
      'porVehiculo': porVehiculoMap,
      'version': 1,
    };
  }

  /// Etiquetas legibles por tramo (último = "140+ km" si el límite es 140).
  List<String> etiquetasTramos() {
    if (tramosKm.isEmpty) return const <String>['Total'];
    final out = <String>[];
    var desde = 0.0;
    for (var i = 0; i < tramosKm.length; i++) {
      final hasta = tramosKm[i];
      out.add('${desde.toStringAsFixed(0)}–${hasta.toStringAsFixed(0)} km');
      desde = hasta;
    }
    out.add('${desde.toStringAsFixed(0)}+ km');
    return out;
  }

  static String normalizarClaveVehiculo(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return t;
    final lower = t.toLowerCase();
    if (lower.contains('motor') || lower.contains('moto')) return 'motor';
    if (lower.contains('jeep')) return 'Jeepeta';
    if (lower.contains('minivan')) return 'Minivan';
    if (lower.contains('minib')) return 'Minibús';
    if (lower.contains('guagua') ||
        lower.contains('autobus') ||
        lower.contains('autobús') ||
        lower.contains('bus')) {
      return 'AutobusGuagua';
    }
    if (lower == 'carro' || lower.contains('carro')) return 'Carro';
    return t;
  }

  List<double>? ratesFor(String claveVehiculo, {required double porKmLocal}) {
    final key = normalizarClaveVehiculo(claveVehiculo);
    if (key.isEmpty) return null;
    final direct = porVehiculo[key];
    if (direct != null && direct.isNotEmpty) return direct;

    final lower = key.toLowerCase();
    for (final e in porVehiculo.entries) {
      if (e.key.toLowerCase() == lower) return e.value;
    }
    return null;
  }

  bool distanciaCotizable(double km) =>
      km.isFinite && km > 0 && km <= distanciaMaximaCotizableKm + 1e-6;

  static List<double>? _parseRates(Object? raw, int expectedLen) {
    if (raw is! Map) return null;
    final listRaw = raw['porKmPorTramo'];
    if (listRaw is! List) return null;
    final out = <double>[];
    for (final v in listRaw) {
      if (v is num && v.isFinite && v >= 0) out.add(v.toDouble());
    }
    if (out.length != expectedLen) return null;
    return out;
  }

  static List<double> defaultRatesFor({
    required double porKmLocal,
    List<double> tramos = tramosKmDefault,
  }) {
    return <double>[
      porKmLocal,
      porKmLocal * 1.8,
      porKmLocal * 2.4,
      porKmLocal * 2.88,
    ].take(tramos.length + 1).toList(growable: false);
  }
}
