import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
/// Textos coherentes del recibo post-viaje (cliente y taxista).
abstract final class PostViajeReciboCopy {
  PostViajeReciboCopy._();

  static bool _transferVerificada(Map<String, dynamic> d) {
    if (d['transferenciaConfirmada'] == true) return true;
    final ep = (d['estadoPago'] ?? '').toString().trim().toLowerCase();
    if (ep == 'verificado') return true;
    return (d['comprobanteTransferenciaUrl'] ?? '').toString().trim().isNotEmpty;
  }

  static String titulo({
    required String role,
    required String metodo,
    required Map<String, dynamic> data,
    bool corporativo = false,
  }) {
    if (corporativo) return 'Ruta corporativa finalizada';
    if (MetodoPagoViaje.esTarjeta(metodo)) {
      if (MetodoPagoViaje.tarjetaPagadoVerificado(data)) {
        return role == 'cliente' ? 'Pago exitoso' : 'Cobro confirmado';
      }
      return 'Recibo del viaje';
    }
    if (MetodoPagoViaje.esEfectivo(metodo)) {
      return 'Viaje finalizado';
    }
    if (MetodoPagoViaje.esTransferencia(metodo)) {
      return _transferVerificada(data)
          ? 'Transferencia registrada'
          : 'Recibo del viaje';
    }
    return 'Recibo del viaje';
  }

  static String subtitulo({
    required String role,
    required String metodo,
    required Map<String, dynamic> data,
    bool corporativo = false,
    bool usaRecaudoRai = false,
  }) {
    if (corporativo) {
      return role == 'cliente'
          ? 'Tu ruta corporativa quedó registrada. La empresa liquida con RAI.'
          : 'Tu neto corporativo se acumula en Ganancias. RAI te transfiere al liquidar el período.';
    }
    if (MetodoPagoViaje.esTarjeta(metodo)) {
      if (MetodoPagoViaje.tarjetaPagadoVerificado(data)) {
        return role == 'cliente'
            ? 'Tu tarjeta fue procesada correctamente. Conservá este resumen.'
            : 'El pasajero pagó con tarjeta. El neto entra en tu liquidación semanal.';
      }
      if (MetodoPagoViaje.tarjetaPagoFallido(data)) {
        return 'El pago con tarjeta no se completó. Coordiná efectivo o transferencia.';
      }
      return 'Pago con tarjeta pendiente de confirmación.';
    }
    if (MetodoPagoViaje.esEfectivo(metodo)) {
      return role == 'cliente'
          ? 'Pagaste al conductor en efectivo. Conservá este comprobante.'
          : 'Cobraste al pasajero en efectivo. La comisión RAI se descuenta de tu prepago.';
    }
    if (MetodoPagoViaje.esTransferencia(metodo)) {
      if (usaRecaudoRai) {
        return role == 'cliente'
            ? 'Transferencia a la cuenta corporativa de RAI con la referencia del viaje.'
            : 'El pasajero transfiere a RAI. Tu neto se liquida según conciliación.';
      }
      if (_transferVerificada(data)) {
        return role == 'cliente'
            ? 'Tu transferencia quedó registrada en el viaje.'
            : 'El pasajero transfirió a tu cuenta bancaria.';
      }
      return role == 'cliente'
          ? 'Transferí el monto acordado y conservá el comprobante.'
          : 'El pasajero debe transferirte el total acordado a tu cuenta.';
    }
    return 'Gracias por preferir RAI.';
  }

  static String etiquetaMonto({
    required String role,
    required String metodo,
    required Map<String, dynamic> data,
    bool corporativo = false,
    bool usaRecaudoRai = false,
  }) {
    if (corporativo) {
      return role == 'cliente' ? 'Tarifa de la ruta' : 'Tu neto en esta ruta';
    }
    if (MetodoPagoViaje.esTarjeta(metodo)) {
      return role == 'cliente' ? 'Total cobrado con tarjeta' : 'Total del servicio';
    }
    if (MetodoPagoViaje.esEfectivo(metodo)) {
      return role == 'cliente' ? 'Total pagado en efectivo' : 'Total cobrado en efectivo';
    }
    if (MetodoPagoViaje.esTransferencia(metodo)) {
      if (usaRecaudoRai) return 'Monto a transferir a RAI';
      return _transferVerificada(data)
          ? 'Monto de la transferencia'
          : 'Monto acordado';
    }
    return 'Total del viaje';
  }

  static String? selloEstado({
    required String role,
    required String metodo,
    required Map<String, dynamic> data,
    bool corporativo = false,
  }) {
    if (corporativo) return 'CORPORATIVO';
    if (MetodoPagoViaje.esTarjeta(metodo)) {
      if (MetodoPagoViaje.tarjetaPagadoVerificado(data)) {
        return role == 'cliente' ? 'PAGO EXITOSO' : 'COBRO CONFIRMADO';
      }
      if (MetodoPagoViaje.tarjetaPagoFallido(data)) return 'PAGO RECHAZADO';
      return 'PENDIENTE';
    }
    if (MetodoPagoViaje.esEfectivo(metodo)) {
      return role == 'cliente' ? 'PAGADO EN EFECTIVO' : 'COBRO EN EFECTIVO';
    }
    if (MetodoPagoViaje.esTransferencia(metodo)) {
      return _transferVerificada(data) ? 'TRANSFERENCIA OK' : 'TRANSFERENCIA';
    }
    return null;
  }
}
