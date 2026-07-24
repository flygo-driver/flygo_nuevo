import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Logo de empresa corporativa en vivo (`empresas_corporativas.logoUrl`).
class CorporativoEmpresaLogoBadge extends StatelessWidget {
  const CorporativoEmpresaLogoBadge({
    super.key,
    required this.empresaId,
    this.logoUrlSnapshot,
    this.size = 40,
    this.borderRadius = 8,
    this.fallbackColor,
    this.fallbackIcon = Icons.apartment_rounded,
  });

  final String empresaId;
  final String? logoUrlSnapshot;
  final double size;
  final double borderRadius;
  final Color? fallbackColor;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final id = empresaId.trim();
    final snapshotUrl = logoUrlSnapshot?.trim() ?? '';
    if (id.isEmpty) {
      return snapshotUrl.isNotEmpty
          ? _logoImage(context, snapshotUrl)
          : _fallback(context);
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('empresas_corporativas')
          .doc(id)
          .snapshots(),
      builder: (context, snap) {
        var url = snapshotUrl;
        if (snap.hasData && snap.data!.exists) {
          final d = snap.data!.data() ?? <String, dynamic>{};
          final live =
              (d['logoUrl'] ?? d['logo'] ?? '').toString().trim();
          if (live.isNotEmpty) url = live;
        }
        if (url.isEmpty) return _fallback(context);
        return _logoImage(context, url);
      },
    );
  }

  Widget _logoImage(BuildContext context, String url) {
    return _logoBox(
      child: Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Center(
            child: SizedBox(
              width: size * 0.35,
              height: size * 0.35,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: fallbackColor ?? Theme.of(context).colorScheme.primary,
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => _fallbackIcon(),
      ),
    );
  }

  Widget _logoBox({required Widget child}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        color: Colors.white.withValues(alpha: 0.06),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _fallback(BuildContext context) {
    return _logoBox(child: _fallbackIcon(context));
  }

  Widget _fallbackIcon([BuildContext? context]) {
    final c = fallbackColor ??
        (context != null
            ? Theme.of(context).colorScheme.tertiary
            : Colors.amber);
    return Center(
      child: Icon(fallbackIcon, color: c, size: size * 0.5),
    );
  }
}
