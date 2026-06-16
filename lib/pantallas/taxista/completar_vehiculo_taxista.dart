import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/utils/firebase_auth_resolve.dart';
import 'package:flygo_nuevo/servicios/taxista_operacion_gate.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

/// Datos básicos del carro (placa, modelo, año, color) antes de operar en pool.
class CompletarVehiculoTaxista extends StatefulWidget {
  const CompletarVehiculoTaxista({
    super.key,
    this.onCompletado,
    this.onContinuarSinOperar,
  });

  final VoidCallback? onCompletado;
  final VoidCallback? onContinuarSinOperar;

  @override
  State<CompletarVehiculoTaxista> createState() =>
      _CompletarVehiculoTaxistaState();
}

class _CompletarVehiculoTaxistaState extends State<CompletarVehiculoTaxista> {
  final _formKey = GlobalKey<FormState>();
  final _placa = TextEditingController();
  final _modelo = TextEditingController();
  final _marca = TextEditingController();
  final _anio = TextEditingController();
  final _color = TextEditingController();

  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  @override
  void dispose() {
    _placa.dispose();
    _modelo.dispose();
    _marca.dispose();
    _anio.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _cargarPerfil() async {
    User? u = FirebaseAuth.instance.currentUser;
    u ??= await resolveFirebaseUser(timeout: const Duration(seconds: 12));
    if (u == null) {
      if (mounted) setState(() => _cargando = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(u.uid)
          .get();
      final d = snap.data() ?? {};
      _placa.text = (d['placa'] ?? '').toString();
      _modelo.text = (d['vehiculoModelo'] ?? d['modelo'] ?? '').toString();
      _marca.text = (d['vehiculoMarca'] ?? d['marca'] ?? '').toString();
      _color.text = (d['vehiculoColor'] ?? d['color'] ?? '').toString();
      final anio = d['anio'] ?? d['vehiculoAnio'];
      if (anio != null) _anio.text = anio.toString();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final anio = int.tryParse(_anio.text.trim());
    if (anio == null) {
      _snack('Año inválido.');
      return;
    }

    setState(() => _guardando = true);
    try {
      final merge = taxistaMergeVehiculoPerfil(
        placa: _placa.text,
        modelo: _modelo.text,
        anio: anio,
        color: _color.text,
        marca: _marca.text,
      );
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(u.uid)
          .set(merge, SetOptions(merge: true));
      _snack('Vehículo guardado. Ya puedes ver el pool cuando tus documentos estén listos.');
      widget.onCompletado?.call();
    } catch (e) {
      _snack('Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const RaiAppBar(title: 'Tu vehículo'),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Text(
                'Completa tu vehículo para recibir viajes',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Son datos básicos enlazados a tu cuenta (Google o correo). '
                'La foto del vehículo la subís en Documentos.',
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _placa,
                decoration: const InputDecoration(labelText: 'Placa *'),
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _modelo,
                decoration: const InputDecoration(labelText: 'Modelo *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _marca,
                decoration: const InputDecoration(
                  labelText: 'Marca (opcional)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _anio,
                decoration: const InputDecoration(labelText: 'Año *'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null || n < 1990 || n > DateTime.now().year + 1) {
                    return 'Año inválido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _color,
                decoration: const InputDecoration(labelText: 'Color *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: Text(_guardando ? 'Guardando...' : 'Guardar y continuar'),
              ),
              if (widget.onContinuarSinOperar != null) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _guardando ? null : widget.onContinuarSinOperar,
                  child: const Text('Ir a la app (sin operar en pool aún)'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
