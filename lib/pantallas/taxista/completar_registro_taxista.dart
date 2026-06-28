import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flygo_nuevo/utils/firebase_auth_resolve.dart';
import 'package:flygo_nuevo/servicios/taxista_registro_perfil_data.dart';
import 'package:flygo_nuevo/servicios/logout.dart';
import 'package:flygo_nuevo/pantallas/taxista/documentos_taxista.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';
import 'package:flygo_nuevo/widgets/taxista_onboarding_acciones_footer.dart';

/// Onboarding obligatorio tras Google (o perfil incompleto).
class CompletarRegistroTaxista extends StatefulWidget {
  const CompletarRegistroTaxista({super.key});

  @override
  State<CompletarRegistroTaxista> createState() =>
      _CompletarRegistroTaxistaState();
}

class _CompletarRegistroTaxistaState extends State<CompletarRegistroTaxista> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  final _placa = TextEditingController();
  final _marca = TextEditingController();
  final _modelo = TextEditingController();
  final _color = TextEditingController();
  final _anio = TextEditingController();

  String _tipoServicio = 'bola_ahorro';
  String _tipoVehiculo = 'Carro';
  String? _subtipoTurismo = 'carro';
  bool _cargando = true;
  bool _guardando = false;

  static const _tiposVehiculoNormal = [
    'Carro',
    'Jeepeta',
    'Minivan',
    'Minibús',
    'Autobús',
    'Guagua',
  ];

  static const _subtiposTurismo = [
    {'value': 'carro', 'label': 'Carro turismo'},
    {'value': 'jeepeta', 'label': 'Jeepeta turismo'},
    {'value': 'minivan', 'label': 'Minivan turismo'},
    {'value': 'bus', 'label': 'Bus turismo'},
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    _placa.dispose();
    _marca.dispose();
    _modelo.dispose();
    _color.dispose();
    _anio.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      final User? resolved = await resolveFirebaseUser(
        timeout: const Duration(seconds: 12),
      );
      if (resolved == null) {
        if (mounted) setState(() => _cargando = false);
        return;
      }
      await _cargarDatosPerfil(resolved);
      return;
    }
    await _cargarDatosPerfil(u);
  }

  Future<void> _cargarDatosPerfil(User u) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(u.uid)
          .get();
      final d = snap.data() ?? {};
      _nombre.text = (d['nombre'] ?? u.displayName ?? '').toString().trim();
      _telefono.text = (d['telefono'] ?? '').toString();
      _placa.text = (d['placa'] ?? '').toString();
      _marca.text = (d['vehiculoMarca'] ?? d['marca'] ?? '').toString();
      _modelo.text = (d['vehiculoModelo'] ?? d['modelo'] ?? '').toString();
      _color.text = (d['vehiculoColor'] ?? d['color'] ?? '').toString();
      final anio = d['anio'] ?? d['vehiculoAnio'];
      if (anio != null) _anio.text = anio.toString();
      final tipo = (d['tipoServicio'] ?? '').toString().trim().toLowerCase();
      if (TaxistaRegistroPerfilData.tiposServicioValidos.contains(tipo)) {
        _tipoServicio = tipo;
      }
      final tv = (d['tipoVehiculo'] ?? d['vehiculoTipo'] ?? '').toString();
      if (tv.isNotEmpty) {
        if (_tipoServicio == 'turismo') {
          _subtipoTurismo = tv;
        } else if (_tiposVehiculoNormal.contains(tv)) {
          _tipoVehiculo = tv;
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _bloquearSalida() {
    _snack('Completá tu registro para operar como conductor en RAI.');
  }

  Future<void> _volverAlInicio() async {
    await cerrarSesion(context);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    User? u = FirebaseAuth.instance.currentUser;
    u ??= await resolveFirebaseUser(timeout: const Duration(seconds: 12));
    if (u == null) {
      _snack('Sesión expirada. Vuelve a iniciar sesión.');
      return;
    }

    final anio = int.tryParse(_anio.text.trim());
    if (anio == null) {
      _snack('Año inválido.');
      return;
    }

    setState(() => _guardando = true);
    try {
      final merge = TaxistaRegistroPerfilData.mergeRegistroOperativo(
        nombre: _nombre.text,
        telefono: _telefono.text,
        tipoServicio: _tipoServicio,
        placa: _placa.text,
        marca: _marca.text,
        modelo: _modelo.text,
        color: _color.text,
        anio: anio,
        tipoVehiculoNormal: _tipoVehiculo,
        subtipoTurismo: _subtipoTurismo,
      );
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(u.uid)
          .set(merge, SetOptions(merge: true));
      await u.updateDisplayName(_nombre.text.trim());
      if (!mounted) return;
      _snack('Registro guardado. Ahora subí tus documentos.');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const DocumentosTaxista(onboardingObligatorio: true),
        ),
        (route) => false,
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        _snack(
          'No se pudo guardar el registro (permisos). Actualiza la app o contacta soporte.',
        );
      } else {
        _snack('Error al guardar: ${e.message ?? e.code}');
      }
    } catch (e) {
      _snack('Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  InputDecoration _dec(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
    );
  }

  Widget _tipoServicioTile({
    required String value,
    required IconData icon,
    required String label,
  }) {
    final sel = _tipoServicio == value;
    return ListTile(
      leading: Icon(icon, color: sel ? Colors.greenAccent : null),
      title: Text(label),
      trailing: sel ? const Icon(Icons.check_circle, color: Colors.greenAccent) : null,
      onTap: () => setState(() => _tipoServicio = value),
    );
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
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _bloquearSalida();
      },
      child: Scaffold(
        appBar: const RaiAppBar(title: 'Completa tu registro de conductor'),
        body: SafeArea(
          bottom: false,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                TaxistaOnboardingAccionesFooter.scrollBottomPadding(context),
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                Text(
                  'RAI necesita tus datos y tu vehículo. Al guardar, '
                  'continuás con licencia, matrícula, seguro, foto del vehículo '
                  'y demás documentos. Después de subirlos, pulsa «Enviar a revisión» '
                  'para que administración los valide.',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.75),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Datos personales',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nombre,
                  decoration: _dec('Nombre completo', Icons.person),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) {
                    if ((v ?? '').trim().length < 2) return 'Requerido';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telefono,
                  decoration: _dec('Teléfono RD', Icons.phone),
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    if (!TaxistaRegistroPerfilData.telefonoRdValido(v)) {
                      return 'Teléfono inválido (10 dígitos)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'Tipo de servicio',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                _tipoServicioTile(
                  value: 'bola_ahorro',
                  icon: Icons.savings_outlined,
                  label: 'Bola de ahorro',
                ),
                _tipoServicioTile(
                  value: 'normal',
                  icon: Icons.local_taxi,
                  label: 'Taxi normal',
                ),
                _tipoServicioTile(
                  value: 'motor',
                  icon: Icons.two_wheeler,
                  label: 'Motor',
                ),
                _tipoServicioTile(
                  value: 'turismo',
                  icon: Icons.tour,
                  label: 'Turismo',
                ),
                if (_tipoServicio == 'normal' || _tipoServicio == 'bola_ahorro') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _tipoVehiculo,
                    decoration: _dec('Tipo de vehículo', Icons.directions_car),
                    items: _tiposVehiculoNormal
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _tipoVehiculo = v);
                    },
                  ),
                ],
                if (_tipoServicio == 'turismo') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _subtipoTurismo,
                    decoration: _dec('Vehículo turismo', Icons.airport_shuttle),
                    items: _subtiposTurismo
                        .map(
                          (e) => DropdownMenuItem(
                            value: e['value'],
                            child: Text(e['label']!),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _subtipoTurismo = v),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Datos del vehículo',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _placa,
                  decoration: _dec('Placa', Icons.pin),
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _modelo,
                  decoration: _dec('Modelo', Icons.directions_car),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _marca,
                  decoration: _dec('Marca', Icons.factory_outlined),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _anio,
                  decoration: _dec('Año', Icons.calendar_today),
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
                  decoration: _dec('Color', Icons.palette),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: TaxistaOnboardingAccionesFooter(
          primaryLabel: 'Guardar y continuar',
          primaryIcon: Icons.check_circle_outline_rounded,
          busy: _guardando,
          onPrimary: _guardar,
          onSalirInicio: () => unawaited(_volverAlInicio()),
        ),
      ),
    );
  }
}
