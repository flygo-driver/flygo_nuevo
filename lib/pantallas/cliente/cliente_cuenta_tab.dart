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

/// Perfil, pagos, soporte y ajustes (misma lógica que el drawer, sin duplicar rutas).
class ClienteCuentaTab extends StatelessWidget {
  const ClienteCuentaTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuenta'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          if (uid == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Inicia sesión para ver tu cuenta.'),
            )
          else
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
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      AvatarCircle(
                        imageUrl: (foto ?? '').trim(),
                        name: nombre.isEmpty ? 'Usuario' : nombre,
                        size: 64,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nombre,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            if (user?.email != null &&
                                user!.email!.trim().isNotEmpty)
                              Text(
                                user.email!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              )
                            else if (user != null &&
                                user.providerData.any(
                                  (p) => p.providerId == 'google.com',
                                ))
                              Text(
                                'Sesión con Google',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          const Divider(height: 1),
          if (uid != null)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? const <String, dynamic>{};
                final texto = _textoPerfilCliente(
                  data,
                  fallbackEmail: user?.email ?? '',
                );
                return Card(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: ListTile(
                    leading: Icon(Icons.badge_outlined, color: cs.primary),
                    title: const Text('Datos del perfil'),
                    subtitle: Text(texto),
                  ),
                );
              },
            ),
          if (uid != null) ClienteCuentaPromoPanel(uidCliente: uid),
          ListTile(
            leading: Icon(Icons.location_on_outlined, color: cs.primary),
            title: const Text('Ubicación'),
            subtitle: const Text('Permisos GPS y ajustes del teléfono'),
            trailing: Icon(Icons.chevron_right, color: cs.outline),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RaiUbicacionAjustesPage(
                    rol: RaiUbicacionRol.cliente,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.person_outline, color: cs.primary),
            title: const Text('Configuración de perfil'),
            subtitle: const Text('Foto y nombre'),
            trailing: Icon(Icons.chevron_right, color: cs.outline),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ConfiguracionPerfil(),
                ),
              );
            },
          ),
          ListTile(
            leading:
                Icon(Icons.account_balance_wallet_outlined, color: cs.primary),
            title: const Text('Pagos'),
            subtitle: const Text('Efectivo y transferencia'),
            trailing: Icon(Icons.chevron_right, color: cs.outline),
            onTap: () => showClienteMetodosPago(context),
          ),
          ListTile(
            leading: Icon(Icons.auto_awesome_rounded, color: cs.primary),
            title: const Text('Asistente RAI'),
            subtitle: const Text('IA · direcciones · cómo funciona'),
            trailing: Icon(Icons.chevron_right, color: cs.outline),
            onTap: () => RaiAsistenteLauncher.abrirAsistente(context),
          ),
          ListTile(
            leading: Icon(Icons.support_agent, color: cs.primary),
            title: const Text('Soporte'),
            subtitle: const Text('Ayuda y contacto'),
            trailing: Icon(Icons.chevron_right, color: cs.outline),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const Soporte()),
              );
            },
          ),
          const CuentaLegalTiles(),
          const Divider(height: 1),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeModeService.mode,
            builder: (context, mode, _) {
              final isLight = mode == ThemeMode.light;
              return SwitchListTile(
                secondary: Icon(
                  isLight ? Icons.light_mode : Icons.dark_mode,
                  color: cs.primary,
                ),
                title: const Text('Modo claro'),
                subtitle: const Text('Personaliza la apariencia'),
                value: isLight,
                onChanged: (v) => ThemeModeService.setMode(
                  v ? ThemeMode.light : ThemeMode.dark,
                ),
              );
            },
          ),
          const CuentaAparienciaTile(),
          if (uid != null) const CuentaCerrarSesionTile(),
        ],
      ),
    );
  }
}
