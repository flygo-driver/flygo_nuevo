import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/pantallas/comun/factura_viaje.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/utils/multiparada_ruta_helper.dart';
import 'package:flygo_nuevo/utils/post_viaje_recibo_copy.dart';
import 'package:flygo_nuevo/utils/recibo_tarjeta_azul.dart';
import 'package:flygo_nuevo/utils/transferencia_recaudo_ui.dart';
import 'package:flygo_nuevo/widgets/metodo_pago_visual_badge.dart';
import 'package:flygo_nuevo/widgets/rai_recibo_tarjeta_panel.dart';
import 'package:flygo_nuevo/widgets/subir_comprobante_viaje_button.dart';
import 'package:flygo_nuevo/widgets/taxista_perfil_post_viaje_card.dart';

/// Recibo unificado post-viaje (cliente o taxista), coherente por método de pago.
class PostViajeReciboResumen extends StatelessWidget {
  const PostViajeReciboResumen({
    super.key,
    required this.role,
    required this.viaje,
    required this.data,
    this.fondoOscuro = true,
  });

  final String role;
  final Viaje viaje;
  final Map<String, dynamic> data;
  final bool fondoOscuro;

  bool get _esCliente => role == 'cliente';
  bool get _esCorp => CorporativoTaxistaService.esViajeCorporativoDoc(data);

  String get _metodo =>
      (data['metodoPago'] ?? viaje.metodoPago).toString();

  bool get _usaRecaudoRai =>
      MetodoPagoViaje.esTransferencia(_metodo) &&
      TransferenciaRecaudoUi.viajeUsaRecaudoEnCuentaRai(data);

  double get _totalRd {
    if (data['precioFinal'] is num) {
      return (data['precioFinal'] as num).toDouble();
    }
    if (data['precio'] is num) return (data['precio'] as num).toDouble();
    return viaje.precio;
  }

  double get _netoTaxistaRd {
    final gc = data['ganancia_cents'];
    if (gc is num && gc > 0) return gc / 100.0;
    final g = data['gananciaTaxista'];
    if (g is num && g > 0) return g.toDouble();
    return PlataformaEconomia.gananciaTaxistaRdDesdeTotal(_totalRd);
  }

  double get _comisionRd {
    final cc = data['comision_cents'];
    if (cc is num && cc >= 0) return cc / 100.0;
    final c = data['comision'] ?? data['comisionFlygo'];
    if (c is num && c >= 0) return c.toDouble();
    return (_totalRd - _netoTaxistaRd).clamp(0, double.infinity);
  }

  String get _uidTaxista => viaje.uidTaxista.isNotEmpty
      ? viaje.uidTaxista
      : (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString().trim();

  String _money(num n) => FormatosMoneda.rd(n.toDouble());

  String _fecha(Timestamp? ts) {
    if (ts == null) return '—';
    final d = ts.toDate().toLocal();
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year} · $h:$m';
  }

