import 'package:flygo_nuevo/config/recarga_bancaria_config.dart';

/// Copy visible — salidas por cupos (gira, excursión o viaje en grupo).
abstract final class PoolsProductoCopy {
  PoolsProductoCopy._();

  /// Entidad que recibe transferencias de clientes (cuenta corporativa RAI).
  static String get entidadRecaudoLegal =>
      '${RecargaBancariaConfig.titular} (RAI Driver)';

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

  static const String accionConfirmarInicioCentralTitulo =
      'Iniciar salida · recaudo central RAI';

  static String accionConfirmarInicioCentralCuerpo({
    required int cuposFirmes,
    required int asientosEfectivo,
    required double comisionEfectivoRd,
    required double pctComision,
  }) {
    final buf = StringBuffer()
      ..writeln('Cupos firmes (pago verificado en RAI o efectivo reservado): $cuposFirmes.')
      ..writeln(
        'Transferencias: el cliente pagó el 100% a $entidadRecaudoLegal; '
        'RAI ya retuvo la comisión al verificar cada pago.',
      );
    if (asientosEfectivo > 0) {
      buf.writeln(
        'Efectivo al abordar: $asientosEfectivo asiento(s). '
        'Comisión RAI del prepago al iniciar: RD\$ ${comisionEfectivoRd.toStringAsFixed(0)} '
        '(${pctComision.toStringAsFixed(0)}%).',
      );
    }
    buf.write(
      'Al cerrar la salida, RAI transfiere tu neto desde admin (Verificar pagos → Giras RAI).',
    );
    return buf.toString();
  }

  static const String accionInicioCentralOk =
      'Catálogo cerrado. Salida en ruta — recaudo central RAI.';

  static const String accionFinalizarCentralNetoPendiente =
      'Salida cerrada. El neto al organizador quedó pendiente en Verificar pagos → Giras RAI.';

  static const String adminFinalizarCentralNetoPendiente =
      'Salida finalizada. Transferí el neto al organizador y marcá liquidado en Verificar pagos → Giras RAI.';

  static const String accionCerrarEnRai = 'Cerrar salida en RAI';
  static const String accionCerrarEnRaiSub =
      'Solo cierre en la app; no es GPS ni viaje en curso';

  static const String ventasFueraNoCuentan =
      'Ventas fuera de la app (WhatsApp, mostrador, etc.) no pagan comisión a RAI.';

  static const String recaudoCentralCliente =
      'Transferís el total de tu reserva a la cuenta de RAI. RAI retiene la comisión '
      'y transfiere el neto al organizador de la salida.';

  static const String recaudoCentralClientePasos =
      '1. Reservá tus asientos.\n'
      '2. Transferí el total a la cuenta de RAI con la referencia que te damos.\n'
      '3. Guardá el comprobante del banco — RAI concilia el pago.\n'
      '4. RAI confirma tu cupo en la app cuando el pago está verificado.\n'
      'No envíes el bauche al chofer: el dinero va a RAI, no a su cuenta.';

  static const String recaudoCentralClientePie =
      'Reservá, pagá el total a RAI con tu referencia y guardá el comprobante. '
      'No hace falta enviar bauche al organizador.';

  static const String recaudoCentralClienteSheetCierre =
      'Cuando RAI verifique tu transferencia, el organizador confirmará tu cupo en la app. '
      'Conservá el comprobante por si soporte lo necesita.';

  static const String recaudoCentralTaxista =
      'Transferencia: el cliente paga a RAI; RAI verifica en banco y confirma el cupo. '
      'Efectivo: el cliente paga al abordar y la comisión RAI sale de tu prepago al iniciar la salida.';

  static const String recaudoCentralTaxistaPasos =
      '1. Publicás la salida (foto/video, fecha, cupos).\n'
      '2. El cliente reserva: transferencia a RAI o efectivo al abordar.\n'
      '3. Transferencia: RAI verifica el pago en Open ASK — vos no confirmás transferencias.\n'
      '4. Efectivo: al iniciar la salida se descuenta la comisión RAI de tu prepago (recarga).\n'
      '5. Al cerrar la salida, RAI transfiere tu neto a la cuenta bancaria que indicaste.';

