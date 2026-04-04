// lib/modelo/ubicacion.dart
class Ubicacion {
  final double latitud;
  final double longitud;
  final String? direccion;

  Ubicacion({
    required this.latitud,
    required this.longitud,
    this.direccion,
  });

  factory Ubicacion.fromMap(Map<String, dynamic> map) {
    return Ubicacion(
      latitud: (map['lat'] ?? 0.0).toDouble(),
      longitud: (map['lon'] ?? 0.0).toDouble(),
      direccion: map['direccion']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lat': latitud,
      'lon': longitud,
      'direccion': direccion,
    };
  }
}
