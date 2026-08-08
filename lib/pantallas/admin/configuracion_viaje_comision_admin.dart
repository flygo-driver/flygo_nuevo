// lib/pantallas/admin/configuracion_viaje_comision_admin.dart

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_ui_theme.dart';
import 'package:flygo_nuevo/servicios/admin_config_service.dart';
import 'package:flygo_nuevo/servicios/comision_viaje_pct_service.dart';
import 'package:flygo_nuevo/widgets/admin_app_bar.dart';
import 'package:flygo_nuevo/widgets/admin_guia_uso.dart';
import 'package:flygo_nuevo/widgets/admin_drawer.dart';

class ConfiguracionViajeComisionAdmin extends StatefulWidget {
  const ConfiguracionViajeComisionAdmin({super.key});

  @override
  State<ConfiguracionViajeComisionAdmin> createState() =>
      _ConfiguracionViajeComisionAdminState();
}

class _ConfiguracionViajeComisionAdminState
    extends State<ConfiguracionViajeComisionAdmin> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _pctEfectivoCtrl;
  late final TextEditingController _pctTransferenciaCtrl;
  late final TextEditingController _pctTarjetaCtrl;
  late final TextEditingController _motivoCtrl;
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pctEfectivoCtrl = TextEditingController();
    _pctTransferenciaCtrl = TextEditingController();
    _pctTarjetaCtrl = TextEditingController();
    _motivoCtrl = TextEditingController();
    _cargar();
  }

  @override
  void dispose() {
    _pctEfectivoCtrl.dispose();
    _pctTransferenciaCtrl.dispose();
    _pctTarjetaCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  static String _fmtPct(double p) =>
      p == p.roundToDouble() ? '${p.round()}' : p.toStringAsFixed(1);

  String? _validarPct(String? s) {
    final t = (s ?? '').trim().replaceAll(',', '.');
    final v = double.tryParse(t);
    if (v == null || !v.isFinite) return 'Número inválido';
    if (v < 0 || v > 100) return 'Debe estar entre 0 y 100';
    return null;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final cfg = await ComisionViajePctService.refresh(force: true);
      if (mounted) {
        _pctEfectivoCtrl.text = _fmtPct(cfg.efectivo);
        _pctTransferenciaCtrl.text = _fmtPct(cfg.transferencia);
        _pctTarjetaCtrl.text = _fmtPct(cfg.tarjeta);
      }
    } catch (e) {
      if (mounted) _error = '$e';
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final efectivo =
          double.parse(_pctEfectivoCtrl.text.trim().replaceAll(',', '.'));
      final transferencia = double.parse(
        _pctTransferenciaCtrl.text.trim().replaceAll(',', '.'),
      );
      final tarjeta =
          double.parse(_pctTarjetaCtrl.text.trim().replaceAll(',', '.'));
      await AdminConfigService.setComisionPorcentaje(
        porcentaje: efectivo,
        porcentajeTransferencia: transferencia,
        porcentajeTarjeta: tarjeta,
        motivo: _motivoCtrl.text.trim(),
      );
      await ComisionViajePctService.refresh(force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Comisiones guardadas (efectivo, transferencia, tarjeta)'),
          backgroundColor: Colors.green,
        ),
      );
      _motivoCtrl.clear();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() => _error = e.message ?? e.code);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: const AdminAppBar(
        guiaId: AdminGuiaIds.comisionEfectivo,
        title: 'Comisiones RAI por método',
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Corazón del negocio: RAI retiene un % del total del viaje. '
                      'El servidor calcula `comision_cents` al cerrar el viaje con la '
                      'fórmula oficial (redondeo a 2 decimales en RD\$). '
                      'Los tres valores se guardan juntos en `config/comision`.',
                      style: TextStyle(
                        color: AdminUi.muted(context),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Material(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Apertura sugerida: efectivo 10% · transferencia 15% · tarjeta 15%. '
                          'Podés cambiarlos cuando quieras; viajes ya cerrados conservan su comisión.',
                          style: TextStyle(
                            color: AdminUi.onCard(context),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Material(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Vigente ahora en app',
                              style: TextStyle(
                                color: AdminUi.onCard(context),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Efectivo (prepago): '
                              '${PlataformaEconomia.comisionViajePorcentaje}%',
                              style: TextStyle(color: AdminUi.secondary(context)),
                            ),
                            Text(
                              'Transferencia: '
                              '${PlataformaEconomia.comisionTransferenciaPorcentaje}%',
                              style: TextStyle(color: AdminUi.secondary(context)),
                            ),
                            Text(
                              'Tarjeta (AZUL): '
                              '${PlataformaEconomia.comisionTarjetaPorcentaje}%',
                              style: TextStyle(color: AdminUi.secondary(context)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _pctEfectivoCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Efectivo (%)',
                        helperText:
                            'Comisión descontada del prepago del taxista al cerrar viaje.',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validarPct,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _pctTransferenciaCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Transferencia (%)',
                        helperText:
                            'RAI retiene al liquidar; el neto va al chofer por ACH.',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validarPct,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _pctTarjetaCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Tarjeta (%)',
                        helperText: 'Cobro AZUL; RAI retiene; neto en lote semanal.',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validarPct,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _motivoCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Motivo (mín. 6 caracteres, auditoría obligatoria)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (s) {
                        final t = (s ?? '').trim();
                        if (t.length < 6) return 'Motivo demasiado corto';
                        return null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style:
                            TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _guardando ? null : _guardar,
                      child: _guardando
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Guardar los tres porcentajes'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
