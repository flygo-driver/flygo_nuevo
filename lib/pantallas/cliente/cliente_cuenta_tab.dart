import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/comun/configuracion_perfil.dart';
import 'package:flygo_nuevo/pantallas/comun/soporte.dart';
import 'package:flygo_nuevo/servicios/theme_mode_service.dart';
import 'package:flygo_nuevo/widgets/avatar_circle.dart';
import 'package:flygo_nuevo/widgets/cliente_pagos_sheet.dart';
import 'package:flygo_nuevo/widgets/cuenta_legal_tiles.dart';
import 'package:flygo_nuevo/widgets/cuenta_promo_resumen_panel.dart';
import 'package:flygo_nuevo/widgets/cuenta_settings_tiles.dart';
import 'package:flygo_nuevo/widgets/rai_asistente_launcher.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_config_panel.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_rol.dart';
import 'package:flygo_nuevo/widgets/shell_tab_nav.dart';

String _textoPerfilCliente(
  Map<String, dynamic> data, {
  required String fallbackEmail,
}) {
  final List<String> lineas = <String>[];
  final String nombre = (data['nombre'] ?? '').toString().trim();
  final String telefono = (data['telefono'] ?? '').toString().trim();

  if (nombre.isNotEmpty) lineas.add('Nombre: $nombre');
  if (telefono.isNotEmpty) lineas.add('Teléfono: $telefono');
  if (fallbackEmail.trim().isNotEmpty) lineas.add('Correo: $fallbackEmail');

  return lineas.isEmpty
      ? 'Aún no has guardado datos de perfil.'
      : lineas.join('\n');
}

void _openPage(BuildContext context, Widget page) {
  Navigator.push<void>(
    context,
    MaterialPageRoute<void>(builder: (_) => page),
  );
}

/// Perfil, pagos, soporte y ajustes (misma lógica que el drawer, sin duplicar rutas).
class ClienteCuentaTab extends StatelessWidget {
  const ClienteCuentaTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = cs.primary;
    final accentSoft = accent.withValues(alpha: isDark ? 0.18 : 0.12);

