// Configuración empresa RAI: datos bancarios + prepago comisión.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../config/recarga_bancaria_config.dart';
import '../../servicios/admin_config_service.dart';
import '../../servicios/app_config_service.dart';
import '../../widgets/admin_app_bar.dart';
import 'package:flygo_nuevo/widgets/admin_guia_uso.dart';
import '../../widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';

class AdminConfigEmpresa extends StatefulWidget {
  const AdminConfigEmpresa({super.key});

  @override
  State<AdminConfigEmpresa> createState() => _AdminConfigEmpresaPageState();
}

class _AdminConfigEmpresaPageState extends State<AdminConfigEmpresa>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _formBanco = GlobalKey<FormState>();
  final _formPrepago = GlobalKey<FormState>();

  final _banco = TextEditingController();
  final _tipoCuenta = TextEditingController(text: 'Cuenta Corriente');
  final _numero = TextEditingController();
  final _titular = TextEditingController();
  final _rnc = TextEditingController();
  final _alias = TextEditingController();
  final _nota = TextEditingController();
  final _qr = TextEditingController();
  final _whatsapp = TextEditingController();

  final _minOperativo = TextEditingController();
  final _umbralPreventivo = TextEditingController();
  final _motivoPrepago = TextEditingController();

  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _banco.dispose();
    _tipoCuenta.dispose();
    _numero.dispose();
    _titular.dispose();
    _rnc.dispose();
    _alias.dispose();
    _nota.dispose();
    _qr.dispose();
    _whatsapp.dispose();
    _minOperativo.dispose();
    _umbralPreventivo.dispose();
    _motivoPrepago.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final remoto = await AppConfigService.obtenerDatosBancarios();
      final banco = AppConfigService.efectivos(remoto);
      _banco.text = banco.bancoNombre;
      _tipoCuenta.text = banco.tipoCuenta;
      _numero.text = banco.numeroCuenta;
      _titular.text = banco.titular;
      _rnc.text = banco.rnc;
      _alias.text = banco.alias;
      _nota.text = banco.nota;
      _qr.text = banco.qrUrl;
      _whatsapp.text = banco.whatsappSoporte;
      final prep = await FirebaseFirestore.instance
          .collection('config')
          .doc('comision_prepago')
          .get();
      final p = prep.data() ?? {};
      _minOperativo.text = ((p['minimoOperativoRd'] as num?) ?? 200).toString();
      _umbralPreventivo.text =
          ((p['umbralPreventivoRd'] as num?) ?? 250).toString();
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _guardarBanco() async {
    if (!(_formBanco.currentState?.validate() ?? false)) return;
    setState(() => _guardando = true);
    try {
      await AppConfigService.actualizarDatosBancarios(DatosBancarios(
        bancoNombre: _banco.text.trim(),
        tipoCuenta: _tipoCuenta.text.trim(),
        numeroCuenta: _numero.text.trim(),
        titular: _titular.text.trim(),
        rnc: _rnc.text.trim(),
        alias: _alias.text.trim(),
        nota: _nota.text.trim(),
        qrUrl: _qr.text.trim(),
        whatsappSoporte: _whatsapp.text.trim(),
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos bancarios actualizados')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _publicarDatosEmpresa() async {
    setState(() => _guardando = true);
    try {
      await AppConfigService.publicarDatosEmpresaProduccion();
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cuenta ${RecargaBancariaConfig.titular} publicada '
              '(${RecargaBancariaConfig.banco} ${RecargaBancariaConfig.numeroCuenta})',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _guardarPrepago() async {
    if (!(_formPrepago.currentState?.validate() ?? false)) return;
    final motivo = _motivoPrepago.text.trim();
    if (motivo.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Motivo mínimo 6 caracteres')),
      );
      return;
    }
    setState(() => _guardando = true);
    try {
      await AdminConfigService.updateComisionPrepagoConfig(
        minimoOperativoRd: double.parse(_minOperativo.text.trim()),
        umbralPreventivoRd: double.parse(_umbralPreventivo.text.trim()),
        motivo: motivo,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prepago comisión actualizado')),
        );
        _motivoPrepago.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: AdminAppBar(
        guiaId: AdminGuiaIds.configRai,
        title: 'Configuración RAI',
        bottom: TabBar(
          controller: _tabs,
          labelColor: AdminUi.accentGreen(context),
          unselectedLabelColor: AdminUi.tabUnselected(context),
          indicatorColor: AdminUi.accentGreen(context),
          tabs: const [
            Tab(text: 'Cuenta bancaria'),
            Tab(text: 'Prepago comisión'),
          ],
        ),
      ),
      body: _cargando
          ? Center(
              child: CircularProgressIndicator(
                color: AdminUi.progressAccent(context),
              ),
            )
          : TabBarView(
              controller: _tabs,
              children: [
                _tabBanco(),
                _tabPrepago(),
              ],
            ),
    );
  }

  Widget _tabBanco() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formBanco,
        child: Column(
          children: [
            Text(
              'Datos que ven taxistas al depositar comisión (app_config/pagos).',
              style: TextStyle(color: AdminUi.secondary(context)),
            ),
            const SizedBox(height: 16),
            _field(_banco, 'Banco'),
            _field(_tipoCuenta, 'Tipo cuenta'),
            _field(_numero, 'Número cuenta'),
            _field(_titular, 'Titular'),
            _field(_rnc, 'RNC'),
            _field(_alias, 'Alias'),
            _field(_nota, 'Nota', maxLines: 2),
            _field(_qr, 'URL QR'),
            _field(_whatsapp, 'WhatsApp soporte'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _guardando ? null : _guardarBanco,
                child: Text(_guardando ? 'Guardando…' : 'Guardar banco'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _guardando ? null : _publicarDatosEmpresa,
                child: const Text('Publicar cuenta empresa RAI en Firestore'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabPrepago() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formPrepago,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Umbrales prepago chofer (config/comision_prepago). Cambio vía Cloud Function con historial.',
              style: TextStyle(color: AdminUi.secondary(context)),
            ),
            const SizedBox(height: 16),
            _field(_minOperativo, 'Mínimo operativo RD\$', keyboard: TextInputType.number),
            _field(_umbralPreventivo, 'Umbral preventivo RD\$', keyboard: TextInputType.number),
            _field(_motivoPrepago, 'Motivo del cambio', maxLines: 2),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _guardando ? null : _guardarPrepago,
                child: Text(_guardando ? 'Guardando…' : 'Guardar prepago'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {int maxLines = 1, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Requerido' : null,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AdminUi.inputFill(context),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
