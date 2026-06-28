// lib/pantallas/admin/admin_tarifas_tramos_panel.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/modelo/tarifas_tramos_config.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_ui_theme.dart';
import 'package:flygo_nuevo/servicios/admin_config_service.dart';
import 'package:flygo_nuevo/servicios/tarifa_service_unificado.dart';

/// Formulario completo de `config/tarifas_tramos` (reutilizable en Tarifas y drawer).
class AdminTarifasTramosPanel extends StatefulWidget {
  const AdminTarifasTramosPanel({super.key, this.embedded = false});

  /// En [AdminTarifas]: mismo scroll, tramos arriba sin pestañas.
  final bool embedded;

  @override
  State<AdminTarifasTramosPanel> createState() =>
      _AdminTarifasTramosPanelState();
}

class _AdminTarifasTramosPanelState extends State<AdminTarifasTramosPanel> {
  final _formKey = GlobalKey<FormState>();
  final _ref =
      FirebaseFirestore.instance.collection('config').doc('tarifas_tramos');

  bool _sincronizando = false;
  bool _guardando = false;
  bool _tramosActivo = true;
  bool _promoSoloLocal = true;
  Map<String, List<double>> _porVehiculoExtra = {};

  late TextEditingController _tramo1Ctrl;
  late TextEditingController _tramo2Ctrl;
  late TextEditingController _tramo3Ctrl;
  late TextEditingController _minimoLargaCtrl;
  late TextEditingController _distanciaMaxKmCtrl;
  late TextEditingController _carroT1Ctrl;
  late TextEditingController _carroT2Ctrl;
  late TextEditingController _carroT3Ctrl;
  late TextEditingController _carroT4Ctrl;
  late TextEditingController _jeepetaT1Ctrl;
  late TextEditingController _jeepetaT2Ctrl;
  late TextEditingController _jeepetaT3Ctrl;
  late TextEditingController _jeepetaT4Ctrl;
  late TextEditingController _minivanT1Ctrl;
  late TextEditingController _minivanT2Ctrl;
  late TextEditingController _minivanT3Ctrl;
  late TextEditingController _minivanT4Ctrl;
  late TextEditingController _minibusT1Ctrl;
  late TextEditingController _minibusT2Ctrl;
  late TextEditingController _minibusT3Ctrl;
  late TextEditingController _minibusT4Ctrl;
  late TextEditingController _autobusT1Ctrl;
  late TextEditingController _autobusT2Ctrl;
  late TextEditingController _autobusT3Ctrl;
  late TextEditingController _autobusT4Ctrl;
  late TextEditingController _motorT1Ctrl;
  late TextEditingController _motorT2Ctrl;
  late TextEditingController _motorT3Ctrl;
  late TextEditingController _motorT4Ctrl;

  static const Set<String> _clavesFormulario = {
    'Carro',
    'Jeepeta',
    'Minivan',
    'Minibús',
    'AutobusGuagua',
    'motor',
    'carro',
    'jeepeta',
    'minivan',
    'bus',
  };

  @override
  void initState() {
    super.initState();
    _tramo1Ctrl = TextEditingController(text: '40');
    _tramo2Ctrl = TextEditingController(text: '80');
    _tramo3Ctrl = TextEditingController(text: '140');
    _minimoLargaCtrl = TextEditingController(text: '1200');
    _distanciaMaxKmCtrl = TextEditingController(text: '800');
    _carroT1Ctrl = TextEditingController(text: '25');
    _carroT2Ctrl = TextEditingController(text: '45');
    _carroT3Ctrl = TextEditingController(text: '60');
    _carroT4Ctrl = TextEditingController(text: '72');
    _jeepetaT1Ctrl = TextEditingController(text: '30');
    _jeepetaT2Ctrl = TextEditingController(text: '50');
    _jeepetaT3Ctrl = TextEditingController(text: '65');
    _jeepetaT4Ctrl = TextEditingController(text: '80');
    _minivanT1Ctrl = TextEditingController(text: '32');
    _minivanT2Ctrl = TextEditingController(text: '52');
    _minivanT3Ctrl = TextEditingController(text: '68');
    _minivanT4Ctrl = TextEditingController(text: '82');
    _minibusT1Ctrl = TextEditingController(text: '35');
    _minibusT2Ctrl = TextEditingController(text: '55');
    _minibusT3Ctrl = TextEditingController(text: '70');
    _minibusT4Ctrl = TextEditingController(text: '85');
    _autobusT1Ctrl = TextEditingController(text: '45');
    _autobusT2Ctrl = TextEditingController(text: '65');
    _autobusT3Ctrl = TextEditingController(text: '80');
    _autobusT4Ctrl = TextEditingController(text: '95');
    _motorT1Ctrl = TextEditingController(text: '12');
    _motorT2Ctrl = TextEditingController(text: '22');
    _motorT3Ctrl = TextEditingController(text: '35');
    _motorT4Ctrl = TextEditingController(text: '42');
    _cargar();
  }

