import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/formato_distancia_cercania.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/widgets/viajes_cercanos_taxista.dart';

/// Próximo viaje encolado / ruta corporativa lista (pool taxista).
class ColaSiguienteViajeBannerTaxista extends StatelessWidget {
  const ColaSiguienteViajeBannerTaxista({
    super.key,
    required this.uidTaxista,
    this.compact = false,
    this.referenciaOrden,
  });

  final String uidTaxista;
  final bool compact;

  /// Destino del viaje actual o GPS: ordena cola por pickup más cercano.
  final ValueNotifier<ColaCercaniaReferencia?>? referenciaOrden;

  static int _slotOf(Map<String, dynamic> m) {
    final s = m['slot'];
    if (s is int) return s;
    if (s is num) return s.toInt();
    return 1;
  }

  static int _createdMs(Map<String, dynamic> m) {
    final c = m['createdAt'];
    if (c is Timestamp) return c.millisecondsSinceEpoch;
    return 0;
  }

  static bool _viajeCerradoParaBanner(Map<String, dynamic> m) {
    if (m['completado'] == true) return true;
    final st = EstadosViaje.normalizar((m['estado'] ?? '').toString());
    return EstadosViaje.esTerminal(st) || EstadosViaje.esCompletado(st);
  }

  static Future<void> _limpiarColaColgadaSiViajeCerrado({
    required String uidTaxista,
    required String viajeId,
  }) async {
    final uid = uidTaxista.trim();
    final vid = viajeId.trim();
    if (uid.isEmpty || vid.isEmpty) return;
    try {
      final uRef = FirebaseFirestore.instance.collection('usuarios').doc(uid);
      final uSnap = await uRef.get();
      if (!uSnap.exists) return;
      final u = uSnap.data() ?? <String, dynamic>{};
      final sig = (u['siguienteViajeId'] ?? '').toString().trim();
      final enc = (u['viajeEncoladoId'] ?? '').toString().trim();
      if (sig != vid && enc != vid) return;
      final patch = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      };
      if (sig == vid) patch['siguienteViajeId'] = '';
      if (enc == vid) patch['viajeEncoladoId'] = '';
      await uRef.set(patch, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<bool> _viajeEsCorporativoDelChofer(
    String viajeId,
    String uidTaxista,
  ) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .get();
      if (!snap.exists) return false;
      return CorporativoTaxistaService.esViajeCorporativoAsignado(
        snap.data() ?? <String, dynamic>{},
        uidTaxista,
      );
    } catch (_) {
      return false;
    }
  }

  static QueryDocumentSnapshot<Map<String, dynamic>>? _primerPendienteCola(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (docs.isEmpty) return null;
    final copy = [...docs];
    copy.sort((a, b) {
      final ma = a.data();
      final mb = b.data();
      final sa = _slotOf(ma);
      final sb = _slotOf(mb);
      if (sa != sb) return sa.compareTo(sb);
      return _createdMs(ma).compareTo(_createdMs(mb));
    });
    return copy.first;
  }

