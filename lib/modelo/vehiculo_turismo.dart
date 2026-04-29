// lib/modelo/vehiculo_turismo.dart
class VehiculoTurismo {
  final String tipo; // 'carro', 'jeepeta', 'minivan', 'bus'
  final String marca;
  final String modelo;
  final String color;
  final String placa;
  final int anio; // 👈 CAMBIADO de "año" a "anio"
  final String? fotoUrl;

  VehiculoTurismo({
    required this.tipo,
    required this.marca,
    required this.modelo,
    required this.color,
    required this.placa,
    required this.anio, // 👈 CAMBIADO
    this.fotoUrl,
  });

  factory VehiculoTurismo.fromMap(Map<String, dynamic> map) {
    return VehiculoTurismo(
      tipo: map['tipo'] ?? '',
      marca: map['marca'] ?? '',
      modelo: map['modelo'] ?? '',
      color: map['color'] ?? '',
      placa: map['placa'] ?? '',
      anio: map['anio'] ?? 0, // 👈 CAMBIADO (en Firebase debe ser "anio")
      fotoUrl: map['fotoUrl']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tipo': tipo,
      'marca': marca,
      'modelo': modelo,
      'color': color,
      'placa': placa,
      'anio': anio, // 👈 CAMBIADO
      'fotoUrl': fotoUrl,
    };
  }

  String get nombreCompleto => '$marca $modelo ($color)';

  String get tipoLabel {
    switch (tipo) {
      case 'carro':
        return '🚗 Carro Turismo';
      case 'jeepeta':
        return '🚙 Jeepeta Turismo';
      case 'minivan':
        return '🚐 Minivan Turismo';
      case 'bus':
        return '🚌 Bus Turismo';
      default:
        return tipo;
    }
  }
}
