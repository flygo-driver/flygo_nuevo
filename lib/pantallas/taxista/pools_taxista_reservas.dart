import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/analytics_rai.dart';
import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/servicios/pool_repo.dart';
import 'package:flygo_nuevo/pantallas/comun/pool_gira_validar_entrada_page.dart';
import 'package:flygo_nuevo/utils/pool_gira_cancelar_ui.dart';
import 'package:flygo_nuevo/utils/pool_recaudo_central.dart';
import 'package:flygo_nuevo/utils/pools_producto_copy.dart';
import 'package:flygo_nuevo/widgets/pool_recaudo_central_taxista_panel.dart';
import 'package:url_launcher/url_launcher.dart';

class PoolsTaxistaReservas extends StatefulWidget {
  final String poolId;
  const PoolsTaxistaReservas({super.key, required this.poolId});

  @override
  State<PoolsTaxistaReservas> createState() => _PoolsTaxistaReservasState();
}

class _PoolsTaxistaReservasState extends State<PoolsTaxistaReservas> {
  bool _yaCerroPorCancelacion = false;
  bool _cancelando = false;

  void _volverSiGiraCancelada(String estadoPool) {
    final s = estadoPool.trim().toLowerCase();
    if (s != 'cancelado' && s != 'cancelado_por_admin') return;
    if (_yaCerroPorCancelacion) return;
    _yaCerroPorCancelacion = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = Navigator.of(context);
      if (nav.canPop()) nav.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta salida fue cancelada.')),
      );
    });
  }

  void _snack(ScaffoldMessengerState messenger, String m) {
    messenger.showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _cancelarSalida(
    BuildContext context,
    Map<String, dynamic> poolData,
  ) async {
    if (_cancelando) return;
    if (!await confirmarCancelarGiraSalida(context, poolData)) return;
    if (!context.mounted) return;
    setState(() => _cancelando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      const motivo = 'Cancelado por chofer';
      final r = await PoolRepo.cancelarViajePoolSeguro(
        poolId: widget.poolId,
        motivo: motivo,
      );
      final dev = (r['comisionDevuelta'] as num?)?.toDouble() ?? 0;
      unawaited(AnalyticsRai.logGiraCanceled(
        motivo: motivo,
        comisionDevuelta: dev,
      ));
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Salida cancelada — desaparece del catálogo')),
      );
      Navigator.of(context).pop();
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            msg.isNotEmpty ? msg : 'No se pudo cancelar la salida (${e.code})',
          ),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _cancelando = false);
    }
  }

  String _cleanPhone(String raw) {
    final v = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (v.startsWith('1') && v.length == 11) return v;
    if (v.length == 10) return '1$v';
    return v;
  }

  Future<void> _call(BuildContext context, String phone) async {
    final messenger = ScaffoldMessenger.of(context);
    final p = _cleanPhone(phone);
    if (p.isEmpty) {
      _snack(messenger, 'Telefono no disponible');
      return;
    }
    final ok = await launchUrl(
      Uri.parse('tel:+$p'),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) {
      _snack(messenger, 'No se pudo abrir llamada');
    }
  }

  String _normName(Map<String, dynamic> reserva, Map<String, dynamic>? perfil) {
    final p = (perfil?['nombre'] ?? '').toString().trim();
    if (p.isNotEmpty) return p;
    final r = (reserva['clienteNombre'] ?? '').toString().trim();
    if (r.isNotEmpty) return r;
    return 'Pasajero';
  }

  String? _fotoUrl(Map<String, dynamic>? perfil) {
    final u = (perfil?['fotoUrl'] ?? '').toString().trim();
    return u.isEmpty ? null : u;
  }

  Future<void> _whatsApp(BuildContext context, String phone, String msg) async {
    final messenger = ScaffoldMessenger.of(context);
    final p = _cleanPhone(phone);
    if (p.isEmpty) {
      _snack(messenger, 'WhatsApp no disponible');
      return;
    }
    final m = Uri.encodeComponent(msg);
    final waApp = Uri.parse('whatsapp://send?phone=%2B$p&text=$m');
    final waWeb = Uri.parse('https://wa.me/$p?text=$m');
    final ok1 = await launchUrl(waApp, mode: LaunchMode.externalApplication);
    if (ok1) return;
    final ok2 = await launchUrl(waWeb, mode: LaunchMode.externalApplication);
    if (!ok2) {
      _snack(messenger, 'No se pudo abrir WhatsApp');
    }
  }

  Widget _reservaContenido(
    BuildContext context, {
    required Map<String, dynamic> d,
    required Map<String, dynamic>? perfil,
    required String estado,
    required int seats,
    required double total,
    required double deposit,
    required String metodo,
    required String telEfectivo,
    required String waEfectivo,
    required bool recaudoCentral,
    required Map<String, dynamic> poolData,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textPrimary = isDark ? Colors.white : const Color(0xFF101828);
    final Color textSecondary =
        isDark ? Colors.white70 : const Color(0xFF475467);

    final nombre = _normName(d, perfil);
    final telPerfil = (perfil?['telefono'] ?? '').toString().trim();
    final waPerfil = (perfil?['whatsapp'] ?? '').toString().trim();
    final tel = telPerfil.isNotEmpty ? telPerfil : telEfectivo;
    final wa = waPerfil.isNotEmpty
        ? waPerfil
        : (waEfectivo.isNotEmpty ? waEfectivo : tel);

    final foto = _fotoUrl(perfil);
    final metodoL = metodo.trim().toLowerCase();
    final estadoL = estado.trim().toLowerCase();
    final referencia = (d['referenciaRecaudo'] ?? '').toString().trim();
    final netoReserva = ((d['netoOrganizadorRd'] ?? 0) as num).toDouble();
    final pct = PoolRecaudoCentral.pctComisionPool(
      poolData,
      fallbackPct: PlataformaEconomia.comisionGiraPorcentaje,
    );
    final desgloseCentral = recaudoCentral && seats > 0
        ? PoolRecaudoCentral.desgloseReserva(
            pool: poolData,
            asientos: seats,
            pctComision: pct,
          )
        : null;

    String pagoLinea;
    if (recaudoCentral && metodoL == 'transferencia') {
      pagoLinea = estadoL == 'pagado'
          ? PoolsProductoCopy.recaudoCentralEstadoReservaTaxista(d)
          : 'Cliente paga el total a RAI — RAI verifica en banco; no confirmás transferencias';
    } else if (recaudoCentral && metodoL == 'efectivo') {
      pagoLinea = PoolsProductoCopy.recaudoCentralEstadoReservaTaxista(d);
    } else if (metodoL == 'transferencia') {
      pagoLinea =
          'Pago: transferencia — coordina el bauche por WhatsApp o llamada';
    } else {
      pagoLinea = 'Pago: $metodo';
    }

    final String montoLinea;
    if (recaudoCentral && metodoL == 'transferencia') {
      montoLinea =
          'Total reserva: RD\$ ${total.toStringAsFixed(0)} (100% a cuenta RAI)';
    } else if (recaudoCentral && metodoL == 'efectivo' && desgloseCentral != null) {
      montoLinea = desgloseCentral.resumenLinea(efectivoAlAbordar: true);
    } else {
      montoLinea =
          'Total RD\$ ${total.toStringAsFixed(0)} · Deposito RD\$ ${deposit.toStringAsFixed(0)}';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: textSecondary.withValues(alpha: 0.22),
          backgroundImage: foto != null ? NetworkImage(foto) : null,
          child: foto == null
              ? Icon(Icons.person_outline, color: textSecondary, size: 22)
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$nombre · $seats asiento(s) · $estado',
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (metodoL.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    pagoLinea,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  montoLinea,
                  style: TextStyle(color: textSecondary, fontSize: 13),
                ),
              ),
              if (recaudoCentral &&
                  metodoL == 'transferencia' &&
                  referencia.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Ref. cliente: $referencia',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (recaudoCentral && estadoL == 'pagado' && netoReserva > 0) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Tu neto por esta reserva: RD\$ ${netoReserva.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (tel.isNotEmpty) ...[
                const SizedBox(height: 4),
                SelectableText(
                  'Tel: $tel',
                  style: TextStyle(color: textSecondary, fontSize: 12),
                ),
              ],
              if (wa.isNotEmpty && wa.trim() != tel.trim()) ...[
                SelectableText(
                  'WhatsApp: $wa',
                  style: TextStyle(color: textSecondary, fontSize: 12),
                ),
              ],
              if (tel.isNotEmpty || wa.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (tel.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => _call(context, tel),
                        icon: const Icon(Icons.call, size: 15),
                        label: const Text('Llamar'),
                      ),
                    if (wa.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => _whatsApp(
                          context,
                          wa,
                          recaudoCentral
                              ? 'Hola $nombre, te escribo por tu reserva de cupos en esta salida.'
                              : 'Hola $nombre, te escribo por tu reserva de cupos en esta salida (pago / bauche).',
                        ),
                        icon: const Icon(Icons.chat, size: 15),
                        label: const Text('WhatsApp'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final poolRef = PoolRepo.pools.doc(widget.poolId);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textPrimary = isDark ? Colors.white : const Color(0xFF101828);
    final Color textMuted = isDark ? Colors.white60 : const Color(0xFF667085);
    final Color accent = isDark ? Colors.greenAccent : const Color(0xFF0F9D58);
    final Color scaffoldBg = isDark ? Colors.black : const Color(0xFFE8EAED);
    final Color cardBg = isDark ? const Color(0xFF121212) : Colors.white;
    final Color cardBorder = isDark ? Colors.white24 : const Color(0xFFD0D5DD);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: textPrimary,
        elevation: isDark ? 0 : 0.5,
        title: Text(
          'Reservas',
          style: TextStyle(color: accent, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Validar entrada (QR/código)',
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => PoolGiraValidarEntradaPage(
                    poolId: widget.poolId,
                  ),
                ),
              );
            },
            icon: Icon(Icons.qr_code_scanner_outlined, color: accent),
          ),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: poolRef.snapshots(),
            builder: (context, snap) {
              if (!snap.hasData || !snap.data!.exists) {
                return const SizedBox.shrink();
              }
              final d = snap.data!.data() ?? {};
              if (!PoolRepo.giraPuedeCancelarseAntesDeIniciar(d)) {
                return const SizedBox.shrink();
              }
              return TextButton.icon(
                onPressed: _cancelando
                    ? null
                    : () => _cancelarSalida(context, d),
                icon: _cancelando
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.orange.shade700,
                        ),
                      )
                    : Icon(Icons.cancel_outlined,
                        color: Colors.orange.shade700, size: 20),
                label: Text(
                  'Cancelar',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: poolRef.snapshots(),
        builder: (context, poolSnap) {
          if (poolSnap.hasData && poolSnap.data!.exists) {
            final poolEstado =
                (poolSnap.data!.data()?['estado'] ?? '').toString();
            _volverSiGiraCancelada(poolEstado);
            final poolEstadoL = poolEstado.trim().toLowerCase();
            if (poolEstadoL == 'cancelado' ||
                poolEstadoL == 'cancelado_por_admin') {
              return Center(
                child: Text(
                  'Salida cancelada',
                  style: TextStyle(color: textMuted),
                ),
              );
            }
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: poolRef.collection('reservas').snapshots(),
            builder: (context, snap) {
              final poolData = poolSnap.data?.data() ?? <String, dynamic>{};
              final recaudoCentral = PoolRecaudoCentral.esPoolCentral(poolData);
              final panelCentral = recaudoCentral
                  ? PoolRecaudoCentralTaxistaPanel(poolData: poolData)
                  : null;

              if (snap.connectionState == ConnectionState.waiting) {
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (panelCentral != null) panelCentral,
                    const SizedBox(height: 24),
                    Center(child: CircularProgressIndicator(color: accent)),
                  ],
                );
              }
              if (snap.hasError) {
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (panelCentral != null) panelCentral,
                    Center(
                      child: Text(
                        'Error cargando reservas.',
                        style: TextStyle(color: textMuted),
                      ),
                    ),
                  ],
                );
              }

              var docs = snap.data?.docs ?? [];
              docs = docs
                  .where(
                    (doc) => PoolRepo.reservaPoolActivaParaCliente(
                      (doc.data()['estado'] ?? '').toString(),
                    ),
                  )
                  .toList();
              docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                docs,
              )..sort((a, b) {
                  final ta = a.data()['createdAt'];
                  final tb = b.data()['createdAt'];
                  final da = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
                  final db = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
                  return db.compareTo(da);
                });
              if (docs.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (panelCentral != null) panelCentral,
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Sin reservas activas.',
                        style: TextStyle(color: textMuted),
                      ),
                    ),
                  ],
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(12),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemCount: docs.length + (panelCentral != null ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (panelCentral != null && i == 0) {
                    return panelCentral;
                  }
                  final docIndex = panelCentral != null ? i - 1 : i;
                  final doc = docs[docIndex];
                  final d = doc.data();
                  final id = doc.id;
                  final estado = (d['estado'] ?? '').toString();
                  final seats = ((d['seats'] ?? 0) as num).toInt();
                  final total = ((d['total'] ?? 0.0) as num).toDouble();
                  final deposit = ((d['deposit'] ?? 0.0) as num).toDouble();
                  final uidCliente = (d['uidCliente'] ?? '').toString();
                  final metodo = (d['metodoPago'] ?? '').toString();
                  final telReserva =
                      (d['clienteTelefono'] ?? '').toString().trim();
                  final waReserva =
                      (d['clienteWhatsApp'] ?? '').toString().trim();

                  final streamPerfil = uidCliente.isEmpty
                      ? null
                      : FirebaseFirestore.instance
                          .collection('usuarios')
                          .doc(uidCliente)
                          .snapshots();

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cardBorder),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: streamPerfil == null
                              ? _reservaContenido(
                                  ctx,
                                  d: d,
                                  perfil: null,
                                  estado: estado,
                                  seats: seats,
                                  total: total,
                                  deposit: deposit,
                                  metodo: metodo,
                                  telEfectivo: telReserva,
                                  waEfectivo: waReserva.isNotEmpty
                                      ? waReserva
                                      : telReserva,
                                  recaudoCentral: recaudoCentral,
                                  poolData: poolData,
                                )
                              : StreamBuilder<
                                  DocumentSnapshot<Map<String, dynamic>>>(
                                  stream: streamPerfil,
                                  builder: (context, userSnap) {
                                    final perfil = userSnap.data?.data();
                                    return _reservaContenido(
                                      ctx,
                                      d: d,
                                      perfil: perfil,
                                      estado: estado,
                                      seats: seats,
                                      total: total,
                                      deposit: deposit,
                                      metodo: metodo,
                                      telEfectivo: telReserva,
                                      waEfectivo: waReserva.isNotEmpty
                                          ? waReserva
                                          : telReserva,
                                      recaudoCentral: recaudoCentral,
                                      poolData: poolData,
                                    );
                                  },
                                ),
                        ),
                        if (estado != 'pagado' &&
                            !(recaudoCentral && metodo == 'transferencia'))
                          Tooltip(
                            message: recaudoCentral
                                ? PoolsProductoCopy
                                    .recaudoCentralTaxistaMarcarPagadaAyuda
                                : 'Marcar cuando recibiste el depósito',
                            child: TextButton.icon(
                              onPressed: () async {
                                final messenger =
                                    ScaffoldMessenger.of(ctx);
                                try {
                                  await PoolRepo.marcarReservaPagadaSegura(
                                    poolId: widget.poolId,
                                    reservaId: id,
                                  );
                                  _snack(
                                    messenger,
                                    recaudoCentral
                                        ? 'Pago RAI confirmado — sumó a tu neto'
                                        : 'Marcada como pagada',
                                  );
                                } catch (e) {
                                  _snack(messenger, 'Error: $e');
                                }
                              },
                              icon: const Icon(Icons.check_circle_outline),
                              label: Text(
                                recaudoCentral
                                    ? PoolsProductoCopy
                                        .recaudoCentralTaxistaMarcarPagada
                                    : 'Marcar pagada',
                              ),
                            ),
                          )
                        else if (recaudoCentral &&
                            metodo == 'transferencia' &&
                            estado != 'pagado')
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'RAI verifica la transferencia del cliente. '
                              'Cupos firmes cuando admin confirme el pago en Open ASK.',
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
