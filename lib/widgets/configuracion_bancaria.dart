// lib/widgets/configuracion_bancaria.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  bool _cargando = false;

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
      setState(() {
        _bancoCtrl.text = data['banco'] ?? '';
        _cuentaCtrl.text = data['numeroCuenta'] ?? '';
        _titularCtrl.text = data['titularCuenta'] ?? data['titular'] ?? '';
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
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Configuración bancaria'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: cs.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 1,
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