  @override
  void dispose() {
    _tramo1Ctrl.dispose();
    _tramo2Ctrl.dispose();
    _tramo3Ctrl.dispose();
    _minimoLargaCtrl.dispose();
    _distanciaMaxKmCtrl.dispose();
    _carroT1Ctrl.dispose();
    _carroT2Ctrl.dispose();
    _carroT3Ctrl.dispose();
    _carroT4Ctrl.dispose();
    _jeepetaT1Ctrl.dispose();
    _jeepetaT2Ctrl.dispose();
    _jeepetaT3Ctrl.dispose();
    _jeepetaT4Ctrl.dispose();
    _minivanT1Ctrl.dispose();
    _minivanT2Ctrl.dispose();
    _minivanT3Ctrl.dispose();
    _minivanT4Ctrl.dispose();
    _minibusT1Ctrl.dispose();
    _minibusT2Ctrl.dispose();
    _minibusT3Ctrl.dispose();
    _minibusT4Ctrl.dispose();
    _autobusT1Ctrl.dispose();
    _autobusT2Ctrl.dispose();
    _autobusT3Ctrl.dispose();
    _autobusT4Ctrl.dispose();
    _motorT1Ctrl.dispose();
    _motorT2Ctrl.dispose();
    _motorT3Ctrl.dispose();
    _motorT4Ctrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() => _sincronizando = true);
    try {
      await TarifaServiceUnificado().recargar();
      final snap = await _ref.get(const GetOptions(source: Source.server));
      if (!mounted) return;
      final tramos = TarifasTramosConfig.fromFirestore(snap.data());
      _aplicarEnFormulario(tramos);
      _porVehiculoExtra = Map<String, List<double>>.from(tramos.porVehiculo)
        ..removeWhere((k, _) => _clavesFormulario.contains(k));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Usando valores locales. Firebase: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  void _aplicarEnFormulario(TarifasTramosConfig tramos) {
    _tramosActivo = tramos.activo;
    _promoSoloLocal = tramos.promoAplicaSoloTramoLocal;
    if (tramos.tramosKm.length >= 3) {
      _tramo1Ctrl.text = tramos.tramosKm[0].toStringAsFixed(0);
      _tramo2Ctrl.text = tramos.tramosKm[1].toStringAsFixed(0);
      _tramo3Ctrl.text = tramos.tramosKm[2].toStringAsFixed(0);
    }
    _minimoLargaCtrl.text = tramos.minimoLargaDistanciaRd.toStringAsFixed(0);
    _distanciaMaxKmCtrl.text =
        tramos.distanciaMaximaCotizableKm.toStringAsFixed(0);
    _setRates('Carro', tramos, _carroT1Ctrl, _carroT2Ctrl, _carroT3Ctrl,
        _carroT4Ctrl, '25', '45', '60', '72');
    _setRates('Jeepeta', tramos, _jeepetaT1Ctrl, _jeepetaT2Ctrl, _jeepetaT3Ctrl,
        _jeepetaT4Ctrl, '30', '50', '65', '80');
    _setRates('Minivan', tramos, _minivanT1Ctrl, _minivanT2Ctrl, _minivanT3Ctrl,
        _minivanT4Ctrl, '32', '52', '68', '82');
    _setRates('Minibús', tramos, _minibusT1Ctrl, _minibusT2Ctrl,
        _minibusT3Ctrl, _minibusT4Ctrl, '35', '55', '70', '85');
    _setRates('AutobusGuagua', tramos, _autobusT1Ctrl, _autobusT2Ctrl,
        _autobusT3Ctrl, _autobusT4Ctrl, '45', '65', '80', '95');
    _setRates('motor', tramos, _motorT1Ctrl, _motorT2Ctrl, _motorT3Ctrl,
        _motorT4Ctrl, '12', '22', '35', '42');
  }

  void _setRates(
    String clave,
    TarifasTramosConfig tramos,
    TextEditingController t1,
    TextEditingController t2,
    TextEditingController t3,
    TextEditingController t4,
    String d1,
    String d2,
    String d3,
    String d4,
  ) {
    final rates =
        tramos.ratesFor(clave, porKmLocal: double.tryParse(d1) ?? 25);
    if (rates == null || rates.length < 4) {
      t1.text = d1;
      t2.text = d2;
      t3.text = d3;
      t4.text = d4;
      return;
    }
    t1.text = rates[0].toStringAsFixed(0);
    t2.text = rates[1].toStringAsFixed(0);
    t3.text = rates[2].toStringAsFixed(0);
    t4.text = rates[3].toStringAsFixed(0);
  }

  List<double> _ratesFrom(
    TextEditingController t1,
    TextEditingController t2,
    TextEditingController t3,
    TextEditingController t4,
  ) {
    return <double>[
      double.parse(t1.text),
      double.parse(t2.text),
      double.parse(t3.text),
      double.parse(t4.text),
    ];
  }

  TarifasTramosConfig _desdeFormulario() {
    final tramosKm = <double>[
      double.parse(_tramo1Ctrl.text),
      double.parse(_tramo2Ctrl.text),
      double.parse(_tramo3Ctrl.text),
    ]..sort();

    final carro =
        _ratesFrom(_carroT1Ctrl, _carroT2Ctrl, _carroT3Ctrl, _carroT4Ctrl);
    final jeepeta = _ratesFrom(
        _jeepetaT1Ctrl, _jeepetaT2Ctrl, _jeepetaT3Ctrl, _jeepetaT4Ctrl);
    final minivan = _ratesFrom(
        _minivanT1Ctrl, _minivanT2Ctrl, _minivanT3Ctrl, _minivanT4Ctrl);
    final minibusRates = _ratesFrom(
        _minibusT1Ctrl, _minibusT2Ctrl, _minibusT3Ctrl, _minibusT4Ctrl);
    final autobus = _ratesFrom(
        _autobusT1Ctrl, _autobusT2Ctrl, _autobusT3Ctrl, _autobusT4Ctrl);
    final motor =
        _ratesFrom(_motorT1Ctrl, _motorT2Ctrl, _motorT3Ctrl, _motorT4Ctrl);

    return TarifasTramosConfig(
      activo: _tramosActivo,
      tramosKm: tramosKm,
      minimoLargaDistanciaRd: double.parse(_minimoLargaCtrl.text),
      promoAplicaSoloTramoLocal: _promoSoloLocal,
      distanciaMaximaCotizableKm: double.parse(_distanciaMaxKmCtrl.text),
      porVehiculo: <String, List<double>>{
        'Carro': carro,
        'Jeepeta': jeepeta,
        'Minivan': minivan,
        'Minibús': minibusRates,
        'AutobusGuagua': autobus,
        'motor': motor,
        'carro': carro,
        'jeepeta': jeepeta,
        'minivan': minivan,
        'bus': autobus,
        ..._porVehiculoExtra,
      },
    );
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final motivo = await _pedirMotivo();
    if (motivo == null) return;
    setState(() => _guardando = true);
    try {
      await AdminConfigService.updateTarifasTramosConfig(
        tarifasTramos: _desdeFormulario().toFirestore(),
        motivo: motivo,
      );
      await TarifaServiceUnificado().recargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Tramos larga distancia guardados'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<String?> _pedirMotivo() async {
    final ctrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AdminUi.dialogSurface(ctx),
          title: Text(
            'Motivo del cambio',
            style: TextStyle(color: AdminUi.onCard(ctx)),
          ),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Ej: Ajuste tramos interurbanos / corrección mínimo',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      );
      if (ok != true) return null;
      final m = ctrl.text.trim();
      if (m.length < 6) return null;
      return m;
    } finally {
      ctrl.dispose();
    }
  }

  Widget _buildCampo({
    required String label,
    required TextEditingController controller,
    String? hint,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: TextStyle(color: AdminUi.onCard(context)),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: AdminUi.secondary(context)),
          filled: true,
          fillColor: AdminUi.inputFill(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AdminUi.borderSubtle(context)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AdminUi.borderSubtle(context)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: cs.primary, width: 1.4),
          ),
        ),
        validator: (v) {
          if (v == null || v.isEmpty) return 'Requerido';
          if (double.tryParse(v) == null) return 'Número inválido';
          return null;
        },
      ),
    );
  }

  Widget _buildRatesRow(
    String titulo,
    TextEditingController t1,
    TextEditingController t2,
    TextEditingController t3,
    TextEditingController t4,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo,
            style: TextStyle(
                color: AdminUi.onCard(context), fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _buildCampo(label: '0–40 RD\$/km', controller: t1)),
            const SizedBox(width: 6),
            Expanded(child: _buildCampo(label: '40–80', controller: t2)),
            const SizedBox(width: 6),
            Expanded(child: _buildCampo(label: '80–140', controller: t3)),
            const SizedBox(width: 6),
            Expanded(child: _buildCampo(label: '140+', controller: t4)),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  List<Widget> _contenidoTramos(BuildContext context) {
    return [
          if (_sincronizando)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AdminUi.progressAccent(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Sincronizando con Firebase…',
                    style: TextStyle(
                      color: AdminUi.secondary(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _tramosActivo
                  ? Colors.green.withValues(alpha: 0.14)
                  : Colors.orange.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _tramosActivo ? Colors.green : Colors.orange,
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tramosActivo
                      ? '✅ Tramos ACTIVOS en producción'
                      : '⚠️ Tramos APAGADOS — tarifa única por km',
                  style: TextStyle(
                    color: AdminUi.onCard(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Firebase config/tarifas_tramos · > 40 km = interurbano (SD→Bávaro)',
                  style: TextStyle(
                    color: AdminUi.secondary(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: AdminUi.card(context),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Activar tramos larga distancia',
                        style: TextStyle(
                            color: AdminUi.onCard(context),
                            fontWeight: FontWeight.w800)),
                    subtitle: Text(
                      'Dejar ON en producción.',
                      style: TextStyle(
                          color: AdminUi.secondary(context), fontSize: 12),
                    ),
                    value: _tramosActivo,
                    onChanged: (v) => setState(() => _tramosActivo = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Promo solo en tramo local',
                        style: TextStyle(color: AdminUi.onCard(context))),
                    subtitle: Text(
                      'MxK no descuenta viajes largos.',
                      style: TextStyle(
                          color: AdminUi.secondary(context), fontSize: 12),
                    ),
                    value: _promoSoloLocal,
                    onChanged: (v) => setState(() => _promoSoloLocal = v),
                  ),
                  Row(
                    children: [
                      Expanded(
                          child: _buildCampo(
                              label: 'Tramo 1 (km)', controller: _tramo1Ctrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Tramo 2 (km)', controller: _tramo2Ctrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Tramo 3 (km)', controller: _tramo3Ctrl)),
                    ],
                  ),
                  _buildCampo(
                    label: 'Mínimo larga distancia (RD\$)',
                    controller: _minimoLargaCtrl,
                  ),
                  _buildCampo(
                    label: 'Distancia máxima cotizable (km)',
                    controller: _distanciaMaxKmCtrl,
                    hint: 'Tope técnico — ej. 800',
                  ),
                  const SizedBox(height: 8),
                  Text('RD\$ / km por tramo',
                      style: TextStyle(
                          color: AdminUi.onCard(context),
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildRatesRow('Carro', _carroT1Ctrl, _carroT2Ctrl,
                      _carroT3Ctrl, _carroT4Ctrl),
                  _buildRatesRow('Jeepeta', _jeepetaT1Ctrl, _jeepetaT2Ctrl,
                      _jeepetaT3Ctrl, _jeepetaT4Ctrl),
                  _buildRatesRow('Minivan', _minivanT1Ctrl, _minivanT2Ctrl,
                      _minivanT3Ctrl, _minivanT4Ctrl),
                  _buildRatesRow('Minibús', _minibusT1Ctrl, _minibusT2Ctrl,
                      _minibusT3Ctrl, _minibusT4Ctrl),
                  _buildRatesRow('Autobús/Guagua', _autobusT1Ctrl,
                      _autobusT2Ctrl, _autobusT3Ctrl, _autobusT4Ctrl),
                  _buildRatesRow('Motor', _motorT1Ctrl, _motorT2Ctrl,
                      _motorT3Ctrl, _motorT4Ctrl),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: const Icon(Icons.save),
            label: Text(_guardando
                ? 'Guardando...'
                : 'Guardar tramos larga distancia'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
        ];
  }

  @override
  Widget build(BuildContext context) {
    final children = _contenidoTramos(context);

    return Form(
      key: _formKey,
      child: widget.embedded
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: children,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: children,
            ),
    );
  }
}
