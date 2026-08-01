import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/widgets/metodo_pago_visual_badge.dart';
import 'package:flygo_nuevo/widgets/tarjeta_pago_estado_viaje.dart';

/// Cabecera operativa del viaje: forma de pago + PIN + encadenamiento (taxista).
class ViajeFlujoProfesionalTaxistaHeader extends StatelessWidget {
  const ViajeFlujoProfesionalTaxistaHeader({
    super.key,
    required this.viajeId,
    required this.estadoBase,
    required this.metodoPagoFallback,
    required this.codigoVerificado,
    required this.montoFallback,
    this.codigoEsperado,
  });

  final String viajeId;
  final String estadoBase;
  final String metodoPagoFallback;
  final bool codigoVerificado;
  final double montoFallback;
  final String? codigoEsperado;

  bool get _fasePickup =>
      EstadosViaje.esAceptado(estadoBase) ||
      EstadosViaje.esEnCaminoPickup(estadoBase);

  bool get _faseRuta =>
      EstadosViaje.esAbordo(estadoBase) || EstadosViaje.esEnCurso(estadoBase);

  bool _pinValido(String? raw) {
    final String s = (raw ?? '').trim();
    return s.length >= 4 && s.length <= 8;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .snapshots(),
      builder: (context, snap) {
        final Map<String, dynamic> data =
            snap.data?.data() ?? <String, dynamic>{};
        final bool encadenado = data['promovidoDesdeCola'] == true;
        final String metodo = (data['metodoPago']?.toString().isNotEmpty == true
                ? data['metodoPago'].toString()
                : metodoPagoFallback)
            .trim();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (encadenado) ...<Widget>[
              _bannerEncadenado(metodo),
              const SizedBox(height: 10),
            ],
            MetodoPagoVisualCard(
              metodoPago: metodo,
              viajeData: data.isEmpty ? null : data,
              fondoOscuro: true,
              subtitulo: _subtituloPago(metodo, data),
            ),
            const SizedBox(height: 10),
            TarjetaPagoEstadoTaxistaBanner(
              viajeId: viajeId,
              metodoPagoFallback: metodoPagoFallback,
            ),
            EfectivoPagoTaxistaBanner(
              viajeId: viajeId,
              metodoPagoFallback: metodoPagoFallback,
              montoFallback: montoFallback,
            ),
            if (!codigoVerificado && (_fasePickup || _faseRuta)) ...<Widget>[
              const SizedBox(height: 10),
              _tarjetaPin(
                fasePickup: _fasePickup,
                pinValido: _pinValido(
                  (data['codigoVerificacion'] ?? codigoEsperado)?.toString(),
                ),
              ),
            ],
            if (_fasePickup || _faseRuta) ...<Widget>[
              const SizedBox(height: 10),
              _pasosFlujo(encadenado: encadenado, enRuta: _faseRuta),
            ],
          ],
        );
      },
    );
  }

  String _subtituloPago(String metodo, Map<String, dynamic> data) {
    if (MetodoPagoViaje.esTarjeta(metodo)) {
      if (MetodoPagoViaje.tarjetaPagadoVerificado(data)) {
        return 'Tarjeta confirmada por AZUL. Podés operar con tranquilidad.';
      }
      return 'El cliente debe pagar con tarjeta en su app antes o al finalizar.';
    }
    if (MetodoPagoViaje.esEfectivo(metodo)) {
      return 'Cobrás en efectivo al cliente al terminar el viaje.';
    }
    if (MetodoPagoViaje.esTransferencia(metodo)) {
      return 'Transferencia: el cliente sube comprobante o vos confirmás en app.';
    }
    return MetodoPagoVisualTheme.subtituloResumen(metodo: metodo, viajeData: data);
  }

  Widget _bannerEncadenado(String metodo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF1A1208), Color(0xFF0F172A)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB020).withValues(alpha: 0.55)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFFB020).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.fork_right_rounded, color: Color(0xFFFFB020)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Siguiente recogida conectada',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Mismo flujo profesional: recogida → PIN → destino · ${MetodoPagoViaje.etiquetaDocumento(metodo)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaPin({required bool fasePickup, required bool pinValido}) {
    final Color accent = pinValido ? Colors.amberAccent : Colors.orangeAccent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.pin_rounded, color: accent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fasePickup
                      ? 'Código de verificación al abordar'
                      : 'PIN verificado · ruta al destino',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            pinValido
                ? (fasePickup
                    ? 'Al llegar al pickup, pedile al cliente el PIN de su app y validalo antes de iniciar la ruta.'
                    : 'Cliente verificado. Seguí la navegación al destino y finalizá cuando corresponda.')
                : 'Este viaje no tiene PIN válido en el sistema. Contactá soporte antes de continuar.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pasosFlujo({required bool encadenado, required bool enRuta}) {
    final String pasoActual = enRuta
        ? '3'
        : encadenado
            ? '1'
            : '1';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        encadenado
            ? 'Flujo encadenado · Paso $pasoActual de 4: '
                '${enRuta ? 'Destino' : 'Recogida → PIN → Destino → Finalizar'}'
            : 'Paso $pasoActual: ${enRuta ? 'Llevar al destino y finalizar' : 'Ir al cliente → PIN → destino'}',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.68),
          fontSize: 11.5,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
