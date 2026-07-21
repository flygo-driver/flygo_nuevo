// lib/pantallas/admin/admin_corporativo_tarifas_config.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flygo_nuevo/pantallas/admin/admin_ui_theme.dart';
import 'package:flygo_nuevo/servicios/admin_config_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_tarifa_config_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_tarifa_modelos.dart';
import 'package:flygo_nuevo/widgets/admin_app_bar.dart';
import 'package:flygo_nuevo/widgets/admin_guia_uso.dart';
import 'package:flygo_nuevo/widgets/admin_drawer.dart';

class AdminCorporativoTarifasConfigPage extends StatefulWidget {
  const AdminCorporativoTarifasConfigPage({super.key});

  @override
  State<AdminCorporativoTarifasConfigPage> createState() =>
      _AdminCorporativoTarifasConfigPageState();
}

class _AdminCorporativoTarifasConfigPageState
    extends State<AdminCorporativoTarifasConfigPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _minimoCtrl;
  late final TextEditingController _factorKmCtrl;
  late final TextEditingController _zonaCtrl;
  late final TextEditingController _transferCtrl;
  late final TextEditingController _isrCtrl;
  late final TextEditingController _itbisCtrl;
  late final TextEditingController _comisionCtrl;
  late final TextEditingController _dinamicaBaseCtrl;
  late final TextEditingController _dinamicaKmCortoCtrl;
  late final TextEditingController _dinamicaKmLargoCtrl;
  late final TextEditingController _dinamicaMinCtrl;
  late final TextEditingController _dinamicaMinutosKmCtrl;
  late final TextEditingController _combustibleLitroCtrl;
  late final TextEditingController _rendimientoKmCtrl;
  late final TextEditingController _factorOperativoCtrl;
  late final TextEditingController _recargoEmpresaCtrl;
  late final TextEditingController _motivoCtrl;
  bool _usarComisionGlobal = false;
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _minimoCtrl = TextEditingController();
    _factorKmCtrl = TextEditingController();
    _zonaCtrl = TextEditingController();
    _transferCtrl = TextEditingController();
    _isrCtrl = TextEditingController();
    _itbisCtrl = TextEditingController();
    _comisionCtrl = TextEditingController();
    _dinamicaBaseCtrl = TextEditingController();
    _dinamicaKmCortoCtrl = TextEditingController();
    _dinamicaKmLargoCtrl = TextEditingController();
    _dinamicaMinCtrl = TextEditingController();
    _dinamicaMinutosKmCtrl = TextEditingController();
    _combustibleLitroCtrl = TextEditingController();
    _rendimientoKmCtrl = TextEditingController();
    _factorOperativoCtrl = TextEditingController();
    _recargoEmpresaCtrl = TextEditingController();
    _motivoCtrl = TextEditingController();
    _cargar();
  }

  @override
  void dispose() {
    _minimoCtrl.dispose();
    _factorKmCtrl.dispose();
    _zonaCtrl.dispose();
    _transferCtrl.dispose();
    _isrCtrl.dispose();
    _itbisCtrl.dispose();
    _comisionCtrl.dispose();
    _dinamicaBaseCtrl.dispose();
    _dinamicaKmCortoCtrl.dispose();
    _dinamicaKmLargoCtrl.dispose();
    _dinamicaMinCtrl.dispose();
    _dinamicaMinutosKmCtrl.dispose();
    _combustibleLitroCtrl.dispose();
    _rendimientoKmCtrl.dispose();
    _factorOperativoCtrl.dispose();
    _recargoEmpresaCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  void _fill(CorporativoTarifaConfig cfg) {
    _minimoCtrl.text = cfg.minimoViajeRd.round().toString();
    _factorKmCtrl.text = cfg.factorKmCarretera.toStringAsFixed(2);
    _zonaCtrl.text = cfg.recargoZonaDificilPorcentaje.toStringAsFixed(0);
    _transferCtrl.text =
        (cfg.tasaImpuestoTransferencia * 100).toStringAsFixed(2);
    _isrCtrl.text = cfg.retencionIsrPorcentaje.toStringAsFixed(0);
    _itbisCtrl.text = cfg.itbisPorcentaje.toStringAsFixed(0);
    _comisionCtrl.text = cfg.comisionPlataformaPorcentaje.toStringAsFixed(0);
    _dinamicaBaseCtrl.text = cfg.dinamicaBaseRd.round().toString();
    _dinamicaKmCortoCtrl.text = cfg.dinamicaPorKmCortoRd.toStringAsFixed(1);
    _dinamicaKmLargoCtrl.text = cfg.dinamicaPorKmLargoRd.toStringAsFixed(0);
    _dinamicaMinCtrl.text = cfg.dinamicaPorMinutoRd.toStringAsFixed(0);
    _dinamicaMinutosKmCtrl.text = cfg.dinamicaMinutosPorKm.toStringAsFixed(2);
    _combustibleLitroCtrl.text = cfg.precioCombustibleLitroRd.round().toString();
    _rendimientoKmCtrl.text =
        cfg.rendimientoVehiculoKmPorLitro.toStringAsFixed(1);
    _factorOperativoCtrl.text =
        cfg.factorOperativoSobreCombustible.toStringAsFixed(2);
    _recargoEmpresaCtrl.text =
        cfg.recargoEmpresaServicioPorcentaje.toStringAsFixed(0);
    _usarComisionGlobal = cfg.usarComisionGlobalViaje;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final cfg = await CorporativoTarifaConfigService.refresh(force: true);
      if (mounted) _fill(cfg);
    } catch (e) {
      if (mounted) _error = '$e';
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  double _parsePct(TextEditingController c) =>
      double.parse(c.text.trim().replaceAll(',', '.'));

  /// Tarifa B2B justa: cortas razonables, largas más conscientes
  /// (buscar empleados, esperar y llevarlos a casa).
  void _aplicarTarifaJustaB2b() {
    setState(() {
      _dinamicaBaseCtrl.text = '200';
      _dinamicaKmCortoCtrl.text = '18';
      _dinamicaKmLargoCtrl.text = '24';
      _dinamicaMinCtrl.text = '7';
      _dinamicaMinutosKmCtrl.text = '1.4';
      _minimoCtrl.text = '550';
      _factorKmCtrl.text = '1.15';
      _comisionCtrl.text = '10';
      _combustibleLitroCtrl.text = '330';
      _rendimientoKmCtrl.text = '11';
      _factorOperativoCtrl.text = '1.35';
      _recargoEmpresaCtrl.text = '5';
      if (_motivoCtrl.text.trim().length < 6) {
        _motivoCtrl.text =
            'Tarifa RD 2026: combustible + 5% empresa + 90% chofer';
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Valores cargados. Tocá «Guardar configuración» para aplicarlos en producción.',
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final pctTransfer = _parsePct(_transferCtrl);
        // Admin ingresa 0.20 (= 0.20%). Si pone 0.002 por error, se acepta como tasa.
        final tasa = pctTransfer > 0 && pctTransfer < 0.01
            ? pctTransfer
            : pctTransfer / 100.0;
        final cfg = CorporativoTarifaConfig(
          modeloTarifa: CorporativoTarifaDinamicaModel.modeloId,
          minimoViajeRd: double.parse(_minimoCtrl.text.trim()),
          factorKmCarretera: double.parse(
            _factorKmCtrl.text.trim().replaceAll(',', '.'),
          ),
          recargoZonaDificilPorcentaje: _parsePct(_zonaCtrl),
          tasaImpuestoTransferencia: tasa,
          recargoTransferenciaPorcentaje: tasa * 100.0,
          retencionIsrPorcentaje: _parsePct(_isrCtrl),
          itbisPorcentaje: _parsePct(_itbisCtrl),
          incluirItbisEnPrecioViaje: false,
          usarComisionGlobalViaje: _usarComisionGlobal,
          comisionPlataformaPorcentaje: _parsePct(_comisionCtrl),
          dinamicaBaseRd: double.parse(_dinamicaBaseCtrl.text.trim()),
          dinamicaPorKmCortoRd: double.parse(
            _dinamicaKmCortoCtrl.text.trim().replaceAll(',', '.'),
          ),
          dinamicaPorKmLargoRd: double.parse(_dinamicaKmLargoCtrl.text.trim()),
          dinamicaPorMinutoRd: double.parse(_dinamicaMinCtrl.text.trim()),
          dinamicaUmbralKmLargo: 12,
          dinamicaMinutosPorKm: double.parse(
            _dinamicaMinutosKmCtrl.text.trim().replaceAll(',', '.'),
          ),
          dinamicaMinutosPorParada: 4,
          dinamicaMinutosMinimo: 10,
          precioCombustibleLitroRd: double.parse(_combustibleLitroCtrl.text.trim()),
          rendimientoVehiculoKmPorLitro: double.parse(
            _rendimientoKmCtrl.text.trim().replaceAll(',', '.'),
          ),
          factorOperativoSobreCombustible: double.parse(
            _factorOperativoCtrl.text.trim().replaceAll(',', '.'),
          ),
          recargoEmpresaServicioPorcentaje: _parsePct(_recargoEmpresaCtrl),
        );
      await AdminConfigService.setCorporativoTarifaConfig(
        config: cfg,
        motivo: _motivoCtrl.text.trim(),
      );
      await CorporativoTarifaConfigService.refresh(force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tarifas corporativas actualizadas')),
      );
      _motivoCtrl.clear();
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
      appBar: const AdminAppBar(title: 'Tarifas corporativas (global)', guiaId: AdminGuiaIds.tarifasCorp),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.teal.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        'Solo RAI Corporativo (factura B2B a la empresa).\n'
                        'No aplica a viaje de calle, pool ni giras de consumidor.',
                        style: TextStyle(
                          color: Colors.teal.shade900,
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _guiaAjusteTarifas(context),
                    const SizedBox(height: 16),
                    Text(
                      '1. Precio por distancia y tiempo (lo más usado)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AdminUi.onCard(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cuanto más lejos o con más paradas, más cobra la ruta. '
                      'Para subir precios en general: sube la base o el RD\$ por km. '
                      'Para bajar: bájalos.',
                      style: TextStyle(
                        color: AdminUi.muted(context),
                        height: 1.4,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _numField(
                      _dinamicaBaseCtrl,
                      label: 'Tarifa base RD\$',
                      hint: '200',
                      helper:
                          '↑ Sube = todas las rutas pagan más, aunque sean cortas. '
                          '↓ Baja = todas pagan menos.',
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _numField(
                            _dinamicaKmCortoCtrl,
                            label: 'RD\$ / km (hasta 12 km)',
                            hint: '18',
                            decimal: true,
                            helper:
                                '↑ Sube = rutas cortas (urbanas) más caras. '
                                'Es lo principal por distancia.',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _numField(
                            _dinamicaKmLargoCtrl,
                            label: 'RD\$ / km (más de 12 km)',
                            hint: '24',
                            helper:
                                '↑ Sube = rutas largas (interurbanas) más caras.',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _numField(
                            _dinamicaMinCtrl,
                            label: 'RD\$ / minuto',
                            hint: '7',
                            helper:
                                '↑ Sube = rutas con tráfico o muchas paradas pagan más.',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _numField(
                            _dinamicaMinutosKmCtrl,
                            label: 'Minutos por km (estimado)',
                            hint: '1.4',
                            decimal: true,
                            helper:
                                '↑ Sube = el sistema cree que el viaje dura más → cobra más.',
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    Text(
                      '2. Combustible República Dominicana',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AdminUi.onCard(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Piso mínimo: si la tabla de km da poco, el sistema usa el costo '
                      'real de gasolina. Cuando sube la gasolina en RD, sube este valor.',
                      style: TextStyle(
                        color: AdminUi.muted(context),
                        height: 1.4,
                        fontSize: 13,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _numField(
                            _combustibleLitroCtrl,
                            label: 'Gasolina RD\$ / litro',
                            hint: '330',
                            helper:
                                '↑ Sube gasolina en RD → sube el piso de todas las rutas.',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _numField(
                            _rendimientoKmCtrl,
                            label: 'Rendimiento km/l',
                            hint: '11',
                            decimal: true,
                            helper:
                                '↓ Baja (auto gasta más) → sube el costo por km.',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _numField(
                            _factorOperativoCtrl,
                            label: 'Factor sobre combustible',
                            hint: '1.35',
                            decimal: true,
                            helper:
                                '↑ Sube = más margen operativo (aceite, desgaste).',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _numField(
                            _recargoEmpresaCtrl,
                            label: 'Recargo servicio empresa %',
                            hint: '5',
                            suffix: '%',
                            helper:
                                '↑ Sube = la empresa paga más (sobre el costo calculado). '
                                'No afecta cuánto gana el chofer en % (sigue 90%).',
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    Text(
                      '3. Límites y ajustes finos',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AdminUi.onCard(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _numField(
                      _minimoCtrl,
                      label: 'Mínimo por viaje RD\$',
                      hint: '550',
                      helper:
                          'Ninguna ruta cobra menos que esto, aunque sea muy corta. '
                          '↑ Sube = sube rutas cortas.',
                    ),
                    const SizedBox(height: 12),
                    _numField(
                      _factorKmCtrl,
                      label: 'Factor km carretera',
                      hint: '1.15',
                      decimal: true,
                      helper:
                          'Multiplica la distancia GPS. ↑ Sube (ej. 1.20) = más km '
                          'cobrados → precio sube. GPS en línea recta; la carretera es más larga.',
                    ),
                    const SizedBox(height: 12),
                    _numField(
                      _zonaCtrl,
                      label: 'Recargo zona difícil %',
                      hint: '0',
                      suffix: '%',
                      helper:
                          'Extra % sobre todo el viaje (montaña, hora pico). 0 = apagado.',
                    ),
                    const Divider(height: 28),
                    Text(
                      '4. Impuestos y reparto (casi no los toques)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AdminUi.onCard(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Impuesto transferencia 0.20%: lo paga la empresa, casi no mueve el total. '
                      'Comisión 10%: RAI se queda 10% del precio base; el chofer 90%. '
                      'Si subes comisión, el chofer gana menos (la empresa paga igual).',
                      style: TextStyle(
                        color: AdminUi.muted(context),
                        height: 1.4,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _numField(
                      _transferCtrl,
                      label: 'Impuesto transferencia DGII % (Ley 30-26)',
                      hint: '0.20',
                      suffix: '%',
                      decimal: true,
                      helper:
                          'Valor activo esperado: 0.20 (= tasa 0.002). '
                          'Se suma solo a la factura corporativa del cliente.',
                    ),
                    const SizedBox(height: 12),
                    _numField(
                      _isrCtrl,
                      label: 'Retención ISR % (sobre Precio_Base)',
                      hint: '2',
                      suffix: '%',
                      helper:
                          'Valor activo esperado: 2. Retención del cliente empresa; '
                          'no se suma a la factura. Transporte exento ITBIS.',
                    ),
                    const SizedBox(height: 12),
                    _numField(
                      _itbisCtrl,
                      label: 'ITBIS % (referencia interna, no en factura cliente)',
                      hint: '18',
                      suffix: '%',
                      helper:
                          'Transporte exento ITBIS al cliente. Solo referencia interna.',
                    ),
                    const Divider(height: 28),
                    Text(
                      '5. Reparto RAI / chofer',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AdminUi.onCard(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Usar % global de viajes (efectivo)'),
                      value: _usarComisionGlobal,
                      onChanged: (v) => setState(() => _usarComisionGlobal = v),
                    ),
                    if (!_usarComisionGlobal) ...[
                      const SizedBox(height: 8),
                      _numField(
                        _comisionCtrl,
                        label: 'Compañía % (sobre Precio_Base)',
                        hint: '10',
                        suffix: '%',
                        helper:
                            'Dejar en 10. ↑ Sube = menos para el chofer. '
                            '↓ Baja = más para el chofer. La empresa no cambia.',
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _motivoCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Motivo (auditoría, mín. 6 caracteres)',
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
                    OutlinedButton.icon(
                      onPressed: _guardando ? null : _aplicarTarifaJustaB2b,
                      icon: const Icon(Icons.trending_up),
                      label: const Text(
                        'Cargar tarifa justa B2B (cortas ok · largas +)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _guardando ? null : _guardar,
                      child: _guardando
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Guardar configuración'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _cargar,
                      child: const Text('Recargar'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _guiaAjusteTarifas(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminUi.onCard(context).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.muted(context).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿Cómo ajustar precios? (guía rápida)',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: AdminUi.onCard(context),
            ),
          ),
          const SizedBox(height: 10),
          _guiaLinea(
            context,
            'Hay dos formas de fijar precio:',
          ),
          _guiaLinea(
            context,
            'A) Precio fijo por empresa → ADM Corporativo → Empresas → '
            '«Cambiar tarifa». Un solo monto por viaje (ej. RD\$4,500). '
            'No depende de km; es el contrato.',
          ),
          _guiaLinea(
            context,
            'B) Precio automático (esta pantalla) → se calcula por '
            'distancia + tiempo + combustible. Ruta más larga = más caro.',
          ),
          const SizedBox(height: 8),
          Text(
            'Si querés subir o bajar el precio automático:',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AdminUi.onCard(context),
            ),
          ),
          const SizedBox(height: 6),
          _guiaLinea(context, '• Subir TODO un poco → aumenta «Tarifa base».'),
          _guiaLinea(
            context,
            '• Subir solo rutas largas → aumenta «RD\$ / km (más de 12 km)».',
          ),
          _guiaLinea(
            context,
            '• Subir solo rutas cortas → aumenta «RD\$ / km (hasta 12 km)» o «Mínimo por viaje».',
          ),
          _guiaLinea(
            context,
            '• Subió la gasolina en RD → actualiza «Gasolina RD\$ / litro».',
          ),
          _guiaLinea(
            context,
            '• La empresa debe pagar un poco más sin tocar km → sube «Recargo servicio empresa %».',
          ),
          _guiaLinea(
            context,
            '• El chofer debe ganar más sin subir factura → baja «Compañía %» (ej. de 10 a 8).',
          ),
          const SizedBox(height: 8),
          Text(
            'La empresa paga: precio calculado + 0.20% impuesto DGII. '
            'El chofer recibe el 90% del precio base; RAI el 10%.',
            style: TextStyle(
              color: AdminUi.muted(context),
              fontSize: 12.5,
              height: 1.45,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _guiaLinea(BuildContext context, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        texto,
        style: TextStyle(
          color: AdminUi.onCard(context),
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _numField(
    TextEditingController ctrl, {
    required String label,
    String? hint,
    String? suffix,
    String? helper,
    bool decimal = false,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        if (decimal)
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
        else
          FilteringTextInputFormatter.digitsOnly,
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        helperText: helper,
        border: const OutlineInputBorder(),
      ),
      validator: (s) {
        final t = (s ?? '').trim().replaceAll(',', '.');
        final v = double.tryParse(t);
        if (v == null || !v.isFinite) return 'Número inválido';
        return null;
      },
    );
  }
}
