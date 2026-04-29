// lib/utils/calculos/estados.dart
class EstadosViaje {
  // ====== Estados base (normalizados) ======
  static const String pendiente = 'pendiente';
  static const String pendientePago = 'pendiente_pago';
  static const String aceptado = 'aceptado';
  static const String enCaminoPickup = 'en_camino_pickup';
  static const String aBordo = 'a_bordo';
  static const String enCurso = 'en_curso';
  static const String completado = 'completado';
  static const String cancelado = 'cancelado';
  static const String rechazado = 'rechazado';

  // ====== Compatibilidad con variantes antiguas ======
  static const Set<String> _aliasAceptado = {
    'aceptado',
    'asignado',
  };

  static const Set<String> _aliasEnCaminoPickup = {
    'en_camino_pickup',
    'en_camino',
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
    'encurzo',
  };

  static const Set<String> _aliasPendiente = {
    'pendiente',
    'buscando',
  };

  static const Set<String> _aliasCompletado = {
    'completado',
    'finalizado',
  };

  static const Set<String> _aliasCancelado = {
    'cancelado',
    'cancelado_cliente',
  };

  // ====== Conjuntos útiles ======
  static const Set<String> activos = {
    aceptado,
    enCaminoPickup,
    aBordo,
    enCurso,
  };

  static const Set<String> terminales = {
    completado,
    cancelado,
    rechazado,
  };

  // ====== Normalización ======
  static String normalizar(String estado) {
    final s = (estado.isEmpty ? '' : estado.trim().toLowerCase());

    if (_aliasAceptado.contains(s)) return aceptado;
    if (_aliasPendiente.contains(s)) return pendiente;
    if (_aliasEnCaminoPickup.contains(s)) return enCaminoPickup;
    if (_aliasABordo.contains(s)) return aBordo;
    if (_aliasEnCurso.contains(s)) return enCurso;
    if (_aliasCompletado.contains(s)) return completado;
    if (_aliasCancelado.contains(s)) return cancelado;

    switch (s) {
      case pendiente:
        return pendiente;
      case pendientePago:
        return pendientePago;
      case aceptado:
        return aceptado;
      case enCaminoPickup:
        return enCaminoPickup;
      case aBordo:
        return aBordo;
      case enCurso:
        return enCurso;
      case completado:
        return completado;
      case cancelado:
        return cancelado;
      case rechazado:
        return rechazado;
      default:
        return pendiente;
    }
  }

  // ====== Helpers booleanos ======
  static bool esPendiente(String e) => normalizar(e) == pendiente;
  static bool esPendientePago(String e) => normalizar(e) == pendientePago;

  // 🔥 CORREGIDO: esAceptado incluye tanto aceptado como en_camino_pickup
  static bool esAceptado(String e) {
    final n = normalizar(e);
    return n == aceptado || n == enCaminoPickup;
  }

  static bool esEnCaminoPickup(String e) => normalizar(e) == enCaminoPickup;
  static bool esAbordo(String e) => normalizar(e) == aBordo;
  static bool esEnCurso(String e) => normalizar(e) == enCurso;
  static bool esCompletado(String e) => normalizar(e) == completado;
  static bool esCancelado(String e) => normalizar(e) == cancelado;
  static bool esRechazado(String e) => normalizar(e) == rechazado;

  static bool esActivo(String e) => activos.contains(normalizar(e));
  static bool esTerminal(String e) => terminales.contains(normalizar(e));

  /// Cliente/taxista vía app: no cancelar tras abordar o en ruta (anti‑fraude).
  static bool esEstadoSinCancelacionApp(String e) {
    final String n = normalizar(e);
    return n == aBordo || n == enCurso;
  }

  /// Si el botón “Cancelar viaje” debe mostrarse al cliente.
  static bool clientePuedeCancelarViajeDesdeApp(String estadoRaw) {
    final String n = normalizar(estadoRaw);
    if (n == completado || n == cancelado || n == rechazado) return false;
    return !esEstadoSinCancelacionApp(n);
  }

  static const String mensajeNoCancelarViajeTrasAbordarApp =
      'Una vez el cliente está a bordo o el viaje está en curso, no se puede cancelar desde la app. '
      'Si hay una emergencia o un incidente grave, contacta a soporte de la plataforma.';

  // ====== Transiciones válidas ======
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

  // ====== Texto para UI ======
  static String descripcion(String estado) {
    final String raw = estado.trim().toLowerCase();
    if (raw == 'pendiente_admin') {
      return 'Solicitud enviada — asignación por administración';
    }
    switch (normalizar(estado)) {
      case pendiente:
        return 'Pendiente';
      case pendientePago:
        return 'Pendiente de pago';
      case aceptado:
        return 'Aceptado';
      case enCaminoPickup:
        return 'Ir a buscar cliente';
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
      default:
        return 'Estado desconocido';
    }
  }
}
