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
import 'package:flygo_nuevo/pantallas/admin/admin_turismo_control.dart';
import 'package:flygo_nuevo/pantallas/admin/viajes_turismo_admin.dart';
import 'package:flygo_nuevo/pantallas/admin/taxistas_turismo_admin.dart';
import 'package:flygo_nuevo/pantallas/admin/aprobar_choferes_turismo.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_corporativo_tarifas_config.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_corporativo_cuentas.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_corporativo_empresas.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_corporativo_plantillas.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_choferes_corporativo.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_corporativo_mapa.dart';
import 'package:flygo_nuevo/pantallas/admin/verificar_pagos.dart';

// ✅ NUEVO - Resumen de Comisiones
import 'package:flygo_nuevo/pantallas/admin/resumen_comisiones_admin.dart';

// ✅ PROMOS MxK
import 'package:flygo_nuevo/pantallas/admin/admin_promos_mxk.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_negocios_aliados.dart';

// ✅ Documentos / Usuarios / Reportes / Tarifas
import 'package:flygo_nuevo/pantallas/admin/admin_centro_operaciones.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_mensajes_operaciones.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_home.dart';
import 'package:flygo_nuevo/pantallas/admin/panel_finanzas.dart';
import 'package:flygo_nuevo/pantallas/admin/revision_documentos_admin.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_verificacion_identidad_cliente.dart';
import 'package:flygo_nuevo/pantallas/admin/gestionar_usuarios_admin.dart';
import 'package:flygo_nuevo/pantallas/admin/reportes_admin.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_tarifas.dart';
import 'package:flygo_nuevo/pantallas/admin/configuracion_viaje_comision_admin.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_comision_incentivos_taxista.dart';
import 'package:flygo_nuevo/pantallas/admin/incidencias_admin.dart';
import 'package:flygo_nuevo/widgets/rai_header_logo.dart';

class AdminDrawer extends StatelessWidget {
  const AdminDrawer({
    super.key,
    this.asSheetBody = false,
    this.scrollController,
  });

  final bool asSheetBody;
  final ScrollController? scrollController;

