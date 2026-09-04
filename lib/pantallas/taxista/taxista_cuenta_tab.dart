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
import 'package:flygo_nuevo/servicios/rai_cambio_modo_sesion.dart';
import 'package:flygo_nuevo/servicios/taxista_promociones_ui.dart';
import 'package:flygo_nuevo/servicios/theme_mode_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/widgets/avatar_circle.dart';
import 'package:flygo_nuevo/widgets/configuracion_bancaria.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_taxista_service.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_ui_constants.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_config_panel.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_rol.dart';
import 'package:flygo_nuevo/widgets/rai_driver_ui.dart';

String _pctLabel(double p) =>
    p == p.roundToDouble() ? p.round().toString() : p.toStringAsFixed(1);

String _subtituloRepartoComision(double c) {
  final t = 100.0 - c;
  return 'Saldo ${_pctLabel(t)} %, comisión ${_pctLabel(c)} %';
}

String _subtituloGananciasComision(double c) {
  final t = 100.0 - c;
  return 'Calle + corporativo · ${_pctLabel(t)}/${_pctLabel(c)}';
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
  if (tipoServicio.isNotEmpty) {
    lineas.add('Servicio: ${_labelServicio(tipoServicio)}');
  }
  if (tipoVehiculo.isNotEmpty) lineas.add('Vehículo: $tipoVehiculo');
  if (placa.isNotEmpty) lineas.add('Placa: $placa');

  final String marcaModelo =
      [marca, modelo].where((v) => v.isNotEmpty).join(' ');
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

void _openPage(BuildContext context, Widget page) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(builder: (_) => page),
  );
}

/// Finanzas, documentos y ajustes de cuenta.
class TaxistaCuentaTab extends StatelessWidget {
  const TaxistaCuentaTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = cs.primary;
    final accentSoft = accent.withValues(alpha: isDark ? 0.18 : 0.12);

