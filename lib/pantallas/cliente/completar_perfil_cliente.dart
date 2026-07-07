import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/cliente_perfil_onboarding.dart';
import 'package:flygo_nuevo/servicios/logout.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

/// Paso 2 pasajero: nombre + teléfono (datos reales, pantalla simple).
class CompletarPerfilCliente extends StatefulWidget {
  const CompletarPerfilCliente({super.key});

  @override
  State<CompletarPerfilCliente> createState() => _CompletarPerfilClienteState();
}

class _CompletarPerfilClienteState extends State<CompletarPerfilCliente> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  bool _cargando = true;
  bool _guardando = false;
  bool _telDesdeSms = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _cargando = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();
      final data = snap.data() ?? {};
      _nombre.text = ClientePerfilOnboarding.nombreDesdeUsuario(user, data);
      final tel = ClientePerfilOnboarding.telefonoDesdeUsuario(user, data);
      _telefono.text = _soloDigitosRd(tel);
      _telDesdeSms = user.providerData.any((p) => p.providerId == 'phone') &&
          _telefono.text.length >= 10;
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _soloDigitosRd(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('1') && d.length == 11) d = d.substring(1);
    return d;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Sesión expirada. Vuelve a entrar.');
      return;
    }
    setState(() => _guardando = true);
    try {
      await ClientePerfilOnboarding.guardarPerfilMinimo(
        uid: user.uid,
        nombre: _nombre.text.trim(),
        telefono: _telefono.text.trim(),
      );
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _snack('No se pudo guardar. Intenta de nuevo.');
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

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: const RaiAppBar(title: 'Tu perfil'),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Paso 2 de 2',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '¿Cómo te llamamos?',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'El conductor usa tu nombre y teléfono para contactarte.',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.65),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _nombre,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) {
                      if ((v ?? '').trim().length < 2) {
                        return 'Escribe tu nombre';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _telefono,
                    enabled: !_telDesdeSms,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Teléfono',
                      prefixText: '+1 ',
                      prefixStyle: TextStyle(color: cs.primary),
                      prefixIcon: const Icon(Icons.phone_android),
                      helperText: _telDesdeSms
                          ? 'Verificado por SMS'
                          : '809, 829 o 849',
                    ),
                    validator: (v) {
                      if (!ClientePerfilOnboarding.telefonoValido(v)) {
                        return 'Teléfono RD inválido (10 dígitos)';
                      }
                      return null;
                    },
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _guardando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Continuar',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  TextButton(
                    onPressed: () => cerrarSesion(context),
                    child: const Text('Usar otra cuenta'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
