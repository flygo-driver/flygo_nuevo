// Pega este archivo COMPLETO si aún no tienes la versión con avatar + cuenta.
// Si ya pegaste mi versión anterior, no hace falta cambiar nada.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/utils/estilos.dart';
import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/servicios/comision_viaje_pct_service.dart';
import 'package:flygo_nuevo/servicios/billetera_service.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/modelo/liquidacion.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/widgets/saldo_ganancias_chip.dart';
import 'package:flygo_nuevo/widgets/rai_cuenta_deposito_panel.dart';
import 'package:flygo_nuevo/pantallas/taxista/mis_pagos.dart';

class BilleteraTaxista extends StatefulWidget {
  const BilleteraTaxista({super.key});
  @override
  State<BilleteraTaxista> createState() => _BilleteraTaxistaState();
}

class _BilleteraTaxistaState extends State<BilleteraTaxista> {
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    unawaited(ComisionViajePctService.refresh(force: true));
  }

  Future<void> _refrescarPantalla() async {
    await ComisionViajePctService.refresh(force: true);
    if (mounted) setState(() {});
  }

  Color _chipColor(String estado) {
    switch (estado) {
      case 'aprobado':
        return Colors.greenAccent;
      case 'rechazado':
        return Colors.redAccent;
      default:
        return Colors.orangeAccent;
    }
  }

  Future<void> _solicitarRetiroDialog() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final saldoActual = await BilleteraService.calcularSaldoDisponible(u.uid);
    if (!mounted) return;

    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EstilosRai.fondoOscuro,
        title: const Text('Solicitar retiro',
            style: TextStyle(color: EstilosRai.textoBlanco)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Saldo para retiro: ${FormatosMoneda.rd(saldoActual)}',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Monto en RD\$', hintText: 'Ej: 1500.00'),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: _enviando ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: _enviando ? null : () => Navigator.pop(ctx, true),
              child: const Text('Solicitar')),
        ],
      ),
    );

    if (ok != true) return;

    final raw = ctrl.text.trim().replaceAll(',', '.');
    final monto = double.tryParse(raw) ?? -1;

    if (monto <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Monto inválido.')));
      return;
    }
    if (monto > saldoActual) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('El monto excede tu saldo para retiro.')));
      return;
    }

    try {
      setState(() => _enviando = true);
      await BilleteraService.solicitarRetiro(uidTaxista: u.uid, monto: monto);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('✅ Solicitud enviada.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('❌ Error: $e')));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: EstilosRai.fondoOscuro,
      appBar: AppBar(
        backgroundColor: EstilosRai.fondoOscuro,
        title: const Text("Mi Billetera",
            style: TextStyle(color: EstilosRai.textoBlanco)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: EstilosRai.textoBlanco),
        actions: [
          const SaldoGananciasChip(),
          IconButton(
            onPressed: _enviando ? null : () => unawaited(_refrescarPantalla()),
            icon: const Icon(Icons.refresh, color: EstilosRai.textoBlanco),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: u == null
          ? const Center(
              child: Text('Inicia sesión',
                  style: TextStyle(color: EstilosRai.textoBlanco)))
          : RefreshIndicator(
              onRefresh: _refrescarPantalla,
              color: EstilosRai.textoVerde,
              backgroundColor: EstilosRai.fondoOscuro,
              child: StreamBuilder<double>(
                stream: ComisionViajePctService.streamPorcentajeVigente(),
                initialData: PlataformaEconomia.comisionViajePorcentaje,
                builder: (context, pctSnap) {
                  return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _HeaderTaxista(uid: u.uid),
                  const SizedBox(height: 18),

                  StreamBuilder<ResumenBilleteraLive>(
                    stream: BilleteraService.streamResumenBilletera(u.uid),
                    builder: (context, snap) {
                      final r = snap.data ??
                          const ResumenBilleteraLive(
                            saldoDisponible: 0,
                            gananciaTotal: 0,
                            comisionTotal: 0,
                            viajesCompletados: 0,
                          );
                      if (snap.connectionState == ConnectionState.waiting &&
                          !snap.hasData) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: CircularProgressIndicator(
                                color: EstilosRai.textoVerde),
                          ),
                        );
                      }

                      return Column(
                        children: [
                          _infoBox(
                              "Saldo para retiro",
                              FormatosMoneda.rd(r.saldoDisponible),
                              EstilosRai.textoVerde),
                          const SizedBox(height: 16),
                          _infoBox(
                              "Ganancia total (viajes completados)",
                              FormatosMoneda.rd(r.gananciaTotal), Colors.green),
                          const SizedBox(height: 16),
                          _infoBox(
                              _tituloComisionRaiHistorico(),
                              FormatosMoneda.rd(r.comisionTotal),
                              Colors.deepOrangeAccent),
                          const SizedBox(height: 16),
                          _infoBox("Viajes Completados",
                              "${r.viajesCompletados}", Colors.blueAccent),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed:
                                  _enviando ? null : _solicitarRetiroDialog,
                              icon: _enviando
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.account_balance_wallet,
                                      color: EstilosRai.textoVerde),
                              label: Text(
                                  _enviando
                                      ? 'Enviando...'
                                      : 'Solicitar retiro',
                                  style: const TextStyle(
                                      color: EstilosRai.textoVerde,
                                      fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 50)),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 24),
                  _OperativaPrepagoCard(uid: u.uid),

                  const SizedBox(height: 24),
                  const RaiCuentaDepositoPanel(
                    titulo: 'Cuenta para recargar prepago (transferencia a RAI)',
                    subtitulo:
                        'No es tu cuenta personal para cobrar viajes; sirve para depositar y verificar recargas de comisión.',
                  ),

                  const SizedBox(height: 28),
                  const Text("Historial de liquidaciones",
                      style: TextStyle(
                        fontSize: EstilosRai.tamanioLetraGrande,
                        fontWeight: FontWeight.bold,
                        color: EstilosRai.textoBlanco,
                      )),
                  const SizedBox(height: 10),

                  StreamBuilder<List<Liquidacion>>(
                    stream:
                        BilleteraService.streamLiquidacionesPorTaxista(u.uid),
                    builder: (context, liqSnap) {
                      if (liqSnap.connectionState == ConnectionState.waiting &&
                          !liqSnap.hasData) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: CircularProgressIndicator(
                                color: EstilosRai.textoVerde),
                          ),
                        );
                      }

                      final items = liqSnap.data ?? [];
                      if (items.isEmpty) {
                        return const Text('Sin liquidaciones aún.',
                            style: TextStyle(color: Colors.white70));
                      }

                      final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
                      return ListView.separated(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final l = items[i];
                          final fecha = (l.solicitadoEn != null)
                              ? formatoFecha.format(l.solicitadoEn!.toLocal())
                              : '—';
                          final color = _chipColor(l.estado);

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[900],
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: color.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(FormatosMoneda.rd(l.monto),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Text('Solicitado: $fecha',
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: color.withValues(alpha: 0.6)),
                                  ),
                                  child: Text(l.estado.toUpperCase(),
                                      style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 30),
                  const Text("¿Cómo funciona?",
                      style: TextStyle(
                        fontSize: EstilosRai.tamanioLetraGrande,
                        fontWeight: FontWeight.bold,
                        color: EstilosRai.textoBlanco,
                      )),
                  const SizedBox(height: 8),
                  Text(
                    _textoComoFuncionaBilletera(),
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 16, height: 1.35),
                  ),
                ],
              );
                },
              ),
            ),
    );
  }

  /// Etiqueta compacta de porcentaje (sync con `config/comision` → [PlataformaEconomia]).
  static String _pctMostrar(double p) {
    if (!p.isFinite || p < 0) return '?';
    final r = p.roundToDouble();
    if ((p - r).abs() < 1e-6) return r.toInt().toString();
    return p.toStringAsFixed(1);
  }

  /// Título tarjeta naranja: montos = suma real en viajes; % global es referencia actual.
  String _tituloComisionRaiHistorico() {
    final rai = PlataformaEconomia.comisionViajePorcentaje;
    return 'Comisión RAI en tus viajes (histórico; estándar hoy ${_pctMostrar(rai)}%)';
  }

  String _textoComoFuncionaBilletera() {
    final rai = PlataformaEconomia.comisionViajePorcentaje;
    final drv = (100.0 - rai).clamp(0.0, 100.0);
    return '• En viajes estándar, la app usa hoy ${_pctMostrar(drv)}% para ti y ${_pctMostrar(rai)}% comisión RAI (sale de configuración; cambios futuros no reescriben viajes ya guardados).\n'
        '• La tarjeta naranja suma lo que consta en tus viajes completados; turismo u otros servicios pueden tener otro reparto.\n'
        '• Eso no es prepago en efectivo: recarga y bloqueos van en el recuadro verde y en Mis pagos.\n'
        '• Las solicitudes de retiro descuentan tu saldo para retiro.\n'
        '• Cuando una liquidación se aprueba, queda reflejada en el historial.\n'
        '• Próximamente podrás recibir transferencias automáticas.';
  }

  Widget _infoBox(String titulo, String valor, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: RaiDsColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: TextStyle(
                  fontSize: 18, color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(valor,
              style: const TextStyle(fontSize: 24, color: Colors.white)),
        ],
      ),
    );
  }
}

