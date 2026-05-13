// lib/pantallas/admin/configuracion_viaje_comision_admin.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_ui_theme.dart';
import 'package:flygo_nuevo/servicios/admin_config_service.dart';
import 'package:flygo_nuevo/servicios/comision_viaje_pct_service.dart';

class ConfiguracionViajeComisionAdmin extends StatefulWidget {
  const ConfiguracionViajeComisionAdmin({super.key});

  @override
  State<ConfiguracionViajeComisionAdmin> createState() =>
      _ConfiguracionViajeComisionAdminState();
}

class _ConfiguracionViajeComisionAdminState
    extends State<ConfiguracionViajeComisionAdmin> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _pctCtrl;
  late final TextEditingController _motivoCtrl;
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pctCtrl = TextEditingController();
    _motivoCtrl = TextEditingController();
    _cargar();
  }

  @override
  void dispose() {
    _pctCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await ComisionViajePctService.refresh(force: true);
      final snap = await FirebaseFirestore.instance
          .collection('config')
          .doc('comision')
          .get();
      final raw = snap.data()?['porcentaje'];
      final double p = raw is num ? raw.toDouble() : 20.0;
      if (mounted) {
        _pctCtrl.text = (p == p.roundToDouble() ? p.round() : p).toString();
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
      final pct = double.parse(_pctCtrl.text.trim().replaceAll(',', '.'));
      await AdminConfigService.setComisionPorcentaje(
        porcentaje: pct,
        motivo: _motivoCtrl.text.trim(),
      );
      await ComisionViajePctService.refresh(force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Porcentaje actualizado')),
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
    final bg = AdminUi.scaffold(context);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Comisión viaje (efectivo)'),
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
                      'Porcentaje global sobre el total del viaje en efectivo '
                      '(misma fórmula que en Cloud Functions: redondeo a 2 decimales en RD\$). '
                      'Valor en app ahora: ${PlataformaEconomia.comisionViajePorcentaje}%.',
                      style: TextStyle(
                        color: AdminUi.muted(context),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _pctCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Porcentaje (0–100)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (s) {
                        final t = (s ?? '').trim().replaceAll(',', '.');
                        final v = double.tryParse(t);
                        if (v == null || !v.isFinite) {
                          return 'Número inválido';
                        }
                        if (v < 0 || v > 100) {
                          return 'Debe estar entre 0 y 100';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _motivoCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Motivo (mín. 6 caracteres, auditoría)',
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
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
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
                          : const Text('Guardar'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
