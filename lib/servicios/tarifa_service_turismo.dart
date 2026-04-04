// lib/servicios/tarifa_service_turismo.dart

/// Servicio SEPARADO para calcular tarifas de turismo
/// NO toca la lógica normal de tarifas
class TarifaServiceTurismo {
  /// Tarifas base por tipo de vehículo turístico (RD$)
  static const Map<String, double> tarifasBase = {
    'carro': 2500.0,      // Carro turismo
    'jeepeta': 3500.0,    // Jeepeta turismo
    'minivan': 5000.0,    // Minivan turismo
    'bus': 8000.0,        // Bus turismo
  };

  /// Porcentajes adicionales por distancia (por km sobre base)
  static const Map<String, double> porcentajePorKm = {
    'carro': 0.05,        // 5% del precio base por km extra
    'jeepeta': 0.04,      // 4%
    'minivan': 0.03,      // 3%
    'bus': 0.02,          // 2%
  };

  /// Catálogo de destinos turísticos con tarifas fijas
  /// ✅ MEJORADO: Tipos explícitos y más destinos
  static final Map<String, Map<String, double>> catalogoDestinos = {
    'aeropuerto_las_americas': {
      'carro': 1800.0,
      'jeepeta': 2800.0,
      'minivan': 4000.0,
      'bus': 6500.0,
    },
    'punta_cana': {
      'carro': 3500.0,
      'jeepeta': 5000.0,
      'minivan': 7000.0,
      'bus': 10000.0,
    },
    'puerto_plata': {
      'carro': 2800.0,
      'jeepeta': 4200.0,
      'minivan': 5800.0,
      'bus': 8500.0,
    },
  };

  /// Calcula tarifa para servicio turístico
  /// [subtipoTurismo]: 'carro' | 'jeepeta' | 'minivan' | 'bus'
  /// [distanciaKm]: distancia estimada (para cálculo semi-fijo)
  /// [destinoId]: ID del destino en catálogo (null para cálculo por km)
  static double calcularTarifa({
    required String subtipoTurismo,
    double distanciaKm = 0.0,
    String? destinoId,
  }) {
    final String clave = subtipoTurismo.toLowerCase();
    
    // ✅ VALIDACIÓN: Subtipo debe existir
    if (!tarifasBase.containsKey(clave)) {
      throw ArgumentError('Subtipo de turismo no válido: $subtipoTurismo');
    }
    
    // 1) Si hay destino en catálogo, usa tarifa fija
    if (destinoId != null && catalogoDestinos.containsKey(destinoId)) {
      final tarifasDestino = catalogoDestinos[destinoId]!;
      return tarifasDestino[clave] ?? tarifasBase[clave]!;
    }
    
    // 2) Tarifa semi-fija: base + porcentaje por km
    final double base = tarifasBase[clave]!;
    final double porcentaje = porcentajePorKm[clave]!;
    
    double tarifa = base;
    
    // Aplicar porcentaje por km si hay distancia
    if (distanciaKm > 0) {
      final adicional = base * porcentaje * distanciaKm;
      tarifa += adicional;
    }
    
    return double.parse(tarifa.toStringAsFixed(2));
  }

  /// Verifica si un vehículo es de tipo turismo
  static bool esVehiculoTurismo(String tipoVehiculo) {
    final t = tipoVehiculo.toLowerCase();
    return t.contains('turismo') ||
           tarifasBase.keys.any((key) => t.contains(key));
  }

  /// Obtiene lista de subtipos de turismo disponibles
  static List<String> get subtiposDisponibles =>
      tarifasBase.keys.toList();

  /// Obtiene lista de destinos del catálogo
  static List<String> get destinosDisponibles =>
      catalogoDestinos.keys.toList();

  /// ✅ NUEVO: Obtiene subtipos válidos para UI
  static List<Map<String, dynamic>> get opcionesParaUI {
    return [
      {'value': 'carro', 'label': 'Carro Turismo', 'icon': '🚗'},
      {'value': 'jeepeta', 'label': 'Jeepeta Turismo', 'icon': '🚙'},
      {'value': 'minivan', 'label': 'Minivan Turismo', 'icon': '🚐'},
      {'value': 'bus', 'label': 'Bus Turismo', 'icon': '🚌'},
    ];
  }
}