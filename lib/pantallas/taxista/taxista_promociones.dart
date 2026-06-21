import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/servicios/comision_viaje_pct_service.dart';
import 'package:flygo_nuevo/servicios/taxista_promociones_ui.dart';
import 'package:flygo_nuevo/config/plataforma_economia.dart';

/// Promociones y comisión global (solo lectura, conectado a admin).
class TaxistaPromocionesScreen extends StatelessWidget {
  const TaxistaPromocionesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Promociones y comisión'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          StreamBuilder<double>(
            stream: ComisionViajePctService.streamPorcentajeVigente(),
            initialData: PlataformaEconomia.comisionViajePorcentaje,
            builder: (context, pctSnap) {
              final double globalPct = pctSnap.data ?? 20.0;
              return StreamBuilder<Map<String, dynamic>?>(
                stream: TaxistaPromocionesUi.streamIncentivoConfig(),
                builder: (context, cfgSnap) {
                  if (uid == null) {
                    return _comisionCard(cs, globalPct: globalPct, efectivaPct: globalPct);
                  }
                  return StreamBuilder<Map<String, dynamic>?>(
                    stream: TaxistaPromocionesUi.streamTaxistaStats(uid),
                    builder: (context, statsSnap) {
                      final incentivo = TaxistaIncentivoComisionUi.fromFirestore(
                        cfg: cfgSnap.data,
                        stats: statsSnap.data,
                        globalPct: globalPct,
                      );
                      final double efectiva = incentivo.comisionEfectivaPct;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _comisionCard(
                            cs,
                            globalPct: globalPct,
                            efectivaPct: efectiva,
                            incentivo: incentivo,
                          ),
                          if (incentivo.programaActivo) ...[
                            const SizedBox(height: 14),
                            _incentivoCard(cs, incentivo),
                          ],
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
          const SizedBox(height: 14),
          StreamBuilder<TaxistaPromoMxKUi?>(
            stream: TaxistaPromocionesUi.streamPromoMxK(),
            builder: (context, promoSnap) {
              final TaxistaPromoMxKUi promo = promoSnap.data ??
                  const TaxistaPromoMxKUi(
                    activa: false,
                    m: 3,
                    k: 1,
                    porcentaje: 15,
                    modo: '3x1',
                  );
              return _card(
                cs,
                accent: promo.activa ? Colors.greenAccent : cs.outline,
                icon: Icons.local_offer_outlined,
                title: promo.titulo,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      promo.explicacionTaxista,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                        fontSize: 13.5,
                      ),
                    ),
                    if (promo.activa) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Secuencia (por cliente)',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List<Widget>.generate(
                          promo.ciclo.clamp(1, 12),
                          (int i) {
                            final int pos = i + 1;
                            final bool desc = pos <= promo.m;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: desc
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : Colors.blue.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: desc ? Colors.green : Colors.blue,
                                ),
                              ),
                              child: Text(
                                desc
                                    ? '#$pos −${promo.porcentaje}%'
                                    : '#$pos precio full',
                                style: TextStyle(
                                  color: desc
                                      ? Colors.green.shade700
                                      : Colors.blue.shade700,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          _card(
            cs,
            accent: cs.primary,
            icon: Icons.info_outline_rounded,
            title: 'Importante',
            child: Text(
              'Cambiar la comisión global o la promo M×K solo la hace el equipo RAI '
              'desde admin. Esta pantalla es informativa: no modifica tus viajes ni tu saldo.',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                height: 1.4,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _comisionCard(
    ColorScheme cs, {
    required double globalPct,
    required double efectivaPct,
    TaxistaIncentivoComisionUi? incentivo,
  }) {
    final double gan = (100.0 - efectivaPct).clamp(0.0, 100.0);
    final String pctTxt = TaxistaPromocionesUi.pctLabel(efectivaPct);
    final String ganTxt = TaxistaPromocionesUi.pctLabel(gan);
    final bool tieneIncentivo = incentivo?.incentivoActivo == true;
    return _card(
      cs,
      accent: Colors.deepOrangeAccent,
      icon: Icons.percent_rounded,
      title: tieneIncentivo ? 'Comisión RAI aplicada a ti' : 'Comisión RAI vigente',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$pctTxt% RAI · $ganTxt% para ti',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (tieneIncentivo) ...[
            const SizedBox(height: 6),
            Text(
              'Incentivo activo · base global '
              '${TaxistaPromocionesUi.pctLabel(globalPct)}%',
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Este porcentaje lo define RAI en admin y se aplica al cerrar '
            'cada viaje en efectivo: la comisión sale de tu prepago (Mis pagos) '
            'según el total cobrado al cliente.',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              height: 1.4,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Ejemplo: viaje RD\$1,000 → comisión RAI RD\$${(1000 * efectivaPct / 100).toStringAsFixed(0)} · '
              'tu ganancia RD\$${(1000 * gan / 100).toStringAsFixed(0)}',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _incentivoCard(ColorScheme cs, TaxistaIncentivoComisionUi inc) {
    final prox = inc.proximoViajes;
    final restantes = inc.viajesRestantes;
    return _card(
      cs,
      accent: Colors.amber.shade700,
      icon: Icons.emoji_events_outlined,
      title: inc.titulo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${inc.viajesCompletados} viajes completados ${inc.ventanaLabel}',
            style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          if (inc.incentivoActivo && inc.escalonEtiqueta.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Nivel: ${inc.escalonEtiqueta}',
              style: TextStyle(color: Colors.green.shade700, fontSize: 13),
            ),
          ],
          if (prox != null && restantes != null && restantes > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: inc.progresoFraction,
                minHeight: 10,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Te faltan $restantes viaje${restantes == 1 ? '' : 's'} para '
              '${inc.proximoEtiqueta.isNotEmpty ? inc.proximoEtiqueta : 'el siguiente nivel'}'
              '${inc.proximoPct != null ? ' (${TaxistaPromocionesUi.pctLabel(inc.proximoPct!)}% RAI)' : ''}',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                height: 1.35,
                fontSize: 13,
              ),
            ),
          ] else if (inc.incentivoActivo) ...[
            const SizedBox(height: 10),
            Text(
              '¡Estás en el mejor nivel disponible ${inc.ventanaLabel}!',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ] else if (prox != null) ...[
            const SizedBox(height: 10),
            Text(
              'Completa $prox viajes ${inc.ventanaLabel} para activar tu primer incentivo.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card(
    ColorScheme cs, {
    required Color accent,
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
