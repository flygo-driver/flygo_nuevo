import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/servicios/auth_service.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';
import 'package:flygo_nuevo/pantallas/cliente/cliente_home.dart';

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

  Future<void> _registrar() async {
    if (!_formKey.currentState!.validate()) return;
    if (mounted) setState(() => _cargando = true);

    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await AuthService().registerCliente(
        nombre: _nombre.text.trim(),
        telefono: _telefono.text.trim(),
        email: _email.text.trim(),
        password: _password.text.trim(),
      );

      final uid = FirebaseAuth.instance.currentUser!.uid;

      await RolesService.setRol(
        uid,
        Roles.cliente,
        extra: {
          'uid': uid,
          'email': _email.text.trim(),
          'nombre': _nombre.text.trim(),
          'telefono': _telefono.text.trim(),
          'fechaRegistro': FieldValue.serverTimestamp(),
        },
      );

      if (!mounted) return;
      nav.pushReplacement(
        MaterialPageRoute(builder: (_) => const ClienteHome()),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
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

  InputDecoration _decoracion(String texto, IconData icono) {
    return InputDecoration(
      labelText: texto,
      labelStyle: const TextStyle(color: Colors.white, fontSize: 18),
      prefixIcon: Icon(icono, color: Colors.greenAccent),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.greenAccent),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.greenAccent, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Registro de Cliente',
          style: TextStyle(color: Colors.greenAccent, fontSize: 24),
        ),
        centerTitle: true,
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
                style: const TextStyle(color: Colors.white),
                decoration: _decoracion('Nombre completo', Icons.person),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
                autofillHints: const [AutofillHints.name],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _telefono,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.phone,
                decoration: _decoracion('Teléfono', Icons.phone),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
                autofillHints: const [AutofillHints.telephoneNumber],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.emailAddress,
                decoration: _decoracion('Correo electrónico', Icons.email),
                validator: (v) => (v == null || !v.contains('@')) ? 'Correo inválido' : null,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: _decoracion('Contraseña', Icons.lock),
                validator: (v) => (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
                autofillHints: const [AutofillHints.newPassword],
              ),
              const SizedBox(height: 30),
              _cargando
                  ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
                  : ElevatedButton.icon(
                      onPressed: _registrar,
                      icon: const Icon(Icons.check),
                      label: const Text('Crear cuenta'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(fontSize: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
