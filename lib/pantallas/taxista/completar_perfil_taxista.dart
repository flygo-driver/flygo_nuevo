// lib/pantallas/taxista/completar_perfil_taxista.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import 'package:flygo_nuevo/pantallas/taxista/entry_taxista.dart';

class CompletarPerfilTaxista extends StatefulWidget {
  const CompletarPerfilTaxista({super.key});

  @override
  State<CompletarPerfilTaxista> createState() => _CompletarPerfilTaxistaState();
}

class _CompletarPerfilTaxistaState extends State<CompletarPerfilTaxista> {
  // 🔥 ELIMINADO: _formKey no se usaba
  final user = FirebaseAuth.instance.currentUser;

  // Documentos
  File? _licenciaImage;
  File? _matriculaImage;
  File? _seguroImage;

  bool _loading = false;
  int _currentStep = 0;

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('No hay sesión activa',
              style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Completa tu perfil',
          style: TextStyle(color: Colors.greenAccent, fontSize: 22),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent))
          : Stepper(
              type: StepperType.vertical,
              currentStep: _currentStep,
              onStepContinue: _currentStep < 2
                  ? () {
                      if (_currentStep == 0) {
                        setState(() => _currentStep++);
                      } else if (_currentStep == 1) {
                        setState(() => _currentStep++);
                      }
                    }
                  : null,
              onStepCancel: _currentStep > 0
                  ? () {
                      setState(() => _currentStep--);
                    }
                  : null,
              onStepTapped: (step) {
                setState(() => _currentStep = step);
              },
              controlsBuilder: (context, details) {
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: [
                      if (details.onStepContinue != null)
                        Expanded(
                          child: ElevatedButton(
                            onPressed: details.onStepContinue,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.greenAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Text(
                                _currentStep == 2 ? 'FINALIZAR' : 'CONTINUAR'),
                          ),
                        ),
                      if (details.onStepCancel != null) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextButton(
                            onPressed: details.onStepCancel,
                            child: const Text('ATRÁS',
                                style: TextStyle(color: Colors.white70)),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
              steps: [
                // PASO 1: Información personal adicional
                Step(
                  title: const Text('Información personal',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Completa tus datos',
                      style: TextStyle(color: Colors.white70)),
                  content: _buildPersonalInfoStep(),
                  isActive: _currentStep >= 0,
                  state:
                      _currentStep > 0 ? StepState.complete : StepState.indexed,
                ),

                // PASO 2: Subir documentos
                Step(
                  title: const Text('Documentos',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Licencia, matrícula, seguro',
                      style: TextStyle(color: Colors.white70)),
                  content: _buildDocumentsStep(),
                  isActive: _currentStep >= 1,
                  state:
                      _currentStep > 1 ? StepState.complete : StepState.indexed,
                ),

                // PASO 3: Confirmar y finalizar
                Step(
                  title: const Text('Finalizar',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Revisa y confirma',
                      style: TextStyle(color: Colors.white70)),
                  content: _buildConfirmStep(),
                  isActive: _currentStep >= 2,
                  state:
                      _currentStep > 2 ? StepState.complete : StepState.indexed,
                ),
              ],
            ),
    );
  }

  // PASO 1: Información personal adicional
  Widget _buildPersonalInfoStep() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user!.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};

        return Column(
          children: [
            _buildInfoRow('Nombre:', data['nombre'] ?? 'Cargando...'),
            const Divider(color: Colors.white24),
            _buildInfoRow('Email:', data['email'] ?? 'Cargando...'),
            const Divider(color: Colors.white24),
            _buildInfoRow('Teléfono:', data['telefono'] ?? 'Cargando...'),
            const Divider(color: Colors.white24),
            _buildInfoRow(
                'Vehículo:', '${data['marca'] ?? ''} ${data['modelo'] ?? ''}'),
            const Divider(color: Colors.white24),
            _buildInfoRow('Placa:', data['placa'] ?? 'Cargando...'),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // PASO 2: Subir documentos
  Widget _buildDocumentsStep() {
    return Column(
      children: [
        _buildDocumentButton(
          'Licencia de conducir',
          Icons.badge,
          _licenciaImage,
          () => _pickImage('licencia'),
        ),
        const SizedBox(height: 12),
        _buildDocumentButton(
          'Matrícula del vehículo',
          Icons.description,
          _matriculaImage,
          () => _pickImage('matricula'),
        ),
        const SizedBox(height: 12),
        _buildDocumentButton(
          'Seguro del vehículo',
          Icons.security,
          _seguroImage,
          () => _pickImage('seguro'),
        ),
        const SizedBox(height: 16),
        const Text(
          'Los documentos serán verificados por el administrador',
          style: TextStyle(color: Colors.white54, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildDocumentButton(
      String label, IconData icon, File? image, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: image != null
              ? Colors.green.withValues(alpha: 0.1)
              : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: image != null ? Colors.green : Colors.white24,
            width: image != null ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              image != null ? Icons.check_circle : icon,
              color: image != null ? Colors.green : Colors.white70,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: image != null ? Colors.green : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (image != null)
                    const Text('Documento seleccionado',
                        style: TextStyle(color: Colors.green, fontSize: 12)),
                ],
              ),
            ),
            Icon(
              Icons.upload_file,
              color: image != null ? Colors.green : Colors.white54,
            ),
          ],
        ),
      ),
    );
  }

  // PASO 3: Confirmar y finalizar
  Widget _buildConfirmStep() {
    // 🔥 CAMBIADO: final para variable local
    final bool allDocumentsSelected = _licenciaImage != null &&
        _matriculaImage != null &&
        _seguroImage != null;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: allDocumentsSelected
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: allDocumentsSelected ? Colors.green : Colors.orange,
            ),
          ),
          child: Column(
            children: [
              Icon(
                allDocumentsSelected ? Icons.check_circle : Icons.warning,
                color: allDocumentsSelected ? Colors.green : Colors.orange,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                allDocumentsSelected
                    ? '¡Todo listo para continuar!'
                    : 'Faltan documentos por subir',
                style: TextStyle(
                  color: allDocumentsSelected ? Colors.green : Colors.orange,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                allDocumentsSelected
                    ? 'Tus documentos serán verificados. Mientras tanto, puedes comenzar a usar la app.'
                    : 'Completa todos los documentos para poder trabajar.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (allDocumentsSelected)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _finalizarRegistro,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('FINALIZAR Y COMENZAR',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }

  Future<void> _pickImage(String tipo) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        if (tipo == 'licencia') {
          _licenciaImage = File(pickedFile.path);
        } else if (tipo == 'matricula') {
          _matriculaImage = File(pickedFile.path);
        } else if (tipo == 'seguro') {
          _seguroImage = File(pickedFile.path);
        }
      });
    }
  }

  Future<void> _finalizarRegistro() async {
    setState(() => _loading = true);

    try {
      // Aquí iría la lógica para subir las imágenes a Storage
      // Por ahora, solo actualizamos el estado

      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user!.uid)
          .update({
        'documentosCompletos': true,
        'docsEstado': 'pendiente',
        'perfilCompletado': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Perfil completado. Bienvenido a FlyGo Taxista!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const TaxistaEntry()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
