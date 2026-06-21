// lib/widgets/admin_drawer.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flygo_nuevo/servicios/theme_mode_service.dart';

// 🔰 PANTALLAS DE ADMIN
import 'package:flygo_nuevo/pantallas/admin/admin_alertas.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_auditoria.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_bola_pueblo_ops.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_config_empresa.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_giras_tours_cupos.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_regularizar_giras_taxista.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_rai_monitor.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_torre_control.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_turismo_destinos.dart';
import 'package:flygo_nuevo/pantallas/admin/viajes_turismo_admin.dart';
import 'package:flygo_nuevo/pantallas/admin/taxistas_turismo_admin.dart';
import 'package:flygo_nuevo/pantallas/admin/aprobar_choferes_turismo.dart';
import 'package:flygo_nuevo/pantallas/admin/verificar_pagos.dart';

// ✅ NUEVO - Resumen de Comisiones
import 'package:flygo_nuevo/pantallas/admin/resumen_comisiones_admin.dart';

// ✅ PROMOS MxK
import 'package:flygo_nuevo/pantallas/admin/admin_promos_mxk.dart';

// ✅ Documentos / Usuarios / Reportes / Tarifas
import 'package:flygo_nuevo/pantallas/admin/admin_centro_operaciones.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_home.dart';
import 'package:flygo_nuevo/pantallas/admin/panel_finanzas.dart';
import 'package:flygo_nuevo/pantallas/admin/revision_documentos_admin.dart';
import 'package:flygo_nuevo/pantallas/admin/gestionar_usuarios_admin.dart';
import 'package:flygo_nuevo/pantallas/admin/reportes_admin.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_tarifas.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_tarifas_tramos.dart';
import 'package:flygo_nuevo/pantallas/admin/configuracion_viaje_comision_admin.dart';
import 'package:flygo_nuevo/pantallas/admin/incidencias_admin.dart';
import 'package:flygo_nuevo/widgets/rai_header_logo.dart';

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
      color:
          isLight ? cs.onSurfaceVariant.withValues(alpha: 0.9) : Colors.white54,
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
              leading: const RaiHeaderLogo(height: 32),
              title: Text('Panel Administrativo', style: titleStyle),
              subtitle: Text(
                'RAI Driver — Administración',
                style: bodyStyle.copyWith(fontSize: 13),
              ),
            ),
            Divider(color: dividerColor),
            ListTile(
              leading: Icon(Icons.dashboard_outlined, color: iconNeutral),
              title: Text('Centro de operaciones',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text('Colas pendientes del día', style: subtleStyle),
              onTap: () => _push(context, const AdminCentroOperaciones()),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
              child: Text(
                'TIEMPO REAL',
                style: TextStyle(
                  color: isLight
                      ? Colors.blue.shade800
                      : Colors.lightBlueAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.radar,
                  color: isLight ? Colors.blue.shade700 : Colors.lightBlueAccent),
              title: Text('Torre de control',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text('Viajes en vivo y buscando chofer', style: subtleStyle),
              onTap: () => _push(context, const AdminTorreControl()),
            ),
            ListTile(
              leading: Icon(Icons.notifications_active,
                  color: isLight ? Colors.red.shade700 : Colors.redAccent),
              title: Text('Alertas operativas',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text('Resumen horario y umbrales', style: subtleStyle),
              onTap: () => _push(context, const AdminAlertasPage()),
            ),
            ListTile(
              leading: Icon(Icons.hub_outlined, color: iconNeutral),
              title: Text('Bola Pueblo',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text('Publicaciones, rutas y transferencias', style: subtleStyle),
              onTap: () => _push(context, const AdminBolaPuebloOps()),
            ),
            ListTile(
              leading: Icon(Icons.smart_toy_outlined,
                  color: isLight ? Colors.deepPurple : Colors.purpleAccent),
              title: Text('Asistente RAI',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text('Uso diario y cuotas', style: subtleStyle),
              onTap: () => _push(context, const AdminRaiMonitor()),
            ),
            Divider(color: dividerColor),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
              child: Text(
                'FINANZAS',
                style: TextStyle(
                  color: isLight
                      ? Colors.deepOrange.shade800
                      : Colors.orangeAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.verified,
                  color: isLight ? Colors.deepOrange : Colors.orangeAccent),
              title: Text('Verificar pagos',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text(
                'Recargas prepago · comisiones · transferencias',
                style: subtleStyle,
              ),
              onTap: () => _push(context, const VerificarPagos()),
            ),
            ListTile(
              leading: Icon(Icons.account_balance_wallet_outlined,
                  color: isLight ? Colors.teal.shade700 : Colors.tealAccent),
              title: Text('Finanzas en vivo',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text('Panel financiero agregado', style: subtleStyle),
              onTap: () => _push(context, const PanelFinanzasAdmin()),
            ),
            ListTile(
              leading: Icon(Icons.home, color: iconNeutral),
              title: Text('Liquidaciones',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text('Comisiones semanales', style: subtleStyle),
              onTap: () => _push(context, const AdminHome()),
            ),
            ListTile(
              leading: Icon(Icons.analytics,
                  color:
                      isLight ? const Color(0xFF0F9D58) : Colors.greenAccent),
              title: Text('Resumen de comisiones',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text('Estadísticas diarias', style: subtleStyle),
              onTap: () => _push(context, const ResumenComisionesAdmin()),
            ),
            ListTile(
              leading: Icon(Icons.percent, color: iconNeutral),
              title: Text('Comisión viaje (efectivo)',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text('% global Firestore', style: subtleStyle),
              onTap: () => _push(context, const ConfiguracionViajeComisionAdmin()),
            ),
            ListTile(
              leading: Icon(Icons.attach_money, color: iconNeutral),
              title: Text('Tarifas',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text(
                'Pestaña Tramos distancia + tarifas locales',
                style: subtleStyle,
              ),
              onTap: () => _push(context, const AdminTarifas()),
            ),
            ListTile(
              leading: Icon(Icons.alt_route,
                  color: isLight ? Colors.green.shade700 : Colors.greenAccent),
              title: Text('Tramos larga distancia',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w700)),
              subtitle: Text(
                'Mismo panel Tarifas — tramos arriba en verde',
                style: subtleStyle,
              ),
              onTap: () => _push(context, const AdminTarifasTramos()),
            ),
            ListTile(
              leading: Icon(Icons.local_offer, color: iconNeutral),
              title: Text('Promociones',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              onTap: () => _push(context, const AdminPromosMxK()),
            ),
            ListTile(
              leading: Icon(Icons.bar_chart, color: iconNeutral),
              title: Text('Reportes y Estadísticas',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text(
                'Quejas viaje, calificaciones, CSV',
                style: subtleStyle,
              ),
              onTap: () => _push(context, const ReportesAdmin()),
            ),
            ListTile(
              leading: Icon(Icons.support_agent, color: iconNeutral),
              title: Text('Gestión de incidencias',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text(
                'Tickets soporte (no es calificación de viaje)',
                style: subtleStyle,
              ),
              onTap: () => _push(context, const IncidenciasAdminPage()),
            ),
            ListTile(
              leading: Icon(Icons.history,
                  color:
                      isLight ? Colors.blue.shade700 : Colors.lightBlueAccent),
              title: Text('Auditoría e historial',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text('Cambios config y log sistema', style: subtleStyle),
              onTap: () => _push(context, const AdminAuditoriaPage()),
            ),
            ListTile(
              leading: Icon(Icons.account_balance_outlined, color: iconNeutral),
              title: Text('Configuración RAI',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text('Cuenta bancaria y prepago', style: subtleStyle),
              onTap: () => _push(context, const AdminConfigEmpresa()),
            ),
            Divider(color: dividerColor),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeModeService.mode,
              builder: (context, mode, _) {
                final isLightMode = mode == ThemeMode.light;
                return SwitchListTile(
                  secondary: Icon(
                    isLightMode ? Icons.light_mode : Icons.dark_mode,
                    color: iconNeutral,
                  ),
                  title: Text('Modo claro',
                      style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
                  subtitle: Text('Personaliza apariencia', style: subtleStyle),
                  value: isLightMode,
                  onChanged: (v) => ThemeModeService.setMode(
                    v ? ThemeMode.light : ThemeMode.dark,
                  ),
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return isLight
                          ? const Color(0xFF0F9D58)
                          : Colors.greenAccent;
                    }
                    return null;
                  }),
                );
              },
            ),
            Divider(color: dividerColor),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
              child: Text(
                'CONDUCTORES',
                style: TextStyle(
                  color:
                      isLight ? Colors.green.shade800 : Colors.greenAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.folder_shared_outlined,
                  color: isLight ? Colors.green.shade700 : Colors.greenAccent),
              title: Text('Expedientes choferes',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle:
                  Text('Normal · Motor · Bola Ahorro', style: subtleStyle),
              onTap: () => _push(context, const RevisionDocumentosAdmin()),
            ),
            ListTile(
              leading: Icon(Icons.manage_accounts, color: iconNeutral),
              title: Text('Gestionar Usuarios',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text(
                'Bloqueos prepago · roles · movimientos',
                style: subtleStyle,
              ),
              onTap: () => _push(context, const GestionarUsuariosAdmin()),
            ),
            Divider(color: dividerColor),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
              child: Text(
                'SALIDAS POR CUPOS · TURISMO',
                style: TextStyle(
                  color: isLight
                      ? Colors.deepPurple.shade700
                      : Colors.purpleAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.pending_actions,
                  color: isLight ? Colors.deepOrange : Colors.orangeAccent),
              title: Text('Aprobar solicitudes turismo',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text('Registro y documentos turísticos', style: subtleStyle),
              onTap: () => _push(context, const AprobarChoferesTurismo()),
            ),
            ListTile(
              leading: Icon(Icons.travel_explore, color: iconNeutral),
              title: Text('Viajes Turismo',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              onTap: () => _push(context, const ViajesTurismoAdmin()),
            ),
            ListTile(
              leading: Icon(Icons.route,
                  color: isLight
                      ? const Color(0xFF2E7D32)
                      : Colors.lightGreenAccent),
              title: Text('Salidas por cupos (giras, excursiones, grupos)',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle:
                  Text('viajes_pool — estados y reservas', style: subtleStyle),
              onTap: () => _push(context, const AdminGirasToursCupos()),
            ),
            ListTile(
              leading: Icon(Icons.lock_open,
                  color: isLight
                      ? const Color(0xFF2E7D32)
                      : Colors.lightGreenAccent),
              title: Text('Desbloquear salidas por cupos',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text(
                'Cola automática · bloqueados por RAI',
                style: subtleStyle,
              ),
              onTap: () => _push(context, const AdminRegularizarGirasTaxista()),
            ),
            ListTile(
              leading: Icon(Icons.tour, color: iconNeutral),
              title: Text('Choferes Turismo',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              onTap: () => _push(context, const TaxistasTurismoAdmin()),
            ),
            ListTile(
              leading: Icon(Icons.place_outlined, color: iconNeutral),
              title: Text('Destinos turismo',
                  style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text('Catálogo extendido Firestore', style: subtleStyle),
              onTap: () => _push(context, const AdminTurismoDestinos()),
            ),
            Divider(color: dividerColor),
            ListTile(
              leading: Icon(Icons.logout,
                  color: isLight ? Colors.red.shade700 : Colors.redAccent),
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
