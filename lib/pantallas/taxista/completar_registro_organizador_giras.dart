import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flygo_nuevo/pantallas/taxista/completar_registro_taxista.dart';
import 'package:flygo_nuevo/servicios/logout.dart';
import 'package:flygo_nuevo/servicios/organizador_giras_perfil_data.dart';
import 'package:flygo_nuevo/servicios/taxista_registro_perfil_data.dart';
import 'package:flygo_nuevo/utils/bancos_rd.dart';
import 'package:flygo_nuevo/utils/firebase_auth_resolve.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';
import 'package:flygo_nuevo/utils/pool_publicar_errores.dart';
import 'package:flygo_nuevo/widgets/pool_gira_publicar_ui.dart';
import 'package:flygo_nuevo/widgets/taxista_onboarding_acciones_footer.dart';

/// Registro corto: organiza giras, contrata guagua y chofer (sin documentos de vehículo).
class CompletarRegistroOrganizadorGiras extends StatefulWidget {
  const CompletarRegistroOrganizadorGiras({super.key});

  @override
  State<CompletarRegistroOrganizadorGiras> createState() =>
      _CompletarRegistroOrganizadorGirasState();
}

class _CompletarRegistroOrganizadorGirasState
    extends State<CompletarRegistroOrganizadorGiras> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  final _whatsapp = TextEditingController();
  final _cedula = TextEditingController();
  final _agencia = TextEditingController();
  final _bancoCuenta = TextEditingController();
  final _bancoTitular = TextEditingController();

  final _picker = ImagePicker();
  final _storage =
      FirebaseStorage.instanceFor(bucket: 'gs://flygo-rd.firebasestorage.app');

  String? _cedulaFotoUrl;
  String _bancoNombre = '';
  String _bancoTipoCuenta = '';
  bool _cargando = true;
  bool _guardando = false;
  bool _subiendoFoto = false;

  @override
  void initState() {
    super.initState();
    unawaited(_cargar());
  }

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    _whatsapp.dispose();
    _cedula.dispose();
    _agencia.dispose();
    _bancoCuenta.dispose();
    _bancoTitular.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final u = FirebaseAuth.instance.currentUser ??
        await resolveFirebaseUser(timeout: const Duration(seconds: 12));
    if (u == null) {
      if (mounted) setState(() => _cargando = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(u.uid)
          .get();
      final d = snap.data() ?? {};
      _nombre.text = (d['nombre'] ?? u.displayName ?? '').toString().trim();
      _telefono.text = (d['telefono'] ?? u.phoneNumber ?? '').toString();
      _whatsapp.text = (d['whatsapp'] ?? '').toString();
      _cedula.text = (d['cedula'] ?? d['ciTaxista'] ?? '').toString();
      _agencia.text = (d['agenciaNombre'] ?? '').toString();
      _bancoCuenta.text = (d['bancoCuenta'] ?? '').toString();
      _bancoTitular.text = (d['bancoTitular'] ?? '').toString();
      _bancoNombre = (d['bancoNombre'] ?? '').toString();
      _bancoTipoCuenta = (d['bancoTipoCuenta'] ?? '').toString();
      _cedulaFotoUrl = (d['cedulaFotoUrl'] ?? d['documentoIdentidadUrl'] ?? '')
          .toString()
          .trim();
      if (_cedulaFotoUrl!.isEmpty) _cedulaFotoUrl = null;
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<ImageSource?> _elegirOrigenFotoCedula() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Foto de cédula o pasaporte',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Tomar foto con cámara'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Elegir de galería'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _subirCedula() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final source = await _elegirOrigenFotoCedula();
    if (source == null || !mounted) return;

    setState(() => _subiendoFoto = true);
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 6 * 1024 * 1024) {
        _snack('La foto pesa más de 6 MB.');
        return;
      }
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage
          .ref()
          .child('organizadores_giras')
          .child(uid)
          .child('cedula_$ts.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() => _cedulaFotoUrl = url);
      _snack('Foto de identidad guardada.');
    } on FirebaseException catch (e) {
      if (e.code == 'unauthorized' || e.plugin == 'firebase_storage') {
        _snack(
          'No se pudo subir la foto (permisos Storage). '
          'Actualiza la app o contacta soporte si persiste.',
        );
      } else {
        _snack(PoolPublicarErrores.traducirSubida(e));
      }
    } catch (e) {
      _snack(PoolPublicarErrores.traducirSubida(e));
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_cedulaFotoUrl == null || _cedulaFotoUrl!.isEmpty) {
      _snack('Sube una foto de tu cédula o pasaporte.');
      return;
    }

    User? u = FirebaseAuth.instance.currentUser;
    u ??= await resolveFirebaseUser(timeout: const Duration(seconds: 12));
    if (u == null) {
      _snack('Sesión expirada. Vuelve a iniciar sesión.');
      return;
    }

    setState(() => _guardando = true);
    try {
      final merge = OrganizadorGirasPerfilData.mergeRegistro(
        nombre: _nombre.text,
        telefono: _telefono.text,
        whatsapp: _whatsapp.text,
        cedula: _cedula.text,
        cedulaFotoUrl: _cedulaFotoUrl!,
        agenciaNombre: _agencia.text,
        bancoNombre: _bancoNombre.isEmpty ? null : _bancoNombre,
        bancoCuenta: _bancoCuenta.text,
        bancoTipoCuenta: _bancoTipoCuenta.isEmpty ? null : _bancoTipoCuenta,
        bancoTitular: _bancoTitular.text,
      );
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(u.uid)
          .set(merge, SetOptions(merge: true));
      await u.updateDisplayName(_nombre.text.trim());
      if (!mounted) return;
      _snack('Registro listo. Ya puedes publicar giras.');
      Navigator.of(context).pushNamedAndRemoveUntil('/auth_check', (r) => false);
    } on FirebaseException catch (e) {
      _snack('Error al guardar: ${e.message ?? e.code}');
    } catch (e) {
      _snack('Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  InputDecoration _dec(String label, IconData icon) {
    return InputDecoration(labelText: label, prefixIcon: Icon(icon));
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _snack('Completa tu registro para publicar giras en RAI.');
        }
      },
      child: Scaffold(
        appBar: const RaiAppBar(title: 'Registro organizador de giras'),
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
              children: [
                const OrganizadorGirasBrandHeader(
                  subtitulo:
                      'Completa tu perfil para publicar excursiones y vender cupos.',
                ),
                const SizedBox(height: 16),
                Text(
                  'Publicas excursiones y contratas guagua con chofer. '
                  'No necesitas licencia ni datos del vehículo: solo tu identidad '
                  'y los datos de tu agencia o negocio.',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.75),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => const _RedirectConductorVehiculoHint(),
                    ),
                  ),
                  icon: const Icon(Icons.directions_bus_outlined),
                  label: const Text('¿Tienes guagua? Regístrate como conductor'),
                ),
                const SizedBox(height: 16),
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
                  validator: (v) =>
                      (v ?? '').trim().length < 2 ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cedula,
                  decoration: _dec('Cédula o pasaporte', Icons.badge_outlined),
                  validator: (v) => OrganizadorGirasPerfilData.cedulaValida(v)
                      ? null
                      : 'Documento inválido',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _subiendoFoto ? null : _subirCedula,
                  icon: _subiendoFoto
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _cedulaFotoUrl != null
                              ? Icons.check_circle
                              : Icons.add_a_photo_outlined,
                          color: _cedulaFotoUrl != null ? Colors.green : null,
                        ),
                  label: Text(
                    _cedulaFotoUrl != null
                        ? 'Foto de identidad lista'
                        : 'Foto cédula o pasaporte (cámara o galería) *',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telefono,
                  decoration: _dec('Teléfono RD', Icons.phone),
                  keyboardType: TextInputType.phone,
                  validator: (v) =>
                      TaxistaRegistroPerfilData.telefonoRdValido(v)
                          ? null
                          : 'Teléfono inválido (10 dígitos)',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _whatsapp,
                  decoration: _dec('WhatsApp (opcional)', Icons.chat),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 24),
                Text(
                  'Agencia o negocio',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _agencia,
                  decoration: _dec('Nombre de agencia o negocio', Icons.store),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v ?? '').trim().length < 2 ? 'Requerido' : null,
                ),
                const SizedBox(height: 24),
                Text(
                  'Cuenta bancaria (opcional ahora)',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'La necesitarás para cobrar reservas. También puedes completarla al publicar tu primera gira.',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.65),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue:
                      _bancoNombre.isEmpty ? null : _bancoNombre,
                  decoration: _dec('Banco', Icons.account_balance),
                  items: BancosRd.nombres
                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (v) => setState(() => _bancoNombre = v ?? ''),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bancoCuenta,
                  decoration: _dec('Número de cuenta', Icons.numbers),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue:
                      _bancoTipoCuenta.isEmpty ? null : _bancoTipoCuenta,
                  decoration: _dec('Tipo de cuenta', Icons.savings_outlined),
                  items: BancosRd.tiposCuentaGira
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _bancoTipoCuenta = v ?? ''),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bancoTitular,
                  decoration: _dec('Titular de la cuenta', Icons.person_outline),
                  textCapitalization: TextCapitalization.words,
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: TaxistaOnboardingAccionesFooter(
          primaryLabel: 'Guardar y entrar a giras',
          primaryIcon: Icons.tour_outlined,
          busy: _guardando,
          onPrimary: _guardar,
          onSalirInicio: () => unawaited(cerrarSesion(context)),
        ),
      ),
    );
  }
}

