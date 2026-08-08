// lib/widgets/negocio_aliado_taxista_banner.dart
//
// Aviso visible al taxista: promo QR 5+1, no cobrar en 6.º gratis local.

import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/negocio_aliado_config.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/negocio_aliado_viaje_doc.dart';

class NegocioAliadoTaxistaBanner extends StatelessWidget {
  const NegocioAliadoTaxistaBanner({
    super.key,
    required this.viajeData,
    this.compacto = false,
  });

  final Map<String, dynamic> viajeData;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    if (!NegocioAliadoViajeDoc.esReferidoQr(viajeData)) {
      return const SizedBox.shrink();
    }

    final bool gratis = NegocioAliadoViajeDoc.esViajeGratisPromo(viajeData);
    final bool interPueblo =
        NegocioAliadoViajeDoc.esInterPuebloConPromoPendiente(viajeData);
    final String ciudad = NegocioAliadoViajeDoc.ciudadPueblo(viajeData);
    final String negocio = NegocioAliadoViajeDoc.nombreNegocio(viajeData);
    final int contador = NegocioAliadoViajeDoc.contadorAlCrear(viajeData);
    final int m = NegocioAliadoConfig.promoViajesM;
    final double nominal = NegocioAliadoViajeDoc.precioNominalRd(viajeData);

    if (gratis) {
      return _caja(
        color: const Color(0xFFB71C1C),
        borde: const Color(0xFFFF5252),
        icono: Icons.money_off_rounded,
        titulo: compacto ? '6.º GRATIS · NO COBRAR' : 'PROMO QR · 6.º VIAJE GRATIS',
        detalle: compacto
            ? 'Cliente QR${ciudad.isNotEmpty ? ' · $ciudad' : ''} · RD\$0'
            : 'Cliente referido por negocio aliado (${negocio.isEmpty ? NegocioAliadoViajeDoc.codigo(viajeData) : negocio}). '
                'NO cobres al pasajero. '
                '${ciudad.isNotEmpty ? 'Válido solo en $ciudad. ' : ''}'
                'RAI liquida comisión ${NegocioAliadoConfig.pctComisionTaxistaReferido.toStringAsFixed(0)}% '
                'sobre ${FormatosMoneda.rd(nominal)} nominal.',
      );
    }

    if (interPueblo) {
      return _caja(
        color: const Color(0xFF5D4037),
        borde: const Color(0xFFFFB74D),
        icono: Icons.location_off_outlined,
        titulo: 'Promo QR · cobrar precio completo',
        detalle: 'El cliente ya tiene $m viajes pagados, pero este trayecto es '
            'fuera de ${ciudad.isEmpty ? 'su pueblo aliado' : ciudad}. '
            'Cobrá ${FormatosMoneda.rd(nominal)}. La promo gratis aplica solo '
            'dentro del mismo pueblo.',
      );
    }

    return _caja(
      color: const Color(0xFF1B5E20),
      borde: const Color(0xFF66BB6A),
      icono: Icons.qr_code_2_rounded,
      titulo: compacto ? 'Cliente QR aliado' : 'Viaje cliente referido QR',
      detalle: compacto
          ? '${contador + 1}.º viaje promo · ${contador}/$m hacia gratis'
          : 'Cliente del programa negocios aliados'
              '${negocio.isNotEmpty ? ' ($negocio)' : ''}. '
              'Lleva $contador de $m viajes pagados hacia el 6.º gratis '
              '${ciudad.isNotEmpty ? 'en $ciudad' : 'en su pueblo'}. '
              'Cobrá el precio normal del viaje.',
    );
  }

  Widget _caja({
    required Color color,
    required Color borde,
    required IconData icono,
    required String titulo,
    required String detalle,
  }) {
    return Container(
      width: double.infinity,
      margin: compacto
          ? const EdgeInsets.only(bottom: 6)
          : const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 10 : 12,
        vertical: compacto ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(compacto ? 10 : 12),
        border: Border.all(color: borde.withValues(alpha: 0.85)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: Colors.white, size: compacto ? 18 : 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: compacto ? 12 : 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detalle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: compacto ? 10.5 : 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
