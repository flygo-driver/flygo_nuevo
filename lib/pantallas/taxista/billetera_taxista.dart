// Pega este archivo COMPLETO si aún no tienes la versión con avatar + cuenta.
// Si ya pegaste mi versión anterior, no hace falta cambiar nada.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

import 'package:flygo_nuevo/utils/estilos.dart';
import 'package:flygo_nuevo/servicios/billetera_service.dart';
import 'package:flygo_nuevo/modelo/liquidacion.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/widgets/taxista_drawer.dart';
import 'package:flygo_nuevo/widgets/saldo_ganancias_chip.dart';

class BilleteraTaxista extends StatefulWidget {
  const BilleteraTaxista({super.key});
  @override
  State<BilleteraTaxista> createState() => _BilleteraTaxistaState();
}

class _BilleteraTaxistaState extends State<BilleteraTaxista> {
  bool _enviando = false;

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
        backgroundColor: EstilosFlyGo.fondoOscuro,
        title: const Text('Solicitar retiro', style: TextStyle(color: EstilosFlyGo.textoBlanco)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Saldo disponible: ${FormatosMoneda.rd(saldoActual)}',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto en RD\$', hintText: 'Ej: 1500.00'),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: _enviando ? null : () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: _enviando ? null : () => Navigator.pop(ctx, true), child: const Text('Solicitar')),
        ],
      ),
    );

    if (ok != true) return;

    final raw = ctrl.text.trim().replaceAll(',', '.');
    final monto = double.tryParse(raw) ?? -1;

    if (monto <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Monto inválido.')));
      return;
    }
    if (monto > saldoActual) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El monto excede el saldo disponible.')));
      return;
    }

    try {
      setState(() => _enviando = true);
      await BilleteraService.solicitarRetiro(uidTaxista: u.uid, monto: monto);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Solicitud enviada.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: EstilosFlyGo.fondoOscuro,
      drawer: const TaxistaDrawer(),
      appBar: AppBar(
        backgroundColor: EstilosFlyGo.fondoOscuro,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: EstilosFlyGo.textoBlanco),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            tooltip: 'Menú',
          ),
        ),
        title: const Text("Mi Billetera", style: TextStyle(color: EstilosFlyGo.textoBlanco)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: EstilosFlyGo.textoBlanco),
        actions: [
          const SaldoGananciasChip(),
          IconButton(
            onPressed: _enviando ? null : () => setState(() {}),
            icon: const Icon(Icons.refresh, color: EstilosFlyGo.textoBlanco),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: u == null
          ? const Center(child: Text('Inicia sesión', style: TextStyle(color: EstilosFlyGo.textoBlanco)))
          : RefreshIndicator(
              onRefresh: () async => setState(() {}),
              color: EstilosFlyGo.textoVerde,
              backgroundColor: EstilosFlyGo.fondoOscuro,
              child: ListView(
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
                      if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child:
                                CircularProgressIndicator(color: EstilosFlyGo.textoVerde),
                          ),
                        );
                      }

                      return Column(
                        children: [
                          _infoBox("Saldo disponible", FormatosMoneda.rd(r.saldoDisponible), EstilosFlyGo.textoVerde),
                          const SizedBox(height: 16),
                          _infoBox("Ganancia Total", FormatosMoneda.rd(r.gananciaTotal), Colors.green),
                          const SizedBox(height: 16),
                          _infoBox("Comisión acumulada (RAI)", FormatosMoneda.rd(r.comisionTotal), Colors.redAccent),
                          const SizedBox(height: 16),
                          _infoBox("Viajes Completados", "${r.viajesCompletados}", Colors.blueAccent),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _enviando ? null : _solicitarRetiroDialog,
                              icon: _enviando
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.account_balance_wallet, color: EstilosFlyGo.textoVerde),
                              label: Text(_enviando ? 'Enviando...' : 'Solicitar retiro',
                                  style: const TextStyle(color: EstilosFlyGo.textoVerde, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 24),
                  const _CuentaEmpresaCard(), // datos bancarios empresa

                  const SizedBox(height: 28),
                  const Text("Historial de liquidaciones",
                      style: TextStyle(
                        fontSize: EstilosFlyGo.tamanioLetraGrande,
                        fontWeight: FontWeight.bold,
                        color: EstilosFlyGo.textoBlanco,
                      )),
                  const SizedBox(height: 10),

                  StreamBuilder<List<Liquidacion>>(
                    stream: BilleteraService.streamLiquidacionesPorTaxista(u.uid),
                    builder: (context, liqSnap) {
                      if (liqSnap.connectionState == ConnectionState.waiting && !liqSnap.hasData) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: CircularProgressIndicator(color: EstilosFlyGo.textoVerde),
                          ),
                        );
                      }

                      final items = liqSnap.data ?? [];
                      if (items.isEmpty) {
                        return const Text('Sin liquidaciones aún.', style: TextStyle(color: Colors.white70));
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
                              border: Border.all(color: color.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(FormatosMoneda.rd(l.monto),
                                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Text('Solicitado: $fecha',
                                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: color.withValues(alpha: 0.6)),
                                  ),
                                  child: Text(l.estado.toUpperCase(),
                                      style: TextStyle(color: color, fontWeight: FontWeight.w700)),
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
                        fontSize: EstilosFlyGo.tamanioLetraGrande,
                        fontWeight: FontWeight.bold,
                        color: EstilosFlyGo.textoBlanco,
                      )),
                  const SizedBox(height: 8),
                  const Text(
                    "• Recibes el 80% de cada viaje completado.\n"
                    "• FlyGo retiene el 20% como comisión.\n"
                    "• Las solicitudes de retiro descuentan tu saldo disponible.\n"
                    "• Cuando una liquidación se aprueba, queda reflejada en el historial.\n"
                    "• Próximamente podrás recibir transferencias automáticas.",
                    style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.35),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _infoBox(String titulo, String valor, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: TextStyle(fontSize: 18, color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(valor, style: const TextStyle(fontSize: 24, color: Colors.white)),
        ],
      ),
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
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
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

class _CuentaEmpresaCard extends StatelessWidget {
  const _CuentaEmpresaCard();

  @override
  Widget build(BuildContext context) {
    // Valores fijos para que el taxista tenga siempre los datos correctos
    // de transferencia (independiente de `config/empresa`).
    const String titular = 'Open ASK Service SRL';
    const String banco = 'Banco Popular';
    const String tipo = 'Cuenta Corriente';
    const String cuenta = '787726249';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Datos para transferencia',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              )),
          const SizedBox(height: 10),
          _kv('Titular', titular),
          _kv('Banco', banco),
          _kv('Tipo', tipo),
          Row(
            children: [
              Expanded(child: _kv('Cuenta', cuenta)),
              IconButton(
                tooltip: 'Copiar cuenta',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: cuenta));
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Número de cuenta copiado')),
                  );
                },
                icon: const Icon(Icons.copy, color: Colors.greenAccent),
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          text: '$k: ',
          style: const TextStyle(color: Colors.white70),
          children: [
            TextSpan(text: v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
