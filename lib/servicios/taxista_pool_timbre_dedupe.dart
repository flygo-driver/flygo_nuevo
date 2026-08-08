/// Dedupe compartido entre listeners de timbre (pool normal, Bola, turismo).
class TaxistaPoolTimbreDedupe {
  TaxistaPoolTimbreDedupe._();

  static final TaxistaPoolTimbreDedupe instance = TaxistaPoolTimbreDedupe._();

  final Set<String> _vistos = <String>{};

  bool yaVisto(String clave) => _vistos.contains(clave);

  bool marcarSiNuevo(String clave) {
    if (_vistos.contains(clave)) return false;
    _vistos.add(clave);
    return true;
  }

  void marcarVisto(String clave) => _vistos.add(clave);
}
