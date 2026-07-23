// ignore_for_file: avoid_print -- logs depuración recarga comisión (bauche / Firestore)

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../modelo/liquidacion_semanal.dart';
import '../../modelo/recarga_comision_taxista.dart';
import '../../modelo/pago_taxista.dart';
import '../../servicios/analytics_rai.dart';
import '../../servicios/finance_config_service.dart';
import '../../servicios/liquidacion_semanal_repo.dart';
import '../../servicios/pagos_taxista_repo.dart';
import '../../servicios/rai_local_read_cache.dart';
import '../../servicios/comision_prepago_config_service.dart';
import '../../widgets/configuracion_bancaria.dart';
import '../../widgets/cuenta_open_ask_deposito_panel.dart';
import '../../widgets/rai_offline_banner.dart';
import '../../widgets/taxista_credito_rai_monedero.dart';

Widget _pasoRecarga(
  ColorScheme cs, {
  required int numero,
  required String titulo,
  required String detalle,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleAvatar(
        radius: 14,
        backgroundColor: cs.primary.withValues(alpha: 0.22),
        foregroundColor: cs.primary,
        child: Text(
          '$numero',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detalle,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Aviso si faltan datos bancarios para que el cliente pueda transferir en viajes.
class _AvisoPerfilBancarioTransferencia extends StatelessWidget {
  const _AvisoPerfilBancarioTransferencia({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .snapshots(),
      builder: (
        BuildContext context,
        AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snap,
      ) {
        if (!snap.hasData) return const SizedBox.shrink();
        final Map<String, dynamic>? data = snap.data?.data();
        if (PagosTaxistaRepo.perfilBancarioTransferenciaCompleto(data)) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Material(
            color: Colors.orange.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const ConfiguracionBancaria(),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.account_balance_outlined,
                        color: Colors.orangeAccent, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Completa tu cuenta bancaria',
                            style: TextStyle(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Si aceptás viajes por transferencia, el cliente necesita ver '
                            'tu banco, número de cuenta y titular. Completá esos datos '
                            'antes de tomar ese tipo de viajes.',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tocá aquí para ir a Datos bancarios',
                            style: TextStyle(
                              color: Colors.orangeAccent.shade200,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class MisPagos extends StatefulWidget {
  const MisPagos({
    super.key,
    /// Desde Cuenta: abre Mis pagos y desplaza a la sección de recarga (sin abrir galería/cámara sola).
    this.scrollToRecargaSection = false,
  });
  final bool scrollToRecargaSection;

  @override
  State<MisPagos> createState() => _MisPagosState();
}

class _MisPagosState extends State<MisPagos> {
  final user = FirebaseAuth.instance.currentUser;
  final formatter = NumberFormat.currency(locale: 'es', symbol: 'RD\$');
  final dateFormat = DateFormat('dd/MM/yyyy');
  final GlobalKey _recargaSeccionKey = GlobalKey();
  bool _scrollRecargaAgendado = false;
  StreamSubscription<List<RecargaComisionTaxista>>? _recargasAnalyticsSub;

  /// Solo para analytics: transición a `pagado` (aprobación admin).
  final Map<String, String> _prevEstadoRecargaPorId = <String, String>{};

  void _detectRecargaAprobadaAnalytics(List<RecargaComisionTaxista> list) {
    for (final r in list) {
      final prev = _prevEstadoRecargaPorId[r.id];
      _prevEstadoRecargaPorId[r.id] = r.estado;
      if (r.estado == 'pagado' && prev != null && prev != 'pagado') {
        unawaited(AnalyticsRai.logRechargeApproved());
      }
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(FinanceConfigService.ensureStarted());
    final String? uid = user?.uid;
    if (uid != null && uid.trim().isNotEmpty) {
      unawaited(PagosTaxistaRepo.sincronizarBloqueoOperativo(uid.trim()));
      _recargasAnalyticsSub =
          PagosTaxistaRepo.streamRecargasComisionPorTaxista(uid.trim()).listen(
        _detectRecargaAprobadaAnalytics,
      );
    }
    if (widget.scrollToRecargaSection) {
      void tryScroll() {
        if (!mounted || _scrollRecargaAgendado) return;
        final ctx = _recargaSeccionKey.currentContext;
        if (ctx != null) {
          _scrollRecargaAgendado = true;
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.06,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
          );
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        tryScroll();
        WidgetsBinding.instance.addPostFrameCallback((_) => tryScroll());
      });
      Future<void>.delayed(const Duration(milliseconds: 550), tryScroll);
    }
  }

  @override
  void dispose() {
    _recargasAnalyticsSub?.cancel();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _cargarDetallesViajesPago(
      List<String> viajeIds) async {
    final ids = viajeIds.where((e) => e.trim().isNotEmpty).take(200).toList();
    if (ids.isEmpty) return const <Map<String, dynamic>>[];

    final snaps = await Future.wait(
      ids.map((id) => FirebaseFirestore.instance.collection('viajes').doc(id).get()),
    );

    final out = <Map<String, dynamic>>[];
    for (final s in snaps) {
      if (!s.exists) continue;
      final d = s.data() ?? <String, dynamic>{};
      out.add(<String, dynamic>{
        'id': s.id,
        'estado': (d['estado'] ?? '').toString(),
        'origen': (d['origen'] ?? d['origenNombre'] ?? '').toString(),
        'destino': (d['destino'] ?? d['destinoNombre'] ?? '').toString(),
        'precio': d['precio'] ?? d['precioFinal'] ?? d['total'] ?? 0,
      });
    }
    return out;
  }

  Future<void> _mostrarLineasLiquidacionSemanal(LiquidacionSemanal liq) async {
    final snap = await FirebaseFirestore.instance
        .collection('liquidaciones_semanales')
        .doc(liq.id)
        .collection('lineas')
        .get();
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Viajes ${liq.periodo}'),
        content: SizedBox(
          width: double.maxFinite,
          child: snap.docs.isEmpty
              ? const Text('Sin líneas de detalle')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: snap.docs.length,
                  itemBuilder: (_, i) {
                    final d = snap.docs[i].data();
                    final metodo =
                        (d['metodoPagoNormalizado'] ?? '').toString();
                    final neto =
                        ((d['gananciaCents'] as num?)?.toInt() ?? 0) / 100.0;
                    return ListTile(
                      dense: true,
                      title: Text(
                        '${metodo.isEmpty ? 'viaje' : metodo} · ${formatter.format(neto)}',
                        style: TextStyle(color: cs.onSurface, fontSize: 13),
                      ),
                      subtitle: Text(
                        'Estado: ${(d['estadoViajeSnapshot'] ?? '').toString()}',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionPagoSemanal(ColorScheme cs) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('config')
          .doc('finance')
          .snapshots(),
      builder: (context, cfgSnap) {
        final useLiq =
            cfgSnap.data?.data()?['useLiquidacionesSemanales'] == true;
        if (useLiq) {
          return _buildLiquidacionesSemanalesTaxista(cs);
        }
        return _buildPagosTaxistasLegacy(cs);
      },
    );
  }

  Widget _buildLiquidacionesSemanalesTaxista(ColorScheme cs) {
    return StreamBuilder<List<LiquidacionSemanal>>(
      stream: LiquidacionSemanalRepo.streamPorTaxista(user!.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: CircularProgressIndicator(color: cs.primary),
            ),
          );
        }
        final list = snapshot.data ?? const <LiquidacionSemanal>[];
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No tienes liquidaciones semanales registradas',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          );
        }
        final LiquidacionSemanal pendiente = list.firstWhere(
          (l) => l.esPendiente,
          orElse: () => list.first,
        );
        return Column(
          children: [
            if (pendiente.esPendiente)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: pendiente.estado == 'borrador'
                          ? Colors.amber.withValues(alpha: 0.12)
                          : Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: pendiente.estado == 'borrador'
                            ? Colors.amber
                            : Colors.blue,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          pendiente.estado == 'borrador'
                              ? Icons.account_balance_outlined
                              : Icons.schedule,
                          color: pendiente.estado == 'borrador'
                              ? Colors.amber
                              : Colors.blue,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          pendiente.estado == 'borrador'
                              ? 'LIQUIDACIÓN EN BORRADOR'
                              : 'PAGO SEMANAL PENDIENTE',
                          style: TextStyle(
                            color: pendiente.estado == 'borrador'
                                ? Colors.amber.shade800
                                : Colors.blue,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Periodo: ${pendiente.periodo}',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                        Text(
                          '${dateFormat.format(pendiente.periodoInicio)} - ${dateFormat.format(pendiente.periodoFin)}',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Neto a recibir: ${formatter.format(pendiente.totalNetoRd)}',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (pendiente.estado == 'borrador') ...[
                          const SizedBox(height: 12),
                          Text(
                            'Completa tu cuenta bancaria para que admin pueda procesar el ACH.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'HISTORIAL DE LIQUIDACIONES',
                      style: TextStyle(
                        color: cs.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final liq = list[index];
                    Color estadoColor;
                    String estadoText;
                    IconData estadoIcon;
                    switch (liq.estado) {
                      case 'pagado':
                        estadoColor = Colors.green;
                        estadoText = 'PAGADO';
                        estadoIcon = Icons.check_circle;
                        break;
                      case 'pendiente_pago':
                        estadoColor = Colors.blue;
                        estadoText = 'PENDIENTE';
                        estadoIcon = Icons.schedule;
                        break;
                      case 'borrador':
                        estadoColor = Colors.amber;
                        estadoText = 'BORRADOR';
                        estadoIcon = Icons.edit_note;
                        break;
                      case 'cancelado':
                        estadoColor = Colors.red.shade900;
                        estadoText = 'CANCELADO';
                        estadoIcon = Icons.cancel;
                        break;
                      default:
                        estadoColor = cs.outline;
                        estadoText = liq.estado.toUpperCase();
                        estadoIcon = Icons.help;
                    }
                    return Card(
                      color: cs.surfaceContainerHighest.withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.55
                            : 0.65,
                      ),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  estadoColor.withValues(alpha: 0.2),
                              radius: 20,
                              child: Icon(estadoIcon,
                                  color: estadoColor, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Semana ${liq.periodo}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: cs.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${liq.viajesCount} viajes',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'Transf. ${formatter.format(liq.totalesPorMetodo.transferencia.totalNetoRd)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  Text(
                                    'Tarj. ${formatter.format(liq.totalesPorMetodo.tarjeta.totalNetoRd)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  if (liq.viajeIds.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            _mostrarLineasLiquidacionSemanal(
                                                liq),
                                        icon: const Icon(Icons.list_alt,
                                            size: 18),
                                        label: Text(
                                            'Ver viajes (${liq.viajeIds.length})'),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 92,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      formatter.format(liq.totalNetoRd),
                                      style: TextStyle(
                                        color: estadoColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          estadoColor.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      estadoText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: estadoColor,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
      },
    );
  }

  Widget _buildPagosTaxistasLegacy(ColorScheme cs) {
    return StreamBuilder<List<PagoTaxista>>(
      stream: PagosTaxistaRepo.streamPagosPorTaxista(user!.uid),
      builder: (BuildContext context, AsyncSnapshot<List<PagoTaxista>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: CircularProgressIndicator(color: cs.primary),
            ),
          );
        }

        final List<PagoTaxista> pagos = snapshot.data ?? [];

        if (pagos.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No tienes pagos semanales registrados',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          );
        }

        final PagoTaxista pendiente = pagos.firstWhere(
          (PagoTaxista p) =>
              p.estado == 'pendiente' || p.estado == 'pendiente_verificacion',
          orElse: () => pagos.first,
        );

        return _buildPagosTaxistasLegacyBody(cs, pagos, pendiente);
      },
    );
  }

  Widget _buildPagosTaxistasLegacyBody(
    ColorScheme cs,
    List<PagoTaxista> pagos,
    PagoTaxista pendiente,
  ) {
    return Column(
      children: <Widget>[
        if (pendiente.estado == 'pendiente' ||
            pendiente.estado == 'pendiente_verificacion')
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: pendiente.estado == 'pendiente_verificacion'
                  ? Colors.orange.withValues(alpha: 0.1)
                  : Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: pendiente.estado == 'pendiente_verificacion'
                    ? Colors.orange
                    : Colors.red,
                width: 2,
              ),
            ),
            child: Column(
              children: <Widget>[
                Icon(
                  pendiente.estado == 'pendiente_verificacion'
                      ? Icons.hourglass_top
                      : Icons.warning_amber_rounded,
                  color: pendiente.estado == 'pendiente_verificacion'
                      ? Colors.orange
                      : Colors.red,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  pendiente.estado == 'pendiente_verificacion'
                      ? 'COMPROBANTE EN REVISIÓN'
                      : 'PAGO PENDIENTE',
                  style: TextStyle(
                    color: pendiente.estado == 'pendiente_verificacion'
                        ? Colors.orange
                        : Colors.red,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Semana: ${pendiente.semana}',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                Text(
                  'Período: ${dateFormat.format(pendiente.fechaInicio)} - ${dateFormat.format(pendiente.fechaFin)}',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Text(
                  'Total a pagar: ${formatter.format(pendiente.comision)}',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Transferí el total a la cuenta Open ASK de arriba antes de subir el comprobante.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                if (pendiente.estado == 'pendiente')
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _subirComprobante(pendiente.id),
                      icon: Icon(Icons.upload_file, color: cs.onPrimary),
                      label: const Text('SUBIR COMPROBANTE DE PAGO'),
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                if (pendiente.estado == 'pendiente_verificacion')
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.info, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tu comprobante está siendo revisado por el administrador',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'HISTORIAL DE PAGOS',
              style: TextStyle(
                color: cs.primary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: pagos.length,
          itemBuilder: (BuildContext context, int index) {
            final PagoTaxista pago = pagos[index];
            Color estadoColor;
            String estadoText;
            IconData estadoIcon;
            switch (pago.estado) {
              case 'pagado':
                estadoColor = Colors.green;
                estadoText = 'PAGADO';
                estadoIcon = Icons.check_circle;
                break;
              case 'pendiente_verificacion':
                estadoColor = Colors.orange;
                estadoText = 'EN REVISIÓN';
                estadoIcon = Icons.hourglass_top;
                break;
              case 'pendiente':
                estadoColor = Colors.red;
                estadoText = 'PENDIENTE';
                estadoIcon = Icons.warning;
                break;
              case 'rechazado':
                estadoColor = Colors.red.shade900;
                estadoText = 'RECHAZADO';
                estadoIcon = Icons.cancel;
                break;
              default:
                estadoColor = cs.outline;
                estadoText = pago.estado.toUpperCase();
                estadoIcon = Icons.help;
            }
            return Card(
              color: cs.surfaceContainerHighest.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.55
                    : 0.65,
              ),
              margin: const EdgeInsets.only(bottom: 8),
              elevation: Theme.of(context).brightness == Brightness.dark
                  ? 1
                  : 0.5,
              shadowColor: cs.shadow.withValues(alpha: 0.15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: estadoColor.withValues(alpha: 0.2),
                      radius: 20,
                      child:
                          Icon(estadoIcon, color: estadoColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Semana ${pago.semana}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${pago.viajesSemana} viajes',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            '${dateFormat.format(pago.fechaInicio)} - ${dateFormat.format(pago.fechaFin)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                              fontSize: 11,
                            ),
                          ),
                          if (pago.viajesLiquidados.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () => _mostrarViajesLiquidados(pago),
                                icon: const Icon(Icons.list_alt, size: 18),
                                label: Text(
                                  'Ver viajes (${pago.viajesLiquidados.length})',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 92,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              formatter.format(pago.comision),
                              style: TextStyle(
                                color: estadoColor,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: estadoColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              estadoText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: estadoColor,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _mostrarViajesLiquidados(PagoTaxista pago) async {
    final ids = pago.viajesLiquidados.take(200).toList(growable: false);
    if (ids.isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: cs.surfaceContainerHigh,
          title: Text(
            'Viajes liquidados (${ids.length})',
            style: TextStyle(color: cs.onSurface),
          ),
          content: SizedBox(
            width: 560,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _cargarDetallesViajesPago(ids),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return SelectableText(
                    'No se pudieron cargar detalles. IDs:\n${ids.join('\n')}',
                    style: TextStyle(color: cs.onSurface),
                  );
                }
                final viajes = snapshot.data ?? const <Map<String, dynamic>>[];
                if (viajes.isEmpty) {
                  return SelectableText(
                    ids.join('\n'),
                    style: TextStyle(color: cs.onSurface),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: viajes.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (context, index) {
                    final v = viajes[index];
                    final precioRaw = v['precio'];
                    final precio = precioRaw is num
                        ? precioRaw.toDouble()
                        : double.tryParse('$precioRaw') ?? 0;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'ID: ${v['id']}',
                        style: TextStyle(color: cs.onSurface, fontSize: 12),
                      ),
                      subtitle: Text(
                        '${v['origen']} -> ${v['destino']}\nEstado: ${v['estado']} | Precio: ${formatter.format(precio)}',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _subirComprobante(String pagoId) async {
    final TextEditingController urlCtrl = TextEditingController();
    String metodo = 'transferencia';
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dcs = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setStateModal) => AlertDialog(
            backgroundColor: dcs.surfaceContainerHigh,
            title: Text(
              'Enviar comprobante',
              style: TextStyle(color: dcs.onSurface),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(metodo),
                  initialValue: metodo,
                  dropdownColor: dcs.surfaceContainerHighest,
                  style: TextStyle(color: dcs.onSurface),
                  decoration: InputDecoration(
                    labelText: 'Método de pago',
                    labelStyle: TextStyle(color: dcs.onSurfaceVariant),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'transferencia', child: Text('Transferencia')),
                    DropdownMenuItem(
                        value: 'efectivo', child: Text('Efectivo')),
                    DropdownMenuItem(value: 'tarjeta', child: Text('Tarjeta')),
                  ],
                  onChanged: (v) => setStateModal(() => metodo = v ?? metodo),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: urlCtrl,
                  style: TextStyle(color: dcs.onSurface),
                  cursorColor: dcs.primary,
                  decoration: InputDecoration(
                    labelText: 'URL del comprobante',
                    hintText: 'https://...',
                    labelStyle: TextStyle(color: dcs.onSurfaceVariant),
                    hintStyle: TextStyle(
                        color: dcs.onSurfaceVariant.withValues(alpha: 0.8)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancelar', style: TextStyle(color: dcs.primary)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enviar'),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true) return;
    final url = urlCtrl.text.trim();
    if (url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes indicar la URL del comprobante')),
      );
      return;
    }
    try {
      await PagosTaxistaRepo.subirComprobante(
        pagoId: pagoId,
        comprobanteUrl: url,
        metodoPago: metodo,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Comprobante enviado para revisión'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar comprobante: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (user == null) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: Center(
          child: Text(
            'No hay sesión activa',
            style: TextStyle(color: cs.onSurface),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: cs.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Text(
          'Mis Pagos',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: Builder(
        builder: (context) {
          final mq = MediaQuery.of(context);
          // Espacio generoso abajo para barra del sistema + shell + pulgar; evita que los botones
          // de recarga queden fuera del área desplazable.
          final double scrollBottomPad =
              28 + mq.viewInsets.bottom + mq.padding.bottom + 96;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(bottom: scrollBottomPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                  RaiOfflineBanner(uid: user?.uid),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: CuentaOpenAskDepositoPanel(),
                  ),
                  _AvisoPerfilBancarioTransferencia(uid: user!.uid),
                  KeyedSubtree(
                    key: _recargaSeccionKey,
                    child: _PanelRecargaComisionEfectivo(
                      user: user!,
                      formatter: formatter,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      'Viajes en efectivo usan tu crédito RAI. '
                      'Transferencias y tarjetas se liquidan en el pago semanal.',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                  _buildSeccionPagoSemanal(cs),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Recarga por comisión de viajes en efectivo: sube comprobante y queda en cola del admin.
class _PanelRecargaComisionEfectivo extends StatefulWidget {
  final User user;
  final NumberFormat formatter;

  const _PanelRecargaComisionEfectivo({
    required this.user,
    required this.formatter,
  });

  @override
  State<_PanelRecargaComisionEfectivo> createState() =>
      _PanelRecargaComisionEfectivoState();
}

class _PanelRecargaComisionEfectivoState
    extends State<_PanelRecargaComisionEfectivo> {
  static const List<double> _montosSugeridos = <double>[200, 500, 700];
  final TextEditingController _montoCtrl = TextEditingController();
  bool _subiendo = false;
  bool _enviando = false;
  String? _comprobanteUrl;
  double? _montoElegidoRd;
  double? _lastSaldoPrepagoCached;

  @override
  void initState() {
    super.initState();
    unawaited(ComisionPrepagoConfigService.ensureStarted());
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _elegirOrigenYSubirComprobante() async {
    if (_subiendo) return;
    print('[MisPagos][RecargaComision] Abriendo bottom sheet galería/cámara');
    final ImageSource? origen = await showModalBottomSheet<ImageSource>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      barrierColor: Colors.black.withValues(alpha: 0.54),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final dcs = Theme.of(ctx).colorScheme;
        final bottomInset =
            MediaQuery.viewPaddingOf(ctx).bottom + MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Subir foto del comprobante',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: dcs.onSurface,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Solo después de haber transferido a la cuenta de arriba. '
                'Elegí si la imagen ya está en el teléfono (galería) o si preferís sacarla ahora (cámara). '
                'Podés cerrar tocando fuera, arrastrando hacia abajo o en Cancelar.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: dcs.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: dcs.outlineVariant),
                ),
                leading: Icon(Icons.photo_library_outlined, color: dcs.primary, size: 28),
                title: const Text('Galería'),
                subtitle: const Text('Elegir imagen ya guardada'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: dcs.outlineVariant),
                ),
                leading: Icon(Icons.photo_camera_outlined, color: dcs.primary, size: 28),
                title: const Text('Cámara'),
                subtitle: const Text('Tomar foto al comprobante (papel o pantalla del banco)'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
    if (origen == null) {
      print('[MisPagos][RecargaComision] Usuario canceló selección de origen');
      return;
    }
    print(
        '[MisPagos][RecargaComision] Origen elegido: ${origen == ImageSource.gallery ? "galería" : "cámara"}');
    await _subirComprobanteDesdeOrigen(origen);
  }

  Future<void> _subirComprobanteDesdeOrigen(ImageSource source) async {
    if (_subiendo) return;
    final ImagePicker picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1920,
    );
    if (file == null) {
      print('[MisPagos][RecargaComision] pickImage cancelado o sin archivo');
      return;
    }
    setState(() => _subiendo = true);
    try {
      final bytes = await file.readAsBytes();
      // Misma ruta que exige storage.rules: comprobantes/{uid}/{carpeta}/{archivo}
      final path =
          'comprobantes/${widget.user.uid}/recarga_comision/rec_${DateTime.now().millisecondsSinceEpoch}.jpg';
      print('[MisPagos][RecargaComision] Subiendo comprobante a Storage path=$path');
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      print('[MisPagos][RecargaComision] Subida OK, URL obtenida');
      if (!mounted) return;
      setState(() => _comprobanteUrl = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Comprobante listo. Revisa la vista previa y pulsa Enviar.'),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseException catch (e) {
      print(
          '[MisPagos][RecargaComision] Error Firebase al subir: ${e.code} ${e.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('No se pudo subir la foto: ${e.code} ${e.message ?? ''}')),
      );
    } catch (e) {
      print('[MisPagos][RecargaComision] Error al subir comprobante: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Future<void> _enviarSolicitud() async {
    if (_enviando) return;
    final raw = _montoCtrl.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indica un monto mayor que 0')),
      );
      return;
    }
    final monto = double.tryParse(raw) ?? 0;
    if (monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El monto debe ser mayor que 0')),
      );
      return;
    }
    if (monto > 500000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Monto demasiado alto. Revisa el valor e inténtalo de nuevo.'),
        ),
      );
      return;
    }
    if ((_comprobanteUrl ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sube la foto del comprobante primero')),
      );
      return;
    }
    final nombre = widget.user.displayName ?? widget.user.email ?? 'Taxista';
    setState(() => _enviando = true);
    try {
      print(
          '[MisPagos][RecargaComision] Enviando solicitud: monto=$monto preset=$_montoElegidoRd uid=${widget.user.uid}');
      await PagosTaxistaRepo.taxistaEnviarRecargaComisionEfectivo(
        uidTaxista: widget.user.uid,
        nombreTaxista: nombre,
        montoDeclaradoRd: monto,
        montoElegidoRd: _montoElegidoRd,
        paqueteRecarga: _montoElegidoRd != null
            ? 'preset_${_montoElegidoRd!.toStringAsFixed(0)}'
            : 'manual',
        comprobanteUrl: _comprobanteUrl!,
      );
      print('[MisPagos][RecargaComision] Solicitud guardada en Firestore OK');
      unawaited(AnalyticsRai.logRechargeRequested());
      if (!mounted) return;
      _montoCtrl.clear();
      setState(() {
        _comprobanteUrl = null;
        _montoElegidoRd = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Solicitud enviada con tu foto. El admin revisará el comprobante y, si coincide, acreditará tu saldo.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('[MisPagos][RecargaComision] Error al enviar solicitud: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('billeteras_taxista')
          .doc(widget.user.uid)
          .snapshots(),
      builder: (context, billSnap) {
        final bill = billSnap.data?.data();
        final pend = PagosTaxistaRepo.comisionPendienteDesdeBilletera(bill);
        final saldo = PagosTaxistaRepo.saldoPrepagoComisionDesdeBilletera(bill);
        final reservGiras =
            PagosTaxistaRepo.saldoReservadoParaGirasDesdeBilletera(bill);
        final disponible =
            PagosTaxistaRepo.saldoDisponiblePrepagoComisionDesdeBilletera(bill);
        if (billSnap.hasData && bill != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_lastSaldoPrepagoCached != null &&
                (saldo - _lastSaldoPrepagoCached!).abs() < 0.01) {
              return;
            }
            _lastSaldoPrepagoCached = saldo;
            unawaited(RaiLocalReadCache.rememberSaldoPrepago(
              widget.user.uid,
              saldo,
            ));
          });
        }
        final minSaldo = PagosTaxistaRepo.minSaldoPrepagoComisionRd;
        final primerViajeConsumido =
            PagosTaxistaRepo.primerViajeComisionGratisConsumido(bill);
        final bloqueoOperativo =
            PagosTaxistaRepo.bloqueoOperativoPorComisionEfectivo(bill);
        final bloqueoLegacy =
            PagosTaxistaRepo.bloqueoPorComisionLegacyTope(bill);

        return StreamBuilder<List<RecargaComisionTaxista>>(
          stream: PagosTaxistaRepo.streamRecargasComisionPorTaxista(
              widget.user.uid),
          builder: (context, recSnap) {
            final list = recSnap.data ?? [];
            final enRevision =
                list.any((r) => r.estado == 'pendiente_verificacion');

            return Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TaxistaCreditoRaiMonederoHero(
                    disponible: disponible,
                    saldoBruto: saldo,
                    reservadoGiras: reservGiras,
                    comisionLegacyPendiente: pend,
                    bloqueoOperativo: bloqueoOperativo,
                    bloqueoLegacy: bloqueoLegacy,
                    primerViajeConsumido: primerViajeConsumido,
                    formatter: widget.formatter,
                    minSaldoRd: minSaldo,
                  ),
                  const SizedBox(height: 16),
                  TaxistaCreditoRaiMovimientosRecientes(
                    uidTaxista: widget.user.uid,
                    formatter: widget.formatter,
                  ),
                  if (bloqueoLegacy) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cuánto transferir',
                            style: TextStyle(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Mínimo para desbloquear: '
                            '${widget.formatter.format(PagosTaxistaRepo.montoMinimoRecargaParaSalirBloqueoLegacyRd(pend))}.',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                          if (PagosTaxistaRepo.montoParaLiquidarLegacyCompletoRd(pend) >
                              PagosTaxistaRepo.montoMinimoRecargaParaSalirBloqueoLegacyRd(
                                      pend) +
                                  0.01) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Para dejar legacy en cero: '
                              '${widget.formatter.format(PagosTaxistaRepo.montoParaLiquidarLegacyCompletoRd(pend))}.',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (enRevision) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.hourglass_top,
                              color: Colors.orange, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Tu recarga está en revisión. No envíes otra hasta tener respuesta.',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Text(
                      'Cómo recargar (en orden)',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _pasoRecarga(
                      cs,
                      numero: 1,
                      titulo: 'Transferir al banco',
                      detalle:
                          'Usá la cuenta Open ASK de arriba (Banco Popular). '
                          'Guardá el comprobante que te da el banco o una captura clara.',
                    ),
                    const SizedBox(height: 8),
                    _pasoRecarga(
                      cs,
                      numero: 2,
                      titulo: 'Indicar el monto',
                      detalle:
                          'Escribí exactamente lo que transferiste (o tocá un monto sugerido).',
                    ),
                    const SizedBox(height: 8),
                    _pasoRecarga(
                      cs,
                      numero: 3,
                      titulo: 'Adjuntar el bauche y enviar',
                      detalle:
                          'Tocá “Adjuntar foto del bauche”: ahí elegís galería o cámara. '
                          'Revisá la vista previa y pulsá Enviar solicitud.',
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.7),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.touch_app_outlined,
                              color: cs.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Galería y cámara solo se abren al tocar “Adjuntar foto del bauche”. '
                              'Si se abrió sin querer, Cancelar o tocá fuera del recuadro.',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 11.5,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _montosSugeridos.map((m) {
                        final selected = _montoElegidoRd != null &&
                            (_montoElegidoRd! - m).abs() < 1e-6;
                        return ChoiceChip(
                          label: Text('RD\$${m.toStringAsFixed(0)}'),
                          selected: selected,
                          onSelected: (bool sel) {
                            if (!sel) return;
                            print(
                                '[MisPagos][RecargaComision] Monto preset seleccionado: $m');
                            setState(() {
                              _montoElegidoRd = m;
                              _montoCtrl.text = m.toStringAsFixed(0);
                            });
                          },
                        );
                      }).toList(growable: false),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _montoCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: cs.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Monto transferido (RD\$)',
                        labelStyle: TextStyle(color: cs.onSurfaceVariant),
                        filled: true,
                        fillColor:
                            cs.surfaceContainerHighest.withValues(alpha: 0.4),
                      ),
                      onChanged: (v) {
                        final raw = v.trim().replaceAll(',', '.');
                        final parsed = double.tryParse(raw);
                        if (parsed == null) {
                          if (_montoElegidoRd != null) {
                            setState(() => _montoElegidoRd = null);
                          }
                          return;
                        }
                        final match = _montosSugeridos.firstWhere(
                          (m) => (m - parsed).abs() < 1e-6,
                          orElse: () => -1,
                        );
                        final next = match > 0 ? match : null;
                        if (_montoElegidoRd != next) {
                          setState(() => _montoElegidoRd = next);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed:
                            _subiendo ? null : _elegirOrigenYSubirComprobante,
                        icon: _subiendo
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: cs.primary),
                              )
                            : const Icon(Icons.add_a_photo_outlined),
                        label: Text(
                          _comprobanteUrl != null
                              ? 'Cambiar foto del bauche'
                              : 'Adjuntar foto del bauche',
                        ),
                      ),
                    ),
                    if (_comprobanteUrl != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              _comprobanteUrl!,
                              width: 88,
                              height: 88,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 88,
                                height: 88,
                                color: cs.surfaceContainerHighest,
                                child: Icon(Icons.broken_image_outlined,
                                    color: cs.onSurfaceVariant),
                              ),
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return SizedBox(
                                  width: 88,
                                  height: 88,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: cs.primary,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Vista previa: esta imagen y el monto se envían al panel de administración RAI '
                              'para acreditar tu saldo prepago cuando coincida con el depósito.',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 12,
                                  height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _enviando ? null : _enviarSolicitud,
                        child: _enviando
                            ? SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: cs.onPrimary),
                              )
                            : const Text('Enviar a administración RAI'),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
