import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/pool_repo.dart';
import 'package:flygo_nuevo/utils/pool_gira_contenido.dart';
import 'package:flygo_nuevo/widgets/pool_gira_ticket_card.dart';

/// Pantalla de ticket digital tras pago confirmado.
class PoolGiraTicketPage extends StatefulWidget {
  const PoolGiraTicketPage({
    super.key,
    required this.poolId,
    required this.reservaId,
  });

  final String poolId;
  final String reservaId;

  @override
  State<PoolGiraTicketPage> createState() => _PoolGiraTicketPageState();
}

class _PoolGiraTicketPageState extends State<PoolGiraTicketPage> {
  bool _asegurando = false;
  String? _error;

  DateTime _dateFromAny(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.now();
  }

  Future<void> _asegurarToken(Map<String, dynamic> reserva) async {
    final token = (reserva['tokenEntrada'] ?? '').toString().trim();
    if (token.isNotEmpty || _asegurando) return;
    setState(() {
      _asegurando = true;
      _error = null;
    });
    try {
      await PoolRepo.ensurePoolReservaTicket(
        poolId: widget.poolId,
        reservaId: widget.reservaId,
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _asegurando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Tu ticket'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('viajes_pool')
            .doc(widget.poolId)
            .snapshots(),
        builder: (context, poolSnap) {
          if (!poolSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final pool = poolSnap.data!.data() ?? <String, dynamic>{};

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('viajes_pool')
                .doc(widget.poolId)
                .collection('reservas')
                .doc(widget.reservaId)
                .snapshots(),
            builder: (context, resSnap) {
              if (!resSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final reserva = resSnap.data!.data() ?? <String, dynamic>{};
              final estado =
                  (reserva['estado'] ?? '').toString().trim().toLowerCase();

              if (estado != 'pagado') {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'El ticket estará disponible cuando RAI confirme tu pago.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                );
              }

              final token = (reserva['tokenEntrada'] ?? '').toString().trim();
              if (token.isEmpty && !_asegurando) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _asegurarToken(reserva);
                });
              }

              if (_asegurando && token.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (token.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error ?? 'Generando ticket…',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                );
              }

              final extra = PoolGiraContenidoExtra.fromMap(pool);
              final giraNombre = extra.nombreGira.trim().isNotEmpty
                  ? extra.nombreGira.trim()
                  : (pool['servicioBadge'] ?? pool['destino'] ?? 'Gira')
                      .toString();
              final empresa = (pool['agenciaNombre'] ?? '').toString().trim();
              final punto = (pool['puntoSalida'] ?? '').toString().trim();
              final fechaSalida = _dateFromAny(pool['fechaSalida']);
              final fechaVuelta = pool['fechaVuelta'] != null
                  ? _dateFromAny(pool['fechaVuelta'])
                  : null;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  PoolGiraTicketCard(
                    tokenEntrada: token,
                    reservaId: widget.reservaId,
                    pasajero: (reserva['clienteNombre'] ?? 'Pasajero').toString(),
                    giraNombre: giraNombre,
                    empresa: empresa,
                    asientos: ((reserva['seats'] ?? 1) as num).toInt(),
                    fechaSalida: fechaSalida,
                    fechaRegreso: fechaVuelta,
                    puntoEncuentro: punto,
                    tokenEstado: (reserva['tokenEstado'] ?? 'activo').toString(),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Presenta este código QR o el código alfanumérico el día de la salida. '
                    'RAI Driver validará tu entrada.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
