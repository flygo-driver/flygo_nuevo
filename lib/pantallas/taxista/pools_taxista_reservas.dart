import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/pool_repo.dart';
import 'package:url_launcher/url_launcher.dart';

class PoolsTaxistaReservas extends StatelessWidget {
  final String poolId;
  const PoolsTaxistaReservas({super.key, required this.poolId});

  void _snack(ScaffoldMessengerState messenger, String m) {
    messenger.showSnackBar(SnackBar(content: Text(m)));
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

  @override
  Widget build(BuildContext context) {
    final poolRef = PoolRepo.pools.doc(poolId);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textPrimary = isDark ? Colors.white : const Color(0xFF101828);
    final Color textSecondary = isDark ? Colors.white70 : const Color(0xFF475467);
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
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: poolRef.collection('reservas').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: accent));
          }
          if (snap.hasError) {
            return Center(child: Text('Error cargando reservas.', style: TextStyle(color: textMuted)));
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(child: Text('Sin reservas aún.', style: TextStyle(color: textMuted)));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final d = docs[i].data();
              final id = docs[i].id;
              final estado = (d['estado'] ?? '').toString();
              final seats = (d['seats'] ?? 0) as int;
              final total = ((d['total'] ?? 0.0) as num).toDouble();
              final deposit = ((d['deposit'] ?? 0.0) as num).toDouble();
              final uidCliente = (d['uidCliente'] ?? '').toString();
              final waReserva = (d['clienteWhatsApp'] ?? d['clienteTelefono'] ?? '').toString();

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cardBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        future: uidCliente.isEmpty
                            ? null
                            : FirebaseFirestore.instance
                                .collection('usuarios')
                                .doc(uidCliente)
                                .get(),
                        builder: (context, userSnap) {
                          final userData = userSnap.data?.data() ?? const <String, dynamic>{};
                          final nombre = (userData['nombre'] ?? 'Pasajero').toString();
                          final tel = (userData['telefono'] ?? '').toString();
                          final wa = waReserva.trim().isNotEmpty ? waReserva : tel;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$nombre • Asientos: $seats • Estado: $estado',
                                style: TextStyle(
                                  color: textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Total: RD\$ ${total.toStringAsFixed(0)}  •  Depósito: RD\$ ${deposit.toStringAsFixed(0)}',
                                style: TextStyle(color: textSecondary),
                              ),
                              if (tel.trim().isNotEmpty || wa.trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    if (tel.trim().isNotEmpty)
                                      OutlinedButton.icon(
                                        onPressed: () => _call(ctx, tel),
                                        icon: const Icon(Icons.call, size: 15),
                                        label: const Text('Llamar'),
                                      ),
                                    if (wa.trim().isNotEmpty)
                                      OutlinedButton.icon(
                                        onPressed: () => _whatsApp(
                                          ctx,
                                          wa,
                                          'Hola $nombre, te escribo por tu reserva de la gira/viaje por cupos.',
                                        ),
                                        icon: const Icon(Icons.chat, size: 15),
                                        label: const Text('WhatsApp'),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                    if (estado != 'pagado')
                      TextButton.icon(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(ctx);
                          try {
                            await PoolRepo.marcarReservaPagadaSegura(
                              poolId: poolId,
                              reservaId: id,
                            );
                            _snack(messenger, 'Marcada como pagada');
                          } catch (e) {
                            _snack(messenger, '❌ $e');
                          }
                        },
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Marcar pagada'),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
