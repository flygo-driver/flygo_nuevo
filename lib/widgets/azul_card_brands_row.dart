import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/legal/terms_data.dart';

/// Marcas de tarjeta + enlaces legales (certificación AZUL).
class AzulCardBrandsRow extends StatelessWidget {
  const AzulCardBrandsRow({
    super.key,
    this.compact = false,
    this.showSecurityLink = true,
    this.showPaymentsLink = true,
    this.darkSurface = false,
  });

  final bool compact;
  final bool showSecurityLink;
  final bool showPaymentsLink;
  final bool darkSurface;

  static const _brands = <_BrandSpec>[
    _BrandSpec('assets/pagos/visa.svg', 'Visa', 44),
    _BrandSpec('assets/pagos/mastercard.svg', 'Mastercard', 44),
    _BrandSpec('assets/pagos/amex.svg', 'American Express', 44),
    _BrandSpec('assets/pagos/discover.svg', 'Discover', 44),
  ];

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = darkSurface || Theme.of(context).brightness == Brightness.dark;
    final Color muted = dark ? Colors.white54 : RaiDsColors.textMuted;
    final double badgeH = compact ? 26.0 : 30.0;
    final double iconW = compact ? 34.0 : 40.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.verified_user_outlined, size: 14, color: muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Pasarela segura AZUL · 3-D Secure',
                style: TextStyle(
                  color: muted,
                  fontSize: compact ? 10.5 : 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.15,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final brand in _brands)
              _BrandBadge(
                asset: brand.asset,
                label: brand.label,
                height: badgeH,
                iconWidth: iconW,
                dark: dark,
              ),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: const [
              _SecureChip(icon: Icons.lock_outline, label: 'Cifrado SSL'),
              _SecureChip(icon: Icons.shield_outlined, label: 'Visa Secure'),
              _SecureChip(icon: Icons.shield_outlined, label: 'ID Check'),
            ],
          ),
        ],
        if (showPaymentsLink || showSecurityLink) ...[
          const SizedBox(height: 10),
          if (showPaymentsLink)
            _LegalLink(
              label: 'Información de pagos con tarjeta',
              onTap: () => _openUrl(kCardPaymentsPublicUrl),
              color: RaiDsColors.neonSoft.withValues(alpha: dark ? 0.95 : 0.85),
            ),
          if (showSecurityLink)
            _LegalLink(
              label: 'Política de seguridad de datos',
              onTap: () => _openUrl(kCardSecurityPolicyPublicUrl),
              color: RaiDsColors.neonSoft.withValues(alpha: dark ? 0.95 : 0.85),
            ),
        ],
      ],
    );
  }
}

class _BrandSpec {
  const _BrandSpec(this.asset, this.label, this.width);

  final String asset;
  final String label;
  final double width;
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge({
    required this.asset,
    required this.label,
    required this.height,
    required this.iconWidth,
    required this.dark,
  });

  final String asset;
  final String label;
  final double height;
  final double iconWidth;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFFFAFAFA) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.12)
              : const Color(0xFFE5E7EB),
        ),
        boxShadow: dark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: SvgPicture.asset(
        asset,
        width: iconWidth,
        height: height * 0.55,
        fit: BoxFit.contain,
        semanticsLabel: label,
      ),
    );
  }
}

class _SecureChip extends StatelessWidget {
  const _SecureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white60),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({
    required this.label,
    required this.onTap,
    required this.color,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.open_in_new_rounded, size: 12, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
