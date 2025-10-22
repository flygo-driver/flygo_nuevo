// lib/pantallas/taxista/registro_taxista.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// 🔁 antes importabas DocumentosTaxista; para QA vamos directo al panel:
import 'package:flygo_nuevo/pantallas/taxista/entry_taxista.dart';

class RegistroTaxista extends StatefulWidget {
  const RegistroTaxista({super.key});

  @override
  State<RegistroTaxista> createState() => _RegistroTaxistaState();
}

class _RegistroTaxistaState extends State<RegistroTaxista> {
  final _formKey = GlobalKey<FormState>();

  // Datos personales
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();

  // Vehículo
  final _placa = TextEditingController();
  final _marca = TextEditingController();
  final _modelo = TextEditingController();
  final _color = TextEditingController();
  String _tipoVehiculo = 'Carro';

  bool _loading = false;

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    _email.dispose();
    _pass.dispose();
    _placa.dispose();
    _marca.dispose();
    _modelo.dispose();
    _color.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: Colors.greenAccent),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.white24),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.greenAccent, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Future<void> _registrar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      // 1) Crear cuenta
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _pass.text.trim(),
      );
      final user = cred.user!;
      await user.updateDisplayName(_nombre.text.trim());

      // Enviamos verificación (solo informativo; no bloquea el flujo)
      try {
        await user.sendEmailVerification();
      } catch (_) {}

      final uid = user.uid;

      // 2) Guardar perfil (⚠ para QA: documentos “aprobados”)
      final marca = _marca.text.trim();
      final modelo = _modelo.text.trim();
      final color  = _color.text.trim();

      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'uid': uid,
        'email': _email.text.trim(),
        'nombre': _nombre.text.trim(),
        'telefono': _telefono.text.trim(),
        'rol': 'taxista',

        'disponible': false,

        // ✅ Claves para no bloquear el acceso durante pruebas:
        'docsEstado': 'aprobado',
        'documentosCompletos': true,

        'placa': _placa.text.trim(),
        'tipoVehiculo': _tipoVehiculo,
        'marca': marca,
        'modelo': modelo,
        'color': color,

        // Campos usados en el modal de “Ver taxista”
        'vehiculoMarca':  marca,
        'vehiculoModelo': modelo,
        'vehiculoColor':  color,

        'vehiculo': {
          'tipo': _tipoVehiculo,
          'placa': _placa.text.trim(),
          'marca': marca,
          'modelo': modelo,
          'color': color,
        },

        'docs': {
          'licenciaUrl': null,
          'matriculaUrl': null,
          'seguroUrl': null,
          'updatedAt': FieldValue.serverTimestamp(),
        },

        'ratingSuma': 0,
        'ratingConteo': 0,

        'fechaRegistro': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cuenta creada. ¡Bienvenido a FlyGo!')),
      );

      // 3) ✅ Ir directo al panel del taxista (sin paso de documentos)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const TaxistaEntry()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error de registro: ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          "Registro Taxista",
          style: TextStyle(
            fontSize: 26,
            color: Colors.greenAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Icon(Icons.local_taxi, size: 90, color: Colors.greenAccent),
              const SizedBox(height: 24),

              TextFormField(
                controller: _nombre,
                style: const TextStyle(color: Colors.white),
                decoration: _dec('Nombre completo', Icons.person),
                validator: (v) => (v == null || v.trim().length < 2) ? 'Ingresa tu nombre' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _telefono,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.phone,
                decoration: _dec('Teléfono', Icons.phone),
                validator: (v) => (v == null || v.trim().length < 7) ? 'Ingresa un teléfono válido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: _dec('Correo electrónico', Icons.email),
                validator: (v) => (v == null || !v.contains('@')) ? 'Correo inválido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pass,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                autofillHints: const [AutofillHints.newPassword],
                decoration: _dec('Contraseña (mín. 6)', Icons.lock),
                validator: (v) => (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
              ),

              const SizedBox(height: 24),
              const Divider(color: Colors.white24),
              const SizedBox(height: 12),

              Text(
                'Datos del vehículo',
                style: TextStyle(
                  color: Colors.greenAccent.shade100,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _placa,
                style: const TextStyle(color: Colors.white),
                decoration: _dec('Placa', Icons.tag),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa la placa' : null,
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _tipoVehiculo,
                items: const [
                  DropdownMenuItem(value: 'Carro', child: Text('Carro')),
                  DropdownMenuItem(value: 'Jeepeta', child: Text('Jeepeta')),
                  DropdownMenuItem(value: 'Minivan', child: Text('Minivan')),
                  DropdownMenuItem(value: 'Minibús', child: Text('Minibús')),
                  DropdownMenuItem(value: 'Autobús', child: Text('Autobús')),
                  DropdownMenuItem(value: 'Guagua', child: Text('Guagua')),
                ],
                onChanged: (v) => setState(() => _tipoVehiculo = v ?? 'Carro'),
                decoration: _dec('Tipo de vehículo', Icons.directions_car),
                dropdownColor: Colors.black,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _marca,
                style: const TextStyle(color: Colors.white),
                decoration: _dec('Marca (opcional)', Icons.directions_car_filled),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _modelo,
                style: const TextStyle(color: Colors.white),
                decoration: _dec('Modelo (opcional)', Icons.build),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _color,
                style: const TextStyle(color: Colors.white),
                decoration: _dec('Color (opcional)', Icons.color_lens),
              ),

              const SizedBox(height: 24),
              _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _registrar,
                        icon: const Icon(Icons.check_circle, color: Colors.green),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12.0),
                          child: Text(
                            'Crear cuenta',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 56),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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