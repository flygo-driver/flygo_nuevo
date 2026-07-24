import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flygo_nuevo/pantallas/corporativo/corporativo_ui.dart';
import 'package:flygo_nuevo/servicios/corporativo_ruta_service.dart';

/// Tarjeta para subir o cambiar el logo de la empresa (portal corporativo).
class CorporativoEmpresaLogoCard extends StatefulWidget {
  const CorporativoEmpresaLogoCard({
    super.key,
    required this.empresaId,
    required this.nombreEmpresa,
    this.logoUrl = '',
    this.compacto = false,
    this.onLogoChanged,
  });

  final String empresaId;
  final String nombreEmpresa;
  final String logoUrl;
  final bool compacto;
  final VoidCallback? onLogoChanged;

  @override
  State<CorporativoEmpresaLogoCard> createState() =>
      _CorporativoEmpresaLogoCardState();
}

class _CorporativoEmpresaLogoCardState extends State<CorporativoEmpresaLogoCard> {
  final _picker = ImagePicker();
  bool _subiendo = false;
  String? _logoLocal;

  String get _logoActual =>
      (_logoLocal ?? widget.logoUrl).trim();

  Future<void> _elegirYSubir() async {
    if (_subiendo) return;
    if (FirebaseAuth.instance.currentUser == null) {
      _snack('Tu sesión expiró. Volvé a entrar.');
      return;
    }

    ImageSource? source;
    if (kIsWeb) {
      source = ImageSource.gallery;
    } else {
      source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: const Color(0xFF151B2E),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          final p = ctx.corporativoPalette;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.cardBorder,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Logo de la empresa',
                  style: TextStyle(
                    color: p.onCard,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                ListTile(
                  leading: Icon(Icons.photo_library_rounded, color: p.primary),
                  title: Text(
                    'Elegir de galería',
                    style: TextStyle(color: p.onCard),
                  ),
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
                ListTile(
                  leading: Icon(Icons.photo_camera_rounded, color: p.primary),
                  title: Text(
                    'Tomar foto',
                    style: TextStyle(color: p.onCard),
                  ),
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
    }
    if (source == null || !mounted) return;

    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 900,
      maxHeight: 900,
    );
    if (picked == null || !mounted) return;

    setState(() => _subiendo = true);
    try {
      final bytes = await picked.readAsBytes();
      final mime = (picked.mimeType ?? '').trim();
      final url = await CorporativoRutaService.subirLogoEmpresa(
        empresaId: widget.empresaId,
        bytes: bytes,
        contentType: mime.isNotEmpty ? mime : 'image/jpeg',
      );
      if (!mounted) return;
      setState(() => _logoLocal = url);
      widget.onLogoChanged?.call();
      _snack('Logo actualizado.');
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().toLowerCase();
      _snack(
        raw.contains('permission')
            ? 'No tienes permiso para subir el logo. Reintentá o contactá a RAI.'
            : e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Future<void> _quitarLogo() async {
    if (_subiendo || _logoActual.isEmpty) return;
    final p = context.corporativoPalette;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.card,
        title: Text('Quitar logo', style: TextStyle(color: p.onCard)),
        content: Text(
          '¿Querés quitar el logo de ${widget.nombreEmpresa}?',
          style: TextStyle(color: p.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: TextStyle(color: p.muted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: p.danger),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _subiendo = true);
    try {
      await CorporativoRutaService.quitarLogoEmpresa(widget.empresaId);
      if (!mounted) return;
      setState(() => _logoLocal = '');
      widget.onLogoChanged?.call();
      _snack('Logo quitado.');
    } catch (e) {
      if (!mounted) return;
      _snack('No se pudo quitar el logo: $e');
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    final logo = _logoActual;
    final size = widget.compacto ? 64.0 : 88.0;

    Widget avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.compacto ? 16 : 20),
        gradient: logo.isEmpty ? p.ctaGrad : null,
        color: logo.isEmpty ? null : p.primarySoft,
        border: Border.all(
          color: p.primary.withValues(alpha: logo.isEmpty ? 0.35 : 0.5),
          width: 1.5,
        ),
        boxShadow: logo.isEmpty
            ? [
                BoxShadow(
                  color: p.ctaBg.withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
        image: logo.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(logo),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: logo.isEmpty
          ? Icon(
              Icons.apartment_rounded,
              color: Colors.white,
              size: widget.compacto ? 30 : 40,
            )
          : null,
    );

    if (_subiendo) {
      avatar = Stack(
        alignment: Alignment.center,
        children: [
          Opacity(opacity: 0.55, child: avatar),
          SizedBox(
            width: size * 0.42,
            height: size * 0.42,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: p.primary,
            ),
          ),
        ],
      );
    }

    if (widget.compacto) {
      return Tooltip(
        message: logo.isEmpty ? 'Subir logo' : 'Cambiar logo',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _subiendo ? null : _elegirYSubir,
            borderRadius: BorderRadius.circular(16),
            child: avatar,
          ),
        ),
      );
    }

    return corporativoCard(
      context,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatar,
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Logo de la empresa',
                  style: TextStyle(
                    color: p.onCard,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Subí el logo oficial de tu empresa. Se muestra en el panel '
                  'corporativo y refuerza la imagen profesional ante RAI y choferes.',
                  style: TextStyle(
                    color: p.muted,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _subiendo ? null : _elegirYSubir,
                      icon: Icon(
                        logo.isEmpty
                            ? Icons.cloud_upload_outlined
                            : Icons.refresh_rounded,
                        size: 18,
                      ),
                      label: Text(
                        logo.isEmpty ? 'Subir logo' : 'Cambiar logo',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.ctaBg,
                        foregroundColor: p.ctaFg,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                    if (logo.isNotEmpty)
                      OutlinedButton(
                        onPressed: _subiendo ? null : _quitarLogo,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: p.muted,
                          side: BorderSide(color: p.cardBorder),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        child: const Text('Quitar'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'PNG o JPG · cuadrado recomendado · máx. 3 MB',
                  style: TextStyle(color: p.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