    return RaiShellTabScaffold(
      title: 'Cuenta',
      backTooltip: 'Inicio',
      onBack: ShellTabController.clienteIrAInicio,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        children: [
          if (uid == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Inicia sesión para ver tu cuenta.'),
            )
          else ...[
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data();
                final nombre = (() {
                  final n = (data?['nombre'] as String?)?.trim();
                  if (n != null && n.isNotEmpty) return n;
                  final dn = user?.displayName?.trim();
                  return (dn != null && dn.isNotEmpty) ? dn : 'Cliente';
                })();
                final foto = (() {
                  final f = (data?['fotoUrl'] as String?)?.trim();
                  if (f != null && f.isNotEmpty) return f;
                  final fu = user?.photoURL?.trim();
                  return (fu != null && fu.isNotEmpty) ? fu : null;
                })();
                final telefono = (data?['telefono'] ?? '').toString().trim();
                final textoPerfil = _textoPerfilCliente(
                  data ?? const <String, dynamic>{},
                  fallbackEmail: user?.email ?? '',
                );
                final sesionGoogle = user != null &&
                    user.providerData.any(
                      (p) => p.providerId == 'google.com',
                    );

                String? subtituloCuenta;
                if (user?.email != null && user!.email!.trim().isNotEmpty) {
                  subtituloCuenta = user.email;
                } else if (sesionGoogle) {
                  subtituloCuenta = 'Sesión con Google';
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ClienteCuentaHeroCard(
                      nombre: nombre,
                      subtitulo: subtituloCuenta,
                      fotoUrl: foto,
                      telefono: telefono,
                      accent: accent,
                      isDark: isDark,
                      onEditarPerfil: () => _openPage(
                        context,
                        const ConfiguracionPerfil(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ClienteCuentaPerfilExpandible(
                      texto: textoPerfil,
                      accent: accent,
                      isDark: isDark,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            ClienteCuentaPromoPanel(uidCliente: uid),
            const SizedBox(height: 4),
            _ClienteCuentaSection(
              title: 'Tu cuenta',
              children: [
                _ClienteCuentaMenuRow(
                  icon: Icons.location_on_rounded,
                  iconBg: const Color(0xFF16A34A).withValues(alpha: 0.14),
                  iconFg: const Color(0xFF16A34A),
                  title: 'Ubicación',
                  subtitle: 'Permisos GPS y ajustes del teléfono',
                  onTap: () => _openPage(
                    context,
                    const RaiUbicacionAjustesPage(rol: RaiUbicacionRol.cliente),
                  ),
                ),
                _ClienteCuentaMenuRow(
                  icon: Icons.person_rounded,
                  iconBg: accentSoft,
                  iconFg: accent,
                  title: 'Configuración de perfil',
                  subtitle: 'Foto y nombre',
                  onTap: () => _openPage(context, const ConfiguracionPerfil()),
                ),
                _ClienteCuentaMenuRow(
                  icon: Icons.account_balance_wallet_rounded,
                  iconBg: const Color(0xFF0D9488).withValues(alpha: 0.14),
                  iconFg: const Color(0xFF0D9488),
                  title: 'Pagos',
                  subtitle: 'Efectivo y transferencia',
                  onTap: () => showClienteMetodosPago(context),
                  showDivider: false,
                ),
              ],
            ),
            _ClienteCuentaSection(
              title: 'RAI y ayuda',
              children: [
                _ClienteCuentaMenuRow(
                  icon: Icons.auto_awesome_rounded,
                  iconBg: const Color(0xFF7C3AED).withValues(alpha: 0.14),
                  iconFg: const Color(0xFF7C3AED),
                  title: 'Asistente RAI',
                  subtitle: 'IA · direcciones · cómo funciona',
                  onTap: () => RaiAsistenteLauncher.abrirAsistente(context),
                ),
                _ClienteCuentaMenuRow(
                  icon: Icons.headset_mic_rounded,
                  iconBg: const Color(0xFFDB2777).withValues(alpha: 0.14),
                  iconFg: const Color(0xFFDB2777),
                  title: 'Soporte',
                  subtitle: 'Ayuda y contacto',
                  onTap: () => _openPage(context, const Soporte()),
                  showDivider: false,
                ),
              ],
            ),
            const CuentaLegalTiles(),
            _ClienteCuentaSection(
              title: 'Apariencia',
              children: [
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: ThemeModeService.mode,
                  builder: (context, mode, _) {
                    final isLight = mode == ThemeMode.light;
                    return _ClienteCuentaSwitchRow(
                      icon: isLight
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      title: 'Modo claro',
                      subtitle: 'Personaliza la apariencia',
                      value: isLight,
                      onChanged: (v) => ThemeModeService.setMode(
                        v ? ThemeMode.light : ThemeMode.dark,
                      ),
                      accent: accent,
                    );
                  },
                ),
              ],
            ),
            const CuentaAparienciaTile(),
            const CuentaCerrarSesionTile(),
          ],
        ],
      ),
    );
  }
}

class _ClienteCuentaHeroCard extends StatelessWidget {
  const _ClienteCuentaHeroCard({
    required this.nombre,
    required this.subtitulo,
    required this.fotoUrl,
    required this.telefono,
    required this.accent,
    required this.isDark,
    required this.onEditarPerfil,
  });

  final String nombre;
  final String? subtitulo;
  final String? fotoUrl;
  final String telefono;
  final Color accent;
  final bool isDark;
  final VoidCallback onEditarPerfil;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF132238),
                  const Color(0xFF0F766E).withValues(alpha: 0.55),
                ]
              : [
                  Colors.white,
                  accent.withValues(alpha: 0.08),
                ],
        ),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.35 : 0.22),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: accent.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarCircle(
                imageUrl: (fotoUrl ?? '').trim(),
                name: nombre.isEmpty ? 'Usuario' : nombre,
                size: 68,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                    ),
                    if (subtitulo != null && subtitulo!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitulo!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: onEditarPerfil,
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Editar perfil',
              ),
            ],
          ),
          if (telefono.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ClienteCuentaChip(
              label: telefono,
              icon: Icons.phone_outlined,
              accent: accent,
            ),
          ],
        ],
      ),
    );
  }
}

class _ClienteCuentaChip extends StatelessWidget {
  const _ClienteCuentaChip({
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String label;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClienteCuentaPerfilExpandible extends StatelessWidget {
  const _ClienteCuentaPerfilExpandible({
    required this.texto,
    required this.accent,
    required this.isDark,
  });

  final String texto;
  final Color accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121A2B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.badge_outlined, color: accent, size: 21),
          ),
          title: const Text(
            'Datos del perfil',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            texto.split('\n').first,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                texto,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClienteCuentaSection extends StatelessWidget {
  const _ClienteCuentaSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF121A2B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _ClienteCuentaMenuRow extends StatelessWidget {
  const _ClienteCuentaMenuRow({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.showDivider = true,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconFg, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: cs.outline),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 68,
            endIndent: 14,
            color: cs.outlineVariant.withValues(alpha: 0.35),
          ),
      ],
    );
  }
}

class _ClienteCuentaSwitchRow extends StatelessWidget {
  const _ClienteCuentaSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: accent.withValues(alpha: 0.45),
            activeThumbColor: accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
