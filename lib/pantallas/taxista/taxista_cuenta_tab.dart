import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flygo_nuevo/auth/seleccion_usuario.dart';
import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/config/recarga_bancaria_config.dart';
import 'package:flygo_nuevo/legal/terms_policy_screen.dart';
import 'package:flygo_nuevo/pantallas/comun/configuracion_perfil.dart';
import 'package:flygo_nuevo/pantallas/comun/soporte.dart';
import 'package:flygo_nuevo/pantallas/taxista/billetera_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/documentos_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/ganancia_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/historial_viajes_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/mis_pagos.dart';
import 'package:flygo_nuevo/servicios/auth_service.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/servicios/theme_mode_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/widgets/avatar_circle.dart';
import 'package:flygo_nuevo/widgets/configuracion_bancaria.dart';

String _pctLabel(double p) =>
    p == p.roundToDouble() ? p.round().toString() : p.toStringAsFixed(1);

String _subtituloBilleteraComision() {
  final c = PlataformaEconomia.comisionViajePorcentaje;
  final t = 100.0 - c;
  return 'Saldo ${_pctLabel(t)} %, comisión ${_pctLabel(c)} %';
}

String _subtituloGananciasResumen() {
  final c = PlataformaEconomia.comisionViajePorcentaje;
  final t = 100.0 - c;
  return 'Totales y reparto ${_pctLabel(t)}/${_pctLabel(c)}';
}

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
          if (uid != null)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? const <String, dynamic>{};
                final bloqueado = data['tienePagoPendiente'] == true;
                return ListTile(
                  leading: Icon(
                    bloqueado
                        ? Icons.lock_clock_outlined
                        : Icons.lock_open_outlined,
                    color: bloqueado ? Colors.red : Colors.green,
                  ),
                  title: const Text('Estado de recarga y bloqueo'),
                  subtitle: Text(
                    bloqueado
                        ? 'BLOQUEADO: recarga y sube bauche para habilitar viajes/pool.'
                        : 'ACTIVO: abrí Mis pagos y seguí los pasos (banco → monto → foto).',
                  ),
                  trailing: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const MisPagos(scrollToRecargaSection: true),
                        ),
                      );
                    },
                    icon: const Icon(Icons.payment_outlined, size: 18),
                    label: const Text('Mis pagos'),
                  ),
                );
              },
            ),
          if (uid != null)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('billeteras_taxista')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? const <String, dynamic>{};
                final saldo =
                    PagosTaxistaRepo.saldoPrepagoComisionDesdeBilletera(data);
                final legacyPendiente =
                    PagosTaxistaRepo.comisionPendienteDesdeBilletera(data);
                final bloqueado =
                    PagosTaxistaRepo.bloqueoOperativoPorComisionEfectivo(data);
                const minimo = PagosTaxistaRepo.minSaldoPrepagoComisionRd;
                const metaVisual = 500.0;
                final progreso = (saldo / metaVisual).clamp(0.0, 1.0);
                final faltante = (minimo - saldo).clamp(0.0, double.infinity);

                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: bloqueado
                          ? Colors.red.withValues(alpha: 0.6)
                          : cs.outlineVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            bloqueado
                                ? Icons.warning_amber_rounded
                                : Icons.account_balance_wallet_outlined,
                            color: bloqueado ? Colors.red : cs.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Crédito de recarga (tiempo real)',
                              style: TextStyle(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Text(
                            bloqueado ? 'BLOQUEADO' : 'ACTIVO',
                            style: TextStyle(
                              color: bloqueado ? Colors.red : Colors.green,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Saldo actual: ${FormatosMoneda.rd(saldo)}',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          minHeight: 10,
                          value: progreso,
                          backgroundColor: cs.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            bloqueado ? Colors.red : Colors.green,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('0', style: TextStyle(fontSize: 11)),
                          Text('200', style: TextStyle(fontSize: 11)),
                          Text('500+', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        bloqueado
                            ? 'Te faltan ${FormatosMoneda.rd(faltante)} para recuperar mínimo RD\$200.'
                            : 'Mantén el saldo por encima de RD\$200 para no bloquear viajes/pool.',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                      ),
                      if (legacyPendiente > 0.01) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Legacy pendiente: ${FormatosMoneda.rd(legacyPendiente)}',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_balance, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Cuenta para depositar recarga',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Titular: ${RecargaBancariaConfig.titular}'),
                  const Text('RNC: ${RecargaBancariaConfig.rnc}'),
                  const Text('Banco: ${RecargaBancariaConfig.banco}'),
                  const Text('Tipo: ${RecargaBancariaConfig.tipoCuenta}'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'No. cuenta: ${RecargaBancariaConfig.numeroCuenta}',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copiar cuenta',
                        onPressed: () async {
                          await Clipboard.setData(
                            const ClipboardData(
                                text: RecargaBancariaConfig.numeroCuenta),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Número de cuenta copiado'),
                            ),
                          );
                        },
                        icon: Icon(Icons.copy, color: cs.primary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _tile(
            context,
            icon: Icons.account_balance_wallet_outlined,
            title: 'Billetera',
            subtitle: _subtituloBilleteraComision(),
            page: const BilleteraTaxista(),
          ),
          _tile(
            context,
            icon: Icons.payment,
            title: 'Recargas y comprobantes',
            subtitle:
                'Cuenta bancaria, foto del bauche y historial de recargas/pagos',
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
            subtitle: _subtituloGananciasResumen(),
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
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => page),
        );
      },
    );
  }
}
