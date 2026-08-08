import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/utils/negocio_aliado_viaje_doc.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/widgets/metodo_pago_visual_badge.dart';

/// Banner taxista: solo refleja lo que AZUL/servidor escribió en Firestore.
class TarjetaPagoEstadoTaxistaBanner extends StatelessWidget {
  const TarjetaPagoEstadoTaxistaBanner({
    super.key,
    required this.viajeId,
    required this.metodoPagoFallback,
    this.ocultarSiCorporativo = true,
  });

  final String viajeId;
  final String metodoPagoFallback;
  final bool ocultarSiCorporativo;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox.shrink();
        }
        final data = snap.data!.data() ?? const <String, dynamic>{};
        final String metodo = (data['metodoPago']?.toString().isNotEmpty == true
                ? data['metodoPago'].toString()
                : metodoPagoFallback)
            .toString();
        if (!MetodoPagoViaje.esTarjeta(metodo)) {
          return const SizedBox.shrink();
        }
        if (ocultarSiCorporativo &&
            (data['esCorporativo'] == true ||
                (data['tipoServicio'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains('corp'))) {
          return const SizedBox.shrink();
        }

        final bool pagado = MetodoPagoViaje.tarjetaPagadoVerificado(data);
        final bool fallido = MetodoPagoViaje.tarjetaPagoFallido(data);
        final String? errorAzul = MetodoPagoViaje.tarjetaUltimoErrorAzul(data);

        if (pagado) {
          return MetodoPagoEstadoBanner(
            metodoPago: metodo,
            titulo: 'Tarjeta cobrada (AZUL confirmó)',
            detalle:
                'El banco aprobó el pago. Podés finalizar: tu liquidación incluirá este viaje cuando RAI procese el pago semanal.',
            estado: MetodoPagoBannerEstado.exito,
          );
        }
        if (fallido) {
          return MetodoPagoEstadoBanner(
            metodoPago: metodo,
            titulo: 'Tarjeta rechazada — NO pagada',
            detalle: errorAzul != null && errorAzul.isNotEmpty
                ? 'AZUL/banco: $errorAzul. Pedile al cliente otra tarjeta o que toque «Pagar en efectivo» en su app. '
                    'Sin cobro verificado ni cambio a efectivo, vos NO cobrás este viaje.'
                : 'El banco rechazó el intento (sin fondos, tarjeta bloqueada, etc.). '
                    'Pedile que pague de nuevo o que cambie a efectivo desde su app. '
                    'Sin cobro verificado ni cambio a efectivo, vos NO cobrás este viaje.',
            estado: MetodoPagoBannerEstado.error,
          );
        }
        return MetodoPagoEstadoBanner(
          metodoPago: metodo,
          titulo: 'Tarjeta pendiente',
          detalle:
              'AZUL aún no confirmó el cobro. Pedile al cliente «Pagar con tarjeta» o «Pagar en efectivo» en su app. '
              'No confíes en que “ya pagó” hasta que este aviso pase a verde o cambie a efectivo.',
          estado: MetodoPagoBannerEstado.advertencia,
        );
      },
    );
  }
}

/// Banner taxista: cobro en efectivo (o cambio desde tarjeta fallida).
class EfectivoPagoTaxistaBanner extends StatelessWidget {
  const EfectivoPagoTaxistaBanner({
    super.key,
    required this.viajeId,
    required this.metodoPagoFallback,
    required this.montoFallback,
    this.ocultarSiCorporativo = true,
  });

  final String viajeId;
  final String metodoPagoFallback;
  final double montoFallback;
  final bool ocultarSiCorporativo;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox.shrink();
        }
        final data = snap.data!.data() ?? const <String, dynamic>{};
        final String metodo = (data['metodoPago']?.toString().isNotEmpty == true
                ? data['metodoPago'].toString()
                : metodoPagoFallback)
            .toString();
        if (!MetodoPagoViaje.esEfectivo(metodo)) {
          return const SizedBox.shrink();
        }
        if (ocultarSiCorporativo &&
            (data['esCorporativo'] == true ||
                (data['tipoServicio'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains('corp'))) {
          return const SizedBox.shrink();
        }

        final double monto = (data['precio'] is num)
            ? (data['precio'] as num).toDouble()
            : montoFallback;
        final bool promoGratisQr =
            NegocioAliadoViajeDoc.esViajeGratisPromo(data);
        final bool desdeTarjeta =
            MetodoPagoViaje.cambioDesdeTarjetaAEfectivo(data);

        if (promoGratisQr) {
          return MetodoPagoEstadoBanner(
            metodoPago: metodo,
            titulo: 'NO COBRAR · 6.º viaje GRATIS (promo QR)',
            detalle: 'Cliente referido por negocio aliado. '
                'El pasajero no paga este viaje (RD\$0). '
                'RAI registra la comisión al taxista sobre el precio nominal.',
            estado: MetodoPagoBannerEstado.exito,
          );
        }

        return MetodoPagoEstadoBanner(
          metodoPago: metodo,
          titulo: desdeTarjeta
              ? 'Pago en EFECTIVO (cambió desde tarjeta)'
              : 'Cobrá en EFECTIVO',
          detalle: desdeTarjeta
              ? 'La tarjeta no se cobró. El cliente eligió pagar en mano. '
                  'Cobrá ${FormatosMoneda.rd(monto)} antes de dejarlo salir.'
              : 'Cobrá ${FormatosMoneda.rd(monto)} en efectivo al pasajero al finalizar el viaje.',
          estado: MetodoPagoBannerEstado.info,
        );
      },
    );
  }
}

