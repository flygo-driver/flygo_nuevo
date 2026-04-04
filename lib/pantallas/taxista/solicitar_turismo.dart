// lib/pantallas/taxista/solicitar_turismo.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

class SolicitarTurismo extends StatefulWidget {
  const SolicitarTurismo({super.key});

  @override
  State<SolicitarTurismo> createState() => _SolicitarTurismoState();
}

class _SolicitarTurismoState extends State<SolicitarTurismo> {
  final _formKey = GlobalKey<FormState>();
  
  final List<String> _vehiculosSeleccionados = [];
  static const List<Map<String, String>> _vehiculosDisponibles = [
    {'value': 'carro', 'label': 'Carro Turismo', 'icon': '🚗'},
    {'value': 'jeepeta', 'label': 'Jeepeta Turismo', 'icon': '🚙'},
    {'value': 'minivan', 'label': 'Minivan Turismo', 'icon': '🚐'},
    {'value': 'bus', 'label': 'Bus Turismo', 'icon': '🚌'},
  ];

  final _telefonoCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();
  
  File? _licenciaFile;
  File? _seguroFile;
  File? _fotoVehiculoFile;
  
  bool _enviando = false;
  final _picker = ImagePicker();

  Future<void> _seleccionarArchivo(ImageSource source, String tipo) async {
    final XFile? pickedFile = await _picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    
    if (pickedFile != null) {
      setState(() {
        if (tipo == 'licencia') {
          _licenciaFile = File(pickedFile.path);
        } else if (tipo == 'seguro') {
          _seguroFile = File(pickedFile.path);
        } else if (tipo == 'foto') {
          _fotoVehiculoFile = File(pickedFile.path);
        }
      });
    }
  }

  Future<void> _enviarSolicitud() async {
    if (!_formKey.currentState!.validate()) return;
    if (_vehiculosSeleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos un vehículo')),
      );
      return;
    }
    if (_licenciaFile == null || _seguroFile == null || _fotoVehiculoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes subir todos los documentos')),
      );
      return;
    }

    setState(() => _enviando = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No hay sesión');

      // Aquí iría la lógica de subida de imágenes a Storage
      // Por ahora, usamos placeholders
      const String urlLicencia = 'pendiente';
      const String urlSeguro = 'pendiente';
      const String urlFoto = 'pendiente';

      await FirebaseFirestore.instance.collection('solicitudes_turismo').add({
        'uidChofer': user.uid,
        'nombre': user.displayName ?? '',
        'email': user.email ?? '',
        'telefono': _telefonoCtrl.text.trim(),
        'vehiculosSolicitados': _vehiculosSeleccionados,
        'documentos': {
          'licencia': urlLicencia,
          'seguro': urlSeguro,
          'fotoVehiculo': urlFoto,
        },
        'notas': _notasCtrl.text.trim(),
        'estado': 'pendiente',
        'fechaSolicitud': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Solicitud enviada. Espera la aprobación del admin.')),
      );
      
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: const RaiAppBar(
        title: 'Solicitar ser chofer de turismo',
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Selecciona los vehículos que puedes manejar:',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            ..._vehiculosDisponibles.map((v) => CheckboxListTile(
              value: _vehiculosSeleccionados.contains(v['value']),
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    _vehiculosSeleccionados.add(v['value']!);
                  } else {
                    _vehiculosSeleccionados.remove(v['value']);
                  }
                });
              },
              title: Text(
                '${v['icon']} ${v['label']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              activeColor: Colors.purple,
              checkColor: Colors.white,
            )),
            
            const SizedBox(height: 20),
            TextFormField(
              controller: _telefonoCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Teléfono de contacto',
                labelStyle: TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide.none,
                ),
              ),
              validator: (v) => v!.isEmpty ? 'Requerido' : null,
            ),
            
            const SizedBox(height: 20),
            _buildFilePicker('Licencia de conducir', _licenciaFile, () => _seleccionarArchivo(ImageSource.gallery, 'licencia')),
            const SizedBox(height: 12),
            _buildFilePicker('Seguro del vehículo', _seguroFile, () => _seleccionarArchivo(ImageSource.gallery, 'seguro')),
            const SizedBox(height: 12),
            _buildFilePicker('Foto del vehículo', _fotoVehiculoFile, () => _seleccionarArchivo(ImageSource.camera, 'foto')),
            
            const SizedBox(height: 20),
            TextFormField(
              controller: _notasCtrl,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notas adicionales (opcional)',
                labelStyle: TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _enviando ? null : _enviarSolicitud,
                icon: const Icon(Icons.send),
                label: Text(_enviando ? 'Enviando...' : 'Enviar solicitud'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePicker(String label, File? file, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: file != null ? Colors.green : Colors.grey),
        ),
        child: Row(
          children: [
            Icon(
              file != null ? Icons.check_circle : Icons.upload_file,
              color: file != null ? Colors.green : Colors.white70,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                file != null ? '$label (listo)' : label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: file != null ? Colors.green : Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}