/// Perfil del conductor visible para el cliente (calificación post-viaje, etc.).
class TaxistaPerfilCliente {
  const TaxistaPerfilCliente({
    required this.nombre,
    required this.fotoUrl,
    required this.promedioEstrellas,
    required this.totalCalificaciones,
    required this.esPremium,
    this.tipoVehiculo = '',
    this.placa = '',
  });

  final String nombre;
  final String fotoUrl;
  final double promedioEstrellas;
  final int totalCalificaciones;
  final bool esPremium;
  final String tipoVehiculo;
  final String placa;

  static TaxistaPerfilCliente fromMaps({
    required Map<String, dynamic> usuario,
    Map<String, dynamic>? viaje,
    String nombreFallback = '',
  }) {
    final String nombre = _s(usuario['nombre'] ?? usuario['displayName'])
        .trim()
        .isNotEmpty
        ? _s(usuario['nombre'] ?? usuario['displayName']).trim()
        : nombreFallback.trim();

    final double suma = _num(usuario['ratingSuma']);
    final int conteo = _num(usuario['ratingConteo']).round();
    final double promedio = conteo > 0 ? suma / conteo : 0.0;

    final bool flagPremium = usuario['conductorPremium'] == true ||
        usuario['esConductorPremium'] == true ||
        _s(usuario['nivelConductor']).toLowerCase() == 'premium';
    final bool esPremium =
        flagPremium || (promedio >= 4.8 && conteo >= 20);

    String tipo = _s(viaje?['tipoVehiculo']);
    if (tipo.isEmpty) tipo = _s(usuario['tipoVehiculo']);
    String placa = _s(viaje?['placa']);
    if (placa.isEmpty) placa = _s(usuario['placa']);

    return TaxistaPerfilCliente(
      nombre: nombre.isEmpty ? 'Tu conductor' : nombre,
      fotoUrl: _s(usuario['fotoUrl']),
      promedioEstrellas: promedio.clamp(0, 5),
      totalCalificaciones: conteo,
      esPremium: esPremium,
      tipoVehiculo: tipo,
      placa: placa,
    );
  }

  static String _s(dynamic v) => (v ?? '').toString();

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }
}