/// Solo lectura: mismos datos que Mis pagos / bloqueo operativo. No altera saldos ni retiros.
class _OperativaPrepagoCard extends StatelessWidget {
  final String uid;
  const _OperativaPrepagoCard({required this.uid});

  @override
  Widget build(BuildContext context) {
    final ref =
        FirebaseFirestore.instance.collection('billeteras_taxista').doc(uid);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: RaiDsColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: RaiDsColors.border),
            ),
            child: const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: EstilosRai.textoVerde,
                ),
              ),
            ),
          );
        }

        final data = snap.data?.data();
        final prep = PagosTaxistaRepo.saldoDisponiblePrepagoComisionDesdeBilletera(
            data);
        final legacy =
            PagosTaxistaRepo.comisionPendienteDesdeBilletera(data);
        final bloqueoLegacy = legacy + 1e-9 >=
            PagosTaxistaRepo.umbralComisionLegacyBloqueoRd;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: RaiDsColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: bloqueoLegacy ? Colors.redAccent : EstilosRai.textoVerde,
                width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Comisión en efectivo (operar)',
                style: TextStyle(
                  color: EstilosRai.textoVerde,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Distinto del saldo para retiro de arriba. Aquí va el prepago para viajes en efectivo y deudas históricas.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 14),
              Text(
                'Saldo prepago disponible',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75), fontSize: 14)),
              const SizedBox(height: 4),
              Text(
                FormatosMoneda.rd(prep),
                style: const TextStyle(
                    color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
              ),
              if (legacy > 1e-6) ...[
                const SizedBox(height: 12),
                Text(
                  'Comisión pendiente (histórico / admin)',
                  style: TextStyle(
                      color: bloqueoLegacy ? Colors.redAccent : Colors.orangeAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  FormatosMoneda.rd(legacy),
                  style: TextStyle(
                    color: bloqueoLegacy ? Colors.redAccent : Colors.orangeAccent,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (bloqueoLegacy)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '≥ RD\$${PagosTaxistaRepo.umbralComisionLegacyBloqueoRd.toStringAsFixed(0)} en esta deuda puede bloquearte: regulariza en Mis pagos.',
                      style: TextStyle(
                        color: Colors.redAccent.withValues(alpha: 0.9),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MisPagos(
                          scrollToRecargaSection: true,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.payments_outlined,
                      color: EstilosRai.textoVerde),
                  label: const Text(
                    'Ir a Mis pagos (recarga y estado)',
                    style: TextStyle(
                        color: EstilosRai.textoVerde, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: EstilosRai.textoVerde),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ===== extras: avatar + cuenta empresa =====
class _HeaderTaxista extends StatelessWidget {
  final String uid;
  const _HeaderTaxista({required this.uid});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('usuarios').doc(uid);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data() ?? {};
        final nombre = (d['nombre'] ?? d['displayName'] ?? '').toString();
        final foto = (d['fotoUrl'] ?? d['avatarUrl'] ?? '').toString();

        return Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white10,
              backgroundImage: (foto.isNotEmpty) ? NetworkImage(foto) : null,
              child: (foto.isEmpty)
                  ? const Icon(Icons.person, color: Colors.white70, size: 28)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                nombre.isEmpty ? 'Conductor' : nombre,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }
}
