import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flygo_nuevo/utils/bancos_rd.dart';
import 'package:flygo_nuevo/widgets/avatar_circle.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

/// Ajustes del organizador de giras: foto, contacto, agencia y banco.
class OrganizadorGirasConfiguracionPage extends StatefulWidget {
  const OrganizadorGirasConfiguracionPage({super.key});

  @override
  State<OrganizadorGirasConfiguracionPage> createState() =>
      _OrganizadorGirasConfiguracionPageState();
}

class _OrganizadorGirasConfiguracionPageState
    extends State<OrganizadorGirasConfiguracionPage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final _storage =
      FirebaseStorage.instanceFor(bucket: 'gs://flygo-rd.firebasestorage.app');

  final _nombreCtrl = TextEditingController();
  final _agenciaCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  final _bancoCuentaCtrl = TextEditingController();
  final _bancoTitularCtrl = TextEditingController();

  String _bancoNombre = '';
  String _bancoTipoCuenta = '';
  bool _cargando = true;
  bool _guardando = false;
  bool _subiendoFoto = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _agenciaCtrl.dispose();
    _whatsappCtrl.dispose();
    _bancoCuentaCtrl.dispose();
    _bancoTitularCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _cargando = false);
      return;
    }
    try {
      final snap =
          await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      final d = snap.data() ?? {};
      _nombreCtrl.text = (d['nombre'] ?? '').toString();
      _agenciaCtrl.text = (d['agenciaNombre'] ?? '').toString();
      _whatsappCtrl.text = (d['whatsapp'] ?? d['telefono'] ?? '').toString();
      _bancoCuentaCtrl.text = (d['bancoCuenta'] ?? '').toString();
      _bancoTitularCtrl.text = (d['bancoTitular'] ?? '').toString();
      _bancoNombre = (d['bancoNombre'] ?? '').toString();
      _bancoTipoCuenta = (d['bancoTipoCuenta'] ?? '').toString();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<ImageSource?> _elegirOrigenFoto() {
    final cs = Theme.of(context).colorScheme;
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                'Foto de perfil',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: cs.primary),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: cs.primary),
              title: const Text('Elegir de galería'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _cambiarFoto(String uid, String nombre) async {
    final source = await _elegirOrigenFoto();
    if (source == null || !mounted) return;
    setState(() => _subiendoFoto = true);
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        _snack('La imagen pesa más de 5 MB.');
        return;
      }
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref =
          _storage.ref().child('perfiles').child(uid).child('avatar_$ts.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'fotoUrl': url,
        'actualizadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      _snack('Foto de perfil actualizada.');
      setState(() {});
    } on FirebaseException catch (e) {
      _snack('No se pudo subir la foto: ${e.message ?? e.code}');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  Future<void> _guardar(String uid) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'nombre': _nombreCtrl.text.trim(),
        'agenciaNombre': _agenciaCtrl.text.trim(),
        'whatsapp': _whatsappCtrl.text.trim(),
        if (_bancoNombre.isNotEmpty) 'bancoNombre': _bancoNombre.trim(),
        'bancoCuenta': _bancoCuentaCtrl.text.trim(),
        if (_bancoTipoCuenta.isNotEmpty) 'bancoTipoCuenta': _bancoTipoCuenta,
        'bancoTitular': _bancoTitularCtrl.text.trim(),
        'actualizadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final user = FirebaseAuth.instance.currentUser;
      await user?.updateDisplayName(_nombreCtrl.text.trim());
      if (!mounted) return;
      _snack('Perfil guardado.');
      Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      _snack('Error al guardar: ${e.message ?? e.code}');
    } catch (e) {
      _snack('Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Sesión expirada')),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docRef =
        FirebaseFirestore.instance.collection('usuarios').doc(user.uid);

    if (_cargando) {
      return Scaffold(
        appBar: const RaiAppBar(title: 'Configurar perfil'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: const RaiAppBar(title: 'Configurar perfil'),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() ?? {};
          final fotoUrl = (data['fotoUrl'] ?? '').toString();
          final nombre = (data['nombre'] ?? _nombreCtrl.text).toString();

          return SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  24 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                children: [
                  Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AvatarCircle(
                          imageUrl: fotoUrl,
                          name: nombre,
                          size: 108,
                          onTap: _subiendoFoto
                              ? null
                              : () => _cambiarFoto(user.uid, nombre),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Material(
                            color: isDark ? Colors.white : cs.primary,
                            shape: const CircleBorder(),
                            elevation: 2,
                            child: InkWell(
                              onTap: _subiendoFoto
                                  ? null
                                  : () => _cambiarFoto(user.uid, nombre),
                              customBorder: const CircleBorder(),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: _subiendoFoto
                                    ? SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: isDark
                                              ? cs.primary
                                              : Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        Icons.camera_alt_rounded,
                                        size: 20,
                                        color: isDark
                                            ? const Color(0xFF1B5E20)
                                            : Colors.white,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Toca la foto para cambiarla (cámara o galería)',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _nombreCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        (v ?? '').trim().length < 2 ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _agenciaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de agencia o negocio',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        (v ?? '').trim().length < 2 ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _whatsappCtrl,
                    decoration: const InputDecoration(
                      labelText: 'WhatsApp de contacto',
                      prefixIcon: Icon(Icons.chat_outlined),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Cuenta bancaria (liquidación de giras)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue:
                        _bancoNombre.isEmpty ? null : _bancoNombre,
                    decoration: const InputDecoration(
                      labelText: 'Banco',
                      prefixIcon: Icon(Icons.account_balance_outlined),
                    ),
                    items: BancosRd.nombres
                        .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                        .toList(),
                    onChanged: (v) => setState(() => _bancoNombre = v ?? ''),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bancoCuentaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Número de cuenta',
                      prefixIcon: Icon(Icons.numbers),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue:
                        _bancoTipoCuenta.isEmpty ? null : _bancoTipoCuenta,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de cuenta',
                      prefixIcon: Icon(Icons.savings_outlined),
                    ),
                    items: BancosRd.tiposCuentaGira
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => _bancoTipoCuenta = v ?? ''),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bancoTitularCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Titular de la cuenta',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _guardando ? null : () => _guardar(user.uid),
                      icon: _guardando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _guardando ? 'Guardando…' : 'Guardar cambios',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