  static const String recaudoCentralTaxistaMarcarPagada =
      'Confirmar pago RAI';

  static const String recaudoCentralTaxistaMarcarPagadaAyuda =
      'Solo aplica a efectivo u otras modalidades legacy. '
      'Las transferencias central las verifica RAI en admin.';

  static String recaudoCentralEstadoReservaCliente(Map<String, dynamic> r) {
    final estado = (r['estado'] ?? '').toString().trim().toLowerCase();
    final metodo = (r['metodoPago'] ?? '').toString().trim().toLowerCase();
    if (estado == 'pagado') {
      return 'Cupos confirmados — pago verificado en RAI';
    }
    if (metodo == 'transferencia') {
      return 'Pendiente — transferí el total a RAI y guardá tu comprobante';
    }
    if (metodo == 'efectivo') {
      return 'Reservado — pagás RD\$ ${_totalReserva(r)} en efectivo al abordar '
          '(${_seats(r)} × precio publicado). La comisión RAI la descuenta el organizador '
          'de su prepago al iniciar la salida, no vos en la app.';
    }
    return 'Reserva activa';
  }

  static int _seats(Map<String, dynamic> r) =>
      ((r['seats'] ?? 0) as num).toInt();

  static String _totalReserva(Map<String, dynamic> r) {
    final t = ((r['total'] ?? 0) as num).toDouble();
    return t.toStringAsFixed(0);
  }

  static String recaudoCentralEstadoReservaTaxista(Map<String, dynamic> r) {
    final estado = (r['estado'] ?? '').toString().trim().toLowerCase();
    final metodo = (r['metodoPago'] ?? '').toString().trim().toLowerCase();
    final neto = ((r['netoOrganizadorRd'] ?? 0) as num).toDouble();
    if (estado == 'pagado' && neto > 0) {
      return 'Pagado en RAI · Tu neto: RD\$ ${neto.toStringAsFixed(0)}';
    }
    if (estado == 'pagado') {
      return 'Pagado — cupos confirmados';
    }
    if (metodo == 'transferencia') {
      return 'Cliente debe transferir el total a RAI — RAI verifica en banco (no confirmás vos)';
    }
    if (metodo == 'efectivo') {
      return 'Efectivo al abordar — comisión RAI (${pctFromReserva(r)}%) sobre el total '
          'de esta reserva; se descuenta del prepago al iniciar la salida';
    }
    return 'Reserva activa';
  }

  static String pctFromReserva(Map<String, dynamic> r) {
    final total = ((r['total'] ?? 0) as num).toDouble();
    final com = ((r['comisionRaiRd'] ?? 0) as num).toDouble();
    if (total > 0 && com > 0) {
      return ((com / total) * 100).toStringAsFixed(0);
    }
    return '—';
  }

  static const String bancoRecibirNetoTitulo =
      'Tu cuenta bancaria (RAI te transfiere el neto)';
  static const String bancoRecibirNetoAyuda =
      'Esta cuenta es solo para que RAI te pague lo que te corresponde después de retener '
      'la comisión. El cliente NO transfiere aquí: paga el total a la cuenta corporativa '
      'de Open ASK Service SRL (RAI) con la referencia que ve en la app.';

  static const String bancoLegacyDepositoTitulo =
      'Cuenta bancaria del organizador (depósito del cliente)';
  static const String bancoLegacyDepositoAyuda =
      'En este modo el cliente puede transferir un depósito inicial a esta cuenta para reservar. '
      'La comisión RAI se descuenta de tu prepago al publicar y al confirmar ventas en la app. '
      'Si tu operación ya usa recaudo central RAI, el cliente paga a Open ASK Service SRL, no aquí.';

