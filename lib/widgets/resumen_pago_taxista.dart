import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/widgets/rai_cuenta_deposito_panel.dart';
import 'package:flygo_nuevo/servicios/finance_config_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/liquidacion_semanal_viaje.dart';

class ResumenPagoTaxista extends StatelessWidget {
  final double precioTotal;
  final double comision;
  final double ganancia;

  const ResumenPagoTaxista({
    super.key,
    required this.precioTotal,
    required this.comision,
    required this.ganancia,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Card(
      color: Colors.grey[900],
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resumen de Pago (viaje)',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _row('💰 Precio Total del Viaje:', FormatosMoneda.rd(precioTotal)),
            _row(
              '🧾 ${PlataformaEconomia.etiquetaComisionRai()}:',
              FormatosMoneda.rd(comision),
            ),
            _row('🚖 Ganancia del Taxista:', FormatosMoneda.rd(ganancia)),
            const SizedBox(height: 12),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),
            if (uid != null)
              _PendienteDeComision(uidTaxista: uid)
            else
              const Text(
                'Inicia sesión para ver tu comisión pendiente.',
                style: TextStyle(color: Colors.white60),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: const TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 8),
          Text(v,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _PendienteDeComision extends StatelessWidget {
  final String uidTaxista;
  const _PendienteDeComision({required this.uidTaxista});

  Stream<_PendienteData> _streamPendiente() {
    final q = FirebaseFirestore.instance
        .collection('viajes')
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('pagoRegistrado', isEqualTo: true)
        .where('liquidado', isEqualTo: false)
        .where('estado', isEqualTo: 'completado');

    return q.snapshots().map((qs) {
      int sumCents = 0;
      final ids = <String>[];
      for (final d in qs.docs) {
        final data = d.data();
        if (FinanceConfigService.excluirEfectivoDePagoSemanal &&
            !LiquidacionSemanalViaje.esElegible(data)) {
          continue;
        }
        final cc = data['comision_cents'];
        int c;
        if (cc is int) {
          c = cc;
        } else {
          final num? cNum = data['comision'] as num?;
          c = cNum == null ? 0 : (cNum * 100).round();
        }
        sumCents += c;
        ids.add(d.id);
      }
      return _PendienteData(cents: sumCents, viajesIds: ids);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<_PendienteData>(
      stream: _streamPendiente(),
      builder: (context, snap) {
        final cents = snap.data?.cents ?? 0;
        final monto = cents / 100.0;
        final viajesIds = snap.data?.viajesIds ?? const <String>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Comisión pendiente con RAI: ${FormatosMoneda.rd(monto)}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _mostrarDatosBancarios(context),
                    icon:
                        const Icon(Icons.account_balance, color: Colors.green),
                    label: const Text('Ver datos bancarios'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      minimumSize: const Size(double.infinity, 46),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (monto <= 0)
                        ? null
                        : () => _confirmarLiquidacion(
                              context: context,
                              uidTaxista: uidTaxista,
                              monto: monto,
                              viajesPendientes: viajesIds,
                            ),
                    icon: const Icon(Icons.check_circle, color: Colors.green),
                    label: const Text('Ya transferí'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      minimumSize: const Size(double.infinity, 46),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Al confirmar “Ya transferí”, envías tu comprobante a revisión. Un admin validará y marcará tus viajes como liquidados.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}

class _PendienteData {
  final int cents;
  final List<String> viajesIds;
  _PendienteData({required this.cents, required this.viajesIds});
}

/// Modal con cuenta empresa RAI (misma fuente que Mis pagos).
Future<void> _mostrarDatosBancarios(BuildContext context) async {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.black,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: ListView(
            shrinkWrap: true,
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Cuenta empresa RAI (depósito)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const RaiCuentaDepositoPanel(
                titulo: 'Transferir a',
                mostrarNota: true,
                margin: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// --------- Enviar liquidación (taxista → admin) ---------
Future<void> _confirmarLiquidacion({
  required BuildContext context,
  required String uidTaxista,
  required double monto,
  required List<String> viajesPendientes,
}) async {
  final refCtrl = TextEditingController();

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.black,
      title: const Text('Confirmar transferencia',
          style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Monto: ${FormatosMoneda.rd(monto)}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: refCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Referencia/nota de la transferencia',
              hintText: 'Ej: BANCO-123456',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar')),
      ],
    ),
  );

  if (ok != true) return;

  try {
    final db = FirebaseFirestore.instance;
    await db.collection('liquidaciones').add({
      'uidTaxista': uidTaxista,
      'monto': double.parse(monto.toStringAsFixed(2)),
      'estado': 'pendiente',
      'solicitadoEn': FieldValue.serverTimestamp(),
      if (viajesPendientes.isNotEmpty) 'viajesIds': viajesPendientes,
      if (refCtrl.text.trim().isNotEmpty) 'referencia': refCtrl.text.trim(),
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Enviado a revisión')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar: $e')),
      );
    }
  }
}
