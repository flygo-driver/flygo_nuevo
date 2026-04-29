// lib/pantallas/taxista/login_chofer_turismo.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/servicios/choferes_turismo_repo.dart';
import 'package:flygo_nuevo/modelo/vehiculo_turismo.dart';

class LoginChoferTurismo extends StatefulWidget {
  const LoginChoferTurismo({super.key});

  @override
  State<LoginChoferTurismo> createState() => _LoginChoferTurismoState();
}

class _LoginChoferTurismoState extends State<LoginChoferTurismo> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();

  final List<VehiculoTurismo> _vehiculos = [];
  bool _cargando = false;
  String? _error;

  final List<Map<String, dynamic>> _tiposVehiculo = const [
    {'tipo': 'carro', 'label': 'Carro Turismo', 'icon': '🚗'},
    {'tipo': 'jeepeta', 'label': 'Jeepeta Turismo', 'icon': '🚙'},
    {'tipo': 'minivan', 'label': 'Minivan Turismo', 'icon': '🚐'},
    {'tipo': 'bus', 'label': 'Bus Turismo', 'icon': '🚌'},
  ];

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _telefonoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarDatosUsuario() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _nombreCtrl.text = user.displayName ?? '';
      _emailCtrl.text = user.email ?? '';
      await _cargarDatosExistentes(user.uid);
    }
  }

  Future<void> _cargarDatosExistentes(String uid) async {
    try {
      final chofer = await ChoferesTurismoRepo.obtenerChofer(uid);
      if (chofer != null && mounted) {
        setState(() {
          _telefonoCtrl.text = chofer.telefono;
          _vehiculos.clear();
          _vehiculos.addAll(chofer.vehiculos);
        });
      }
    } catch (e) {
      // Silently fail - no hay datos previos
    }
  }

  void _agregarVehiculo() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _FormularioVehiculo(
        tiposVehiculo: _tiposVehiculo,
        onGuardar: (vehiculo) {
          setState(() {
            _vehiculos.add(vehiculo);
          });
        },
      ),
    );
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_vehiculos.isEmpty) {
      setState(() => _error = 'Debes agregar al menos un vehículo');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No hay sesión');

      await user.getIdToken(true);

      final existente = await ChoferesTurismoRepo.obtenerChofer(user.uid);
      final String estEx =
          (existente?.estado ?? '').toString().trim().toLowerCase();
      if (estEx == 'aprobado' || estEx == 'activo') {
        throw Exception('Tu cuenta ya está aprobada como chofer de turismo.');
      }
      if (estEx == 'pendiente') {
        throw Exception(
          'Ya tienes un registro pendiente de revisión. El administrador lo verá en el panel de taxistas turismo.',
        );
      }

      final dupSol = await FirebaseFirestore.instance
          .collection('solicitudes_turismo')
          .where('uidChofer', isEqualTo: user.uid)
          .where('estado', isEqualTo: 'pendiente')
          .limit(1)
          .get();
      if (dupSol.docs.isNotEmpty) {
        throw Exception(
          'Ya enviaste una solicitud pendiente. Espera la respuesta del administrador.',
        );
      }

      final List<Map<String, dynamic>> vehiculosMaps =
          _vehiculos.map((v) => v.toMap()).toList();

      await FirebaseFirestore.instance.collection('solicitudes_turismo').add({
        'uidChofer': user.uid,
        'nombre': _nombreCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'telefono': _telefonoCtrl.text.trim(),
        'vehiculos': vehiculosMaps,
        'documentos': <String, dynamic>{},
        'notas': '',
        'estado': 'pendiente',
        'fechaSolicitud': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Solicitud enviada. Espera aprobación del admin.'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Registro Chofer Turismo',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Completa tus datos para ser chofer de turismo',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),

            // Nombre
            TextFormField(
              controller: _nombreCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                labelStyle: TextStyle(color: Colors.white70),
                prefixIcon: Icon(Icons.person, color: Colors.purple),
                filled: true,
                fillColor: Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide.none,
                ),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),

            // Email
            TextFormField(
              controller: _emailCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Email',
                labelStyle: TextStyle(color: Colors.white70),
                prefixIcon: Icon(Icons.email, color: Colors.purple),
                filled: true,
                fillColor: Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide.none,
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Requerido';
                if (!v.contains('@')) return 'Email válido';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Teléfono
            TextFormField(
              controller: _telefonoCtrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono',
                labelStyle: TextStyle(color: Colors.white70),
                prefixIcon: Icon(Icons.phone, color: Colors.purple),
                filled: true,
                fillColor: Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide.none,
                ),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
            ),
            const SizedBox(height: 24),

            // Vehículos
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Vehículos',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _agregarVehiculo,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_vehiculos.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Center(
                  child: Text(
                    'No has agregado vehículos',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              )
            else
              ..._vehiculos.map((v) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.withAlpha(128)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _tiposVehiculo.firstWhere(
                                      (t) => t['tipo'] == v.tipo,
                                      orElse: () => const {'label': ''},
                                    )['label'] ??
                                    v.tipo,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.purple,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${v.marca} ${v.modelo} ${v.anio}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              Text(
                                '${v.color} • ${v.placa}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _vehiculos.remove(v);
                            });
                          },
                          icon:
                              const Icon(Icons.delete, color: Colors.redAccent),
                        ),
                      ],
                    ),
                  )),

            const SizedBox(height: 24),

            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _cargando ? null : _guardar,
                icon: _cargando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  _cargando ? 'Guardando...' : 'Guardar y solicitar aprobación',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
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
}

