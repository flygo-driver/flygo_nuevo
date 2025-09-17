// lib/utils/calculos/estados.dart
class EstadosViaje {
  // ====== Estados base ======
  static const String pendiente = 'pendiente';
  static const String enCurso = 'en_curso';
  static const String completado = 'completado';
  static const String cancelado = 'cancelado';
  static const String rechazado = 'rechazado';
  static const String pendientePago = 'pendiente_pago';

  // ====== Flujo ampliado ======
  static const String aceptado = 'aceptado';
  static const String enCaminoPickup = 'en_camino_pickup';
  static const String aBordo = 'a_bordo';

  // Aliases que aún pueden aparecer en código o BD
  static const Set<String> _aliasEnCaminoPickup = {
    'en_camino_pickup',
    'encaminopickup',
    'encamino_pickup',
    'encamino',
    'encamino al pickup',
    'encaminoalpickup',
    'encaminopick-up',
    'encaminopick_up',
    'encaminopick up',
    'encaminoalpick',
    'encaminopick',
    'encaminoalpikup',
    'encaminopikup',
  };

  static const Set<String> _aliasABordo = {
    'a_bordo',
    'abordo',
    'a bordo',
  };

  static const Set<String> _aliasEnCurso = {
    'en_curso',
    'encurso',
    'en curso',
    'encurZo' // por si acaso alguien tipeó raro 😅
  };

  static const Set<String> activos = {
    pendiente,
    pendientePago,
    aceptado,
    enCaminoPickup,
    aBordo,
    enCurso,
    // por compatibilidad si llegan “crudos” sin normalizar
    'abordo',
    'encaminopickup',
    'encurso',
  };

  static const Set<String> terminales = {completado, cancelado, rechazado};

  // ====== Normalización ======
  static String normalizar(String estado) {
    final s = (estado.isEmpty ? '' : estado.trim().toLowerCase());

    if (_aliasEnCaminoPickup.contains(s)) return enCaminoPickup;
    if (_aliasABordo.contains(s)) return aBordo;
    if (_aliasEnCurso.contains(s)) return enCurso;

    switch (s) {
      case pendiente:
        return pendiente;
      case aceptado:
        return aceptado;
      case enCurso:
        return enCurso;
      case completado:
        return completado;
      case cancelado:
        return cancelado;
      case rechazado:
        return rechazado;
      case pendientePago:
        return pendientePago;
      default:
        // ante algo desconocido, regrésalo a pendiente para no romper flujos
        return pendiente;
    }
  }

  // ====== Helpers ======
  static bool esPendiente(String e) => normalizar(e) == pendiente;
  static bool esPendientePago(String e) => normalizar(e) == pendientePago;
  static bool esAceptado(String e) => normalizar(e) == aceptado;
  static bool esEnCaminoPickup(String e) => normalizar(e) == enCaminoPickup;
  static bool esAbordo(String e) => normalizar(e) == aBordo;
  static bool esEnCurso(String e) => normalizar(e) == enCurso;
  static bool esCompletado(String e) => normalizar(e) == completado;
  static bool esCancelado(String e) => normalizar(e) == cancelado;
  static bool esRechazado(String e) => normalizar(e) == rechazado;

  static bool esActivo(String e) => activos.contains(normalizar(e));
  static bool esTerminal(String e) => terminales.contains(normalizar(e));

  // Transiciones válidas (normalizadas)
  static const Map<String, List<String>> _transiciones = {
    pendiente: [aceptado, enCaminoPickup, cancelado, pendientePago],
    pendientePago: [pendiente, cancelado],
    aceptado: [enCaminoPickup, cancelado],
    enCaminoPickup: [aBordo, cancelado],
    aBordo: [enCurso, cancelado],
    enCurso: [completado, cancelado],
    completado: [],
    cancelado: [],
    rechazado: [],
  };

  static bool puedeTransicionar(String de, String a) {
    final from = normalizar(de);
    final to = normalizar(a);
    final lista = _transiciones[from];
    return lista != null && lista.contains(to);
  }

  static String descripcion(String estado) {
    switch (normalizar(estado)) {
      case pendiente:
        return 'Pendiente';
      case aceptado:
        return 'Aceptado';
      case enCaminoPickup:
        return 'Conductor en camino a recogerte';
      case aBordo:
        return 'Cliente a bordo';
      case enCurso:
        return 'En curso';
      case completado:
        return 'Completado';
      case cancelado:
        return 'Cancelado';
      case rechazado:
        return 'Rechazado';
      case pendientePago:
        return 'Pendiente de pago';
      default:
        return 'Estado desconocido';
    }
  }
}
