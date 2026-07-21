// lib/pantallas/taxista/login_chofer_turismo.dart
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flygo_nuevo/modelo/vehiculo_turismo.dart';
import 'package:flygo_nuevo/servicios/choferes_turismo_repo.dart';
import 'package:flygo_nuevo/servicios/solicitud_turismo_repo.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

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
  final _notasCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  final List<VehiculoTurismo> _vehiculos = [];
  Uint8List? _licenciaBytes;
  Uint8List? _seguroBytes;
  Uint8List? _fotoVehiculoBytes;

  bool _cargando = false;
  bool _cargandoEstado = true;
  String? _error;
  EstadoRegistroTurismo? _estado;

  final List<Map<String, dynamic>> _tiposVehiculo = const [
    {'tipo': 'carro', 'label': 'Carro Turismo', 'icon': '🚗'},
    {'tipo': 'jeepeta', 'label': 'Jeepeta Turismo', 'icon': '🚙'},
    {'tipo': 'minivan', 'label': 'Minivan Turismo', 'icon': '🚐'},
    {'tipo': 'bus', 'label': 'Bus Turismo', 'icon': '🚌'},
  ];

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _nombreCtrl.text = user.displayName ?? '';
      _emailCtrl.text = user.email ?? '';
      await _cargarDatosExistentes(user.uid);
      final EstadoRegistroTurismo est =
          await SolicitudTurismoRepo.estadoRegistro(user.uid);
      if (mounted) {
        setState(() {
          _estado = est;
          _cargandoEstado = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _cargandoEstado = false);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _telefonoCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarDatosExistentes(String uid) async {
    try {
      final chofer = await ChoferesTurismoRepo.obtenerChofer(uid);
      if (chofer != null && mounted) {
        setState(() {
          _telefonoCtrl.text = chofer.telefono;
          _vehiculos
            ..clear()
            ..addAll(chofer.vehiculos);
        });
      }
    } catch (_) {}
  }

  Future<void> _seleccionarDocumento(String tipo) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      // Leer ya: en Android la ruta en cache (scaled_*.jpg) puede borrarse antes de enviar.
      final Uint8List bytes = await picked.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('No se pudo leer la imagen seleccionada.');
      }
      if (bytes.length > 10 * 1024 * 1024) {
        throw Exception('La imagen excede 10 MB. Elige otra más liviana.');
      }
      if (!mounted) return;
      setState(() {
        switch (tipo) {
          case 'licencia':
            _licenciaBytes = bytes;
            break;
          case 'seguro':
            _seguroBytes = bytes;
            break;
          case 'fotoVehiculo':
            _fotoVehiculoBytes = bytes;
            break;
        }
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _agregarVehiculo() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _FormularioVehiculo(
        tiposVehiculo: _tiposVehiculo,
        onGuardar: (vehiculo) {
          setState(() => _vehiculos.add(vehiculo));
        },
      ),
    );
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_vehiculos.isEmpty) {
      setState(() => _error = 'Debes agregar al menos un vehículo turístico');
      return;
    }
    if (_licenciaBytes == null ||
        _seguroBytes == null ||
        _fotoVehiculoBytes == null) {
      setState(() => _error = 'Sube licencia, seguro y foto del vehículo');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No hay sesión');

      final String urlLicencia =
          await SolicitudTurismoRepo.subirBytesDocumento(
        uid: user.uid,
        tipo: 'licencia',
        bytes: _licenciaBytes!,
      );
      final String urlSeguro = await SolicitudTurismoRepo.subirBytesDocumento(
        uid: user.uid,
        tipo: 'seguro',
        bytes: _seguroBytes!,
      );
      final String urlFoto = await SolicitudTurismoRepo.subirBytesDocumento(
        uid: user.uid,
        tipo: 'foto_vehiculo',
        bytes: _fotoVehiculoBytes!,
      );

      await SolicitudTurismoRepo.enviarSolicitud(
        nombre: _nombreCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        telefono: _telefonoCtrl.text.trim(),
        vehiculos: _vehiculos,
        documentosUrls: <String, String>{
          'licencia': urlLicencia,
          'seguro': urlSeguro,
          'fotoVehiculo': urlFoto,
        },
        notas: _notasCtrl.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Solicitud enviada. Un administrador la revisará en «Aprobar Solicitudes».',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Widget _buildEstadoPantalla() {
    final EstadoRegistroTurismo? est = _estado;
    if (est == null) return const SizedBox.shrink();

    if (est.fase == 'aprobado') {
      return _EstadoCard(
        icon: Icons.verified_rounded,
        color: Colors.green,
        titulo: 'Chofer de turismo aprobado',
        mensaje:
            'Ya puedes entrar al Pool turístico y recibir viajes liberados por administración. '
            'Activa tu disponibilidad en el pool para aceptar servicios.',
        accion: FilledButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.check),
          label: const Text('Entendido'),
        ),
      );
    }

    if (est.fase == 'pendiente_adm') {
      return _EstadoCard(
        icon: Icons.hourglass_top_rounded,
        color: Colors.orange,
        titulo: 'Solicitud en revisión',
        mensaje:
            'Tu registro fue enviado al panel de administración. '
            'Cuando te aprueben podrás ver el Pool turístico y recibir asignaciones automáticas '
            'según tu vehículo registrado.',
        accion: OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Volver'),
        ),
      );
    }

    if (est.fase == 'rechazado') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EstadoCard(
            icon: Icons.info_outline_rounded,
            color: Colors.redAccent,
            titulo: 'Solicitud rechazada',
            mensaje: est.motivoRechazo?.isNotEmpty == true
                ? 'Motivo: ${est.motivoRechazo}'
                : 'Puedes corregir tus datos y enviar una nueva solicitud.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => setState(() => _estado = const EstadoRegistroTurismo(fase: 'sin_solicitud')),
            icon: const Icon(Icons.refresh),
            label: const Text('Enviar nueva solicitud'),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _docPicker(String label, bool listo, String tipo) {
    return InkWell(
      onTap: _cargando ? null : () => _seleccionarDocumento(tipo),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: listo ? Colors.green : Colors.grey),
        ),
        child: Row(
          children: [
            Icon(
              listo ? Icons.check_circle : Icons.upload_file,
              color: listo ? Colors.green : Colors.white70,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                listo ? '$label (listo)' : label,
                style: TextStyle(
                  color: listo ? Colors.green : Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargandoEstado) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: const RaiAppBar(
          title: 'Registro Chofer Turismo',
          showBackWhenCanPop: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final bool mostrarSoloEstado =
        _estado != null && _estado!.fase != 'sin_solicitud' && _estado!.fase != 'rechazado';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: const RaiAppBar(
        title: 'Registro Chofer Turismo',
        showBackWhenCanPop: true,
      ),
      body: mostrarSoloEstado
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [_buildEstadoPantalla()],
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_estado?.fase == 'rechazado') ...[
                    _buildEstadoPantalla(),
                    const SizedBox(height: 8),
                    const Divider(color: Colors.white24),
                    const SizedBox(height: 8),
                  ],
                  const Text(
                    'Completa tus datos. Administración revisará vehículo y documentos antes de aprobarte.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _nombreCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('Nombre completo', Icons.person),
                    validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('Email', Icons.email),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Requerido';
                      if (!v.contains('@')) return 'Email válido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _telefonoCtrl,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.phone,
                    decoration: _inputDeco('Teléfono', Icons.phone),
                    validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Vehículos turísticos',
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
                          'Agrega al menos un vehículo (tipo, placa, marca, modelo)',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  else
                    ..._vehiculos.map(_tileVehiculo),
                  const SizedBox(height: 24),
                  const Text(
                    'Documentos (obligatorios)',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _docPicker('Licencia de conducir', _licenciaBytes != null, 'licencia'),
                  const SizedBox(height: 10),
                  _docPicker('Seguro del vehículo', _seguroBytes != null, 'seguro'),
                  const SizedBox(height: 10),
                  _docPicker('Foto del vehículo', _fotoVehiculoBytes != null, 'fotoVehiculo'),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notasCtrl,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 2,
                    decoration: _inputDeco('Notas para administración (opcional)', Icons.notes),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _cargando ? null : _guardar,
                      icon: _cargando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(
                        _cargando ? 'Enviando solicitud…' : 'Enviar a administración',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.purple,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: Colors.purple),
      filled: true,
      fillColor: const Color(0xFF1E1E1E),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _tileVehiculo(VehiculoTurismo v) {
    return Container(
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
                  style: const TextStyle(
                    color: Colors.purple,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${v.marca} ${v.modelo} ${v.anio} · ${v.color}',
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(
                  'Placa ${v.placa} · Cap. ${SolicitudTurismoRepo.capacidadPorTipo(v.tipo)} pax',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _vehiculos.remove(v)),
            icon: const Icon(Icons.delete, color: Colors.redAccent),
          ),
        ],
      ),
    );
  }
}

class _EstadoCard extends StatelessWidget {
  const _EstadoCard({
    required this.icon,
    required this.color,
    required this.titulo,
    required this.mensaje,
    this.accion,
  });

  final IconData icon;
  final Color color;
  final String titulo;
  final String mensaje;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 48),
          const SizedBox(height: 12),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          if (accion != null) ...[
            const SizedBox(height: 20),
            accion!,
          ],
        ],
      ),
    );
  }
}

