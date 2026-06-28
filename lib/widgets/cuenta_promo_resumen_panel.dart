import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/servicios/comision_viaje_pct_service.dart';
import 'package:flygo_nuevo/servicios/tarifa_service_unificado.dart';
import 'package:flygo_nuevo/servicios/taxista_promociones_ui.dart';
import 'package:flygo_nuevo/widgets/promo_mxk_cliente_panel.dart';

/// Contador M×K del cliente: viajes completados + 1 (próximo a cotizar).
Future<int> contadorProximoViajeCliente(String uidCliente) async {
  final snapshot = await FirebaseFirestore.instance
      .collection('viajes')
      .where('uidCliente', isEqualTo: uidCliente)
      .where('completado', isEqualTo: true)
      .count()
      .get();
  return (snapshot.count ?? 0) + 1;
}

/// Promo M×K en **Cuenta** cliente (solo lectura; no altera cotización).
class ClienteCuentaPromoPanel extends StatelessWidget {
  const ClienteCuentaPromoPanel({super.key, required this.uidCliente});

  final String uidCliente;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('config')
          .doc('promociones')
          .snapshots(),
      builder: (context, promoCfgSnap) {
        if (!TarifaServiceUnificado.promoActivaDesdeConfig(
            promoCfgSnap.data?.data() ?? const {})) {
          return const SizedBox.shrink();
        }
        return FutureBuilder<Map<String, dynamic>>(
          future: _cargarSnapshot(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: LinearProgressIndicator(minHeight: 2),
              );
            }
            if (snap.hasError || !snap.hasData) {
              return const SizedBox.shrink();
            }
            final ui = PromoMxKClienteUi.fromSnapshot(snap.data);
            if (ui == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: PromoMxKClientePanel(promoSnapshot: snap.data),
            );
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>> _cargarSnapshot() async {
    final contador = await contadorProximoViajeCliente(uidCliente);
    return TarifaServiceUnificado().construirPromoSnapshot(contador);
  }
}

/// Resumen de incentivo por volumen en **Cuenta** taxista (solo lectura).
class TaxistaCuentaIncentivoPanel extends StatelessWidget {
  const TaxistaCuentaIncentivoPanel({super.key, required this.uidTaxista});

  final String uidTaxista;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<double>(
      stream: ComisionViajePctService.streamPorcentajeVigente(),
      initialData: PlataformaEconomia.comisionViajePorcentaje,
      builder: (context, pctSnap) {
        final globalPct = pctSnap.data ?? PlataformaEconomia.comisionViajePorcentaje;
        return StreamBuilder<Map<String, dynamic>?>(
          stream: TaxistaPromocionesUi.streamIncentivoConfig(),
          builder: (context, cfgSnap) {
            return StreamBuilder<Map<String, dynamic>?>(
              stream: TaxistaPromocionesUi.streamTaxistaStats(uidTaxista),
              builder: (context, statsSnap) {
                final inc = TaxistaIncentivoComisionUi.fromFirestore(
                  cfg: cfgSnap.data,
                  stats: statsSnap.data,
                  globalPct: globalPct,
                );
                if (!inc.programaActivo) return const SizedBox.shrink();

                final prox = inc.proximoViajes;
                final restantes = inc.viajesRestantes;
                final Color accent = inc.incentivoActivo
                    ? Colors.green.shade700
                    : Colors.amber.shade800;

                String? detalle;
                if (inc.incentivoActivo && inc.escalonEtiqueta.isNotEmpty) {
                  detalle = 'Nivel activo: ${inc.escalonEtiqueta}';
                } else if (prox != null &&
                    restantes != null &&
                    restantes > 0) {
                  detalle =
                      'Te faltan $restantes viaje${restantes == 1 ? '' : 's'} '
                      'para ${inc.proximoEtiqueta.isNotEmpty ? inc.proximoEtiqueta : 'el siguiente nivel'}'
                      '${inc.proximoPct != null ? ' (${TaxistaPromocionesUi.pctLabel(inc.proximoPct!)}% RAI)' : ''}';
                } else if (inc.incentivoActivo) {
                  detalle =
                      '¡Estás en el mejor nivel disponible ${inc.ventanaLabel}!';
                } else if (prox != null) {
                  detalle =
                      'Completa $prox viajes ${inc.ventanaLabel} para tu primer incentivo.';
                }

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Material(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.emoji_events_outlined,
                                  color: accent, size: 22),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  inc.titulo,
                                  style: TextStyle(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${inc.viajesCompletados} viajes completados ${inc.ventanaLabel}',
                            style: TextStyle(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            inc.resumenPct,
                            style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          if (prox != null &&
                              restantes != null &&
                              restantes > 0) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: inc.progresoFraction,
                                minHeight: 8,
                                backgroundColor: cs.surfaceContainerHighest,
                                color: accent,
                              ),
                            ),
                          ],
                          if (detalle != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              detalle,
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
