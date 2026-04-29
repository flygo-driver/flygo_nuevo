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
                    metodoL == 'transferencia'
                        ? 'Pago: transferencia — coordiná el bauche por WhatsApp o llamada'
                        : 'Pago: $metodo',
                    style: TextStyle(
                        color: textSecondary, fontSize: 12, height: 1.25),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Total RD\$ ${total.toStringAsFixed(0)} · Depósito RD\$ ${deposit.toStringAsFixed(0)}',
                  style: TextStyle(color: textSecondary, fontSize: 13),
                ),
              ),
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
                          'Hola $nombre, te escribo por tu reserva del viaje por cupos (pago / bauche).',
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
    final poolRef = PoolRepo.pools.doc(poolId);
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
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // Sin orderBy: evita índices y sigue mostrando reservas legacy sin createdAt.
        stream: poolRef.collection('reservas').snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: accent));
          }
          if (snap.hasError) {
            return Center(
                child: Text('Error cargando reservas.',
                    style: TextStyle(color: textMuted)));
          }

          var docs = snap.data?.docs ?? [];
          docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs)
            ..sort((a, b) {
              final ta = a.data()['createdAt'];
              final tb = b.data()['createdAt'];
              final da = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
              final db = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
              return db.compareTo(da);
            });
          if (docs.isEmpty) {
            return Center(
                child: Text('Sin reservas aún.',
                    style: TextStyle(color: textMuted)));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final d = docs[i].data();
              final id = docs[i].id;
              final estado = (d['estado'] ?? '').toString();
              final seats = ((d['seats'] ?? 0) as num).toInt();
              final total = ((d['total'] ?? 0.0) as num).toDouble();
              final deposit = ((d['deposit'] ?? 0.0) as num).toDouble();
              final uidCliente = (d['uidCliente'] ?? '').toString();
              final metodo = (d['metodoPago'] ?? '').toString();
              final telReserva = (d['clienteTelefono'] ?? '').toString().trim();
              final waReserva = (d['clienteWhatsApp'] ?? '').toString().trim();

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
                              waEfectivo:
                                  waReserva.isNotEmpty ? waReserva : telReserva,
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