  Color? _selloColor(String? sello) {
    if (sello == null) return null;
    final s = sello.toUpperCase();
    if (s.contains('EXITOSO') ||
        s.contains('CONFIRMADO') ||
        s.contains('OK') ||
        s.contains('EFECTIVO')) {
      return const Color(0xFF69F0AE);
    }
    if (s.contains('RECHAZADO')) return Colors.redAccent;
    if (s.contains('TRANSFERENCIA')) return const Color(0xFF64B5F6);
    if (s.contains('PENDIENTE')) return Colors.orangeAccent;
    return const Color(0xFFB388FF);
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              k,
              style: TextStyle(
                color: fondoOscuro ? Colors.white54 : Colors.black54,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              v.isEmpty ? '—' : v,
              style: TextStyle(
                color: fondoOscuro ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String refCorta = viaje.id.length >= 8
        ? viaje.id.substring(0, 8).toUpperCase()
        : viaje.id.toUpperCase();
    final Timestamp? finTs = data['finalizadoEn'] as Timestamp?;
    final String? sello = PostViajeReciboCopy.selloEstado(
      role: role,
      metodo: _metodo,
      data: data,
      corporativo: _esCorp,
    );
    final double montoPrincipal =
        (!_esCliente && _esCorp) ? _netoTaxistaRd : _totalRd;
    final bool esTarjeta = MetodoPagoViaje.esTarjeta(_metodo);
    final bool esTransfer = MetodoPagoViaje.esTransferencia(_metodo);
    final bool tarjetaPagada = MetodoPagoViaje.tarjetaPagadoVerificado(data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          tarjetaPagada && _esCliente
              ? Icons.verified_rounded
              : Icons.check_circle_rounded,
          color: Colors.greenAccent,
          size: 64,
        ),
        const SizedBox(height: 16),
        Text(
          PostViajeReciboCopy.titulo(
            role: role,
            metodo: _metodo,
            data: data,
            corporativo: _esCorp,
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: fondoOscuro ? Colors.white : Colors.black87,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          PostViajeReciboCopy.subtitulo(
            role: role,
            metodo: _metodo,
            data: data,
            corporativo: _esCorp,
            usaRecaudoRai: _usaRecaudoRai,
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: fondoOscuro ? Colors.white70 : Colors.black54,
            height: 1.4,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 18),
        MetodoPagoVisualCard(
          metodoPago: _metodo,
          viajeData: data,
          corporativo: _esCorp,
          usaRecaudoRai: _usaRecaudoRai,
          estadoSello: sello,
          estadoColor: _selloColor(sello),
          fondoOscuro: fondoOscuro,
        ),
        const SizedBox(height: 20),
        if (_esCliente && _uidTaxista.isNotEmpty) ...[
          TaxistaPerfilPostViajeCard(
            uidTaxista: _uidTaxista,
            nombreFallback: viaje.nombreTaxista,
            viajeData: data,
          ),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: fondoOscuro ? const Color(0xFF141414) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: fondoOscuro ? Colors.white12 : Colors.black12,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('Referencia', refCorta),
              _kv('Cierre', _fecha(finTs)),
              if (viaje.origen.isNotEmpty) _kv('Origen', viaje.origen),
              ...MultiparadaRutaHelper.waypointsDesdeDoc(data).asMap().entries.map(
                (MapEntry<int, Map<String, dynamic>> e) {
                  final int n = e.key + 1;
                  final String label =
                      (e.value['label'] ?? 'Parada $n').toString();
                  return _kv('Parada $n', label);
                },
              ),
              if (viaje.destino.isNotEmpty) _kv('Destino final', viaje.destino),
              if (_esCliente && viaje.nombreTaxista.isNotEmpty)
                _kv('Conductor', viaje.nombreTaxista),
              if (!_esCliente) ...[
                if ((data['nombreCliente'] ?? data['clienteNombre'] ?? '')
                    .toString()
                    .trim()
                    .isNotEmpty)
                  _kv(
                    'Pasajero',
                    (data['nombreCliente'] ?? data['clienteNombre'] ?? '')
                        .toString()
                        .trim(),
                  ),
              ],
              const Divider(height: 28, color: Colors.white24),
              Text(
                PostViajeReciboCopy.etiquetaMonto(
                  role: role,
                  metodo: _metodo,
                  data: data,
                  corporativo: _esCorp,
                  usaRecaudoRai: _usaRecaudoRai,
                ),
                style: TextStyle(
                  color: fondoOscuro ? Colors.white54 : Colors.black54,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _money(montoPrincipal),
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    height: 1.05,
                  ),
                ),
              ),
              if (!_esCliente && !_esCorp && _comisionRd > 0) ...[
                const SizedBox(height: 12),
                _kv('Comisión RAI', _money(_comisionRd)),
                _kv('Tu ganancia neta', _money(_netoTaxistaRd)),
              ],
              if (_esCorp && !_esCliente) ...[
                const SizedBox(height: 8),
                Text(
                  'Tarifa ruta ${_money(_totalRd)} · neto acumulado corporativo',
                  style: TextStyle(
                    color: fondoOscuro ? Colors.white54 : Colors.black54,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (esTarjeta) ...[
          const SizedBox(height: 14),
          RaiReciboTarjetaPanel(
            recibo: ReciboTarjetaAzul.fromViaje(
              viajeId: viaje.id,
              data: data,
              montoRd: _totalRd,
            ),
            fondoOscuro: fondoOscuro,
          ),
        ],
        if (esTransfer && _esCliente) ...[
          const SizedBox(height: 14),
          TransferenciaRecaudoUi.panel(
            viajeData: data,
            uidTaxista: _uidTaxista,
            montoRd: _totalRd,
            fondoOscuro: fondoOscuro,
            tituloConductor: 'CUENTA DEL CONDUCTOR PARA TRANSFERIR',
            tituloRai: 'PAGAR A RAI (TRANSFERENCIA)',
          ),
          if (clienteDebePoderSubirComprobanteTransferencia(data)) ...[
            const SizedBox(height: 12),
            SubirComprobanteViajeButton(viajeId: viaje.id),
          ],
        ],
        if (esTransfer && !_esCliente && !_esCorp) ...[
          const SizedBox(height: 14),
          TransferenciaRecaudoUi.panel(
            viajeData: data,
            uidTaxista: _uidTaxista,
            montoRd: _totalRd,
            fondoOscuro: fondoOscuro,
            tituloConductor: 'CUENTA PARA COBRO DEL PASAJERO',
            tituloRai: 'RECAUDO RAI (TRANSFERENCIA DEL PASAJERO)',
          ),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => FacturaViaje.mostrar(
            context,
            viajeId: viaje.id,
            role: role,
          ),
          icon: const Icon(Icons.receipt_long_outlined, size: 20),
          label: const Text('Ver comprobante oficial completo'),
          style: OutlinedButton.styleFrom(
            foregroundColor: fondoOscuro ? Colors.white70 : Colors.black87,
            side: BorderSide(
              color: fondoOscuro ? Colors.white24 : Colors.black26,
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }
}
