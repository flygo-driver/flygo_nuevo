// lib/pantallas/admin/admin_negocio_aliado_detalle.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/pantallas/admin/admin_ui_theme.dart';
import 'package:flygo_nuevo/servicios/negocio_aliado_admin_repo.dart';
import 'package:flygo_nuevo/servicios/negocio_aliado_config.dart';
import 'package:flygo_nuevo/servicios/negocios_aliados_repo.dart';

class AdminNegocioAliadoDetallePage extends StatefulWidget {
  const AdminNegocioAliadoDetallePage({super.key, required this.negocio});

  final NegocioAliado negocio;

  @override
  State<AdminNegocioAliadoDetallePage> createState() =>
      _AdminNegocioAliadoDetallePageState();
}

class _AdminNegocioAliadoDetallePageState
    extends State<AdminNegocioAliadoDetallePage> {
  bool _cargando = true;
  List<NegocioAliadoClienteRef> _clientes = <NegocioAliadoClienteRef>[];
  List<NegocioAliadoViajeComision> _viajes = <NegocioAliadoViajeComision>[];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final clientes =
          await NegocioAliadoAdminRepo.clientesReferidos(widget.negocio.codigo);
      final viajes =
          await NegocioAliadoAdminRepo.viajesConComision(widget.negocio.codigo);
      if (!mounted) return;
      setState(() {
        _clientes = clientes;
        _viajes = viajes;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando detalle: $e')),
        );
      }
    }
  }

  String _fmtFecha(DateTime? d) {
    if (d == null) return '—';
    return DateFormat('dd/MM/yyyy HH:mm').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final pendienteNegocio = _viajes
        .where((v) => !v.pagada)
        .fold<double>(0, (s, v) => s + v.comisionNegocioRd);
    final pagadoNegocio = _viajes
        .where((v) => v.pagada)
        .fold<double>(0, (s, v) => s + v.comisionNegocioRd);
    final totalComisionTaxista15 = _viajes.fold<double>(
      0,
      (s, v) => s + v.comisionTaxistaRd,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.negocio.nombre.isEmpty
            ? widget.negocio.codigo
            : widget.negocio.nombre),
        actions: [
          IconButton(
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resumen comisiones QR',
                          style: AdminUi.titleStyle(context),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Código: ${widget.negocio.codigo}\n'
                          'Pueblo promo gratis: ${widget.negocio.ciudad.isEmpty ? "— (definir ciudad)" : widget.negocio.ciudad}\n\n'
                          'Negocio (${NegocioAliadoConfig.pctComisionNegocio}%):\n'
                          '· Pendiente pagar: RD\$${pendienteNegocio.toStringAsFixed(2)}\n'
                          '· Ya pagado: RD\$${pagadoNegocio.toStringAsFixed(2)}\n\n'
                          'Taxista (${NegocioAliadoConfig.pctComisionTaxistaReferido}% fijo, '
                          'incluye EFECTIVO — sin 1.er viaje gratis):\n'
                          '· Comisión RAI cobrada en viajes cerrados: '
                          'RD\$${totalComisionTaxista15.toStringAsFixed(2)}',
                          style: AdminUi.bodyStyle(context),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Promo cliente: ${NegocioAliadoConfig.promoViajesM} viajes + '
                          '${NegocioAliadoConfig.promoViajesK} gratis solo dentro del pueblo '
                          '(no de pueblo a pueblo). Vigencia ${NegocioAliadoConfig.vigenciaDias} días.',
                          style: AdminUi.bodyStyle(context),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Clientes referidos (${_clientes.length})',
                    style: AdminUi.titleStyle(context)),
                const SizedBox(height: 8),
                if (_clientes.isEmpty)
                  Text('Ningún cliente con este código aún.',
                      style: AdminUi.bodyStyle(context))
                else
                  ..._clientes.map(
                    (c) => ListTile(
                      dense: true,
                      title: Text(
                        c.nombre.isEmpty ? c.uid.substring(0, 8) : c.nombre,
                      ),
                      subtitle: Text(
                        '${c.telefono.isEmpty ? "sin tel" : c.telefono}\n'
                        'Viajes promo: ${c.contadorPromo}/${NegocioAliadoConfig.promoViajesM} '
                        '· vence ${_fmtFecha(c.promoVenceAt)}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
                const SizedBox(height: 20),
                Text('Viajes cerrados con comisión (${_viajes.length})',
                    style: AdminUi.titleStyle(context)),
                const SizedBox(height: 8),
                if (_viajes.isEmpty)
                  Text(
                    'Cuando un cliente referido complete viajes, aparecen aquí con el 3%.',
                    style: AdminUi.bodyStyle(context),
                  )
                else
                  ..._viajes.map((v) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          'Negocio ${NegocioAliadoConfig.pctComisionNegocio}%: '
                          'RD\$${v.comisionNegocioRd.toStringAsFixed(2)} · '
                          'Taxista ${v.comisionTaxistaPct.toStringAsFixed(0)}%: '
                          'RD\$${v.comisionTaxistaRd.toStringAsFixed(2)}',
                        ),
                        subtitle: Text(
                          '${v.metodoPago.isEmpty ? "—" : v.metodoPago} · '
                          'RD\$${v.precioNominalRd.toStringAsFixed(0)} nominal\n'
                          '${v.origen} → ${v.destino}\n'
                          '${_fmtFecha(v.finalizadoAt)}'
                          '${v.esGratis ? " · 6.º GRATIS (local)" : ""}'
                          '${v.pagada ? " · NEGOCIO PAGADO" : " · NEGOCIO PENDIENTE"}',
                        ),
                        isThreeLine: true,
                        trailing: v.pagada
                            ? const Icon(Icons.check, color: Colors.green)
                            : TextButton(
                                onPressed: () async {
                                  await NegocioAliadoAdminRepo
                                      .marcarComisionPagada(v.viajeId);
                                  await _cargar();
                                },
                                child: const Text('Marcar pagado'),
                              ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