class _FormularioVehiculo extends StatefulWidget {
  const _FormularioVehiculo({
    required this.tiposVehiculo,
    required this.onGuardar,
  });

  final List<Map<String, dynamic>> tiposVehiculo;
  final void Function(VehiculoTurismo) onGuardar;

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
              const Text(
                'Agregar vehículo turístico',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                items: widget.tiposVehiculo.map<DropdownMenuItem<String>>((t) {
                  return DropdownMenuItem<String>(
                    value: t['tipo'] as String,
                    child: Text('${t['icon']} ${t['label']}'),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _tipo = v);
                },
                dropdownColor: Colors.grey[900],
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Tipo de vehículo',
                  labelStyle: TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Color(0xFF1E1E1E),
                ),
              ),
              const SizedBox(height: 12),
              _campo(_marcaCtrl, 'Marca'),
              const SizedBox(height: 12),
              _campo(_modeloCtrl, 'Modelo'),
              const SizedBox(height: 12),
              _campo(_colorCtrl, 'Color'),
              const SizedBox(height: 12),
              _campo(_placaCtrl, 'Placa', uppercase: true),
              const SizedBox(height: 12),
              TextFormField(
                controller: _anioCtrl,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Año',
                  labelStyle: TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Color(0xFF1E1E1E),
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
                          widget.onGuardar(
                            VehiculoTurismo(
                              tipo: _tipo,
                              marca: _marcaCtrl.text.trim(),
                              modelo: _modeloCtrl.text.trim(),
                              color: _colorCtrl.text.trim(),
                              placa: _placaCtrl.text.trim().toUpperCase(),
                              anio: int.parse(_anioCtrl.text.trim()),
                            ),
                          );
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

  Widget _campo(TextEditingController c, String label, {bool uppercase = false}) {
    return TextFormField(
      controller: c,
      style: const TextStyle(color: Colors.white),
      textCapitalization:
          uppercase ? TextCapitalization.characters : TextCapitalization.none,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
      ),
      validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
    );
  }
}
