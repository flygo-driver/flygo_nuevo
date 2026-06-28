import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/widgets/cuenta_promo_resumen_panel.dart';
import 'package:flygo_nuevo/widgets/cuenta_settings_tiles.dart';
import 'package:flygo_nuevo/widgets/cuenta_legal_tiles.dart';
import 'package:flygo_nuevo/widgets/cuenta_open_ask_deposito_panel.dart';
import 'package:flygo_nuevo/pantallas/comun/configuracion_perfil.dart';
import 'package:flygo_nuevo/pantallas/comun/soporte.dart';
import 'package:flygo_nuevo/pantallas/taxista/billetera_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/documentos_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/ganancia_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/historial_viajes_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/mis_pagos.dart';
import 'package:flygo_nuevo/pantallas/taxista/taxista_promociones.dart';
import 'package:flygo_nuevo/servicios/comision_viaje_pct_service.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/servicios/taxista_promociones_ui.dart';
import 'package:flygo_nuevo/servicios/theme_mode_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/widgets/avatar_circle.dart';
import 'package:flygo_nuevo/widgets/configuracion_bancaria.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_config_panel.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_rol.dart';

String _pctLabel(double p) =>
    p == p.roundToDouble() ? p.round().toString() : p.toStringAsFixed(1);

String _subtituloRepartoComision(double c) {
  final t = 100.0 - c;
  return 'Saldo ${_pctLabel(t)} %, comisión ${_pctLabel(c)} %';
}

String _subtituloGananciasComision(double c) {
  final t = 100.0 - c;
  return 'Totales y reparto ${_pctLabel(t)}/${_pctLabel(c)}';
}

String _textoPerfilTaxista(
  Map<String, dynamic> data, {
  required String fallbackEmail,
}) {
  final List<String> lineas = <String>[];
  final String nombre = (data['nombre'] ?? '').toString().trim();
  final String telefono = (data['telefono'] ?? '').toString().trim();
  final String tipoServicio =
      (data['tipoServicio'] ?? '').toString().trim().toLowerCase();
  final String placa = (data['placa'] ?? '').toString().trim();
  final String marca =
      (data['vehiculoMarca'] ?? data['marca'] ?? '').toString().trim();
  final String modelo =
      (data['vehiculoModelo'] ?? data['modelo'] ?? '').toString().trim();
  final String color =
      (data['vehiculoColor'] ?? data['color'] ?? '').toString().trim();
  final String anio = (data['anio'] ?? data['vehiculoAnio'] ?? '')
      .toString()
      .trim();

  String tipoVehiculo = (data['tipoVehiculo'] ?? data['vehiculoTipo'] ?? '')
      .toString()
      .trim();
  if (tipoServicio == 'turismo') {
    switch (tipoVehiculo.toLowerCase()) {
      case 'jeepeta':
        tipoVehiculo = 'Jeepeta Turismo';
        break;
      case 'minivan':
        tipoVehiculo = 'Minivan Turismo';
        break;
      case 'bus':
        tipoVehiculo = 'Bus Turismo';
        break;
      case 'carro':
      default:
        tipoVehiculo = tipoVehiculo.isEmpty ? '' : 'Carro Turismo';
        break;
    }
  }

  if (nombre.isNotEmpty) lineas.add('Nombre: $nombre');
  if (telefono.isNotEmpty) lineas.add('Teléfono: $telefono');
  if (fallbackEmail.trim().isNotEmpty) lineas.add('Correo: $fallbackEmail');
  if (tipoServicio.isNotEmpty) lineas.add('Servicio: ${_labelServicio(tipoServicio)}');
  if (tipoVehiculo.isNotEmpty) lineas.add('Vehículo: $tipoVehiculo');
  if (placa.isNotEmpty) lineas.add('Placa: $placa');

  final String marcaModelo = [marca, modelo].where((v) => v.isNotEmpty).join(' ');
  if (marcaModelo.isNotEmpty) lineas.add('Marca / modelo: $marcaModelo');
  if (color.isNotEmpty) lineas.add('Color: $color');
  if (anio.isNotEmpty) lineas.add('Año: $anio');

  return lineas.isEmpty
      ? 'Aún no hay datos de perfil guardados.'
      : lineas.join('\n');
}

String _labelServicio(String raw) {
  switch (raw) {
    case 'normal':
      return 'Normal';
    case 'motor':
      return 'Motor';
    case 'turismo':
      return 'Turismo';
    case 'bola_ahorro':
      return 'Bola Ahorro';
    default:
      return raw.isEmpty ? '—' : raw;
  }
}

/// Finanzas, documentos y ajustes de cuenta.
class TaxistaCuentaTab extends StatelessWidget {
  const TaxistaCuentaTab({super.key});

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
                final texto = _textoPerfilTaxista(
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
            StreamBuilder<double>(
              stream: ComisionViajePctService.streamPorcentajeVigente(),
              initialData: PlataformaEconomia.comisionViajePorcentaje,
              builder: (context, pctSnap) {
                final double pctCom =
                    pctSnap.data ?? PlataformaEconomia.comisionViajePorcentaje;
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
                final minimo = PagosTaxistaRepo.minSaldoPrepagoComisionRd;
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
                        'Comisión vigente en efectivo: ${TaxistaPromocionesUi.pctLabel(pctCom)}% '
                        '(se descuenta del prepago al finalizar cada viaje).',
                        style: TextStyle(
                          color: cs.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 6),
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
            );
              },
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: CuentaOpenAskDepositoPanel(mostrarNota: true),
          ),
          if (uid != null) TaxistaCuentaIncentivoPanel(uidTaxista: uid),
          _tile(
            context,
            icon: Icons.local_offer_outlined,
            title: 'Promociones y comisión',
            subtitle: 'Comisión RAI vigente y promo M×K para clientes',
            page: const TaxistaPromocionesScreen(),
          ),
          StreamBuilder<double>(
            stream: ComisionViajePctService.streamPorcentajeVigente(),
            initialData: PlataformaEconomia.comisionViajePorcentaje,
            builder: (context, pctSnap) {
              final c = pctSnap.data ?? PlataformaEconomia.comisionViajePorcentaje;
              return Column(
                children: [
                  _tile(
                    context,
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Billetera',
                    subtitle: _subtituloRepartoComision(c),
                    page: const BilleteraTaxista(),
                  ),
                  _tile(
                    context,
                    icon: Icons.monetization_on_outlined,
                    title: 'Ganancias',
                    subtitle: _subtituloGananciasComision(c),
                    page: const GananciaTaxista(),
                  ),
                ],
              );
            },
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
            icon: Icons.location_on_outlined,
            title: 'Ubicación',
            subtitle: 'Permisos GPS y ajustes del teléfono',
            page: const RaiUbicacionAjustesPage(rol: RaiUbicacionRol.taxista),
          ),
          _tile(
            context,
            icon: Icons.person_outline,
            title: 'Configuración de perfil',
            subtitle: 'Foto y nombre',
            page: const ConfiguracionPerfil(),
          ),
          const CuentaLegalTiles(),
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
          const CuentaAparienciaTile(audience: AparienciaAudience.taxista),
          if (uid != null) const CuentaCerrarSesionTile(),
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
