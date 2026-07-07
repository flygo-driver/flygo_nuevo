// lib/widgets/configuracion_bancaria.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

class ConfiguracionBancaria extends StatefulWidget {
  const ConfiguracionBancaria({super.key});

  @override
  State<ConfiguracionBancaria> createState() => _ConfiguracionBancariaState();
}

class _ConfiguracionBancariaState extends State<ConfiguracionBancaria> {
  final _formKey = GlobalKey<FormState>();
  final _bancoCtrl = TextEditingController();
  final _cuentaCtrl = TextEditingController();
  final _titularCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  bool _cargando = false;

  /// Tipo de cuenta seleccionado por el taxista. Se persiste en Firestore
  /// dentro del mismo doc de usuario que el banco/cuenta/titular.
  static const List<String> _tiposCuentaPermitidos = <String>[
    'Ahorros',
    'Corriente',
    'Cheques',
  ];
  String? _tipoCuenta;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _bancoCtrl.dispose();
    _cuentaCtrl.dispose();
    _titularCtrl.dispose();
    _cedulaCtrl.dispose();
    super.dispose();
  }

  /// Carga los datos bancarios existentes desde Firestore
  Future<void> _cargarDatos() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(user.uid)
        .get();
    if (doc.exists) {
      final data = doc.data()!;
      final String tipoRaw = (data['tipoCuenta'] ?? '').toString().trim();
      setState(() {
        _bancoCtrl.text = data['banco'] ?? '';
        _cuentaCtrl.text = data['numeroCuenta'] ?? '';
        _titularCtrl.text = data['titularCuenta'] ?? data['titular'] ?? '';
        final String ced = (data['cedula'] ?? data['ciTaxista'] ?? '')
            .toString()
            .trim();
        _cedulaCtrl.text = ced;
        // Solo aceptamos los valores de la lista para no romper el dropdown.
        _tipoCuenta =
            _tiposCuentaPermitidos.contains(tipoRaw) ? tipoRaw : null;
      });
    }
  }

  /// Guarda los datos bancarios en Firestore
  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _cargando = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .set({
        'banco': _bancoCtrl.text.trim(),
        'numeroCuenta': _cuentaCtrl.text.trim(),
        'titularCuenta': _titularCtrl.text.trim(),
        if (_tipoCuenta != null) 'tipoCuenta': _tipoCuenta,
        'cedula': _cedulaCtrl.text.trim(),
        'ciTaxista': _cedulaCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    setState(() => _cargando = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datos bancarios guardados')),
      );
      Navigator.pop(context);
    }
  }

  InputDecoration _fieldDecoration(
      BuildContext context, String label, String hint) {
    final cs = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.65)),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: cs.onSurfaceVariant),
      hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.85)),
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: cs.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: cs.error, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textStyle = TextStyle(color: cs.onSurface);

    return Scaffold(
      appBar: const RaiAppBar(
        title: 'Configuración bancaria',
        centerTitle: true,
        showBackWhenCanPop: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _bancoCtrl,
                style: textStyle,
                cursorColor: cs.primary,
                decoration: _fieldDecoration(
                  context,
                  'Banco',
                  'Ej: Banco Popular',
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cuentaCtrl,
                style: textStyle,
                cursorColor: cs.primary,
                decoration: _fieldDecoration(
                  context,
                  'Número de cuenta',
                  'Ej: 123456789',
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titularCtrl,
                style: textStyle,
                cursorColor: cs.primary,
                decoration: _fieldDecoration(
                  context,
                  'Nombre del titular',
                  'Ej: Juan Pérez',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cedulaCtrl,
                style: textStyle,
                cursorColor: cs.primary,
                keyboardType: TextInputType.text,
                decoration: _fieldDecoration(
                  context,
                  'Cédula (C.I.)',
                  'Opcional; aparece en comprobantes de viaje',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _tipoCuenta,
                style: textStyle,
                decoration: _fieldDecoration(
                  context,
                  'Tipo de cuenta',
                  'Selecciona Ahorros, Corriente o Cheques',
                ),
                items: _tiposCuentaPermitidos
                    .map((t) => DropdownMenuItem<String>(
                          value: t,
                          child: Text(t, style: textStyle),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _tipoCuenta = v),
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Selecciona el tipo de cuenta'
                    : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _cargando ? null : _guardar,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _cargando
                      ? SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onPrimary,
                          ),
                        )
                      : const Text('GUARDAR'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
