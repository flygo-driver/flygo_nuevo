import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/plataforma_economia.dart';
import '../servicios/comision_prepago_config_service.dart';
import '../servicios/taxista_prepago_ledger.dart';

/// Tarjeta principal de crédito prepago (estilo monedero simple, motor RAI intacto).
class TaxistaCreditoRaiMonederoHero extends StatelessWidget {
  const TaxistaCreditoRaiMonederoHero({
    super.key,
    required this.disponible,
    required this.saldoBruto,
    required this.reservadoGiras,
    required this.comisionLegacyPendiente,
    required this.bloqueoOperativo,
    required this.bloqueoLegacy,
    required this.primerViajeConsumido,
    required this.formatter,
    required this.minSaldoRd,
  });

  final double disponible;
  final double saldoBruto;
  final double reservadoGiras;
  final double comisionLegacyPendiente;
  final bool bloqueoOperativo;
  final bool bloqueoLegacy;
  final bool primerViajeConsumido;
  final NumberFormat formatter;
  final double minSaldoRd;

  static const double _viajeReferenciaRd = 500;

  int _viajesEstimados(double pctCom) {
    if (disponible <= 1e-6 || !primerViajeConsumido) return 0;
    final comisionRef = _viajeReferenciaRd * pctCom / 100;
    if (comisionRef <= 1e-6) return 0;
    return (disponible / comisionRef).floor();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pctCom = PlataformaEconomia.comisionViajePorcentaje;
    final pctStr = pctCom == pctCom.roundToDouble()
        ? pctCom.round().toString()
        : pctCom.toStringAsFixed(1);
    final umbralPreventivo = ComisionPrepagoConfigService.umbralPreventivoRd;
    final saldoFaltante =
        (minSaldoRd - disponible).clamp(0.0, double.infinity);
    final viajesEst = _viajesEstimados(pctCom);

    final bool alertaPreventiva = !bloqueoOperativo &&
        comisionLegacyPendiente <= 1e-6 &&
        primerViajeConsumido &&
        disponible > 1e-6 &&
        disponible < umbralPreventivo;

    final Color accent;
    final IconData statusIcon;
    final String statusLabel;
    final String statusHint;

    if (bloqueoLegacy) {
      accent = Colors.redAccent;
      statusIcon = Icons.lock_outline;
      statusLabel = 'Deuda legacy pendiente';
      statusHint =
          'Recargá para saldar la comisión anterior; el excedente queda en tu crédito.';
    } else if (bloqueoOperativo) {
      accent = Colors.redAccent;
      statusIcon = Icons.block;
      statusLabel = 'Crédito insuficiente';
      statusHint =
          'Te faltan ${formatter.format(saldoFaltante)} para el mínimo de ${formatter.format(minSaldoRd)}.';
    } else if (!primerViajeConsumido && comisionLegacyPendiente <= 1e-6) {
      accent = cs.primary;
      statusIcon = Icons.celebration_outlined;
      statusLabel = 'Primer viaje en efectivo gratis';
      statusHint =
          'Tu primer viaje en efectivo no descuenta comisión. Después aplica el $pctStr%.';
    } else if (alertaPreventiva) {
      accent = Colors.orangeAccent;
      statusIcon = Icons.warning_amber_rounded;
      statusLabel = 'Queda poco crédito';
      statusHint =
          'Recargá pronto para no quedar bloqueado al agotar el saldo.';
    } else {
      accent = Colors.greenAccent;
      statusIcon = Icons.check_circle_outline;
      statusLabel = 'Listo para operar';
      statusHint =
          'Podés tomar viajes en efectivo; cada uno descuenta ~$pctStr% del precio.';
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            cs.primaryContainer.withValues(alpha: 0.95),
            cs.surfaceContainerHighest.withValues(alpha: 0.85),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  color: cs.onPrimaryContainer, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Crédito RAI',
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: double.infinity),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: accent.withValues(alpha: 0.5)),
              ),
              child: Wrap(
                spacing: 5,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(statusIcon, size: 14, color: accent),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Disponible para viajes en efectivo',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatter.format(disponible),
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              height: 1.05,
              letterSpacing: -0.5,
            ),
          ),
          if (viajesEst > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Aprox. $viajesEst viaje${viajesEst == 1 ? '' : 's'} de RD\$${_viajeReferenciaRd.toStringAsFixed(0)} antes de recargar',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            statusHint,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              title: Text(
                'Detalle del saldo',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              iconColor: cs.onSurfaceVariant,
              collapsedIconColor: cs.onSurfaceVariant,
              children: [
                _detalleFila(context, 'Saldo prepago (bruto)', formatter.format(saldoBruto)),
                if (reservadoGiras > 1e-6)
                  _detalleFila(
                    context,
                    'Reservado para salidas',
                    formatter.format(reservadoGiras),
                  ),
                _detalleFila(
                  context,
                  'Mínimo para operar',
                  formatter.format(minSaldoRd),
                ),
                if (comisionLegacyPendiente > 1e-6)
                  _detalleFila(
                    context,
                    'Comisión legacy pendiente',
                    formatter.format(comisionLegacyPendiente),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detalleFila(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Últimos movimientos del ledger prepago (solo lectura).
class TaxistaCreditoRaiMovimientosRecientes extends StatelessWidget {
  const TaxistaCreditoRaiMovimientosRecientes({
    super.key,
    required this.uidTaxista,
    required this.formatter,
    this.limite = 6,
  });

  final String uidTaxista;
  final NumberFormat formatter;
  final int limite;

  static String _labelTipo(String tipo) {
    switch (tipo) {
      case 'recarga_prepago':
        return 'Recarga aprobada';
      case 'comision_viaje_efectivo':
        return 'Comisión viaje efectivo';
      case 'comision_bola_pueblo':
        return 'Comisión salida';
      case 'primer_efectivo_sin_descuento':
        return '1.er viaje sin cargo';
      case 'liquidacion_legacy':
        return 'Liquidación legacy';
      default:
        return tipo.isNotEmpty ? tipo : 'Movimiento';
    }
  }

  static double? _montoUi(Map<String, dynamic> m) {
    final acreditado = (m['montoAcreditadoRd'] as num?)?.toDouble();
    if (acreditado != null && acreditado > 1e-6) return acreditado;
    final desdePrepago = (m['desdePrepagoRd'] as num?)?.toDouble() ?? 0;
    if (desdePrepago > 1e-6) return -desdePrepago;
    final comision = (m['comisionTotalRd'] as num?)?.toDouble();
    if (comision != null && comision > 1e-6) return -comision;
    return null;
  }

  static String _fechaUi(dynamic ts) {
    if (ts is Timestamp) {
      return DateFormat('dd/MM HH:mm').format(ts.toDate());
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('billeteras_taxista')
          .doc(uid)
          .collection(TaxistaPrepagoLedger.subcoleccion)
          .orderBy('createdAt', descending: true)
          .limit(limite)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
              ),
            ),
          );
        }
        if (snap.hasError) return const SizedBox.shrink();

        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Últimos movimientos',
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            ...docs.map((doc) {
              final m = doc.data();
              final tipo = (m['tipo'] ?? '').toString();
              final label = _labelTipo(tipo);
              final monto = _montoUi(m);
              final fecha = _fechaUi(m['createdAt']);
              final esCredito = monto != null && monto > 0;
              final esCero = tipo == 'primer_efectivo_sin_descuento';

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      esCero
                          ? Icons.card_giftcard_outlined
                          : (esCredito
                              ? Icons.add_circle_outline
                              : Icons.remove_circle_outline),
                      size: 18,
                      color: esCero
                          ? cs.primary
                          : (esCredito ? Colors.greenAccent : cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (fecha.isNotEmpty)
                            Text(
                              fecha,
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (monto != null && !esCero)
                      Flexible(
                        child: Text(
                          monto >= 0
                              ? '+${formatter.format(monto)}'
                              : '−${formatter.format(monto.abs())}',
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                esCredito ? Colors.greenAccent : cs.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      )
                    else if (esCero)
                      Text(
                        'RD\$0',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
