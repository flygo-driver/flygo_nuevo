import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/design_system/rai_ds_theme.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/widgets/rai_driver_ui.dart';

/// Saldo prepago del conductor (misma fuente que el pool).
class AppBalanceCard extends StatefulWidget {
  const AppBalanceCard({super.key, required this.uidTaxista});

  final String uidTaxista;

  @override
  State<AppBalanceCard> createState() => _AppBalanceCardState();
}

class _AppBalanceCardState extends State<AppBalanceCard> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('billeteras_taxista')
          .doc(widget.uidTaxista)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final saldo =
            PagosTaxistaRepo.saldoPrepagoComisionDesdeBilletera(data);
        final disponible =
            PagosTaxistaRepo.saldoDisponiblePrepagoComisionDesdeBilletera(
          data,
        );
        final pendLegacy = PagosTaxistaRepo.comisionPendienteDesdeBilletera(data);
        final legacyTope = PagosTaxistaRepo.bloqueoPorComisionLegacyTope(data);
        final bloqueado =
            PagosTaxistaRepo.bloqueoOperativoPorComisionEfectivo(data);
        final ultimaComisionCents = data?['ultimaComisionCents'];
        final ultimaComisionRd = (ultimaComisionCents is num)
            ? (ultimaComisionCents.toDouble() / 100.0)
            : 0.0;
        final viajesEstimados = ultimaComisionRd > 0
            ? (disponible / ultimaComisionRd).floor().clamp(0, 9999)
            : null;
        final minSaldo = PagosTaxistaRepo.minSaldoPrepagoComisionRd;
        final faltante = (minSaldo - disponible).clamp(0.0, double.infinity);

        final label = bloqueado ? 'Saldo bloqueado' : 'Saldo disponible';
        final amount = FormatosMoneda.rd(disponible);
        final detalle = bloqueado
            ? (legacyTope
                ? 'Comisión legacy ${FormatosMoneda.rd(pendLegacy)}. Prepago: ${FormatosMoneda.rd(saldo)}.'
                : 'Disponible ${FormatosMoneda.rd(disponible)} · mín. RD\$${minSaldo.toStringAsFixed(0)}. Faltan ${FormatosMoneda.rd(faltante)}.')
            : 'Prepago ${FormatosMoneda.rd(saldo)} · legacy ${FormatosMoneda.rd(pendLegacy)}.'
                '${viajesEstimados == null ? '' : ' ~$viajesEstimados viajes estimados.'}';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: RaiDriverWalletCard(
                key: ValueKey<String>('$label-$amount'),
                label: label,
                amount: amount,
                detail: detalle,
                warning: bloqueado,
                expanded: _expandido,
                onToggleExpand: () => setState(() => _expandido = !_expandido),
              ),
            ),
            if (!_expandido && pendLegacy > 0.01)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                child: Text(
                  'Legacy pendiente: ${FormatosMoneda.rd(pendLegacy)} · Prepago: ${FormatosMoneda.rd(saldo)}',
                  style: TextStyle(
                    color: bloqueado ? Colors.redAccent : RaiDsColors.textMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            AppBalanceProgressStrip(
              progress: (disponible / minSaldo).clamp(0.0, 1.0),
            ),
          ],
        );
      },
    );
  }
}

/// Barra de progreso decorativa bajo el saldo (estilo mockup).
class AppBalanceProgressStrip extends StatelessWidget {
  const AppBalanceProgressStrip({super.key, this.progress = 0.72});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isRaiDark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          minHeight: 3,
          backgroundColor: isDark ? RaiDsColors.border : const Color(0xFFE5E7EB),
          color: RaiDsColors.neon,
        ),
      ),
    );
  }
}
