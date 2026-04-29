import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/auth/seleccion_usuario.dart';
import 'package:flygo_nuevo/legal/terms_policy_screen.dart';
import 'package:flygo_nuevo/pantallas/comun/configuracion_perfil.dart';
import 'package:flygo_nuevo/pantallas/comun/soporte.dart';
import 'package:flygo_nuevo/pantallas/taxista/billetera_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/documentos_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/ganancia_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/historial_viajes_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/mis_pagos.dart';
import 'package:flygo_nuevo/servicios/auth_service.dart';
import 'package:flygo_nuevo/servicios/theme_mode_service.dart';
import 'package:flygo_nuevo/widgets/avatar_circle.dart';
import 'package:flygo_nuevo/widgets/configuracion_bancaria.dart';

/// Finanzas, documentos y ajustes de cuenta.
class TaxistaCuentaTab extends StatelessWidget {
  const TaxistaCuentaTab({super.key});

  Future<void> _logout(BuildContext context) async {
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
    try {
      await AuthService().logout();
    } catch (_) {}
    if (!nav.mounted) return;
    try {
      nav.pushNamedAndRemoveUntil('/login_taxista', (_) => false);
    } catch (_) {
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SeleccionUsuario()),
        (_) => false,
      );
    }
  }

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
              child: Text('Inicia sesión.'),
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
                  return (dn != null && dn.isNotEmpty) ? dn : 'Taxista';
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
                        name: nombre.isEmpty ? 'Taxista' : nombre,
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
          _tile(
            context,
            icon: Icons.account_balance_wallet_outlined,
            title: 'Billetera',
            subtitle: 'Saldo 80 %, comisión 20 %',
            page: const BilleteraTaxista(),
          ),
          _tile(
            context,
            icon: Icons.payment,
            title: 'Mis pagos',
            subtitle: 'Historial de comisiones',
            page: const MisPagos(),
          ),
          _tile(
            context,
            icon: Icons.account_balance,
            title: 'Datos bancarios',
            subtitle: 'Banco y cuenta para transferencias',
            page: const ConfiguracionBancaria(),
          ),
          _tile(
            context,
            icon: Icons.history,
            title: 'Historial de viajes',
            subtitle: null,
            page: const HistorialViajesTaxista(),
          ),
          _tile(
            context,
            icon: Icons.monetization_on_outlined,
            title: 'Ganancias',
            subtitle: 'Totales y cálculo 80/20',
            page: const GananciaTaxista(),
          ),
          _tile(
            context,
            icon: Icons.description_outlined,
            title: 'Documentos',
            subtitle: 'Licencia, cédula, seguro',
            page: const DocumentosTaxista(),
          ),
          _tile(
            context,
            icon: Icons.support_agent,
            title: 'Soporte',
            subtitle: null,
            page: const Soporte(),
          ),
          const Divider(height: 24),
          _tile(
            context,
            icon: Icons.person_outline,
            title: 'Configuración de perfil',
            subtitle: 'Foto y nombre',
            page: const ConfiguracionPerfil(),
          ),
          _tile(
            context,
            icon: Icons.gavel_outlined,
            title: 'Términos y política',
            subtitle: 'Privacidad y condiciones',
            page: const TermsPolicyScreen(),
          ),
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
          if (uid != null)
            ListTile(
              leading: Icon(Icons.logout, color: cs.error),
              title: Text(
                'Cerrar sesión',
                style: TextStyle(
                  color: cs.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => _logout(context),
            ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String? subtitle,
    required Widget page,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: cs.primary),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: Icon(Icons.chevron_right, color: cs.outline),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => page),
        );
      },
    );
  }
}
