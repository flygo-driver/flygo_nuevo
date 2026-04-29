import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/servicios/auth_service.dart';
import 'package:flygo_nuevo/legal/legal_acceptance_service.dart';
import 'package:flygo_nuevo/legal/terms_policy_screen.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

class RegistroCliente extends StatefulWidget {
  const RegistroCliente({super.key});

  @override
  State<RegistroCliente> createState() => _RegistroClienteState();
}

class _RegistroClienteState extends State<RegistroCliente> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _cargando = false;
  bool _acceptedLegal = false;

  Future<void> _registrar() async {
    if (!_acceptedLegal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Debes aceptar los Terminos y Politica para continuar.')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (mounted) setState(() => _cargando = true);

    final nav = Navigator.of(context);
    final msg = ScaffoldMessenger.of(context);

    try {
      // 1) Crear cuenta (Auth) + crear doc en /usuarios con rol=cliente (lo hace AuthService)
      await AuthService().registerCliente(
        nombre: _nombre.text.trim(),
        telefono: _telefono.text.trim(),
        email: _email.text.trim(),
        password: _password.text.trim(),
      );

      // 2) Failsafe: si por cualquier motivo el doc no existe, lo creamos con CREATE (permitido por reglas)
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final ref = FirebaseFirestore.instance.collection('usuarios').doc(uid);
      final snap = await ref.get();
      if (!snap.exists) {
        await ref.set({
          'uid': uid,
          'email': _email.text.trim(),
          'nombre': _nombre.text.trim(),
          'telefono': _telefono.text.trim(),
          'rol': 'cliente', // solo en CREATE está permitido sin restricción
          'fechaRegistro': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
          'registroClienteCompleto': true,
        });
      } else {
        // Si existe, NO intentamos reescribir 'rol' (tus reglas lo bloquean si ya existe).
        await ref.set({
          'actualizadoEn': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
          'registroClienteCompleto': true,
        }, SetOptions(merge: true));
      }
      await LegalAcceptanceService.saveAcceptanceForCurrentUser();

      // 3) Mismo flujo que login: verificación correo + shell cliente
      if (!mounted) return;
      nav.pushNamedAndRemoveUntil('/auth_check', (r) => false);
    } on FirebaseAuthException catch (e) {
      String texto = 'No se pudo registrar.';
      switch (e.code) {
        case 'email-already-in-use':
          texto = 'Ese correo ya está registrado. Inicia sesión.';
          break;
        case 'invalid-email':
          texto = 'Correo inválido.';
          break;
        case 'weak-password':
          texto = 'La contraseña es muy débil.';
          break;
      }
      msg.showSnackBar(SnackBar(content: Text(texto)));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  InputDecoration _decoracion(
      BuildContext context, String texto, IconData icono) {
    final cs = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: texto,
      labelStyle:
          TextStyle(color: cs.onSurface.withValues(alpha: 0.85), fontSize: 18),
      prefixIcon: Icon(icono, color: cs.primary),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: cs.primary),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: const RaiAppBar(
        title: 'Registro de Cliente',
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const SizedBox(height: 16),
              TextFormField(
                controller: _nombre,
                style: TextStyle(color: cs.onSurface),
                decoration:
                    _decoracion(context, 'Nombre completo', Icons.person),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
                autofillHints: const [AutofillHints.name],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _telefono,
                style: TextStyle(color: cs.onSurface),
                keyboardType: TextInputType.phone,
                decoration: _decoracion(context, 'Teléfono', Icons.phone),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
                autofillHints: const [AutofillHints.telephoneNumber],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                style: TextStyle(color: cs.onSurface),
                keyboardType: TextInputType.emailAddress,
                decoration:
                    _decoracion(context, 'Correo electrónico', Icons.email),
                validator: (v) =>
                    (v == null || !v.contains('@')) ? 'Correo inválido' : null,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                obscureText: true,
                style: TextStyle(color: cs.onSurface),
                decoration: _decoracion(context, 'Contraseña', Icons.lock),
                validator: (v) =>
                    (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
                autofillHints: const [AutofillHints.newPassword],
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _acceptedLegal,
                activeColor: cs.primary,
                checkColor: cs.onPrimary,
                onChanged: (v) => setState(() => _acceptedLegal = v ?? false),
                title: Text(
                  'Acepto los Terminos y Condiciones y la Politica de Privacidad de RAI DRIVER, operado por Open ASK Service SRL (RNC: 1320-11767).',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const TermsPolicyScreen()),
                  ),
                  child: const Text('Leer Terminos y Politica'),
                ),
              ),
              const SizedBox(height: 30),
              _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : Center(
                      child: ElevatedButton.icon(
                        onPressed: _acceptedLegal ? _registrar : null,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Aceptar y continuar',
                            style: TextStyle(fontSize: 14)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 10),
                          textStyle: const TextStyle(fontSize: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          minimumSize: const Size(120, 36),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