// ==============================================================
// FORMULARIO PARA AGREGAR VEHÍCULO
// ==============================================================
class _FormularioVehiculo extends StatefulWidget {
  final List<Map<String, dynamic>> tiposVehiculo;
  final Function(VehiculoTurismo) onGuardar;

  const _FormularioVehiculo({
    required this.tiposVehiculo,
    required this.onGuardar,
  });

  @override
  State<_FormularioVehiculo> createState() => __FormularioVehiculoState();
}

class __FormularioVehiculoState extends State<_FormularioVehiculo> {
  final _formKey = GlobalKey<FormState>();
  String _tipo = 'carro';
  final _marcaCtrl = TextEditingController();
  final _modeloCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _placaCtrl = TextEditingController();
  final _anioCtrl = TextEditingController();

  @override
  void dispose() {
    _marcaCtrl.dispose();
    _modeloCtrl.dispose();
    _colorCtrl.dispose();
    _placaCtrl.dispose();
    _anioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Agregar Vehículo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Tipo de vehículo
              DropdownButtonFormField<String>(
                value: _tipo,
                items: widget.tiposVehiculo.map<DropdownMenuItem<String>>((t) {
                  return DropdownMenuItem<String>(
                    value: t['tipo'] as String,
                    child: Text('${t['icon']} ${t['label']}'),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _tipo = v);
                  }
                },
                dropdownColor: Colors.grey[900],
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Tipo de vehículo',
                  labelStyle: TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Color(0xFF1E1E1E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Marca
              TextFormField(
                controller: _marcaCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Marca',
                  labelStyle: TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Color(0xFF1E1E1E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),

              // Modelo
              TextFormField(
                controller: _modeloCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Modelo',
                  labelStyle: TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Color(0xFF1E1E1E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),

              // Color
              TextFormField(
                controller: _colorCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Color',
                  labelStyle: TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Color(0xFF1E1E1E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),

              // Placa
              TextFormField(
                controller: _placaCtrl,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Placa',
                  labelStyle: TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Color(0xFF1E1E1E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),

              // Año
              TextFormField(
                controller: _anioCtrl,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Año',
                  labelStyle: TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Color(0xFF1E1E1E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requerido';
                  final anio = int.tryParse(v);
                  if (anio == null) return 'Número inválido';
                  if (anio < 1990 || anio > DateTime.now().year + 1) {
                    return 'Año inválido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          widget.onGuardar(VehiculoTurismo(
                            tipo: _tipo,
                            marca: _marcaCtrl.text.trim(),
                            modelo: _modeloCtrl.text.trim(),
                            color: _colorCtrl.text.trim(),
                            placa: _placaCtrl.text.trim().toUpperCase(),
                            anio: int.parse(_anioCtrl.text.trim()),
                          ));
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