    return RaiDriverTabScaffold(
      title: 'Cuenta',
      subtitle: 'Perfil, finanzas y ajustes',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          16,
          0,
          16,
          28 + kRaiCambioModoSesionPaddingLista,
        ),
        children: [
          if (uid == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Inicia sesión.'),
            )
          else ...[
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? const <String, dynamic>{};
                final nombre = (() {
                  final n = (data['nombre'] as String?)?.trim();
                  if (n != null && n.isNotEmpty) return n;
                  final dn = user?.displayName?.trim();
                  return (dn != null && dn.isNotEmpty) ? dn : 'Conductor';
                })();
                final foto = (() {
                  final f = (data['fotoUrl'] as String?)?.trim();
                  if (f != null && f.isNotEmpty) return f;
                  final fu = user?.photoURL?.trim();
                  return (fu != null && fu.isNotEmpty) ? fu : null;
                })();
                final tipoServicio =
                    (data['tipoServicio'] ?? '').toString().trim();
                final placa = (data['placa'] ?? '').toString().trim();
                final bloqueadoPago = data['tienePagoPendiente'] == true;
                final textoPerfil = _textoPerfilTaxista(
                  data,
                  fallbackEmail: user?.email ?? '',
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CuentaHeroCard(
                      nombre: nombre,
                      email: user?.email,
                      fotoUrl: foto,
                      tipoServicio: tipoServicio,
                      placa: placa,
                      accent: accent,
                      isDark: isDark,
                      onEditarPerfil: () => _openPage(
                        context,
                        const ConfiguracionPerfil(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _CuentaEstadoBanner(
                      bloqueado: bloqueadoPago,
                      onMisPagos: () => _openPage(
                        context,
                        const MisPagos(scrollToRecargaSection: true),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _CuentaPerfilExpandible(
                      texto: textoPerfil,
                      accent: accent,
                      isDark: isDark,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            StreamBuilder<double>(
              stream: ComisionViajePctService.streamPorcentajeVigente(),
              initialData: PlataformaEconomia.comisionViajePorcentaje,
              builder: (context, pctSnap) {
                final double pctCom = pctSnap.data ??
                    PlataformaEconomia.comisionViajePorcentaje;
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('billeteras_taxista')
                      .doc(uid)
                      .snapshots(),
                  builder: (context, snap) {
                    final data =
                        snap.data?.data() ?? const <String, dynamic>{};
                    final saldo = PagosTaxistaRepo
                        .saldoPrepagoComisionDesdeBilletera(data);
                    final legacyPendiente =
                        PagosTaxistaRepo.comisionPendienteDesdeBilletera(data);
                    final bloqueado = PagosTaxistaRepo
                        .bloqueoOperativoPorComisionEfectivo(data);
                    final minimo = PagosTaxistaRepo.minSaldoPrepagoComisionRd;
                    const metaVisual = 500.0;
                    final progreso = (saldo / metaVisual).clamp(0.0, 1.0);
                    final faltante =
                        (minimo - saldo).clamp(0.0, double.infinity);

                    return _CuentaSaldoCard(
                      saldo: saldo,
                      bloqueado: bloqueado,
                      progreso: progreso,
                      faltante: faltante,
                      pctCom: pctCom,
                      legacyPendiente: legacyPendiente,
                      accent: accent,
                      isDark: isDark,
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: CuentaOpenAskDepositoPanel(mostrarNota: true),
            ),
            TaxistaCuentaIncentivoPanel(uidTaxista: uid),
            const SizedBox(height: 8),
            StreamBuilder<double>(
              stream: ComisionViajePctService.streamPorcentajeVigente(),
              initialData: PlataformaEconomia.comisionViajePorcentaje,
              builder: (context, pctSnap) {
                final c = pctSnap.data ??
                    PlataformaEconomia.comisionViajePorcentaje;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CuentaSection(
                      title: 'Dinero y prepago',
                      children: [
                        _CuentaMenuRow(
                          icon: Icons.payment_rounded,
                          iconBg: accentSoft,
                          iconFg: accent,
                          title: 'Mis pagos',
                          subtitle:
                              'Recarga, bauche y estado de tu cuenta operativa',
                          onTap: () => _openPage(
                            context,
                            const MisPagos(scrollToRecargaSection: true),
                          ),
                        ),
                        _CuentaMenuRow(
                          icon: Icons.account_balance_wallet_rounded,
                          iconBg: const Color(0xFF0D9488).withValues(alpha: 0.14),
                          iconFg: const Color(0xFF0D9488),
                          title: 'Billetera',
                          subtitle: _subtituloRepartoComision(c),
                          onTap: () =>
                              _openPage(context, const BilleteraTaxista()),
                        ),
                        _CuentaMenuRow(
                          icon: Icons.trending_up_rounded,
                          iconBg: const Color(0xFF2563EB).withValues(alpha: 0.14),
                          iconFg: const Color(0xFF2563EB),
                          title: 'Ganancias',
                          subtitle: _subtituloGananciasComision(c),
                          onTap: () =>
                              _openPage(context, const GananciaTaxista()),
                        ),
                        _CuentaMenuRow(
                          icon: Icons.receipt_long_rounded,
                          iconBg: const Color(0xFF7C3AED).withValues(alpha: 0.14),
                          iconFg: const Color(0xFF7C3AED),
                          title: 'Recargas y comprobantes',
                          subtitle:
                              'Cuenta bancaria, foto del bauche e historial',
                          onTap: () => _openPage(context, const MisPagos()),
                        ),
                        _CuentaMenuRow(
                          icon: Icons.account_balance_rounded,
                          iconBg: const Color(0xFF0891B2).withValues(alpha: 0.14),
                          iconFg: const Color(0xFF0891B2),
                          title: 'Datos bancarios',
                          subtitle: 'Banco y cuenta para transferencias',
                          onTap: () => _openPage(
                            context,
                            const ConfiguracionBancaria(),
                          ),
                          showDivider: false,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            _CuentaSection(
              title: 'Promociones',
              children: [
                _CuentaMenuRow(
                  icon: Icons.local_offer_rounded,
                  iconBg: const Color(0xFFEA580C).withValues(alpha: 0.14),
                  iconFg: const Color(0xFFEA580C),
                  title: 'Promociones y comisión',
                  subtitle: 'Comisión RAI vigente y promo M×K para clientes',
                  onTap: () => _openPage(
                    context,
                    const TaxistaPromocionesScreen(),
                  ),
                  showDivider: false,
                ),
              ],
            ),
            _CuentaSection(
              title: 'Mi trabajo',
              children: [
                _CuentaMenuRow(
                  icon: Icons.history_rounded,
                  iconBg: const Color(0xFF4F46E5).withValues(alpha: 0.14),
                  iconFg: const Color(0xFF4F46E5),
                  title: 'Historial de viajes',
                  subtitle: 'Viajes completados y cancelados',
                  onTap: () => _openPage(
                    context,
                    const HistorialViajesTaxista(),
                  ),
                ),
                _CuentaMenuRow(
                  icon: Icons.folder_open_rounded,
                  iconBg: const Color(0xFF059669).withValues(alpha: 0.14),
                  iconFg: const Color(0xFF059669),
                  title: 'Documentos',
                  subtitle: 'Licencia, cédula, seguro',
                  onTap: () =>
                      _openPage(context, const DocumentosTaxista()),
                  showDivider: false,
                ),
              ],
            ),
            _CuentaSection(
              title: 'Ayuda',
              children: [
                _CuentaMenuRow(
                  icon: Icons.headset_mic_rounded,
                  iconBg: const Color(0xFFDB2777).withValues(alpha: 0.14),
                  iconFg: const Color(0xFFDB2777),
                  title: 'Soporte',
                  subtitle: 'Escríbenos si necesitas ayuda',
                  onTap: () => _openPage(context, const Soporte()),
                  showDivider: false,
                ),
              ],
            ),
            _CuentaSection(
              title: 'Ajustes',
              children: [
                ValueListenableBuilder<RaiUbicacionTaxistaModo>(
                  valueListenable: RaiUbicacionTaxistaService.instance.modo,
                  builder: (context, modo, _) {
                    final listo =
                        modo == RaiUbicacionTaxistaModo.listo;
                    return _CuentaMenuRow(
                      icon: Icons.location_on_rounded,
                      iconBg: const Color(0xFF16A34A).withValues(alpha: 0.14),
                      iconFg: listo
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFDC2626),
                      title: 'Ubicación',
                      subtitle: listo
                          ? RaiUbicacionUiConstants
                              .subtituloConfigUbicacionActiva
                          : 'Permisos GPS y ajustes del teléfono',
                      onTap: () => _openPage(
                        context,
                        const RaiUbicacionAjustesPage(
                          rol: RaiUbicacionRol.taxista,
                        ),
                      ),
                    );
                  },
                ),
                _CuentaMenuRow(
                  icon: Icons.person_rounded,
                  iconBg: accentSoft,
                  iconFg: accent,
                  title: 'Configuración de perfil',
                  subtitle: 'Foto, nombre y datos visibles',
                  onTap: () =>
                      _openPage(context, const ConfiguracionPerfil()),
                  showDivider: false,
                ),
              ],
            ),
            const SizedBox(height: 4),
            const CuentaLegalTiles(),
            _CuentaSection(
              title: 'Apariencia',
              children: [
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: ThemeModeService.mode,
                  builder: (context, mode, _) {
                    final isLight = mode == ThemeMode.light;
                    return _CuentaSwitchRow(
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
            const CuentaAparienciaTile(audience: AparienciaAudience.taxista),
            const CuentaCerrarSesionTile(),
          ],
        ],
      ),
    );
  }
}

class _CuentaHeroCard extends StatelessWidget {
  const _CuentaHeroCard({
    required this.nombre,
    required this.email,
    required this.fotoUrl,
    required this.tipoServicio,
    required this.placa,
    required this.accent,
    required this.isDark,
    required this.onEditarPerfil,
  });

  final String nombre;
  final String? email;
  final String? fotoUrl;
  final String tipoServicio;
  final String placa;
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
                  RaiDsColors.card,
                  RaiDsColors.neon.withValues(alpha: 0.12),
                ]
              : [
                  Colors.white,
                  accent.withValues(alpha: 0.08),
                ],
        ),
        border: Border.all(
          color: isDark
              ? RaiDsColors.border
              : accent.withValues(alpha: 0.22),
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
                name: nombre.isEmpty ? 'Conductor' : nombre,
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
                    if (email != null && email!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        email!,
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
          if (tipoServicio.isNotEmpty || placa.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (tipoServicio.isNotEmpty)
                  _CuentaChip(
                    label: _labelServicio(tipoServicio.toLowerCase()),
                    icon: Icons.directions_car_filled_outlined,
                    accent: accent,
                  ),
                if (placa.isNotEmpty)
                  _CuentaChip(
                    label: placa.toUpperCase(),
                    icon: Icons.pin_outlined,
                    accent: accent,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CuentaChip extends StatelessWidget {
  const _CuentaChip({
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

class _CuentaEstadoBanner extends StatelessWidget {
  const _CuentaEstadoBanner({
    required this.bloqueado,
    required this.onMisPagos,
  });

  final bool bloqueado;
  final VoidCallback onMisPagos;

  @override
  Widget build(BuildContext context) {
    final color = bloqueado ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onMisPagos,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  bloqueado
                      ? Icons.lock_clock_rounded
                      : Icons.verified_user_rounded,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bloqueado
                          ? 'Cuenta bloqueada por recarga'
                          : 'Cuenta operativa',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bloqueado
                          ? 'Recarga y sube el bauche para habilitar viajes y pool.'
                          : 'Abrí Mis pagos para ver banco, monto y comprobante.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _CuentaPerfilExpandible extends StatelessWidget {
  const _CuentaPerfilExpandible({
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

class _CuentaSaldoCard extends StatelessWidget {
  const _CuentaSaldoCard({
    required this.saldo,
    required this.bloqueado,
    required this.progreso,
    required this.faltante,
    required this.pctCom,
    required this.legacyPendiente,
    required this.accent,
    required this.isDark,
  });

  final double saldo;
  final bool bloqueado;
  final double progreso;
  final double faltante;
  final double pctCom;
  final double legacyPendiente;
  final Color accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final estadoColor =
        bloqueado ? const Color(0xFFDC2626) : const Color(0xFF16A34A);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121A2B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: estadoColor.withValues(alpha: bloqueado ? 0.45 : 0.25),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
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
                color: bloqueado ? estadoColor : accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Crédito de recarga',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: estadoColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  bloqueado ? 'BLOQUEADO' : 'ACTIVO',
                  style: TextStyle(
                    color: estadoColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            FormatosMoneda.rd(saldo),
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Saldo actual en tiempo real',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progreso,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(estadoColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('RD\$ 0', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
              Text('RD\$ 200', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
              Text('RD\$ 500+', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Comisión vigente en efectivo: ${TaxistaPromocionesUi.pctLabel(pctCom)}% '
            '(se descuenta del prepago al finalizar cada viaje).',
            style: TextStyle(
              color: accent,
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
  }
}

class _CuentaSection extends StatelessWidget {
  const _CuentaSection({
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

class _CuentaMenuRow extends StatelessWidget {
  const _CuentaMenuRow({
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

class _CuentaSwitchRow extends StatelessWidget {
  const _CuentaSwitchRow({
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
