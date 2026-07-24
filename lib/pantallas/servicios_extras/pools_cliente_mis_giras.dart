import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/servicios_extras/pool_gira_ticket_page.dart';
import 'package:flygo_nuevo/pantallas/servicios_extras/pools_cliente_detalle.dart';
import 'package:flygo_nuevo/servicios/pool_repo.dart';
import 'package:flygo_nuevo/utils/hora_am_pm.dart';
import 'package:flygo_nuevo/utils/pool_gira_contenido.dart';

/// Historial global de reservas del cliente en giras por cupos.
class PoolsClienteMisGiras extends StatefulWidget {
  const PoolsClienteMisGiras({super.key});

  @override
  State<PoolsClienteMisGiras> createState() => _PoolsClienteMisGirasState();
}

class _PoolsClienteMisGirasState extends State<PoolsClienteMisGiras> {
  int _filtro = 0; // 0 próximas, 1 pasadas, 2 todas

  DateTime _fechaSalida(Map<String, dynamic> pool) {
    final raw = pool['fechaSalida'] ?? pool['fecha'] ?? pool['fechaHora'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool _esProxima(PoolReservaClienteGira item) {
    final est = (item.reserva['estado'] ?? '').toString().toLowerCase();
    if (est == 'cancelado') return false;
    final salida = _fechaSalida(item.pool);
    return salida.isAfter(DateTime.now().subtract(const Duration(hours: 8)));
  }

  bool _esPasada(PoolReservaClienteGira item) {
    final est = (item.reserva['estado'] ?? '').toString().toLowerCase();
    if (est == 'cancelado') return true;
    final salida = _fechaSalida(item.pool);
    return !salida.isAfter(DateTime.now().subtract(const Duration(hours: 8)));
  }

  List<PoolReservaClienteGira> _filtrar(List<PoolReservaClienteGira> items) {
    switch (_filtro) {
      case 0:
        return items.where(_esProxima).toList();
      case 1:
        return items.where(_esPasada).toList();
      default:
        return items;
    }
  }

  String _estadoLabel(Map<String, dynamic> r) {
    final est = (r['estado'] ?? '').toString().toLowerCase();
    final ep = (r['estadoPago'] ?? '').toString().toLowerCase();
    if (est == 'pagado') return 'Pago confirmado';
    if (est == 'cancelado') return 'Cancelada';
    if (ep == 'comprobante_enviado') return 'Recibo enviado';
    if (ep == 'verificado') return 'Pago verificado';
    return 'Reservado · pendiente pago';
  }

  Color _estadoColor(String label, ColorScheme cs) {
    if (label.contains('confirmado') || label.contains('verificado')) {
      return cs.primary;
    }
    if (label.contains('Cancelada')) return cs.error;
    if (label.contains('Recibo')) return cs.tertiary;
    return cs.outline;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF101828);
    final textMuted = isDark ? Colors.white54 : const Color(0xFF667085);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFE8EAED),
      appBar: AppBar(
        title: const Text('Mis giras'),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Todas tus reservas en giras, tours y excursiones — en un solo lugar.',
              style: TextStyle(color: textMuted, height: 1.35, fontSize: 13),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Próximas'),
                  selected: _filtro == 0,
                  onSelected: (_) => setState(() => _filtro = 0),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Pasadas'),
                  selected: _filtro == 1,
                  onSelected: (_) => setState(() => _filtro = 1),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Todas'),
                  selected: _filtro == 2,
                  onSelected: (_) => setState(() => _filtro = 2),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<PoolReservaClienteGira>>(
              stream: PoolRepo.streamMisReservasGiraCliente(uid),
              builder: (context, snap) {
                if (uid.isEmpty) {
                  return const Center(child: Text('Inicia sesión para ver tus giras'));
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No se pudo cargar el historial.\n${snap.error}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.error),
                      ),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = _filtrar(snap.data!);
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.beach_access_outlined,
                              size: 48, color: textMuted),
                          const SizedBox(height: 12),
                          Text(
                            _filtro == 0
                                ? 'No tienes giras próximas'
                                : _filtro == 1
                                    ? 'Sin giras pasadas aún'
                                    : 'Aún no has reservado ninguna gira',
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Explora el catálogo y reserva cupos cuando quieras.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: textMuted),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final pool = item.pool;
                    final r = item.reserva;
                    final contenido = PoolGiraContenidoExtra.fromMap(pool);
                    final nombre = contenido.nombreGira.trim();
                    final destino = (pool['destino'] ?? '').toString();
                    final origen = (pool['origenTown'] ?? '').toString();
                    final titulo = nombre.isNotEmpty
                        ? nombre
                        : (destino.isNotEmpty
                            ? (origen.isNotEmpty ? '$origen → $destino' : destino)
                            : 'Gira por cupos');
                    final salida = _fechaSalida(pool);
                    final seats = ((r['seats'] ?? 0) as num).toInt();
                    final total = ((r['total'] ?? 0) as num).toDouble();
                    final estLabel = _estadoLabel(r);
                    final est = (r['estado'] ?? '').toString().toLowerCase();
                    final pagado = est == 'pagado';

                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => PoolsClienteDetalle(poolId: item.poolId),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                titulo,
                                style: TextStyle(
                                  color: textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                salida.year > 2000
                                    ? fmtFechaHoraAmPm(salida, conAnio: true)
                                    : 'Fecha por confirmar',
                                style: TextStyle(color: textMuted, fontSize: 13),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '$seats asiento(s) · RD\$ ${total.toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                estLabel,
                                style: TextStyle(
                                  color: _estadoColor(estLabel, cs),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => PoolsClienteDetalle(
                                            poolId: item.poolId,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.open_in_new, size: 16),
                                    label: const Text('Ver gira'),
                                  ),
                                  if (pagado)
                                    FilledButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute<void>(
                                            builder: (_) => PoolGiraTicketPage(
                                              poolId: item.poolId,
                                              reservaId: item.reservaId,
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.qr_code_2, size: 16),
                                      label: const Text('Ticket / QR'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