  static Future<String?> _mejorViajeColaPorCercania({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required ColaCercaniaReferencia referencia,
  }) async {
    if (docs.isEmpty) return null;
    if (docs.length == 1) return docs.first.id;

    String? mejorId;
    double mejorDist = double.infinity;

    for (final QueryDocumentSnapshot<Map<String, dynamic>> d in docs) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('viajes')
            .doc(d.id)
            .get();
        if (!snap.exists) continue;
        final m = snap.data() ?? <String, dynamic>{};
        final double? la =
            (m['latCliente'] is num) ? (m['latCliente'] as num).toDouble() : null;
        final double? lo =
            (m['lonCliente'] is num) ? (m['lonCliente'] as num).toDouble() : null;
        if (la == null || lo == null || !la.isFinite || !lo.isFinite) continue;
        final double dist = Geolocator.distanceBetween(
          referencia.lat,
          referencia.lon,
          la,
          lo,
        );
        if (dist < mejorDist) {
          mejorDist = dist;
          mejorId = d.id;
        }
      } catch (_) {}
    }
    return mejorId ?? _primerPendienteCola(docs)?.id;
  }

  static double? _distanciaMetrosPickupViaje(
    Map<String, dynamic> viaje,
    ColaCercaniaReferencia referencia,
  ) {
    final double? la =
        (viaje['latCliente'] is num) ? (viaje['latCliente'] as num).toDouble() : null;
    final double? lo =
        (viaje['lonCliente'] is num) ? (viaje['lonCliente'] as num).toDouble() : null;
    if (la == null || lo == null || !la.isFinite || !lo.isFinite) return null;
    return Geolocator.distanceBetween(
      referencia.lat,
      referencia.lon,
      la,
      lo,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (uidTaxista.isEmpty) return const SizedBox.shrink();

    try {
      return _buildStreams(context);
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildStreams(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: CorporativoTaxistaService.streamOperacionChofer(uidTaxista),
      builder: (context, opSnap) {
        final rutasOp =
            CorporativoTaxistaService.rutasDesdeOperacion(opSnap.data);
        String corpListoId = '';
        for (final r in rutasOp) {
          if (r['listoParaAbrir'] != true) continue;
          if (r['completadoHoy'] == true) continue;
          final id = (r['viajeHoyId'] ?? r['viajeId'] ?? '').toString().trim();
          if (id.isNotEmpty) {
            corpListoId = id;
            break;
          }
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('usuarios')
              .doc(uidTaxista)
              .collection('cola_viajes')
              .where('estado', isEqualTo: 'pendiente')
              .limit(24)
              .snapshots(),
          builder: (context, colaSnap) {
            if (colaSnap.hasError) return const SizedBox.shrink();

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(uidTaxista)
                  .snapshots(),
              builder: (context, uSnap) {
                if (uSnap.hasError) return const SizedBox.shrink();
                if (!uSnap.hasData || !uSnap.data!.exists) {
                  return const SizedBox.shrink();
                }
                final ud = uSnap.data!.data() ?? {};
                final sig = (ud['siguienteViajeId'] ?? '').toString();
                final enc = (ud['viajeEncoladoId'] ?? '').toString();
                final activo = (ud['viajeActivoId'] ?? '').toString().trim();

                final List<QueryDocumentSnapshot<Map<String, dynamic>>>
                    colaDocs =
                    colaSnap.hasData ? colaSnap.data!.docs : const [];
                final QueryDocumentSnapshot<Map<String, dynamic>>? pendCola =
                    _primerPendienteCola(colaDocs);

                Widget buildForNextId({
                  required String nextId,
                  required bool reservaFormal,
                  required ColaCercaniaReferencia? ref,
                }) {
                  if (nextId.isEmpty) return const SizedBox.shrink();

                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('viajes')
                        .doc(nextId)
                        .snapshots(),
                    builder: (context, vSnap) {
                      if (vSnap.hasError) return const SizedBox.shrink();
                      if (!vSnap.hasData || !vSnap.data!.exists) {
                        return const SizedBox.shrink();
                      }
                      final m = vSnap.data!.data() ?? {};
                      final taxistaViaje =
                          (m['uidTaxista'] ?? m['taxistaId'] ?? '')
                              .toString()
                              .trim();
                      if (taxistaViaje.isNotEmpty &&
                          taxistaViaje != uidTaxista) {
                        return const SizedBox.shrink();
                      }
                      if (_viajeCerradoParaBanner(m)) {
                        _limpiarColaColgadaSiViajeCerrado(
                          uidTaxista: uidTaxista,
                          viajeId: nextId,
                        );
                        return const SizedBox.shrink();
                      }
                      if (!CorporativoTaxistaService
                          .esViajeCorporativoAsignado(m, uidTaxista)) {
                        if (!reservaFormal && corpListoId.isEmpty) {
                          final st = EstadosViaje.normalizar(
                              (m['estado'] ?? '').toString());
                          if (EstadosViaje.esTerminal(st)) {
                            return const SizedBox.shrink();
                          }
                        }
                      }

                      try {
                        final origen = (m['origen'] ?? 'Origen').toString();
                        final destino = (m['destino'] ?? 'Destino').toString();
                        final g = m['gananciaTaxista'];
                        final p = m['precio'];
                        double ganancia = g is num ? g.toDouble() : 0.0;
                        final precio = p is num ? p.toDouble() : 0.0;
                        if (ganancia <= 0 && precio > 0) {
                          ganancia = precio *
                              (1.0 - PlataformaEconomia.factorComision);
                        }
                        final ganTxt =
                            FormatosMoneda.rd(ganancia > 0 ? ganancia : precio);

                        DateTime? fh;
                        final ts = m['fechaHora'];
                        if (ts is Timestamp) fh = ts.toDate();
                        final sw = m['startWindowAt'];
                        if (fh == null && sw is Timestamp) fh = sw.toDate();
                        String ventana = '';
                        if (fh != null) {
                          ventana = DateFormat('dd/MM · HH:mm').format(fh);
                        }

                        final bool esCorp =
                            CorporativoTaxistaService
                                .esViajeCorporativoAsignado(m, uidTaxista);
                        final encoladoTrasViajeActual = activo.isNotEmpty &&
                            activo != nextId &&
                            (esCorp || reservaFormal);

                        String? distanciaLinea;
                        if (ref != null) {
                          final double? metros =
                              _distanciaMetrosPickupViaje(m, ref);
                          if (metros != null && metros.isFinite) {
                            distanciaLinea = ref.porDestinoViajeActivo
                                ? FormatoDistanciaCercania
                                    .pickupCercaDeDestinoActual(
                                    metros,
                                    destinoActual: ref.destinoEtiqueta,
                                  )
                                : FormatoDistanciaCercania.aRecogida(metros);
                          }
                        }

                        final titulo = esCorp
                            ? (encoladoTrasViajeActual
                                ? 'Después de este viaje · Corporativo'
                                : 'Ruta corporativa')
                            : (reservaFormal
                                ? 'Tu siguiente (ya reservado)'
                                : 'Próximo en cola');

                        return _shell(
                          context: context,
                          compact: compact,
                          reservaFormal: reservaFormal,
                          esCorporativo: esCorp,
                          encoladoTrasViajeActual: encoladoTrasViajeActual,
                          viajeId: nextId,
                          uidTaxista: uidTaxista,
                          titulo: titulo,
                          origen: origen,
                          destino: destino,
                          ventanaLine: ventana,
                          gananciaLine: ganTxt,
                          distanciaLine: distanciaLinea,
                        );
                      } catch (_) {
                        return const SizedBox.shrink();
                      }
                    },
                  );
                }

                String nextIdFallback;
                bool reservaFormalFallback;
                if (pendCola != null) {
                  nextIdFallback = pendCola.id;
                  reservaFormalFallback = _slotOf(pendCola.data()) == 0;
                } else if (sig.isNotEmpty || enc.isNotEmpty) {
                  nextIdFallback = sig.isNotEmpty ? sig : enc;
                  reservaFormalFallback = sig.isNotEmpty;
                } else {
                  nextIdFallback = corpListoId;
                  reservaFormalFallback = false;
                }

                if (referenciaOrden == null ||
                    colaDocs.length <= 1 ||
                    pendCola == null) {
                  return buildForNextId(
                    nextId: nextIdFallback,
                    reservaFormal: reservaFormalFallback,
                    ref: referenciaOrden?.value,
                  );
                }

                return ValueListenableBuilder<ColaCercaniaReferencia?>(
                  valueListenable: referenciaOrden!,
                  builder: (context, ref, _) {
                    if (ref == null) {
                      return buildForNextId(
                        nextId: nextIdFallback,
                        reservaFormal: reservaFormalFallback,
                        ref: null,
                      );
                    }
                    return FutureBuilder<String?>(
                      future: _mejorViajeColaPorCercania(
                        docs: colaDocs,
                        referencia: ref,
                      ),
                      builder: (context, pickSnap) {
                        final String picked =
                            (pickSnap.data ?? pendCola.id).trim();
                        QueryDocumentSnapshot<Map<String, dynamic>>? pickedDoc;
                        for (final d in colaDocs) {
                          if (d.id == picked) {
                            pickedDoc = d;
                            break;
                          }
                        }
                        pickedDoc ??= pendCola;
                        return buildForNextId(
                          nextId: picked.isNotEmpty ? picked : nextIdFallback,
                          reservaFormal: _slotOf(pickedDoc.data()) == 0,
                          ref: ref,
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _shell({
    required BuildContext context,
    required bool compact,
    required bool reservaFormal,
    required bool esCorporativo,
    required bool encoladoTrasViajeActual,
    required String viajeId,
    required String uidTaxista,
    required String titulo,
    required String origen,
    required String destino,
    required String ventanaLine,
    required String gananciaLine,
    String? distanciaLine,
  }) {
    Future<void> onTap() async {
      if (viajeId.isEmpty || uidTaxista.isEmpty) return;
      final bool corpTap = esCorporativo ||
          (viajeId.isNotEmpty &&
              await _viajeEsCorporativoDelChofer(viajeId, uidTaxista));
      if (corpTap) {
        await NavigationService.abrirViajeCorporativoTaxista(
          uidTaxista: uidTaxista,
          viajeId: viajeId,
          snackContext: context,
        );
        return;
      }
      await NavigationService.clearAndGoViajeEnCursoTaxista();
    }

    final accent = esCorporativo
        ? const Color(0xFF5EEAD4)
        : (reservaFormal ? Colors.lightBlueAccent : Colors.amberAccent);
    final border = esCorporativo
        ? const Color(0xFF2DD4BF)
        : (reservaFormal
            ? Colors.lightBlueAccent
            : Colors.amber.withValues(alpha: 0.6));

    if (compact) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: viajeId.isNotEmpty ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1B2A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border, width: 1),
            ),
            child: Row(
              children: [
                Icon(
                  esCorporativo ? Icons.business_center : Icons.queue_play_next,
                  color: accent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        destino.isNotEmpty ? '$origen → $destino' : origen,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (ventanaLine.isNotEmpty)
                        Text(
                          ventanaLine,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      if (distanciaLine != null && distanciaLine.isNotEmpty)
                        Text(
                          distanciaLine,
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      gananciaLine,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white.withValues(alpha: 0.5),
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: viajeId.isNotEmpty ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1B2A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    esCorporativo ? Icons.business_center : Icons.queue_play_next,
                    color: accent,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      titulo,
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              if (origen.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  origen,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                if (destino.isNotEmpty)
                  Text(
                    '→ $destino',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
              ],
              if (ventanaLine.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  ventanaLine,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
              if (distanciaLine != null && distanciaLine.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  distanciaLine,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (gananciaLine.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  gananciaLine,
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 13),
                ),
              ],
              if (esCorporativo && viajeId.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  encoladoTrasViajeActual
                      ? 'Terminá el viaje actual · detalle en Trabajo → Mis rutas'
                      : 'Toca para pasajeros, Waze y Maps',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
