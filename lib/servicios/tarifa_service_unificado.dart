import 'package:cloud_firestore/cloud_firestore.dart';
// ✅ Eliminado import no utilizado de turismo_catalogo_rd.dart

class TarifaServiceUnificado {
  static final TarifaServiceUnificado _instance =
      TarifaServiceUnificado._internal();
  factory TarifaServiceUnificado() => _instance;
  TarifaServiceUnificado._internal();

  // Caché en memoria
  Map<String, dynamic>? _cacheGeneral;
  Map<String, dynamic>? _cacheTurismo;
  Map<String, dynamic>? _cachePromo;
  DateTime? _lastFetchGeneral;
  DateTime? _lastFetchTurismo;
  DateTime? _lastFetchPromo;

  static const Duration _cacheDuration = Duration(minutes: 5);

  // ==============================================================
  // TARIFAS POR TIPO DE VEHÍCULO PARA SERVICIOS NORMALES
  // ==============================================================
  static const Map<String, Map<String, double>> _tarifasVehiculos = {
    'Carro': {'base': 50.0, 'porKm': 25.0, 'minimo': 150.0},
    'Jeepeta': {'base': 80.0, 'porKm': 30.0, 'minimo': 200.0},
    'Minibús': {'base': 120.0, 'porKm': 35.0, 'minimo': 300.0},
    'Minivan': {'base': 100.0, 'porKm': 32.0, 'minimo': 250.0},
    'AutobusGuagua': {'base': 200.0, 'porKm': 45.0, 'minimo': 500.0},
  };

  // Fallbacks para servicios generales (combinado)
  static const Map<String, Map<String, double>> _fallbackGeneral = {
    'Carro': {'base': 50.0, 'porKm': 25.0, 'minimo': 150.0},
    'Jeepeta': {'base': 80.0, 'porKm': 30.0, 'minimo': 200.0},
    'Minibús': {'base': 120.0, 'porKm': 35.0, 'minimo': 300.0},
    'Minivan': {'base': 100.0, 'porKm': 32.0, 'minimo': 250.0},
    'AutobusGuagua': {'base': 200.0, 'porKm': 45.0, 'minimo': 500.0},
    'motor': {'base': 30.0, 'porKm': 12.0, 'minimo': 80.0},
  };

  // Fallbacks para turismo (cada vehículo con sus propios campos)
  static const Map<String, Map<String, dynamic>> _fallbackTurismo = {
    'carro': {
      'activo': true,
      'tarifaBase': 100.0,
      'tarifaKm': 25.0,
      'cobraPeaje': true,
      'precioMinimo': 300.0,
    },
    'jeepeta': {
      'activo': true,
      'tarifaBase': 150.0,
      'tarifaKm': 30.0,
      'cobraPeaje': true,
      'precioMinimo': 400.0,
    },
    'minivan': {
      'activo': true,
      'tarifaBase': 200.0,
      'tarifaKm': 35.0,
      'cobraPeaje': true,
      'precioMinimo': 500.0,
    },
    'bus': {
      'activo': true,
      'tarifaBase': 300.0,
      'tarifaKm': 40.0,
      'cobraPeaje': true,
      'precioMinimo': 600.0,
    },
  };

  // ==============================================================
  // 🔥 MAPEO DE SUBTIPOS DE DESTINO A TIPOS DE VEHÍCULO
  // ==============================================================
  static const Map<String, String> _mapeoSubtipoAVehiculo = {
    // Aeropuertos y transporte - usar carro por defecto
    'AEROPUERTO': 'carro',
    'MUELLE': 'carro',

    // Zonas urbanas - carro
    'ZONA_COLONIAL': 'carro',
    'CIUDAD': 'carro',

    // Playas - jeepeta es mejor para terrenos playeros
    'PLAYA': 'jeepeta',
    'RESORT': 'jeepeta',

    // Hoteles - carro
    'HOTEL': 'carro',

    // Tours - según el tipo pueden variar, pero jeepeta es versátil
    'TOUR': 'jeepeta',

    // Parques y naturaleza - jeepeta para terrenos variados
    'PARQUE': 'jeepeta',
    'MONTANA': 'jeepeta',
    'CASCADA': 'jeepeta',
    'LAGO': 'jeepeta',

    // Museos y atracciones urbanas - carro
    'MUSEO': 'carro',
    'ATRACCION': 'carro',
  };

