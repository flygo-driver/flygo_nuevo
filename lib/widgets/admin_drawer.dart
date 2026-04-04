// lib/widgets/admin_drawer.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flygo_nuevo/servicios/theme_mode_service.dart';

// 🔰 PANTALLAS DE ADMIN
import 'package:flygo_nuevo/pantallas/admin/admin_giras_tours_cupos.dart';
import 'package:flygo_nuevo/pantallas/admin/viajes_turismo_admin.dart';
import 'package:flygo_nuevo/pantallas/admin/taxistas_turismo_admin.dart';
import 'package:flygo_nuevo/pantallas/admin/aprobar_choferes_turismo.dart';
import 'package:flygo_nuevo/pantallas/admin/verificar_pagos.dart';

// ✅ NUEVO - Resumen de Comisiones
import 'package:flygo_nuevo/pantallas/admin/resumen_comisiones_admin.dart';

// ✅ PROMOS MxK
import 'package:flygo_nuevo/pantallas/admin/admin_promos_mxk.dart';

// ✅ Documentos / Usuarios / Reportes / Tarifas
import 'package:flygo_nuevo/pantallas/admin/revision_documentos_admin.dart';
import 'package:flygo_nuevo/pantallas/admin/gestionar_usuarios_admin.dart';
import 'package:flygo_nuevo/pantallas/admin/reportes_admin.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_tarifas.dart';

class AdminDrawer extends StatelessWidget {
  const AdminDrawer({super.key});

  Future<void> _signOut(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await FirebaseAuth.instance.signOut();
      navigator.pushNamedAndRemoveUntil('/', (_) => false);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo cerrar sesión: $e')),
      );
    }
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).pop(); // cierra drawer
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    final drawerBg = isLight ? cs.surface : const Color(0xFF0E0E0E);
    final titleStyle = TextStyle(
      color: isLight ? cs.onSurface : Colors.white,
      fontWeight: FontWeight.w600,
    );
    final bodyStyle = TextStyle(
      color: isLight ? cs.onSurfaceVariant : Colors.white70,
    );
    final subtleStyle = TextStyle(
      color: isLight ? cs.onSurfaceVariant.withValues(alpha: 0.9) : Colors.white54,
      fontSize: 12,
    );
    final iconNeutral = isLight ? cs.onSurface : Colors.white;
    final dividerColor =
        isLight ? cs.outlineVariant.withValues(alpha: 0.45) : Colors.white10;

    return Drawer(
      backgroundColor: drawerBg,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            ListTile(
              leading: Icon(Icons.admin_panel_settings, color: iconNeutral),
              title: Text('Panel Administrativo', style: titleStyle),
              subtitle: Text(
                'FlyGo - Sistema de Gestión',
                style: bodyStyle.copyWith(fontSize: 13),
              ),
            ),
            Divider(color: dividerColor),

            ListTile(
              leading: Icon(Icons.home, color: iconNeutral),
              title: Text('Inicio Admin', style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),

            ListTile(
              leading: Icon(Icons.analytics, color: isLight ? const Color(0xFF0F9D58) : Colors.greenAccent),
              title: Text('Resumen de Comisiones', style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text('Estadísticas diarias', style: subtleStyle),
              onTap: () => _push(context, const ResumenComisionesAdmin()),
            ),

            ListTile(
              leading: Icon(Icons.verified, color: isLight ? Colors.deepOrange : Colors.orangeAccent),
              title: Text('Verificar Pagos', style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text('Pendientes de revisión', style: subtleStyle),
              onTap: () => _push(context, const VerificarPagos()),
            ),

            ListTile(
              leading: Icon(Icons.attach_money, color: iconNeutral),
              title: Text('Tarifas', style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              onTap: () => _push(context, const AdminTarifas()),
            ),

            ListTile(
              leading: Icon(Icons.local_offer, color: iconNeutral),
              title: Text('Promociones', style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              onTap: () => _push(context, const AdminPromosMxK()),
            ),

            ListTile(
              leading: Icon(Icons.verified_user, color: iconNeutral),
              title: Text('Revisar Documentos', style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              onTap: () => _push(context, const RevisionDocumentosAdmin()),
            ),

            ListTile(
              leading: Icon(Icons.manage_accounts, color: iconNeutral),
              title: Text('Gestionar Usuarios', style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              onTap: () => _push(context, const GestionarUsuariosAdmin()),
            ),

            ListTile(
              leading: Icon(Icons.bar_chart, color: iconNeutral),
              title: Text('Reportes y Estadísticas', style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              onTap: () => _push(context, const ReportesAdmin()),
            ),

            ListTile(
              leading: Icon(Icons.history, color: isLight ? Colors.blue.shade700 : Colors.lightBlueAccent),
              title: Text('Histórico Promo MxK', style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text('Auditorías guardadas', style: subtleStyle),
              onTap: () => _push(context, const ReportesAdmin()),
            ),

            ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeModeService.mode,
              builder: (context, mode, _) {
                final isLightMode = mode == ThemeMode.light;
                return SwitchListTile(
                  secondary: Icon(
                    isLightMode ? Icons.light_mode : Icons.dark_mode,
                    color: iconNeutral,
                  ),
                  title: Text('Modo claro', style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
                  subtitle: Text('Personaliza apariencia', style: subtleStyle),
                  value: isLightMode,
                  onChanged: (v) => ThemeModeService.setMode(
                    v ? ThemeMode.light : ThemeMode.dark,
                  ),
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return isLight ? const Color(0xFF0F9D58) : Colors.greenAccent;
                    }
                    return null;
                  }),
                );
              },
            ),

            Divider(color: dividerColor),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
              child: Text(
                'TURISMO',
                style: TextStyle(
                  color: isLight ? Colors.deepPurple.shade700 : Colors.purpleAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            ListTile(
              leading: Icon(Icons.pending_actions, color: isLight ? Colors.deepOrange : Colors.orangeAccent),
              title: Text('Aprobar Solicitudes', style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text('Pendientes de revisión', style: subtleStyle),
              onTap: () => _push(context, const AprobarChoferesTurismo()),
            ),

            ListTile(
              leading: Icon(Icons.travel_explore, color: iconNeutral),
              title: Text('Viajes Turismo', style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              onTap: () => _push(context, const ViajesTurismoAdmin()),
            ),

            ListTile(
              leading: Icon(Icons.route, color: isLight ? const Color(0xFF2E7D32) : Colors.lightGreenAccent),
              title: Text('Giras / tours por cupos', style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text('viajes_pool — estados y reservas', style: subtleStyle),
              onTap: () => _push(context, const AdminGirasToursCupos()),
            ),

            ListTile(
              leading: Icon(Icons.tour, color: iconNeutral),
              title: Text('Choferes Turismo', style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              onTap: () => _push(context, const TaxistasTurismoAdmin()),
            ),

            Divider(color: dividerColor),

            ListTile(
              leading: Icon(Icons.logout, color: isLight ? Colors.red.shade700 : Colors.redAccent),
              title: Text(
                'Cerrar Sesión',
                style: TextStyle(
                  color: isLight ? Colors.red.shade700 : Colors.redAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () => _signOut(context),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
