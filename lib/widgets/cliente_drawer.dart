// lib/widgets/cliente_drawer.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/widgets/avatar_circle.dart';
import 'package:flygo_nuevo/servicios/logout.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje_multi.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_en_curso_cliente.dart';
import 'package:flygo_nuevo/pantallas/cliente/historial_cliente.dart';
import 'package:flygo_nuevo/pantallas/cliente/reservas_programadas_cliente.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/pantallas/servicios_extras/pools_cliente_lista.dart';
// ✅ IMPORT ELIMINADO - Ya no se usa pago_metodo.dart
import 'package:flygo_nuevo/pantallas/comun/soporte.dart';
import 'package:flygo_nuevo/pantallas/comun/configuracion_perfil.dart';
import 'package:flygo_nuevo/legal/terms_policy_screen.dart';
import 'package:flygo_nuevo/servicios/theme_mode_service.dart';

class ClienteDrawer extends StatelessWidget {
  const ClienteDrawer({super.key});

  static TextStyle _titleStyleOf(ColorScheme cs) => TextStyle(
        color: cs.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      );

  static TextStyle _subtitleStyleOf(ColorScheme cs) =>
      TextStyle(color: cs.onSurfaceVariant);

  Future<void> _logout(BuildContext context) async {
    Navigator.pop(context);
    await cerrarSesion(context);
  }

