/// Copy visible — salidas por cupos (gira, excursión o viaje en grupo).
abstract final class PoolsProductoCopy {
  PoolsProductoCopy._();

  /// Tipo de producto (texto explicativo).
  static const String tipos =
      'gira, excursión o viaje en grupo';

  static const String salida = 'salida por cupos';
  static const String salidaLa = 'la salida';
  static const String salidaEsta = 'esta salida';
  static const String salidasMis = 'Mis salidas por cupos';
  static const String publicarTitulo = 'Publicar salida por cupos';
  static const String seccionPasajero =
      'Giras, excursiones y viajes en grupo por cupos';

  static const String accionConfirmarComision =
      'Confirmar comisión y cerrar catálogo';
  static const String accionConfirmarComisionSub =
      'Cobra % solo sobre cupos vendidos en RAI; lo de fuera no cuenta';

  static const String accionCerrarEnRai = 'Cerrar salida en RAI';
  static const String accionCerrarEnRaiSub =
      'Solo cierre en la app; no es GPS ni viaje en curso';

  static const String ventasFueraNoCuentan =
      'Ventas fuera de la app (WhatsApp, mostrador, etc.) no pagan comisión a RAI.';

  static const String ayudaFinanzas =
      'RAI publica tu salida ($tipos): fecha, banner, punto de encuentro. '
      'Si vendés cupos por la app, al cerrar el catálogo pagás el % acordado solo por esos asientos. '
      'El recorrido del día lo operás vos; no hace falta GPS en RAI.';

  static String comisionRaiFormula(double pct) =>
      'Comisión RAI = ${pct.toStringAsFixed(0)}% × asientos vendidos en la app. '
      'Lo que vendas por fuera no paga comisión a RAI.';

  static const String avisoTrasPublicar =
      'Al confirmar comisión el día de la salida se cobrará solo sobre los cupos vendidos en RAI.';

  static const String promoTituloDefault = 'Salida por cupos';
  static const String promoSeccionRai =
      'Reserva en RAI Driver desde «$seccionPasajero».';

  /// Menú y pantallas admin (mismo producto).
  static const String adminMenu =
      'Salidas por cupos (giras, excursiones, grupos)';
  static const String adminRegularizarMenu = 'Regularizar salidas (taxista)';
  static const String adminListaTitulo = 'Salidas por cupos — admin';
}
