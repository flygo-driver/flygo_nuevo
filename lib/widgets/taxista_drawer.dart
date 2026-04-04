// lib/widgets/taxista_drawer.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/widgets/avatar_circle.dart';
import 'package:flygo_nuevo/servicios/auth_service.dart';
import 'package:flygo_nuevo/widgets/configuracion_bancaria.dart'; // 🔴 NUEVO

// Pantallas Taxista
import 'package:flygo_nuevo/pantallas/taxista/viaje_disponible.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/billetera_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/historial_viajes_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/ganancia_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/documentos_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/toggle_disponibilidad.dart';
import 'package:flygo_nuevo/pantallas/taxista/mis_pagos.dart';

// Viajes por cupos (consular/tour)
import 'package:flygo_nuevo/pantallas/taxista/pools_taxista_lista.dart';
import 'package:flygo_nuevo/pantallas/taxista/pools_taxista_crear.dart';

// Turismo
import 'package:flygo_nuevo/pantallas/taxista/login_chofer_turismo.dart';
import 'package:flygo_nuevo/pantallas/taxista/viajes_turismo_asignados.dart';
import 'package:flygo_nuevo/pantallas/taxista/pool_turismo_taxista.dart';
import 'package:flygo_nuevo/pantallas/comun/configuracion_perfil.dart';

// Pantalla común
import 'package:flygo_nuevo/pantallas/comun/soporte.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';

// Fallback login
import 'package:flygo_nuevo/auth/seleccion_usuario.dart';
import 'package:flygo_nuevo/legal/terms_policy_screen.dart';
import 'package:flygo_nuevo/servicios/theme_mode_service.dart';

class TaxistaDrawer extends StatelessWidget {
  const TaxistaDrawer({super.key});

  static TextStyle _titleStyleOf(ColorScheme cs) => TextStyle(
        color: cs.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      );

  static TextStyle _subStyleOf(ColorScheme cs) =>
      TextStyle(color: cs.onSurfaceVariant);

  static TextStyle _sectionLabel(ColorScheme cs, {bool turismo = false}) =>
      TextStyle(
        color: turismo ? cs.tertiary : cs.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      );

  static const Set<String> _estadosActivos = {
    'aceptado',
    'en_camino_pickup',
    'a_bordo',
    'en_curso',
  };
  // Ventana de gracia QA: evita autolimpieza agresiva al cambiar de cuenta
  // en el mismo telefono durante pruebas (cliente <-> taxista).
  static const bool _qaGraceOnAccountSwitch = bool.fromEnvironment(
    'QA_ACCOUNT_SWITCH_GRACE',
    defaultValue: true,
  );
  static const Duration _qaGraceWindow = Duration(minutes: 3);

  static DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

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

  void _go(BuildContext context, Widget page, {bool replace = false}) {
    Navigator.pop(context);
    final route = MaterialPageRoute(builder: (_) => page);
    if (replace) {
      Navigator.pushReplacement(context, route);
    } else {
      Navigator.push(context, route);
    }
  }

