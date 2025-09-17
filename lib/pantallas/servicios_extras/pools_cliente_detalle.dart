import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PoolsClienteDetalle extends StatefulWidget {
  final String poolId;
  const PoolsClienteDetalle({super.key, required this.poolId});

  @override
  State<PoolsClienteDetalle> createState() => _PoolsClienteDetalleState();
}

class _PoolsClienteDetalleState extends State<PoolsClienteDetalle> {
  final _db = FirebaseFirestore.instance;
  int _seats = 1;
  String _metodo = 'transferencia'; // 'transferencia' | 'efectivo'
  bool _saving = false;

  // === Config FlyGo (transferencia) ===
  static const String _banco = 'BANRESERVAS';
  static const String _cuenta = '960-1234567-8';
  static const String _tipoCuenta = 'Cuenta Corriente';
  static const String _titular = 'FLYGO RD, SRL';
  static const String _concepto = 'Depósito reserva de cupos';

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('EEE d MMM • HH:mm', 'es');
    final poolRef = _db.collection('pools').doc(widget.poolId);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Detalle del viaje',
          style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: poolRef.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.data!.exists) {
            return const Center(child: Text('El viaje no existe.', style: TextStyle(color: Colors.white54)));
          }
          final d = snap.data!.data()!;
          final origen = (d['origenTown'] ?? '').toString();
          final destino = (d['destino'] ?? '').toString();
          final fecha = (d['fechaSalida'] as Timestamp).toDate();
          final fechaVuelta = d['fechaVuelta'] is Timestamp ? (d['fechaVuelta'] as Timestamp).toDate() : null;
          final sentido = (d['sentido'] ?? 'ida').toString(); // ida | vuelta | ida_y_vuelta
          final mult = (sentido == 'ida_y_vuelta') ? 2 : 1;

          final cap = (d['capacidad'] ?? 0) as int;
          final occ = (d['asientosReservados'] ?? 0) as int;
          final minConf = (d['minParaConfirmar'] ?? 0) as int;
          final estado = (d['estado'] ?? 'abierto').toString(); // abierto | confirmado | cerrado
          final left = (cap - occ).clamp(0, cap);

          final precioSeat = ((d['precioPorAsiento'] ?? 0.0) as num).toDouble();
          final precioTotalPorSeat = precioSeat * mult;
          final depositPct = ((d['depositPct'] ?? 0.3) as num).toDouble().clamp(0, 1);
          // feePct eliminado porque no se usa aquí para evitar warning

          final pickupPoints = (d['pickupPoints'] is List)
              ? List<String>.from(d['pickupPoints'] as List)
              : <String>[];
          final pickup = pickupPoints.isNotEmpty ? pickupPoints.first : 'Parque Central';

          final titulo = '$origen → $destino';
          final confirmado = estado == 'confirmado';

          // Totales con asientos seleccionados
          final total = (_seats * precioTotalPorSeat).toDouble();
          final deposito = (total * depositPct);
          final restante = (total - deposito);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF121212),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          titulo,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (confirmado)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
                          ),
                          child: const Text('Confirmado',
                              style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w700)),
                        ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      fechaVuelta == null
                          ? f.format(fecha)
                          : '${f.format(fecha)}  •  Vuelta: ${f.format(fechaVuelta)}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: cap == 0 ? 0 : (occ / cap).clamp(0, 1),
                              backgroundColor: Colors.white12,
                              color: Colors.greenAccent,
                              minHeight: 8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('$occ/$cap', style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Punto de encuentro: $pickup',
                        style: const TextStyle(color: Colors.white70)),
                    Text('Quedan $left cupos',
                        style: const TextStyle(color: Colors.white70)),
                    if (minConf > 0)
                      Text('Mínimo para confirmar: $minConf',
                          style: const TextStyle(color: Colors.white38)),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Selector de asientos
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF121212),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    const Text('Asientos', style: TextStyle(color: Colors.white70)),
                    const Spacer(),
                    IconButton(
                      onPressed: (_seats > 1)
                          ? () => setState(() => _seats--)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.white70),
                    ),
                    Text('$_seats', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    IconButton(
                      onPressed: (_seats < left)
                          ? () => setState(() => _seats++)
                          : null,
                      icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Precio / Depósito
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF121212),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Precio por persona: RD\$ ${precioTotalPorSeat.toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text('Total: RD\$ ${total.toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text('Depósito (FlyGo): RD\$ ${deposito.toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w900)),
                    Text('Resto al abordar: RD\$ ${restante.toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Método de pago
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF121212),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Método de pago', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 8),
                    RadioListTile<String>(
                      value: 'transferencia',
                      groupValue: _metodo,
                      onChanged: (v) => setState(() => _metodo = v ?? 'transferencia'),
                      activeColor: Colors.greenAccent,
                      title: const Text('Transferencia bancaria (FlyGo)', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Pagar depósito por transferencia', style: TextStyle(color: Colors.white54)),
                    ),
                    RadioListTile<String>(
                      value: 'efectivo',
                      groupValue: _metodo,
                      onChanged: (v) => setState(() => _metodo = v ?? 'transferencia'),
                      activeColor: Colors.greenAccent,
                      title: const Text('Efectivo al abordar', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Pagas el total el día del viaje', style: TextStyle(color: Colors.white54)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Botón reservar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_saving || left == 0) ? null : () => _reservar(
                    poolRef,
                    seats: _seats,
                    total: total,
                    deposito: deposito,
                    restante: restante,
                    metodo: _metodo,
                    minConf: minConf,
                    cap: cap,
                    occ: occ,
                  ),
                  icon: const Icon(Icons.event_seat),
                  label: Text(_saving ? 'Reservando…' : 'Reservar asientos'),
                ),
              ),

              const SizedBox(height: 12),

              // Nota de confianza
              const Text(
                'Todos los depósitos se hacen a la cuenta FlyGo. FlyGo libera el pago al taxista cuando el viaje se confirma/realiza.',
                style: TextStyle(color: Colors.white38),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _reservar(
    DocumentReference<Map<String, dynamic>> poolRef, {
    required int seats,
    required double total,
    required double deposito,
    required double restante,
    required String metodo,
    required int minConf,
    required int cap,
    required int occ,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Debes iniciar sesión.');
      return;
    }
    if (seats <= 0) {
      _snack('Asientos inválidos.');
      return;
    }

    setState(() => _saving = true);
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(poolRef);
        if (!snap.exists) throw 'El viaje no existe.';
        final data = snap.data()!;
        final capT = (data['capacidad'] ?? 0) as int;
        final occT = (data['asientosReservados'] ?? 0) as int;
        final leftT = (capT - occT);
        if (seats > leftT) throw 'No hay cupos suficientes.';

        // Crea la reserva
        final reservasCol = poolRef.collection('reservas');
        final resRef = reservasCol.doc(); // autogen id
        tx.set(resRef, {
          'uidCliente': user.uid,
          'seats': seats,
          'total': total,
          'deposit': deposito,
          'restante': restante,
          'metodo': metodo, // transferencia | efectivo
          'estado': 'reservado', // 'pagado' solo cuando se confirme pago
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Actualiza ocupación
        tx.update(poolRef, {
          'asientosReservados': occT + seats,
        });

        // Si alcanza mínimo → confirmar
        final minT = (data['minParaConfirmar'] ?? minConf) as int;
        final estado = (data['estado'] ?? 'abierto').toString();
        if (estado != 'confirmado' && (occT + seats) >= minT && minT > 0) {
          tx.update(poolRef, {
            'estado': 'confirmado',
            'confirmadoAt': FieldValue.serverTimestamp(),
          });
        }
      });

      if (!mounted) return;

      if (metodo == 'transferencia') {
        _mostrarInstruccionesTransferencia(deposito);
      } else {
        _snack('Reserva creada. Paga en efectivo al abordar.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      _snack('❌ $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _mostrarInstruccionesTransferencia(double deposito) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E0E0E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Transferencia a FlyGo',
                    style: TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _bankRow('Banco', _banco),
                _bankRow('No. de cuenta', _cuenta),
                _bankRow('Tipo de cuenta', _tipoCuenta),
                _bankRow('Titular', _titular),
                _bankRow('Concepto', _concepto),
                const SizedBox(height: 10),
                Text('Monto del depósito: RD\$ ${deposito.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                const Text(
                  'Una vez realices la transferencia, guarda el comprobante. '
                  'FlyGo verificará tu pago y actualizará el estado a "pagado".',
                  style: TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pop(context, true);
                      _snack('Reserva creada. Revisa tu historial para ver el estado.');
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Entendido'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bankRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(k, style: const TextStyle(color: Colors.white54))),
          Expanded(child: Text(v, style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
  }
}