  /// Celular: hoja de abajo → arriba (arrastre libre). Pantalla ancha: drawer.
  static Future<void> openMenu(BuildContext context) async {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 720) {
      Scaffold.of(context).openDrawer();
      return;
    }
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final bg = isLight ? theme.colorScheme.surface : const Color(0xFF0E0E0E);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetCtx) {
        // Sin snap: arrastre continuo abajo → arriba.
        // El asa va DENTRO del ListView (mismo scrollController) para que
        // el gesto no se pelee con un Column fijo encima.
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.22,
          maxChildSize: 0.96,
          shouldCloseOnMinExtent: true,
          builder: (ctx, scrollCtrl) {
            return Material(
              color: bg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              clipBehavior: Clip.antiAlias,
              child: AdminDrawer(
                asSheetBody: true,
                scrollController: scrollCtrl,
              ),
            );
          },
        );
      },
    );
  }

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
    Navigator.of(context).pop(); // cierra drawer / hoja
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

    final list = ListView(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.zero,
      children: [
        if (asSheetBody) ...[
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: isLight ? Colors.black26 : Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        ListTile(
          leading: const RaiHeaderLogo(height: 32),
          title: Text('Panel Administrativo', style: titleStyle),
          subtitle: Text(
            asSheetBody
                ? 'RAI Driver — Tocá ? o «Ver guía» en cada pantalla'
                : 'RAI Driver — cada pantalla tiene guía de uso',
            style: bodyStyle.copyWith(fontSize: 13),
          ),
        ),
        Divider(color: dividerColor),
        ListTile(
          leading: Icon(Icons.dashboard_outlined, color: iconNeutral),
          title: Text('Centro de operaciones',
              style: titleStyle.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(
            'Cola del día · tocá cada tarjeta (hay guía arriba)',
            style: subtleStyle,
          ),
          onTap: () => _push(context, const AdminCentroOperaciones()),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
          child: Text(
            'TIEMPO REAL',
            style: TextStyle(
              color: isLight ? Colors.blue.shade800 : Colors.lightBlueAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ListTile(
          leading: Icon(Icons.forum_outlined,
              color: isLight ? Colors.orange.shade800 : Colors.orangeAccent),
          title: Text('Mensajes de clientes',
              style: titleStyle.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(
            'Cliente sin conductor · espera en viaje',
            style: subtleStyle,
          ),
          onTap: () => _push(context, const AdminMensajesOperacionesPage()),
        ),
        ListTile(
          leading: Icon(Icons.radar,
              color: isLight ? Colors.blue.shade700 : Colors.lightBlueAccent),
          title: Text('Torre de control',
              style: titleStyle.copyWith(fontWeight: FontWeight.w600)),
          subtitle:
              Text('Viajes en vivo y buscando chofer', style: subtleStyle),
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
          subtitle: Text('Publicaciones, rutas y transferencias',
              style: subtleStyle),
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
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
          child: Text(
            'FINANZAS',
            style: TextStyle(
              color:
                  isLight ? Colors.deepOrange.shade800 : Colors.orangeAccent,
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
          leading: Icon(Icons.business_center_outlined,
              color:
                  isLight ? const Color(0xFF0D9488) : const Color(0xFF5EEAD4)),
          title: Text('Empresas corporativas',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text(
            'Alta, contrato, rutas y chofer',
            style: subtleStyle,
          ),
          onTap: () => _push(context, const AdminCorporativoEmpresasPage()),
        ),
        ListTile(
          leading: Icon(Icons.assignment_ind_outlined,
              color:
                  isLight ? const Color(0xFF0D9488) : const Color(0xFF5EEAD4)),
          title: Text('Asignar chofer corporativo',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text(
            'Todas las empresas · pasajeros en orden',
            style: subtleStyle,
          ),
          onTap: () => _push(context, const AdminCorporativoPlantillasPage()),
        ),
        ListTile(
          leading: Icon(Icons.local_taxi_outlined, color: iconNeutral),
          title: Text('Choferes corporativos', style: titleStyle),
          subtitle: Text(
            'Pool · aprobar · pausar / reactivar',
            style: subtleStyle,
          ),
          onTap: () => _push(context, const AdminChoferesCorporativoPage()),
        ),
        ListTile(
          leading: Icon(Icons.map_outlined, color: iconNeutral),
          title: Text('Mapa corporativo', style: titleStyle),
          subtitle: Text(
            'Choferes en ruta en tiempo real',
            style: subtleStyle,
          ),
          onTap: () => _push(context, const AdminCorporativoMapaPage()),
        ),
        ListTile(
          leading: Icon(Icons.tune_outlined,
              color:
                  isLight ? const Color(0xFF0D9488) : const Color(0xFF5EEAD4)),
          title: Text('Tarifas corporativas',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text(
            'Km, transferencia, comisión %',
            style: subtleStyle,
          ),
          onTap: () =>
              _push(context, const AdminCorporativoTarifasConfigPage()),
        ),
        ListTile(
          leading: Icon(Icons.receipt_long_outlined,
              color:
                  isLight ? const Color(0xFF0D9488) : const Color(0xFF5EEAD4)),
          title: Text('Cuentas corporativas',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text(
            'Bauche · validar · poner en cero',
            style: subtleStyle,
          ),
          onTap: () => _push(context, const AdminCorporativoCuentasPage()),
        ),
        ListTile(
          leading: Icon(Icons.home, color: iconNeutral),
          title: Text('Retiros billetera',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text('Solicitudes de retiro del taxista', style: subtleStyle),
          onTap: () => _push(context, const AdminHome()),
        ),
        ListTile(
          leading: Icon(Icons.analytics,
              color: isLight ? const Color(0xFF0F9D58) : Colors.greenAccent),
          title: Text('Resumen de comisiones',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text('Estadísticas diarias', style: subtleStyle),
          onTap: () => _push(context, const ResumenComisionesAdmin()),
        ),
        ListTile(
          leading: Icon(Icons.percent, color: iconNeutral),
          title: Text('Comisiones RAI (efectivo / transf. / tarjeta)',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text('10% · 15% · 15% en Firestore', style: subtleStyle),
          onTap: () =>
              _push(context, const ConfiguracionViajeComisionAdmin()),
        ),
        ListTile(
          leading: Icon(Icons.emoji_events_outlined,
              color: isLight ? Colors.amber.shade800 : Colors.amberAccent),
          title: Text('Incentivos comisión taxista',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text(
            'Menor % por volumen de viajes',
            style: subtleStyle,
          ),
          onTap: () =>
              _push(context, const AdminComisionIncentivosTaxista()),
        ),
        ListTile(
          leading: Icon(Icons.attach_money, color: iconNeutral),
          title: Text('Tarifas',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text(
            'Precio calle / turismo / km · Guardar al cambiar',
            style: subtleStyle,
          ),
          onTap: () => _push(context, const AdminTarifas()),
        ),
        ListTile(
          leading: Icon(Icons.local_offer, color: iconNeutral),
          title: Text('Promociones',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
          onTap: () => _push(context, const AdminPromosMxK()),
        ),
        ListTile(
          leading: Icon(Icons.qr_code_2_outlined,
              color: isLight ? Colors.indigo.shade700 : Colors.indigoAccent),
          title: Text('Negocios aliados (QR)',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text(
            'Código único · letrero PDF · 5+1 gratis',
            style: subtleStyle,
          ),
          onTap: () => _push(context, const AdminNegociosAliados()),
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
              color: isLight ? Colors.blue.shade700 : Colors.lightBlueAccent),
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
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
          child: Text(
            'CONDUCTORES',
            style: TextStyle(
              color: isLight ? Colors.green.shade800 : Colors.greenAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ListTile(
          leading: Icon(Icons.folder_shared_outlined,
              color: isLight ? Colors.green.shade700 : Colors.greenAccent),
          title: Text('Expedientes choferes',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text(
            'Documentos chofer · aprobar o pedir corrección',
            style: subtleStyle,
          ),
          onTap: () => _push(context, const RevisionDocumentosAdmin()),
        ),
        ListTile(
          leading: Icon(Icons.face_retouching_natural_outlined, color: iconNeutral),
          title: const Text('Confirmación selfie clientes'),
          subtitle: Text(
            'Solo lectura · estado de selfie periódica',
            style: subtleStyle,
          ),
          onTap: () => _push(context, const AdminVerificacionIdentidadCliente()),
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
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
          child: Text(
            'SALIDAS POR CUPOS · TURISMO',
            style: TextStyle(
              color:
                  isLight ? Colors.deepPurple.shade700 : Colors.purpleAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ListTile(
          leading: Icon(Icons.pending_actions,
              color: isLight ? Colors.deepOrange : Colors.orangeAccent),
          title: Text('Aprobar solicitudes turismo',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
          subtitle:
              Text('Registro y documentos turísticos', style: subtleStyle),
          onTap: () => _push(context, const AprobarChoferesTurismo()),
        ),
        ListTile(
          leading: Icon(Icons.radar,
              color: isLight ? Colors.deepPurple : Colors.purpleAccent),
          title: Text('Control turismo',
              style: titleStyle.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(
            'Pedidos en vivo y mensajes cliente',
            style: subtleStyle,
          ),
          onTap: () => _push(context, const AdminTurismoControl()),
        ),
        ListTile(
          leading: Icon(Icons.travel_explore, color: iconNeutral),
          title: Text('Viajes Turismo — Asignación',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text('Cola admin · asignar o liberar pool',
              style: subtleStyle),
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
          leading: Icon(Icons.airport_shuttle, color: iconNeutral),
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
        SizedBox(height: asSheetBody ? 28 : 16),
      ],
    );

    if (asSheetBody) return list;

    return Drawer(
      backgroundColor: drawerBg,
      child: SafeArea(child: list),
    );
  }
}
