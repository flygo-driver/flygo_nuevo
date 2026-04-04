import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/pantallas/taxista/documentos_taxista.dart';
import 'package:flygo_nuevo/legal/legal_acceptance_service.dart';
import 'package:flygo_nuevo/legal/terms_policy_screen.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

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

  // Vehículo - comunes
  final _placa = TextEditingController();
  final _marca = TextEditingController();
  final _modelo = TextEditingController();
  final _color = TextEditingController();

  // 🔥 TIPO DE SERVICIO
  String _tipoServicio = 'normal'; // normal, motor, turismo

  // Para servicio normal
  String _tipoVehiculo = 'Carro';
  final List<String> _tiposVehiculoNormal = [
    'Carro',
    'Jeepeta',
    'Minivan',
    'Minibús',
    'Autobús',
    'Guagua',
  ];

  // Para servicio turismo
  String? _subtipoTurismo;
  final List<Map<String, String>> _subtiposTurismo = [
    {'value': 'carro', 'label': 'Carro Turismo'},
    {'value': 'jeepeta', 'label': 'Jeepeta Turismo'},
    {'value': 'minivan', 'label': 'Minivan Turismo'},
    {'value': 'bus', 'label': 'Bus Turismo'},
  ];

  bool _loading = false;
  bool _acceptedLegal = false;

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
    if (!_acceptedLegal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Debes aceptar los Terminos y Politica para continuar.')),
      );
      return;
    }
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

      // Enviamos verificación (solo informativo)
      try {
        await user.sendEmailVerification();
      } catch (_) {}

      final String uid = user.uid;

      // 2) Preparar datos del vehículo según tipo de servicio
      final String marca = _marca.text.trim();
      final String modelo = _modelo.text.trim();
      final String color = _color.text.trim();
      final String placa = _placa.text.trim().toUpperCase();

      // Datos base del vehículo
      final Map<String, dynamic> datosVehiculo = {
        'placa': placa,
        'marca': marca,
        'modelo': modelo,
        'color': color,
        'tipoServicio': _tipoServicio,
      };

      // Datos específicos según tipo
      if (_tipoServicio == 'normal') {
        datosVehiculo.addAll({
          'tipoVehiculo': _tipoVehiculo,
          'vehiculoTipo': _tipoVehiculo,
        });
      } else if (_tipoServicio == 'motor') {
        datosVehiculo.addAll({
          'tipoVehiculo': 'Motor',
          'vehiculoTipo': 'Motor',
          'tipoServicio': 'motor',
        });
      } else if (_tipoServicio == 'turismo') {
        final subtipo = _subtiposTurismo.firstWhere(
          (e) => e['value'] == _subtipoTurismo,
          orElse: () => {'label': 'Carro Turismo'},
        );
        datosVehiculo.addAll({
          'tipoVehiculo': _subtipoTurismo ?? 'carro',
          'tipoVehiculoLabel': subtipo['label'],
          'vehiculoTipo': subtipo['label'],
          'tipoServicio': 'turismo',
        });
      }

      // 3) Guardar perfil en Firestore
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'uid': uid,
        'email': _email.text.trim(),
        'nombre': _nombre.text.trim(),
        'telefono': _telefono.text.trim(),
        'rol': 'taxista',
        'disponible': false,

        // 🔥 ESTADO DE DOCUMENTOS - PENDIENTE DE APROBACIÓN (ambos nombres por compatibilidad)
        'docsEstado': 'pendiente',
        'estadoDocumentos':
            'pendiente', // pendiente, en_revision, aprobado, rechazado
        'documentosCompletos': false,
        'puedeRecibirViajes': false, // NO puede recibir viajes hasta aprobación

        // Datos del vehículo
        ...datosVehiculo,

        // Campos para compatibilidad con vistas existentes
        'vehiculoMarca': marca,
        'vehiculoModelo': modelo,
        'vehiculoColor': color,

        'vehiculo': {
          'tipo': _tipoServicio == 'normal'
              ? _tipoVehiculo
              : (_tipoServicio == 'motor'
                  ? 'Motor'
                  : (_subtipoTurismo ?? 'carro')),
          'placa': placa,
          'marca': marca,
          'modelo': modelo,
          'color': color,
          'tipoServicio': _tipoServicio,
        },

        // Documentos (se llenarán después)
        'docs': {
          'licenciaUrl': null,
          'matriculaUrl': null,
          'seguroUrl': null,
          'fotoVehiculoUrl': null,
          'updatedAt': FieldValue.serverTimestamp(),
        },

        'ratingSuma': 0,
        'ratingConteo': 0,

        'fechaRegistro': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await LegalAcceptanceService.saveAcceptanceForCurrentUser();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cuenta creada. Ahora sube tus documentos.')),
      );

      // 4) Ir a pantalla de documentos (NO directo a taxista)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DocumentosTaxista()),
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
      appBar: const RaiAppBar(
        title: "Registro Taxista",
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Icon(Icons.local_taxi, size: 90, color: Colors.greenAccent),
              const SizedBox(height: 24),

              // =====================================================
              // DATOS PERSONALES
              // =====================================================
              TextFormField(
                controller: _nombre,
                style: const TextStyle(color: Colors.white),
                decoration: _dec('Nombre completo', Icons.person),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Ingresa tu nombre'
                    : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _telefono,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.phone,
                decoration: _dec('Teléfono', Icons.phone),
                validator: (v) => (v == null || v.trim().length < 7)
                    ? 'Ingresa un teléfono válido'
                    : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _email,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: _dec('Correo electrónico', Icons.email),
                validator: (v) =>
                    (v == null || !v.contains('@')) ? 'Correo inválido' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _pass,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                autofillHints: const [AutofillHints.newPassword],
                decoration: _dec('Contraseña (mín. 6)', Icons.lock),
                validator: (v) =>
                    (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
              ),

              const SizedBox(height: 24),
              const Divider(color: Colors.white24),
              const SizedBox(height: 12),

              // =====================================================
              // TIPO DE SERVICIO
              // =====================================================
              const Text(
                'Tipo de servicio',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),

              // Selector de tipo de servicio
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildTipoServicioOption(
                      value: 'normal',
                      icon: Icons.directions_car,
                      label: '🚗 Servicio Normal',
                    ),
                    _buildTipoServicioOption(
                      value: 'motor',
                      icon: Icons.two_wheeler,
                      label: '🛵 Servicio Motor',
                    ),
                    _buildTipoServicioOption(
                      value: 'turismo',
                      icon: Icons.beach_access,
                      label: '🏝️ Servicio Turismo',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // =====================================================
              // DATOS DEL VEHÍCULO
              // =====================================================
              const Text(
                'Datos del vehículo',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),

              // Selector específico según tipo de servicio
              if (_tipoServicio == 'normal') ...[
                DropdownButtonFormField<String>(
                  value: _tipoVehiculo,
                  items: _tiposVehiculoNormal.map((tipo) {
                    return DropdownMenuItem(
                      value: tipo,
                      child: Text(tipo,
                          style: const TextStyle(color: Colors.white)),
                    );
                  }).toList(),
                  onChanged: (v) =>
                      setState(() => _tipoVehiculo = v ?? 'Carro'),
                  decoration: _dec('Tipo de vehículo', Icons.directions_car),
                  dropdownColor: Colors.black,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
              ],

              if (_tipoServicio == 'turismo') ...[
                DropdownButtonFormField<String>(
                  value: _subtipoTurismo ?? 'carro',
                  items: _subtiposTurismo.map((tipo) {
                    return DropdownMenuItem(
                      value: tipo['value'],
                      child: Text(tipo['label']!,
                          style: const TextStyle(color: Colors.white)),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _subtipoTurismo = v),
                  decoration:
                      _dec('Tipo de vehículo turístico', Icons.beach_access),
                  dropdownColor: Colors.black,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
              ],

              if (_tipoServicio == 'motor') ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(26),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.two_wheeler, color: Colors.orange),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Servicio Motor: Motocicleta',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Campos comunes para todos
              TextFormField(
                controller: _placa,
                style: const TextStyle(color: Colors.white),
                decoration: _dec('Placa', Icons.tag),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Ingresa la placa' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _marca,
                style: const TextStyle(color: Colors.white),
                decoration: _dec('Marca', Icons.directions_car_filled),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Ingresa la marca' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _modelo,
                style: const TextStyle(color: Colors.white),
                decoration: _dec('Modelo', Icons.build),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Ingresa el modelo'
                    : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _color,
                style: const TextStyle(color: Colors.white),
                decoration: _dec('Color', Icons.color_lens),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Ingresa el color' : null,
              ),
              const SizedBox(height: 24),

              // =====================================================
              // INFORMACIÓN SOBRE DOCUMENTOS
              // =====================================================
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.info, color: Colors.blue, size: 32),
                    SizedBox(height: 8),
                    Text(
                      'Después del registro, deberás subir:\n\n'
                      '• Licencia de conducir\n'
                      '• Matrícula del vehículo\n'
                      '• Seguro\n'
                      '• Foto con tu vehículo\n\n'
                      'Tu cuenta será revisada por administración antes de recibir viajes.',
                      style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _acceptedLegal,
                activeColor: Colors.greenAccent,
                checkColor: Colors.black,
                onChanged: (v) => setState(() => _acceptedLegal = v ?? false),
                title: const Text(
                  'Acepto los Terminos y Condiciones y la Politica de Privacidad de RAI DRIVER, operado por Open ASK Service SRL (RNC: 1320-11767).',
                  style: TextStyle(color: Colors.white, fontSize: 12),
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
              const SizedBox(height: 12),

              // =====================================================
              // BOTÓN DE REGISTRO - MODIFICADO MÁS PEQUEÑO
              // =====================================================
              _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: Colors.greenAccent))
                  : Center(
                      child: ElevatedButton.icon(
                        onPressed: _acceptedLegal ? _registrar : null,
                        icon: const Icon(Icons.check_circle,
                            color: Colors.green, size: 18),
                        label: const Text(
                          'Aceptar y continuar',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.green),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          minimumSize: const Size(140, 38),
                        ),
                      ),
                    ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // Helper para opciones de tipo de servicio
  Widget _buildTipoServicioOption({
    required String value,
    required IconData icon,
    required String label,
  }) {
    final bool isSelected = _tipoServicio == value;

    return RadioListTile<String>(
      title: Row(
        children: [
          Icon(icon, color: isSelected ? Colors.greenAccent : Colors.white54),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.greenAccent : Colors.white,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
      value: value,
      groupValue: _tipoServicio,
      onChanged: (val) {
        setState(() {
          _tipoServicio = val!;
          // Resetear valores según tipo
          if (_tipoServicio == 'normal') {
            _tipoVehiculo = 'Carro';
          } else if (_tipoServicio == 'turismo') {
            _subtipoTurismo = 'carro';
          }
        });
      },
      activeColor: Colors.greenAccent,
    );
  }
}