/// Banner cliente: instrucción de pago en efectivo (tras cambio desde tarjeta).
class EfectivoPagoClienteBanner extends StatelessWidget {
  const EfectivoPagoClienteBanner({
    super.key,
    required this.montoRd,
    this.desdeTarjeta = false,
  });

  final double montoRd;
  final bool desdeTarjeta;

  @override
  Widget build(BuildContext context) {
    return MetodoPagoEstadoBanner(
      metodoPago: 'efectivo',
      titulo: desdeTarjeta ? 'Pago en efectivo' : 'Pago en efectivo',
      detalle: desdeTarjeta
          ? 'Pagás en efectivo al conductor: ${FormatosMoneda.rd(montoRd)}. '
              'Entregá el monto al bajar del vehículo.'
          : 'Este viaje es en efectivo: ${FormatosMoneda.rd(montoRd)} al conductor al llegar.',
      estado: MetodoPagoBannerEstado.info,
      padding: EdgeInsets.zero,
    );
  }
}

/// Conductor: caso extremo — pasajero sin efectivo ni tarjeta. No bloquea navegación.
class TaxistaRegistrarImpagoButton extends StatefulWidget {
  const TaxistaRegistrarImpagoButton({
    super.key,
    required this.viajeId,
    required this.metodoPagoFallback,
  });

  final String viajeId;
  final String metodoPagoFallback;

  @override
  State<TaxistaRegistrarImpagoButton> createState() =>
      _TaxistaRegistrarImpagoButtonState();
}

class _TaxistaRegistrarImpagoButtonState
    extends State<TaxistaRegistrarImpagoButton> {
  bool _enviando = false;

  Future<void> _registrarImpago(double monto) async {
    if (_enviando) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Pasajero no pudo pagar?'),
        content: Text(
          'Usá esto solo si el pasajero no tiene efectivo ni tarjeta válida.\n\n'
          'RAI registrará la deuda de ${FormatosMoneda.rd(monto)} a su cuenta. '
          'Vos podés seguir trabajando con normalidad; el pasajero quedará bloqueado hasta pagar.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Registrar impago'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _enviando = true);
    try {
      await ViajesRepo.registrarImpagoPasajero(viajeId: widget.viajeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impago registrado. El pasajero debe regularizar con RAI. Podés finalizar el viaje.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo registrar: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('viajes')
          .doc(widget.viajeId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox.shrink();
        }
        final data = snap.data!.data() ?? const <String, dynamic>{};
        if (MetodoPagoViaje.impagoRegistrado(data)) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.4)),
              ),
              child: const Text(
                'Impago registrado con RAI. Finalizá el viaje y seguí trabajando; '
                'el pasajero debe pagar desde su app.',
                style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35),
              ),
            ),
          );
        }

        final String metodo = (data['metodoPago']?.toString().isNotEmpty == true
                ? data['metodoPago'].toString()
                : widget.metodoPagoFallback)
            .toString();
        final bool tarjetaSinCobrar =
            MetodoPagoViaje.esTarjeta(metodo) &&
                !MetodoPagoViaje.tarjetaPagadoVerificado(data);
        final bool efectivo = MetodoPagoViaje.esEfectivo(metodo);
        if (!tarjetaSinCobrar && !efectivo) {
          return const SizedBox.shrink();
        }
        if (MetodoPagoViaje.tarjetaPagadoVerificado(data)) {
          return const SizedBox.shrink();
        }

        final double monto = MetodoPagoViaje.cobroClienteMontoRd(data);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton.icon(
            onPressed: _enviando ? null : () => _registrarImpago(monto),
            icon: _enviando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.report_outlined, size: 18),
            label: Text(
              _enviando
                  ? 'Registrando…'
                  : 'Pasajero no pudo pagar (registrar con RAI)',
              style: const TextStyle(fontSize: 12.5),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orangeAccent,
              side: BorderSide(color: Colors.orangeAccent.withValues(alpha: 0.45)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        );
      },
    );
  }
}
