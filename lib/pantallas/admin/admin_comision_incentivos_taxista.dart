import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/admin/admin_ui_theme.dart';
import 'package:flygo_nuevo/servicios/admin_config_service.dart';
import 'package:flygo_nuevo/widgets/admin_app_bar.dart';
import 'package:flygo_nuevo/widgets/admin_guia_uso.dart';
import 'package:flygo_nuevo/widgets/admin_drawer.dart';

class AdminComisionIncentivosTaxista extends StatefulWidget {
  const AdminComisionIncentivosTaxista({super.key});

  @override
  State<AdminComisionIncentivosTaxista> createState() =>
      _AdminComisionIncentivosTaxistaState();
}

class _EscalonRow {
  _EscalonRow({
    required this.viajesCtrl,
    required this.pctCtrl,
    required this.etiquetaCtrl,
  });

  final TextEditingController viajesCtrl;
  final TextEditingController pctCtrl;
  final TextEditingController etiquetaCtrl;

  void dispose() {
    viajesCtrl.dispose();
    pctCtrl.dispose();
    etiquetaCtrl.dispose();
  }

  Map<String, dynamic> toMap() => {
        'viajesMinimos': int.parse(viajesCtrl.text.trim()),
        'comisionPct': double.parse(
          pctCtrl.text.trim().replaceAll(',', '.'),
        ),
        'etiqueta': etiquetaCtrl.text.trim(),
      };
}

class _AdminComisionIncentivosTaxistaState
    extends State<AdminComisionIncentivosTaxista> {
  final _formKey = GlobalKey<FormState>();
  final _motivoCtrl = TextEditingController();

  bool _activo = false;
  String _ventana = 'semana';
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  final List<_EscalonRow> _escalones = [];

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('config').doc('comision_incentivos_taxista');

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _motivoCtrl.dispose();
    for (final e in _escalones) {
      e.dispose();
    }
    super.dispose();
  }

  int _toInt(dynamic v, {required int fb}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fb;
    return fb;
  }

  double _toDouble(dynamic v, {required double fb}) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim().replaceAll(',', '.')) ?? fb;
    return fb;
  }

  void _addEscalon({int viajes = 20, double pct = 15, String etiqueta = ''}) {
    setState(() {
      _escalones.add(
        _EscalonRow(
          viajesCtrl: TextEditingController(text: '$viajes'),
          pctCtrl: TextEditingController(
            text: pct == pct.roundToDouble() ? '${pct.round()}' : pct.toStringAsFixed(1),
          ),
          etiquetaCtrl: TextEditingController(
            text: etiqueta.isNotEmpty ? etiqueta : 'Conductor activo',
          ),
        ),
      );
    });
  }

  void _removeEscalon(int index) {
    setState(() {
      _escalones[index].dispose();
      _escalones.removeAt(index);
    });
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      for (final e in _escalones) {
        e.dispose();
      }
      _escalones.clear();

      final snap = await _ref.get();
      final d = snap.data() ?? {};
      _activo = d['activo'] == true;
      final ventanaRaw = (d['ventana'] ?? 'semana').toString().trim().toLowerCase();
      _ventana = ventanaRaw == 'mes' ? 'mes' : 'semana';

      final rawEsc = d['escalones'];
      if (rawEsc is List && rawEsc.isNotEmpty) {
        for (final item in rawEsc) {
          if (item is! Map) continue;
          final m = Map<String, dynamic>.from(item);
          _addEscalon(
            viajes: _toInt(m['viajesMinimos'], fb: 20).clamp(1, 999),
            pct: _toDouble(m['comisionPct'], fb: 15).clamp(0, 100),
            etiqueta: (m['etiqueta'] ?? '').toString(),
          );
        }
      } else {
        _addEscalon(viajes: 20, pct: 15, etiqueta: 'Conductor activo');
        _addEscalon(viajes: 40, pct: 12, etiqueta: 'Conductor estrella');
      }
    } catch (e) {
      _error = '$e';
      if (_escalones.isEmpty) {
        _addEscalon();
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_escalones.isEmpty) {
      setState(() => _error = 'Agrega al menos un escalón.');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      final escalones = _escalones.map((e) => e.toMap()).toList();
      await AdminConfigService.updateComisionIncentivosTaxistaConfig(
        activo: _activo,
        ventana: _ventana,
        escalones: escalones,
        motivo: _motivoCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incentivos actualizados')),
      );
      _motivoCtrl.clear();
      await _cargar();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
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
        guiaId: AdminGuiaIds.incentivos,
        title: 'Incentivos comisión taxista',
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
                      'Motiva conductores con comisión reducida al completar más viajes '
                      'en la ventana elegida. El % efectivo nunca supera el % global '
                      '(`config/comision`). El conteo se actualiza al finalizar cada viaje.',
                      style: TextStyle(color: AdminUi.muted(context), height: 1.45),
                    ),
                    const SizedBox(height: 20),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Programa activo'),
                      subtitle: Text(
                        _activo
                            ? 'Los taxistas pueden obtener % menor al cumplir escalones.'
                            : 'Solo se cuenta viajes; aplica siempre el % global.',
                      ),
                      value: _activo,
                      onChanged: _guardando
                          ? null
                          : (v) => setState(() => _activo = v),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _ventana,
                      decoration: const InputDecoration(
                        labelText: 'Ventana de conteo',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'semana',
                          child: Text('Semana (ISO, reinicia cada lunes)'),
                        ),
                        DropdownMenuItem(
                          value: 'mes',
                          child: Text('Mes calendario'),
                        ),
                      ],
                      onChanged: _guardando
                          ? null
                          : (v) {
                              if (v != null) setState(() => _ventana = v);
                            },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text(
                          'Escalones',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _guardando ? null : () => _addEscalon(),
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(_escalones.length, (i) {
                      final row = _escalones[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Nivel ${i + 1}',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  const Spacer(),
                                  if (_escalones.length > 1)
                                    IconButton(
                                      tooltip: 'Quitar',
                                      onPressed: _guardando ? null : () => _removeEscalon(i),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: row.viajesCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Viajes mínimos',
                                        border: OutlineInputBorder(),
                                      ),
                                      validator: (v) {
                                        final n = int.tryParse((v ?? '').trim());
                                        if (n == null || n < 1 || n > 999) {
                                          return '1–999';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: row.pctCtrl,
                                      keyboardType: const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                      decoration: const InputDecoration(
                                        labelText: 'Comisión RAI %',
                                        border: OutlineInputBorder(),
                                      ),
                                      validator: (v) {
                                        final n = double.tryParse(
                                          (v ?? '').trim().replaceAll(',', '.'),
                                        );
                                        if (n == null || n < 0 || n > 100) {
                                          return '0–100';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: row.etiquetaCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Etiqueta (visible al taxista)',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (v) {
                                  if ((v ?? '').trim().length < 2) return 'Mín. 2 caracteres';
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _motivoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Motivo del cambio (auditoría)',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 2,
                      maxLines: 3,
                      validator: (v) {
                        if ((v ?? '').trim().length < 6) {
                          return 'Mínimo 6 caracteres';
                        }
                        return null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _guardando ? null : _guardar,
                      icon: _guardando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_guardando ? 'Guardando…' : 'Guardar incentivos'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