  Future<Map<String, dynamic>> _getTarifasGenerales() async {
    if (_cacheGeneral != null &&
        _lastFetchGeneral != null &&
        DateTime.now().difference(_lastFetchGeneral!) < _cacheDuration) {
      return _cacheGeneral!;
    }
    return _recargarGenerales();
  }

  Future<Map<String, dynamic>> _getTarifasTurismo() async {
    if (_cacheTurismo != null &&
        _lastFetchTurismo != null &&
        DateTime.now().difference(_lastFetchTurismo!) < _cacheDuration) {
      return _cacheTurismo!;
    }
    return _recargarTurismo();
  }

  Future<Map<String, dynamic>> _getConfigPromo() async {
    if (_cachePromo != null &&
        _lastFetchPromo != null &&
        DateTime.now().difference(_lastFetchPromo!) < _cacheDuration) {
      return _cachePromo!;
    }
    return _recargarPromo();
  }

  Future<void> recargar() async {
    await Future.wait([
      _recargarGenerales(),
      _recargarTurismo(),
      _recargarPromo(),
    ]);
  }

  Future<Map<String, dynamic>> _recargarGenerales() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('tarifas')
          .doc('general')
          .get();

      if (doc.exists) {
        _cacheGeneral = Map<String, dynamic>.from(doc.data()!);
      } else {
        _cacheGeneral = Map<String, dynamic>.from(_fallbackGeneral);
        await FirebaseFirestore.instance
            .collection('tarifas')
            .doc('general')
            .set(_fallbackGeneral);
      }
    } catch (e) {
      _cacheGeneral = Map<String, dynamic>.from(_fallbackGeneral);
    }
    _lastFetchGeneral = DateTime.now();
    return _cacheGeneral!;
  }

  Future<Map<String, dynamic>> _recargarTurismo() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('tarifa_turismo').get();

      if (snapshot.docs.isNotEmpty) {
        final Map<String, dynamic> mapa = {};
        for (final doc in snapshot.docs) {
          mapa[doc.id] = doc.data();
        }
        _cacheTurismo = mapa;
      } else {
        final batch = FirebaseFirestore.instance.batch();
        for (final entry in _fallbackTurismo.entries) {
          final docRef = FirebaseFirestore.instance
              .collection('tarifa_turismo')
              .doc(entry.key);
          batch.set(docRef, entry.value);
        }
        await batch.commit();
        _cacheTurismo = Map<String, dynamic>.from(_fallbackTurismo);
      }
    } catch (e) {
      _cacheTurismo = Map<String, dynamic>.from(_fallbackTurismo);
    }
    _lastFetchTurismo = DateTime.now();
    return _cacheTurismo!;
  }

  Future<Map<String, dynamic>> _recargarPromo() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('promociones')
          .get();

      if (doc.exists) {
        _cachePromo = Map<String, dynamic>.from(doc.data()!);
      } else {
        _cachePromo = {
          'activa': false,
          'm': 3,
          'k': 1,
          'porcentaje': 15,
          'modo': '3x1',
          'tipo': 'mxk',
        };
      }
    } catch (e) {
      _cachePromo = {
        'activa': false,
        'm': 3,
        'k': 1,
        'porcentaje': 15,
        'modo': '3x1',
        'tipo': 'mxk',
      };
    }
    _lastFetchPromo = DateTime.now();
    return _cachePromo!;
  }

  double _aplicarDescuento(double precio, int contadorViajes) {
    if (_cachePromo == null) return precio;

    final bool activa = _cachePromo!['activa'] == true;
    if (!activa) return precio;

    final int m = _cachePromo!['m'] ?? 3;
    final int k = _cachePromo!['k'] ?? 1;
    final int porcentaje = _cachePromo!['porcentaje'] ?? 15;

    final int mFinal = m < 1 ? 1 : m;
    final int kFinal = k < 1 ? 1 : k;
    final int porcentajeFinal = porcentaje.clamp(0, 95);

    final int ciclo = mFinal + kFinal;
    final int contadorEfectivo = contadorViajes <= 0 ? 1 : contadorViajes;
    final int posicion = (contadorEfectivo - 1) % ciclo + 1;

    if (posicion <= mFinal) {
      return precio * (100 - porcentajeFinal) / 100;
    }

    return precio;
  }

  /// Turismo: **ida** = tarifa por distancia (núcleo con mínimo). **Ida y vuelta** = esa tarifa + **½** para la vuelta (1,5× el núcleo).
  /// El **peaje** no se multiplica por ese factor: ida suma [peaje] una vez; ida y vuelta suma **2× peaje** cuando `cobraPeaje`.
  double _turismoNucleoIdaVueltaYPeaje({
    required double nucleoTrayecto,
    required bool idaVuelta,
    required double peaje,
    required bool cobraPeaje,
  }) {
    final toll = (cobraPeaje && peaje > 0) ? peaje : 0.0;
    if (!idaVuelta) {
      return nucleoTrayecto + toll;
    }
    return nucleoTrayecto + 0.5 * nucleoTrayecto + toll * 2;
  }

  /// 🔥 Calcula el precio para un servicio dado.
  Future<double> calcularPrecio({
    required String tipoServicio,
    String? tipoVehiculo,
    String? subtipoTurismo,
    required double distanciaKm,
    bool idaVuelta = false,
    double peaje = 0.0,
    int contadorViajes = 1,
  }) async {
    double precioBase;

    // ===== TURISMO =====
    if (tipoServicio == 'turismo') {
      // 🔥 PASO 1: Normalizar el subtipo (de AEROPUERTO a aeropuerto)
      final String subtipoNormalizado = _normalizarSubtipo(subtipoTurismo);
      // 🔇 Prints comentados para producción
      // print('🎯 Turismo - Subtipo original: $subtipoTurismo');
      // print('🎯 Turismo - Subtipo normalizado: $subtipoNormalizado');

      // 🔥 PASO 2: Determinar qué tipo de vehículo usar para este subtipo
      // Si ya viene tipoVehiculo, lo respetamos, si no, usamos el mapeo
      final String vehiculoParaConfig =
          tipoVehiculo ?? _mapeoSubtipoAVehiculo[subtipoNormalizado] ?? 'carro';
      // print('🎯 Turismo - Vehículo a usar: $vehiculoParaConfig');

      final tarifas = await _getTarifasTurismo();
      final config = tarifas[vehiculoParaConfig];

      if (config == null) {
        // Si no hay configuración, usar fallback
        // print('⚠️ No hay configuración para $vehiculoParaConfig, usando fallback');
        return _calcularPrecioTurismoFallback(
          tipoVehiculo: vehiculoParaConfig,
          distanciaKm: distanciaKm,
          idaVuelta: idaVuelta,
          peaje: peaje,
          contadorViajes: contadorViajes,
        );
      }

      final activo = config['activo'] ?? true;
      if (!activo) {
        // print('⚠️ Servicio $vehiculoParaConfig inactivo, usando fallback');
        return _calcularPrecioTurismoFallback(
          tipoVehiculo: vehiculoParaConfig,
          distanciaKm: distanciaKm,
          idaVuelta: idaVuelta,
          peaje: peaje,
          contadorViajes: contadorViajes,
        );
      }

      final base = (config['tarifaBase'] as num).toDouble();
      final porKm = (config['tarifaKm'] as num).toDouble();
      final minimo = (config['precioMinimo'] as num).toDouble();
      final cobraPeaje = config['cobraPeaje'] ?? true;

      var nucleo = base + (distanciaKm * porKm);
      if (nucleo < minimo) nucleo = minimo;
      precioBase = _turismoNucleoIdaVueltaYPeaje(
        nucleoTrayecto: nucleo,
        idaVuelta: idaVuelta,
        peaje: peaje,
        cobraPeaje: cobraPeaje,
      );
    }

    // ===== MOTOR =====
    else if (tipoServicio == 'motor') {
      final tarifas = await _getTarifasGenerales();
      final config = tarifas['motor'];

      if (config == null) {
        throw ArgumentError('Configuración de motor no encontrada');
      }

      final base = (config['base'] as num).toDouble();
      final porKm = (config['porKm'] as num).toDouble();
      final minimo = (config['minimo'] as num).toDouble();

      precioBase = base + (distanciaKm * porKm);
      if (precioBase < minimo) precioBase = minimo;
      if (peaje > 0) precioBase += peaje;
    }

    // ===== NORMAL =====
    else if (tipoServicio == 'normal') {
      if (tipoVehiculo == null) {
        throw ArgumentError(
            'tipoVehiculo es requerido para servicios normales');
      }

      final tarifas = await _getTarifasGenerales();

      double base = 50.0;
      double porKm = 25.0;
      double minimo = 150.0;

      if (tarifas.containsKey(tipoVehiculo)) {
        final rawConfig = tarifas[tipoVehiculo];
        if (rawConfig is Map) {
          base = (rawConfig['base'] as num?)?.toDouble() ?? base;
          porKm = (rawConfig['porKm'] as num?)?.toDouble() ?? porKm;
          minimo = (rawConfig['minimo'] as num?)?.toDouble() ?? minimo;
        }
      }

      precioBase = base + (distanciaKm * porKm);
      if (precioBase < minimo) precioBase = minimo;
      if (peaje > 0) precioBase += peaje;
    } else {
      throw ArgumentError('Tipo de servicio no válido: $tipoServicio');
    }

    // Ida y vuelta (turismo ya aplicado arriba: ida completa + ½ vuelta + peaje sin ×1,8)
    if (idaVuelta && tipoServicio != 'turismo') {
      precioBase *= 1.8;
    }

    // Aplicar promoción si está activa
    await _getConfigPromo();
    final precioFinal = _aplicarDescuento(precioBase, contadorViajes);

    return precioFinal;
  }

  /// 🔥 Función de normalización de subtipos
  String _normalizarSubtipo(String? subtipo) {
    if (subtipo == null) return 'CIUDAD';

    // Convertir a mayúsculas para comparar con las constantes
    final subtipoUpper = subtipo.toUpperCase();

    // Lista de subtipos válidos
    const subtiposValidos = [
      'AEROPUERTO',
      'MUELLE',
      'ZONA_COLONIAL',
      'CIUDAD',
      'PLAYA',
      'RESORT',
      'HOTEL',
      'TOUR',
      'PARQUE',
      'MONTANA',
      'CASCADA',
      'LAGO',
      'MUSEO',
      'ATRACCION',
    ];

    // Si ya es válido, devolverlo
    if (subtiposValidos.contains(subtipoUpper)) {
      return subtipoUpper;
    }

    // Mapeo de strings comunes
    if (subtipoUpper.contains('AEROPUERTO') ||
        subtipoUpper.contains('AIRPORT') ||
        subtipoUpper.contains('SDQ') ||
        subtipoUpper.contains('PUJ') ||
        subtipoUpper.contains('STI')) {
      return 'AEROPUERTO';
    }
    if (subtipoUpper.contains('PLAYA') || subtipoUpper.contains('BEACH')) {
      return 'PLAYA';
    }
    if (subtipoUpper.contains('MUELLE') || subtipoUpper.contains('PUERTO')) {
      return 'MUELLE';
    }
    if (subtipoUpper.contains('ZONA') && subtipoUpper.contains('COLONIAL')) {
      return 'ZONA_COLONIAL';
    }
    if (subtipoUpper.contains('CIUDAD') || subtipoUpper.contains('CENTRO')) {
      return 'CIUDAD';
    }
    if (subtipoUpper.contains('RESORT')) {
      return 'RESORT';
    }
    if (subtipoUpper.contains('HOTEL')) {
      return 'HOTEL';
    }
    if (subtipoUpper.contains('TOUR') || subtipoUpper.contains('EXCURSION')) {
      return 'TOUR';
    }
    if (subtipoUpper.contains('PARQUE') || subtipoUpper.contains('PARK')) {
      return 'PARQUE';
    }
    if (subtipoUpper.contains('MONTANA') || subtipoUpper.contains('MONTAÑA')) {
      return 'MONTANA';
    }
    if (subtipoUpper.contains('CASCADA') || subtipoUpper.contains('SALTO')) {
      return 'CASCADA';
    }
    if (subtipoUpper.contains('LAGO') || subtipoUpper.contains('LAGUNA')) {
      return 'LAGO';
    }
    if (subtipoUpper.contains('MUSEO')) {
      return 'MUSEO';
    }

    // Fallback
    return 'CIUDAD';
  }

  /// 🔥 Función de fallback para turismo
  double _calcularPrecioTurismoFallback({
    required String tipoVehiculo,
    required double distanciaKm,
    required bool idaVuelta,
    required double peaje,
    required int contadorViajes,
  }) {
    // Tarifas base de fallback por tipo de vehículo
    const fallbackPorVehiculo = {
      'carro': {'base': 100.0, 'km': 25.0, 'minimo': 300.0},
      'jeepeta': {'base': 150.0, 'km': 30.0, 'minimo': 400.0},
      'minivan': {'base': 200.0, 'km': 35.0, 'minimo': 500.0},
      'bus': {'base': 300.0, 'km': 40.0, 'minimo': 600.0},
    };

    final config =
        fallbackPorVehiculo[tipoVehiculo] ?? fallbackPorVehiculo['carro']!;

    var nucleo = config['base']! + (distanciaKm * config['km']!);
    if (nucleo < config['minimo']!) nucleo = config['minimo']!;
    final precio = _turismoNucleoIdaVueltaYPeaje(
      nucleoTrayecto: nucleo,
      idaVuelta: idaVuelta,
      peaje: peaje,
      cobraPeaje: true,
    );

    return _aplicarDescuento(precio, contadorViajes);
  }

  /// Obtiene la descripción de la promoción actual
  Future<String> getDescripcionPromocion() async {
    await _getConfigPromo();
    if (_cachePromo == null) return 'Sin promoción';

    final bool activa = _cachePromo!['activa'] == true;
    if (!activa) return 'Promoción inactiva';

    final int m = _cachePromo!['m'] ?? 3;
    final int k = _cachePromo!['k'] ?? 1;
    final int porcentaje = _cachePromo!['porcentaje'] ?? 15;

    return '${m}x$k - $porcentaje% descuento';
  }

  /// Verifica si un viaje aplica descuento según el contador
  Future<bool> aplicaDescuento(int contadorViajes) async {
    await _getConfigPromo();
    if (_cachePromo == null) return false;

    final bool activa = _cachePromo!['activa'] == true;
    if (!activa) return false;

    final int m = _cachePromo!['m'] ?? 3;
    final int k = _cachePromo!['k'] ?? 1;
    final int ciclo = m + k;
    final int contadorEfectivo = contadorViajes <= 0 ? 1 : contadorViajes;
    final int posicion = (contadorEfectivo - 1) % ciclo + 1;

    return posicion <= m;
  }

  /// Snapshot auditable de la promo aplicada para un contador concreto.
  Future<Map<String, dynamic>> construirPromoSnapshot(
      int contadorViajes) async {
    await _getConfigPromo();
    final cfg = _cachePromo ?? <String, dynamic>{};

    final bool activa = cfg['activa'] == true;
    final int m = ((cfg['m'] as num?)?.toInt() ?? 3).clamp(1, 999);
    final int k = ((cfg['k'] as num?)?.toInt() ?? 1).clamp(1, 999);
    final int porcentaje =
        ((cfg['porcentaje'] as num?)?.toInt() ?? 15).clamp(0, 95);
    final int ciclo = m + k;
    final int contadorEfectivo = contadorViajes <= 0 ? 1 : contadorViajes;
    final int posicion = (contadorEfectivo - 1) % ciclo + 1;
    final bool aplica = activa && (posicion <= m);

    return <String, dynamic>{
      'activa': activa,
      'tipo': (cfg['tipo'] ?? 'mxk').toString(),
      'modo': (cfg['modo'] ?? '${m}x$k').toString(),
      'm': m,
      'k': k,
      'porcentaje': porcentaje,
      'ciclo': ciclo,
      'contadorViajesEvaluado': contadorEfectivo,
      'posicionCiclo': posicion,
      'aplicaDescuento': aplica,
      'version': 1,
      'calculadoEn': DateTime.now().toIso8601String(),
    };
  }

  /// Obtiene los tipos de vehículo disponibles para servicios normales
  List<String> getTiposVehiculoNormales() {
    return _tarifasVehiculos.keys.toList();
  }

  /// Verifica si un tipo de vehículo es válido para servicios normales
  bool esTipoVehiculoValido(String tipoVehiculo) {
    return _tarifasVehiculos.containsKey(tipoVehiculo);
  }

  Future<Map<String, dynamic>> getConfigGeneral() => _getTarifasGenerales();
  Future<Map<String, dynamic>> getConfigTurismo() => _getTarifasTurismo();
  Future<Map<String, dynamic>> getConfigPromo() => _getConfigPromo();
}
