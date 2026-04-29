// lib/pantallas/admin/admin_tarifas.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/servicios/tarifa_service_unificado.dart';

import 'admin_ui_theme.dart';

class AdminTarifas extends StatefulWidget {
  const AdminTarifas({super.key});

  @override
  State<AdminTarifas> createState() => _AdminTarifasState();
}

class _AdminTarifasState extends State<AdminTarifas> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  // Controladores para tarifas de vehículos normales
  late TextEditingController _carroBaseCtrl;
  late TextEditingController _carroPorKmCtrl;
  late TextEditingController _carroMinimoCtrl;

  late TextEditingController _jeepetaBaseCtrl;
  late TextEditingController _jeepetaPorKmCtrl;
  late TextEditingController _jeepetaMinimoCtrl;

  late TextEditingController _minibusBaseCtrl;
  late TextEditingController _minibusPorKmCtrl;
  late TextEditingController _minibusMinimoCtrl;

  late TextEditingController _minivanBaseCtrl;
  late TextEditingController _minivanPorKmCtrl;
  late TextEditingController _minivanMinimoCtrl;

  late TextEditingController _autobusBaseCtrl;
  late TextEditingController _autobusPorKmCtrl;
  late TextEditingController _autobusMinimoCtrl;

  // Motor
  late TextEditingController _motorBaseCtrl;
  late TextEditingController _motorPorKmCtrl;
  late TextEditingController _motorMinimoCtrl;

  // Turismo
  late TextEditingController _turismoCarroBaseCtrl;
  late TextEditingController _turismoCarroPorKmCtrl;
  late TextEditingController _turismoCarroMinimoCtrl;

  late TextEditingController _turismoJeepetaBaseCtrl;
  late TextEditingController _turismoJeepetaPorKmCtrl;
  late TextEditingController _turismoJeepetaMinimoCtrl;

  late TextEditingController _turismoMinivanBaseCtrl;
  late TextEditingController _turismoMinivanPorKmCtrl;
  late TextEditingController _turismoMinivanMinimoCtrl;

  late TextEditingController _turismoBusBaseCtrl;
  late TextEditingController _turismoBusPorKmCtrl;
  late TextEditingController _turismoBusMinimoCtrl;

  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _inicializarControladores();
    _cargarDatos();
  }

  void _inicializarControladores() {
    _carroBaseCtrl = TextEditingController();
    _carroPorKmCtrl = TextEditingController();
    _carroMinimoCtrl = TextEditingController();

    _jeepetaBaseCtrl = TextEditingController();
    _jeepetaPorKmCtrl = TextEditingController();
    _jeepetaMinimoCtrl = TextEditingController();

    _minibusBaseCtrl = TextEditingController();
    _minibusPorKmCtrl = TextEditingController();
    _minibusMinimoCtrl = TextEditingController();

    _minivanBaseCtrl = TextEditingController();
    _minivanPorKmCtrl = TextEditingController();
    _minivanMinimoCtrl = TextEditingController();

    _autobusBaseCtrl = TextEditingController();
    _autobusPorKmCtrl = TextEditingController();
    _autobusMinimoCtrl = TextEditingController();

    _motorBaseCtrl = TextEditingController();
    _motorPorKmCtrl = TextEditingController();
    _motorMinimoCtrl = TextEditingController();

    _turismoCarroBaseCtrl = TextEditingController();
    _turismoCarroPorKmCtrl = TextEditingController();
    _turismoCarroMinimoCtrl = TextEditingController();

    _turismoJeepetaBaseCtrl = TextEditingController();
    _turismoJeepetaPorKmCtrl = TextEditingController();
    _turismoJeepetaMinimoCtrl = TextEditingController();

    _turismoMinivanBaseCtrl = TextEditingController();
    _turismoMinivanPorKmCtrl = TextEditingController();
    _turismoMinivanMinimoCtrl = TextEditingController();

    _turismoBusBaseCtrl = TextEditingController();
    _turismoBusPorKmCtrl = TextEditingController();
    _turismoBusMinimoCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _carroBaseCtrl.dispose();
    _carroPorKmCtrl.dispose();
    _carroMinimoCtrl.dispose();
    _jeepetaBaseCtrl.dispose();
    _jeepetaPorKmCtrl.dispose();
    _jeepetaMinimoCtrl.dispose();
    _minibusBaseCtrl.dispose();
    _minibusPorKmCtrl.dispose();
    _minibusMinimoCtrl.dispose();
    _minivanBaseCtrl.dispose();
    _minivanPorKmCtrl.dispose();
    _minivanMinimoCtrl.dispose();
    _autobusBaseCtrl.dispose();
    _autobusPorKmCtrl.dispose();
    _autobusMinimoCtrl.dispose();
    _motorBaseCtrl.dispose();
    _motorPorKmCtrl.dispose();
    _motorMinimoCtrl.dispose();
    _turismoCarroBaseCtrl.dispose();
    _turismoCarroPorKmCtrl.dispose();
    _turismoCarroMinimoCtrl.dispose();
    _turismoJeepetaBaseCtrl.dispose();
    _turismoJeepetaPorKmCtrl.dispose();
    _turismoJeepetaMinimoCtrl.dispose();
    _turismoMinivanBaseCtrl.dispose();
    _turismoMinivanPorKmCtrl.dispose();
    _turismoMinivanMinimoCtrl.dispose();
    _turismoBusBaseCtrl.dispose();
    _turismoBusPorKmCtrl.dispose();
    _turismoBusMinimoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    if (!mounted) return;
    setState(() => _cargando = true);

    try {
      final servicio = TarifaServiceUnificado();
      await servicio.recargar();
      final Map<String, dynamic> general = await servicio.getConfigGeneral();
      final Map<String, dynamic> turismo = await servicio.getConfigTurismo();

      if (!mounted) return;

      // Cargar valores de vehículos normales
      _carroBaseCtrl.text = _getValor(general, 'Carro', 'base', '50.0');
      _carroPorKmCtrl.text = _getValor(general, 'Carro', 'porKm', '25.0');
      _carroMinimoCtrl.text = _getValor(general, 'Carro', 'minimo', '150.0');

      _jeepetaBaseCtrl.text = _getValor(general, 'Jeepeta', 'base', '80.0');
      _jeepetaPorKmCtrl.text = _getValor(general, 'Jeepeta', 'porKm', '30.0');
      _jeepetaMinimoCtrl.text =
          _getValor(general, 'Jeepeta', 'minimo', '200.0');

      _minibusBaseCtrl.text = _getValor(general, 'Minibús', 'base', '120.0');
      _minibusPorKmCtrl.text = _getValor(general, 'Minibús', 'porKm', '35.0');
      _minibusMinimoCtrl.text =
          _getValor(general, 'Minibús', 'minimo', '300.0');

      _minivanBaseCtrl.text = _getValor(general, 'Minivan', 'base', '100.0');
      _minivanPorKmCtrl.text = _getValor(general, 'Minivan', 'porKm', '32.0');
      _minivanMinimoCtrl.text =
          _getValor(general, 'Minivan', 'minimo', '250.0');

      _autobusBaseCtrl.text = _getValor(
          general,
          'AutobusGuagua',
          'base',
          _getValor(
              general,
              'Autobús/Guagua',
              'base',
              _getValor(general, 'Autobús', 'base',
                  _getValor(general, 'Guagua', 'base', '200.0'))));
      _autobusPorKmCtrl.text = _getValor(
          general,
          'AutobusGuagua',
          'porKm',
          _getValor(
              general,
              'Autobús/Guagua',
              'porKm',
              _getValor(general, 'Autobús', 'porKm',
                  _getValor(general, 'Guagua', 'porKm', '45.0'))));
      _autobusMinimoCtrl.text = _getValor(
          general,
          'AutobusGuagua',
          'minimo',
          _getValor(
              general,
              'Autobús/Guagua',
              'minimo',
              _getValor(general, 'Autobús', 'minimo',
                  _getValor(general, 'Guagua', 'minimo', '500.0'))));

      _motorBaseCtrl.text = _getValor(general, 'motor', 'base', '30.0');
      _motorPorKmCtrl.text = _getValor(general, 'motor', 'porKm', '12.0');
      _motorMinimoCtrl.text = _getValor(general, 'motor', 'minimo', '80.0');

      // Cargar valores de turismo
      _turismoCarroBaseCtrl.text =
          _getValor(turismo, 'carro', 'tarifaBase', '80.0');
      _turismoCarroPorKmCtrl.text =
          _getValor(turismo, 'carro', 'tarifaKm', '35.0');
      _turismoCarroMinimoCtrl.text =
          _getValor(turismo, 'carro', 'precioMinimo', '250.0');

      _turismoJeepetaBaseCtrl.text =
          _getValor(turismo, 'jeepeta', 'tarifaBase', '150.0');
      _turismoJeepetaPorKmCtrl.text =
          _getValor(turismo, 'jeepeta', 'tarifaKm', '40.0');
      _turismoJeepetaMinimoCtrl.text =
          _getValor(turismo, 'jeepeta', 'precioMinimo', '500.0');

      _turismoMinivanBaseCtrl.text =
          _getValor(turismo, 'minivan', 'tarifaBase', '250.0');
      _turismoMinivanPorKmCtrl.text =
          _getValor(turismo, 'minivan', 'tarifaKm', '55.0');
      _turismoMinivanMinimoCtrl.text =
          _getValor(turismo, 'minivan', 'precioMinimo', '700.0');

      _turismoBusBaseCtrl.text =
          _getValor(turismo, 'bus', 'tarifaBase', '400.0');
      _turismoBusPorKmCtrl.text = _getValor(turismo, 'bus', 'tarifaKm', '75.0');
      _turismoBusMinimoCtrl.text =
          _getValor(turismo, 'bus', 'precioMinimo', '1200.0');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando tarifas: $e')),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _getValor(Map<String, dynamic> mapa, String clave, String subclave,
      String fallback) {
    try {
      final dynamic valor = mapa[clave]?[subclave];
      if (valor == null) return fallback;
      if (valor is num) return valor.toString();
      if (valor is String) return valor;
      return fallback;
    } catch (e) {
      return fallback;
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (!mounted) return;

    setState(() => _guardando = true);

    try {
      // ✅ Guardar tarifas de vehículos normales en tarifas/general
      final Map<String, dynamic> tarifasNormales = {
        'Carro': {
          'base': double.parse(_carroBaseCtrl.text),
          'porKm': double.parse(_carroPorKmCtrl.text),
          'minimo': double.parse(_carroMinimoCtrl.text),
        },
        'Jeepeta': {
          'base': double.parse(_jeepetaBaseCtrl.text),
          'porKm': double.parse(_jeepetaPorKmCtrl.text),
          'minimo': double.parse(_jeepetaMinimoCtrl.text),
        },
        'Minibús': {
          'base': double.parse(_minibusBaseCtrl.text),
          'porKm': double.parse(_minibusPorKmCtrl.text),
          'minimo': double.parse(_minibusMinimoCtrl.text),
        },
        'Minivan': {
          'base': double.parse(_minivanBaseCtrl.text),
          'porKm': double.parse(_minivanPorKmCtrl.text),
          'minimo': double.parse(_minivanMinimoCtrl.text),
        },
        'Autobús/Guagua': {
          'base': double.parse(_autobusBaseCtrl.text),
          'porKm': double.parse(_autobusPorKmCtrl.text),
          'minimo': double.parse(_autobusMinimoCtrl.text),
        },
        'AutobusGuagua': {
          'base': double.parse(_autobusBaseCtrl.text),
          'porKm': double.parse(_autobusPorKmCtrl.text),
          'minimo': double.parse(_autobusMinimoCtrl.text),
        },
        'Autobús': {
          'base': double.parse(_autobusBaseCtrl.text),
          'porKm': double.parse(_autobusPorKmCtrl.text),
          'minimo': double.parse(_autobusMinimoCtrl.text),
        },
        'Guagua': {
          'base': double.parse(_autobusBaseCtrl.text),
          'porKm': double.parse(_autobusPorKmCtrl.text),
          'minimo': double.parse(_autobusMinimoCtrl.text),
        },
        'motor': {
          'base': double.parse(_motorBaseCtrl.text),
          'porKm': double.parse(_motorPorKmCtrl.text),
          'minimo': double.parse(_motorMinimoCtrl.text),
        },
      };

      await _db
          .collection('tarifas')
          .doc('general')
          .set(tarifasNormales, SetOptions(merge: true));

      // ✅ Guardar tarifas de turismo en documentos separados (como espera el servicio)
      final batch = _db.batch();

      // Carro turismo
      batch.set(
        _db.collection('tarifa_turismo').doc('carro'),
        {
          'tarifaBase': double.parse(_turismoCarroBaseCtrl.text),
          'tarifaKm': double.parse(_turismoCarroPorKmCtrl.text),
          'precioMinimo': double.parse(_turismoCarroMinimoCtrl.text),
          'activo': true,
          'cobraPeaje': true,
        },
        SetOptions(merge: true),
      );

      // Jeepeta turismo
      batch.set(
        _db.collection('tarifa_turismo').doc('jeepeta'),
        {
          'tarifaBase': double.parse(_turismoJeepetaBaseCtrl.text),
          'tarifaKm': double.parse(_turismoJeepetaPorKmCtrl.text),
          'precioMinimo': double.parse(_turismoJeepetaMinimoCtrl.text),
          'activo': true,
          'cobraPeaje': true,
        },
        SetOptions(merge: true),
      );

      // Minivan turismo
      batch.set(
        _db.collection('tarifa_turismo').doc('minivan'),
        {
          'tarifaBase': double.parse(_turismoMinivanBaseCtrl.text),
          'tarifaKm': double.parse(_turismoMinivanPorKmCtrl.text),
          'precioMinimo': double.parse(_turismoMinivanMinimoCtrl.text),
          'activo': true,
          'cobraPeaje': true,
        },
        SetOptions(merge: true),
      );

      // Bus turismo
      batch.set(
        _db.collection('tarifa_turismo').doc('bus'),
        {
          'tarifaBase': double.parse(_turismoBusBaseCtrl.text),
          'tarifaKm': double.parse(_turismoBusPorKmCtrl.text),
          'precioMinimo': double.parse(_turismoBusMinimoCtrl.text),
          'activo': true,
          'cobraPeaje': true,
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      // Limpiar caché del servicio
      await TarifaServiceUnificado().recargar();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Tarifas guardadas correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error guardando: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
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
          hintStyle: TextStyle(
              color: AdminUi.secondary(context).withValues(alpha: 0.75)),
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        validator: (String? value) {
          if (value == null || value.isEmpty) return 'Requerido';
          if (double.tryParse(value) == null) return 'Número inválido';
          return null;
        },
      ),
    );
  }

  Widget _buildSeccion(String titulo, List<Widget> campos) {
    return Card(
      color: AdminUi.card(context),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              titulo,
              style: TextStyle(
                color: AdminUi.onCard(context),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...campos,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        iconTheme: IconThemeData(color: AdminUi.appBarFg(context)),
        title: Text('Administrar Tarifas',
            style: TextStyle(color: AdminUi.onCard(context))),
      ),
      body: _cargando
          ? Center(
              child: CircularProgressIndicator(
                  color: AdminUi.progressAccent(context)))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  _buildSeccion('🚗 VEHÍCULOS NORMALES', <Widget>[
                    Text('Carro',
                        style: TextStyle(color: AdminUi.secondary(context))),
                    Row(children: <Widget>[
                      Expanded(
                          child: _buildCampo(
                              label: 'Base', controller: _carroBaseCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Por km', controller: _carroPorKmCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Mínimo', controller: _carroMinimoCtrl)),
                    ]),
                    const SizedBox(height: 12),
                    Text('Jeepeta',
                        style: TextStyle(color: AdminUi.secondary(context))),
                    Row(children: <Widget>[
                      Expanded(
                          child: _buildCampo(
                              label: 'Base', controller: _jeepetaBaseCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Por km', controller: _jeepetaPorKmCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Mínimo', controller: _jeepetaMinimoCtrl)),
                    ]),
                    const SizedBox(height: 12),
                    Text('Minibús',
                        style: TextStyle(color: AdminUi.secondary(context))),
                    Row(children: <Widget>[
                      Expanded(
                          child: _buildCampo(
                              label: 'Base', controller: _minibusBaseCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Por km', controller: _minibusPorKmCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Mínimo', controller: _minibusMinimoCtrl)),
                    ]),
                    const SizedBox(height: 12),
                    Text('Minivan',
                        style: TextStyle(color: AdminUi.secondary(context))),
                    Row(children: <Widget>[
                      Expanded(
                          child: _buildCampo(
                              label: 'Base', controller: _minivanBaseCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Por km', controller: _minivanPorKmCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Mínimo', controller: _minivanMinimoCtrl)),
                    ]),
                    const SizedBox(height: 12),
                    Text('Autobús/Guagua',
                        style: TextStyle(color: AdminUi.secondary(context))),
                    Row(children: <Widget>[
                      Expanded(
                          child: _buildCampo(
                              label: 'Base', controller: _autobusBaseCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Por km', controller: _autobusPorKmCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Mínimo', controller: _autobusMinimoCtrl)),
                    ]),
                  ]),
                  _buildSeccion('🛵 MOTOR', <Widget>[
                    Row(children: <Widget>[
                      Expanded(
                          child: _buildCampo(
                              label: 'Base', controller: _motorBaseCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Por km', controller: _motorPorKmCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Mínimo', controller: _motorMinimoCtrl)),
                    ]),
                  ]),
                  _buildSeccion('🏝️ TURISMO - CARRO', <Widget>[
                    Row(children: <Widget>[
                      Expanded(
                          child: _buildCampo(
                              label: 'Base',
                              controller: _turismoCarroBaseCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Por km',
                              controller: _turismoCarroPorKmCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Mínimo',
                              controller: _turismoCarroMinimoCtrl)),
                    ]),
                  ]),
                  _buildSeccion('🏝️ TURISMO - JEEPETA', <Widget>[
                    Row(children: <Widget>[
                      Expanded(
                          child: _buildCampo(
                              label: 'Base',
                              controller: _turismoJeepetaBaseCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Por km',
                              controller: _turismoJeepetaPorKmCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Mínimo',
                              controller: _turismoJeepetaMinimoCtrl)),
                    ]),
                  ]),
                  _buildSeccion('🏝️ TURISMO - MINIVAN', <Widget>[
                    Row(children: <Widget>[
                      Expanded(
                          child: _buildCampo(
                              label: 'Base',
                              controller: _turismoMinivanBaseCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Por km',
                              controller: _turismoMinivanPorKmCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Mínimo',
                              controller: _turismoMinivanMinimoCtrl)),
                    ]),
                  ]),
                  _buildSeccion('🏝️ TURISMO - BUS', <Widget>[
                    Row(children: <Widget>[
                      Expanded(
                          child: _buildCampo(
                              label: 'Base', controller: _turismoBusBaseCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Por km',
                              controller: _turismoBusPorKmCtrl)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildCampo(
                              label: 'Mínimo',
                              controller: _turismoBusMinimoCtrl)),
                    ]),
                  ]),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _guardando ? null : _guardar,
                    icon: const Icon(Icons.save),
                    label:
                        Text(_guardando ? 'Guardando...' : 'Guardar Tarifas'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      foregroundColor:
                          Theme.of(context).colorScheme.onPrimaryContainer,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