  void _navegarAPantalla(BuildContext context, Widget pantalla) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
  }

  Widget _header(BuildContext context, {required String nombre, String? fotoUrl}) {
    final cs = Theme.of(context).colorScheme;
    return UserAccountsDrawerHeader(
      decoration: BoxDecoration(color: cs.primary),
      accountName: Text(
        nombre,
        style: TextStyle(
          color: cs.onPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      accountEmail: const SizedBox.shrink(),
      currentAccountPicture: AvatarCircle(
        imageUrl: (fotoUrl ?? '').trim(),
        name: nombre.isEmpty ? 'Usuario' : nombre,
        size: 64,
      ),
    );
  }

  // 🔥 NUEVA FUNCIÓN: Mostrar opciones de pago
  void _mostrarOpcionesPago(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final dcs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: dcs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Métodos de Pago',
                  style: TextStyle(
                    color: dcs.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),

                // EFECTIVO
                _buildPaymentOption(
                  ctx,
                  icon: Icons.money,
                  title: 'Efectivo',
                  subtitle: 'Paga en efectivo al conductor',
                  isEnabled: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _mostrarHistorialPagos(context);
                  },
                ),

                Divider(color: dcs.outlineVariant, height: 1),

                // TARJETA (No disponible)
                _buildPaymentOption(
                  ctx,
                  icon: Icons.credit_card,
                  title: 'Tarjeta',
                  subtitle: 'No disponible',
                  isEnabled: false,
                  onTap: null,
                ),

                Divider(color: dcs.outlineVariant, height: 1),

                // TRANSFERENCIA
                _buildPaymentOption(
                  ctx,
                  icon: Icons.account_balance,
                  title: 'Transferencia',
                  subtitle: 'Paga por transferencia bancaria',
                  isEnabled: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _mostrarInfoTransferencia(context);
                  },
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: FilledButton.styleFrom(
                      backgroundColor: dcs.primary,
                      foregroundColor: dcs.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 🔥 NUEVA FUNCIÓN: Mostrar información de transferencia
  void _mostrarInfoTransferencia(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final dcs = Theme.of(ctx).colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          minChildSize: 0.4,
          maxChildSize: 0.8,
          builder: (_, controller) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: dcs.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Transferencia Bancaria',
                    style: TextStyle(
                      color: dcs.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Explicación
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: dcs.primaryContainer.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: dcs.primary.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.info, color: dcs.primary, size: 32),
                        const SizedBox(height: 8),
                        Text(
                          'Cuando selecciones "Transferencia" como método de pago al programar un viaje, podrás ver los datos bancarios del conductor asignado para realizar el pago directamente.',
                          style: TextStyle(color: dcs.onPrimaryContainer),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Ejemplo visual
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: dcs.surfaceContainerHighest.withValues(
                        alpha: Theme.of(ctx).brightness == Brightness.dark
                            ? 0.55
                            : 0.75,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: dcs.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DATOS DEL CONDUCTOR (ejemplo)',
                          style: TextStyle(
                            color: dcs.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(ctx, 'Banco:', 'Banco de Reservas'),
                        _buildInfoRow(ctx, 'Cuenta:', '960-123456-7'),
                        _buildInfoRow(ctx, 'Titular:', 'Carlos Rodríguez'),
                        _buildInfoRow(ctx, 'Cédula:', '001-2345678-9'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: FilledButton.styleFrom(
                        backgroundColor: dcs.primary,
                        foregroundColor: dcs.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Cerrar'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 🔥 NUEVA FUNCIÓN: Mostrar historial de pagos
  void _mostrarHistorialPagos(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final dcs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: dcs.surfaceContainerHigh,
          title: Text(
            'Historial de Pagos',
            style: TextStyle(color: dcs.onSurface),
          ),
          content: Text(
            'Aquí podrás ver tu historial de pagos en efectivo.',
            style: TextStyle(color: dcs.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cerrar', style: TextStyle(color: dcs.primary)),
            ),
          ],
        );
      },
    );
  }

  // 🔥 NUEVA FUNCIÓN: Opción de pago
  Widget _buildPaymentOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isEnabled,
    required VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        icon,
        color: isEnabled ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.45),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isEnabled ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.45),
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: isEnabled ? cs.onSurfaceVariant : cs.onSurfaceVariant.withValues(alpha: 0.45),
          fontSize: 12,
        ),
      ),
      trailing: isEnabled
          ? Icon(Icons.chevron_right, color: cs.onSurfaceVariant)
          : Icon(Icons.block, color: cs.error, size: 16),
      onTap: isEnabled ? onTap : null,
    );
  }

  // 🔥 NUEVA FUNCIÓN: Fila de información
  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: cs.onSurface, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    final cs = Theme.of(context).colorScheme;

    return Drawer(
      backgroundColor: cs.surface,
      child: SafeArea(
        child: Column(
          children: [
            if (uid == null)
              _header(context, nombre: 'Cliente')
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
                  return _header(context, nombre: nombre, fotoUrl: foto);
                },
              ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // ✅ Solicitar viaje ahora
                  ListTile(
                    leading: Icon(Icons.rocket_launch_outlined, color: cs.onSurface),
                    title: Text('Solicitar viaje ahora', style: _titleStyleOf(cs)),
                    subtitle: Text(
                      'Usar mi ubicación actual',
                      style: _subtitleStyleOf(cs),
                    ),
                    onTap: () => _navegarAPantalla(
                        context, const ProgramarViaje(modoAhora: true)),
                  ),

                  // ✅ Programar viaje
                  ListTile(
                    leading: Icon(Icons.calendar_month_outlined, color: cs.onSurface),
                    title: Text('Programar viaje', style: _titleStyleOf(cs)),
                    subtitle: Text(
                      'Elegir fecha u origen manual',
                      style: _subtitleStyleOf(cs),
                    ),
                    onTap: () => _navegarAPantalla(
                        context, const ProgramarViaje(modoAhora: false)),
                  ),

                  // ✅ Reservas programadas (estado y pool en vivo)
                  ListTile(
                    leading: Icon(Icons.event_available_outlined, color: cs.onSurface),
                    title: Text('Mis reservas programadas', style: _titleStyleOf(cs)),
                    subtitle: Text(
                      'Seguimiento y pool de conductores',
                      style: _subtitleStyleOf(cs),
                    ),
                    onTap: () => _navegarAPantalla(
                      context,
                      const ReservasProgramadasCliente(),
                    ),
                  ),

                  // ✅ NUEVO: Múltiples paradas
                  ListTile(
                    leading: Icon(Icons.alt_route, color: cs.onSurface),
                    title: Text('Múltiples paradas', style: _titleStyleOf(cs)),
                    subtitle: Text(
                      'Añadir paradas intermedias',
                      style: _subtitleStyleOf(cs),
                    ),
                    onTap: () =>
                        _navegarAPantalla(context, const ProgramarViajeMulti()),
                  ),

                  Divider(color: cs.outlineVariant, height: 28),

                  // ✅ NUEVO: Mi viaje en curso
                  if (uid != null)
                    StreamBuilder(
                      stream: ViajesRepo.streamEstadoViajePorCliente(uid),
                      builder: (context, s) {
                        final csV = Theme.of(context).colorScheme;
                        final activo = s.data != null;
                        return ListTile(
                          leading: Icon(Icons.directions_car, color: csV.onSurface),
                          title: Text('Mi viaje en curso', style: _titleStyleOf(csV)),
                          subtitle: Text(
                            activo
                                ? 'Tienes un viaje activo'
                                : 'No tienes viaje en curso',
                            style: _subtitleStyleOf(csV),
                          ),
                          trailing: activo
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: csV.primaryContainer,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: csV.primary),
                                  ),
                                  child: Text(
                                    'Activo',
                                    style: TextStyle(
                                      color: csV.onPrimaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              : null,
                          onTap: () => _navegarAPantalla(
                              context, const ViajeEnCursoCliente()),
                        );
                      },
                    ),

                  // ✅ Historial de viajes
                  ListTile(
                    leading: Icon(Icons.history, color: cs.onSurface),
                    title: Text('Historial de viajes', style: _titleStyleOf(cs)),
                    subtitle: Text(
                      'Completados y pendientes',
                      style: _subtitleStyleOf(cs),
                    ),
                    onTap: () =>
                        _navegarAPantalla(context, const HistorialCliente()),
                  ),

                  ListTile(
                    leading: Icon(Icons.groups_2_outlined, color: cs.onSurface),
                    title: Text('Giras / Tours por cupos', style: _titleStyleOf(cs)),
                    subtitle: Text('Catálogo de agencias', style: _subtitleStyleOf(cs)),
                    onTap: () => _navegarAPantalla(
                      context,
                      const PoolsClienteLista(tipo: 'todos'),
                    ),
                  ),

                  // ✅ PAGOS MODIFICADO (RAI)
                  ListTile(
                    leading: Icon(
                      Icons.account_balance_wallet_outlined,
                      color: cs.onSurface,
                    ),
                    title: Text('Pagos', style: _titleStyleOf(cs)),
                    subtitle: Text(
                      'RAI • Efectivo • Transferencia',
                      style: _subtitleStyleOf(cs),
                    ),
                    onTap: () =>
                        _mostrarOpcionesPago(context), // 🔥 AHORA USA EL MODAL
                  ),

                  // ✅ Soporte
                  ListTile(
                    leading: Icon(Icons.support_agent, color: cs.onSurface),
                    title: Text('Soporte', style: _titleStyleOf(cs)),
                    subtitle: Text('Ayuda y contacto', style: _subtitleStyleOf(cs)),
                    onTap: () => _navegarAPantalla(context, const Soporte()),
                  ),

                  Divider(color: cs.outlineVariant, height: 28),

                  // ✅ Configuración de perfil
                  ListTile(
                    leading: Icon(Icons.person, color: cs.onSurface),
                    title: Text('Configuración de perfil', style: _titleStyleOf(cs)),
                    subtitle: Text('Foto y nombre', style: _subtitleStyleOf(cs)),
                    onTap: () =>
                        _navegarAPantalla(context, const ConfiguracionPerfil()),
                  ),
                  ListTile(
                    leading: Icon(Icons.gavel_outlined, color: cs.onSurface),
                    title: Text('Terminos y Politica', style: _titleStyleOf(cs)),
                    subtitle: Text(
                      'Privacidad y condiciones de uso',
                      style: _subtitleStyleOf(cs),
                    ),
                    onTap: () =>
                        _navegarAPantalla(context, const TermsPolicyScreen()),
                  ),
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: ThemeModeService.mode,
                    builder: (context, mode, _) {
                      final csM = Theme.of(context).colorScheme;
                      final isLight = mode == ThemeMode.light;
                      return SwitchListTile(
                        secondary: Icon(
                          isLight ? Icons.light_mode : Icons.dark_mode,
                          color: csM.onSurface,
                        ),
                        title: Text('Modo claro', style: _titleStyleOf(csM)),
                        subtitle: Text(
                          'Personaliza apariencia',
                          style: _subtitleStyleOf(csM),
                        ),
                        value: isLight,
                        onChanged: (v) => ThemeModeService.setMode(
                          v ? ThemeMode.light : ThemeMode.dark,
                        ),
                        activeColor: csM.primary,
                      );
                    },
                  ),

                  // ✅ Cerrar sesión
                  ListTile(
                    leading: Icon(Icons.logout, color: cs.error),
                    title: Text(
                      'Cerrar sesión',
                      style: TextStyle(
                        color: cs.error,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () => _logout(context),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