/// Puente de vuelta al registro de conductor con vehículo.
class _RedirectConductorVehiculoHint extends StatelessWidget {
  const _RedirectConductorVehiculoHint();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: const RaiAppBar(title: 'Conductor con vehículo'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Icon(
                Icons.directions_bus,
                size: 56,
                color: isDark ? Colors.white : cs.primary,
              ),
              const SizedBox(height: 20),
              Text(
                'Si tienes guagua y manejas (o tu chofer usa tu vehículo), '
                'completa el registro de conductor con licencia, matrícula y datos del vehículo.',
                style: TextStyle(
                  height: 1.45,
                  fontSize: 16,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.92)
                      : cs.onSurface.withValues(alpha: 0.88),
                ),
              ),
              const Spacer(),
              Material(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Text(
                    'Necesitarás licencia, matrícula, seguro y datos del vehículo.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: isDark
                          ? Colors.white70
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => const CompletarRegistroTaxista(),
                      ),
                    ),
                    icon: Icon(
                      Icons.arrow_forward_rounded,
                      color: isDark ? const Color(0xFF1B5E20) : Colors.white,
                    ),
                    label: Text(
                      'Ir a registro de conductor',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: 0.2,
                        color: isDark ? const Color(0xFF1B5E20) : Colors.white,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          isDark ? Colors.white : const Color(0xFF2E7D32),
                      foregroundColor:
                          isDark ? const Color(0xFF1B5E20) : Colors.white,
                      elevation: isDark ? 0 : 1,
                      shadowColor: Colors.black26,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}