  // Header con nombre/foto en tiempo real
  Widget _header(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return UserAccountsDrawerHeader(
        decoration: BoxDecoration(color: cs.primary),
        accountName: Text(
          'Taxista',
          style: TextStyle(
            color: cs.onPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        accountEmail: const SizedBox.shrink(),
        currentAccountPicture: CircleAvatar(
          backgroundColor: cs.onPrimary.withValues(alpha: 0.2),
          child: Icon(Icons.person, color: cs.onPrimary),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .snapshots(),
      builder: (_, s) {
        final data = s.data?.data() ?? {};
        final nombre = (data['nombre'] ?? '').toString().trim();
        final foto = (data['fotoUrl'] ?? '').toString().trim();

        return UserAccountsDrawerHeader(
          decoration: BoxDecoration(color: cs.primary),
          accountName: Text(
            nombre.isEmpty ? 'Taxista' : nombre,
            style: TextStyle(
              color: cs.onPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          accountEmail: const SizedBox.shrink(),
          currentAccountPicture: AvatarCircle(
            imageUrl: foto,
            name: nombre.isEmpty ? 'Taxista' : nombre,
            size: 64,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;

    return Drawer(
      backgroundColor: cs.surface,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _header(context),

            // ==== Operación diaria ====
            ListTile(
              leading: Icon(Icons.list_alt_outlined, color: cs.onSurface),
              title: Text('Viajes disponibles', style: _titleStyleOf(cs)),
              subtitle: Text(
                'Llegan en tiempo real + timbre',
                style: _subStyleOf(cs),
              ),
              onTap: () => _go(context, const ViajeDisponible(), replace: true),
            ),
            if (user != null)
              StreamBuilder(
                stream: FirebaseFirestore.instance
                    .collection('usuarios')
                    .doc(user.uid)
                    .snapshots(),
                builder: (context, uSnap) {
                  final csU = Theme.of(context).colorScheme;
                  final uData = uSnap.data?.data() ?? const <String, dynamic>{};
                  final viajeActivoId =
                      (uData['viajeActivoId'] ?? '').toString().trim();

                  if (viajeActivoId.isEmpty) {
                    return ListTile(
                      leading: Icon(
                        Icons.navigation_outlined,
                        color: csU.onSurface,
                      ),
                      title: Text('Viaje en curso', style: _titleStyleOf(csU)),
                      subtitle: Text(
                        'No tienes viaje en curso',
                        style: _subStyleOf(csU),
                      ),
                      onTap: () => _go(context, const ViajeEnCursoTaxista()),
                    );
                  }

                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('viajes')
                        .doc(viajeActivoId)
                        .snapshots(),
                    builder: (context, vSnap) {
                      final csV = Theme.of(context).colorScheme;
                      final vData = vSnap.data?.data();
                      final uidTx = (vData?['uidTaxista'] ?? vData?['taxistaId'] ?? '')
                          .toString();
                      final estado =
                          EstadosViaje.normalizar((vData?['estado'] ?? '').toString());
                      final activo = vData?['activo'] == true;
                      final uidCliente =
                          (vData?['uidCliente'] ?? vData?['clienteId'] ?? '')
                              .toString()
                              .trim();
                      final visible = vData != null &&
                          uidTx == user.uid &&
                          activo &&
                          uidCliente.isNotEmpty &&
                          _estadosActivos.contains(estado);

                      if (!visible && viajeActivoId.isNotEmpty) {
                        final now = DateTime.now();
                        final lastLoginAt = _toDate(
                          uData['lastLogin'] ?? uData['updatedAt'] ?? uData['actualizadoEn'],
                        );
                        final inQaGrace = _qaGraceOnAccountSwitch &&
                            lastLoginAt != null &&
                            now.difference(lastLoginAt) <= _qaGraceWindow;
                        if (inQaGrace) {
                          // En QA, no limpiar todavia para evitar falsos negativos
                          // cuando el mismo dispositivo alterna de rol.
                          return ListTile(
                            leading: Icon(
                              Icons.navigation_outlined,
                              color: csV.onSurface,
                            ),
                            title: Text('Viaje en curso', style: _titleStyleOf(csV)),
                            subtitle: Text(
                              'Sincronizando estado del viaje...',
                              style: _subStyleOf(csV),
                            ),
                            onTap: () => _go(context, const ViajeEnCursoTaxista()),
                          );
                        }
                        Future<void>(() async {
                          try {
                            await FirebaseFirestore.instance
                                .collection('usuarios')
                                .doc(user.uid)
                                .set({
                              'viajeActivoId': '',
                              'updatedAt': FieldValue.serverTimestamp(),
                              'actualizadoEn': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));
                          } catch (_) {}
                        });
                      }

                      return ListTile(
                        leading: Icon(
                          Icons.navigation_outlined,
                          color: csV.onSurface,
                        ),
                        title: Text('Viaje en curso', style: _titleStyleOf(csV)),
                        subtitle: Text(
                          visible
                              ? 'Tienes un viaje activo'
                              : 'No tienes viaje en curso',
                          style: _subStyleOf(csV),
                        ),
                        trailing: visible
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
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
                        onTap: () => _go(context, const ViajeEnCursoTaxista()),
                      );
                    },
                  );
                },
              )
            else
              ListTile(
                leading: Icon(Icons.navigation_outlined, color: cs.onSurface),
                title: Text('Viaje en curso', style: _titleStyleOf(cs)),
                subtitle: Text('No tienes viaje en curso', style: _subStyleOf(cs)),
                onTap: () => _go(context, const ViajeEnCursoTaxista()),
              ),
            ListTile(
              leading: Icon(Icons.toggle_on, color: cs.onSurface),
              title: Text('Disponibilidad', style: _titleStyleOf(cs)),
              subtitle: Text(
                'Recibir viajes: ON / OFF',
                style: _subStyleOf(cs),
              ),
              onTap: () => _go(context, const ToggleDisponibilidad()),
            ),

            Divider(color: cs.outlineVariant),

            // ==== SECCIÓN TURISMO ====
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
              child: Text(
                'Turismo',
                style: _sectionLabel(cs, turismo: true),
              ),
            ),

            ListTile(
              leading: Icon(Icons.app_registration, color: cs.tertiary),
              title: Text('Ser chofer de turismo', style: _titleStyleOf(cs)),
              subtitle: Text(
                'Regístrate y espera aprobación',
                style: _subStyleOf(cs),
              ),
              onTap: () => _go(context, const LoginChoferTurismo()),
            ),

            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: user != null
                  ? FirebaseFirestore.instance
                      .collection('choferes_turismo')
                      .doc(user.uid)
                      .snapshots()
                  : null,
              builder: (context, snapshot) {
                final csT = Theme.of(context).colorScheme;
                final data = snapshot.data?.data();
                final estado = (data?['estado'] ?? '').toString().trim().toLowerCase();
                final esAprobado = estado == 'aprobado' || estado == 'activo';

                if (!esAprobado) {
                  return ListTile(
                    leading: Icon(Icons.lock_clock, color: csT.tertiary),
                    title: Text('Pool turístico', style: _titleStyleOf(csT)),
                    subtitle: Text(
                      'Disponible al aprobarte en turismo',
                      style: _subStyleOf(csT),
                    ),
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: Icon(Icons.pool, color: csT.tertiary),
                      title: Text('Pool turístico', style: _titleStyleOf(csT)),
                      subtitle: Text(
                        'Turismo liberado por administración',
                        style: _subStyleOf(csT),
                      ),
                      onTap: () => _go(context, const PoolTurismoTaxista(),
                          replace: true),
                    ),
                    ListTile(
                      leading: Icon(Icons.tour, color: csT.tertiary),
                      title: Text('Mis viajes turismo', style: _titleStyleOf(csT)),
                      subtitle: Text(
                        'Viajes que te han asignado',
                        style: _subStyleOf(csT),
                      ),
                      onTap: () =>
                          _go(context, const ViajesTurismoAsignadosTaxista()),
                    ),
                  ],
                );
              },
            ),

            Divider(color: cs.outlineVariant),

            // ==== Viajes por cupos ====
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
              child: Text(
                'Viajes por cupos',
                style: _sectionLabel(cs),
              ),
            ),
            ListTile(
              leading: Icon(Icons.people_alt_outlined, color: cs.onSurface),
              title: Text('Mis viajes por cupos', style: _titleStyleOf(cs)),
              subtitle: Text(
                'Ver ocupación, pagos y reservas',
                style: _subStyleOf(cs),
              ),
              onTap: () => _go(context, const PoolsTaxistaLista()),
            ),
            ListTile(
              leading: Icon(Icons.add_circle_outline, color: cs.onSurface),
              title: Text('Crear viaje por cupos', style: _titleStyleOf(cs)),
              subtitle: Text(
                'Consular o Tour, ida o ida/vuelta',
                style: _subStyleOf(cs),
              ),
              onTap: () => _go(context, const PoolsTaxistaCrear()),
            ),

            Divider(color: cs.outlineVariant),

            // ==== Finanzas / Docs / Soporte ====
            ListTile(
              leading: Icon(
                Icons.account_balance_wallet_outlined,
                color: cs.onSurface,
              ),
              title: Text('Billetera', style: _titleStyleOf(cs)),
              subtitle: Text(
                'Saldo 80 %, comisión 20 %',
                style: _subStyleOf(cs),
              ),
              onTap: () => _go(context, const BilleteraTaxista()),
            ),
            ListTile(
              leading: Icon(Icons.payment, color: cs.onSurface),
              title: Text('Mis Pagos', style: _titleStyleOf(cs)),
              subtitle: Text('Historial de comisiones', style: _subStyleOf(cs)),
              onTap: () => _go(context, const MisPagos()),
            ),
            // 🔴 NUEVO - Datos bancarios
            ListTile(
              leading: Icon(Icons.account_balance, color: cs.onSurface),
              title: Text('Datos bancarios', style: _titleStyleOf(cs)),
              subtitle: Text(
                'Banco y cuenta para transferencias',
                style: _subStyleOf(cs),
              ),
              onTap: () => _go(context, const ConfiguracionBancaria()),
            ),
            ListTile(
              leading: Icon(Icons.history, color: cs.onSurface),
              title: Text('Historial de viajes', style: _titleStyleOf(cs)),
              onTap: () => _go(context, const HistorialViajesTaxista()),
            ),
            ListTile(
              leading: Icon(Icons.monetization_on_outlined, color: cs.onSurface),
              title: Text('Ganancias', style: _titleStyleOf(cs)),
              subtitle: Text('Totales y cálculo 80/20', style: _subStyleOf(cs)),
              onTap: () => _go(context, const GananciaTaxista()),
            ),
            ListTile(
              leading: Icon(Icons.description_outlined, color: cs.onSurface),
              title: Text('Documentos', style: _titleStyleOf(cs)),
              subtitle: Text(
                'Licencia, cédula, seguro',
                style: _subStyleOf(cs),
              ),
              onTap: () => _go(context, const DocumentosTaxista()),
            ),
            ListTile(
              leading: Icon(Icons.support_agent, color: cs.onSurface),
              title: Text('Soporte', style: _titleStyleOf(cs)),
              onTap: () => _go(context, const Soporte()),
            ),

            Divider(color: cs.outlineVariant),

            // ==== Cuenta ====
            ListTile(
              leading: Icon(Icons.person, color: cs.onSurface),
              title: Text('Configuración de perfil', style: _titleStyleOf(cs)),
              subtitle: Text('Foto y nombre', style: _subStyleOf(cs)),
              onTap: () => _go(context, const ConfiguracionPerfil()),
            ),
            ListTile(
              leading: Icon(Icons.gavel_outlined, color: cs.onSurface),
              title: Text('Terminos y Politica', style: _titleStyleOf(cs)),
              subtitle: Text(
                'Privacidad y condiciones de uso',
                style: _subStyleOf(cs),
              ),
              onTap: () => _go(context, const TermsPolicyScreen()),
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
                    style: _subStyleOf(csM),
                  ),
                  value: isLight,
                  onChanged: (v) => ThemeModeService.setMode(
                    v ? ThemeMode.light : ThemeMode.dark,
                  ),
                  activeColor: csM.primary,
                );
              },
            ),
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
    );
  }
}