  /// Formulario taxista — qué hace el organizador al publicar.
  static const String formTuRolOrganizador =
      'Vos publicás la salida (fecha, cupos, banner, ruta) y operás el día. '
      'RAI muestra tu anuncio; seguís reservas en la app y, al cerrar el catálogo, '
      'confirmás la comisión solo sobre cupos vendidos en RAI.';

  static String formHero({required bool recaudoCentral}) {
    if (recaudoCentral) {
      return 'Publicá tu salida ($tipos). El cliente que reserva por transferencia paga a '
          '$entidadRecaudoLegal — no a tu cuenta personal.';
    }
    return 'Publicá tu salida ($tipos): ruta, paradas y cupos. '
        'Indicá abajo cómo reservan y pagan los clientes en RAI.';
  }

  static String formQuienPagaCliente({required bool recaudoCentral}) {
    if (recaudoCentral) {
      return 'Transferencia en la app\n'
          '• El cliente transfiere el 100% del total a $entidadRecaudoLegal.\n'
          '• RAI verifica el pago en banco — no confirmás transferencias en tus reservas.\n'
          '• RAI retiene la comisión y te transfiere el neto a la cuenta que indicás abajo.\n\n'
          'Efectivo al abordar\n'
          '• El cliente te paga en mano el día de la salida.\n'
          '• La comisión RAI se descuenta de tu prepago (Mis pagos → Recarga comisión).\n\n'
          'Importante: no pidas al cliente el bauche de transferencia ni que te deposite a tu cuenta '
          'personal — el dinero de transferencia va a RAI, no a vos.';
    }
    return 'Transferencia / depósito en la app\n'
        '• El cliente puede depositar un % inicial a la cuenta bancaria del organizador '
        '(la que indicás abajo) para reservar.\n'
        '• Al publicar, RAI aparta prepago tuyo como garantía de comisión sobre cupos en la app.\n\n'
        'Efectivo al abordar\n'
        '• El cliente paga en mano; la comisión RAI sale de tu prepago.\n\n'
        'Ventas por WhatsApp o fuera de RAI no pagan comisión a la plataforma.';
  }

  static String formPrepagoAlPublicar({required bool recaudoCentral}) {
    if (recaudoCentral) {
      return 'Recaudo central activo: al publicar no se aparta prepago por cupos pagados '
          'con transferencia a RAI. Mantené prepago en Mis pagos para reservas en efectivo al abordar.';
    }
    return 'Al publicar solo se aparta prepago por el tope de cupos RAI. '
        'Al confirmar comisión se ajusta a lo vendido en la app y se devuelve el exceso.';
  }

  static String formDepositoPctNota({required bool recaudoCentral}) {
    if (recaudoCentral) {
      return '';
    }
    return 'Porcentaje de depósito inicial (modo legacy). El cliente transfiere ese monto a '
        '$entidadRecaudoLegal para reservar; el resto se coordina con el organizador.';
  }

  /// Recaudo central: depósito y comisión fijos — el taxista no los configura.
  static String formRecaudoCentralPagoFijo(double comisionPct) =>
      'Pago por transferencia: el cliente deposita el 100% del total a $entidadRecaudoLegal. '
      'Comisión RAI: ${comisionPct.toStringAsFixed(0)}% por asiento vendido en la app '
      '(la define la plataforma; no la editás acá).';

  static const String clienteTransferenciaTitulo =
      'Transferencia a RAI (Open ASK Service)';
  static const String clienteTransferenciaSubtitulo =
      'Pagás a la cuenta corporativa de RAI. No deposites al taxista ni al operador.';

  static const String clienteCuentaRaiAntesReservar =
      'Al reservar recibirás el monto exacto y, si aplica, una referencia única. '
      'RAI verifica el pago en la cuenta de Open ASK Service SRL.';

  static const String clientePieTransferencia =
      'Transferí a Open ASK Service SRL (RAI). Conservá el comprobante; '
      'no envíes el bauche al chofer para validar el pago.';

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
