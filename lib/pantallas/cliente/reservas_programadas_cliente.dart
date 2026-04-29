import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/pantallas/cliente/viaje_programado_confirmacion.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';

/// Lista de viajes programados aún no terminados (acceso desde el menú).
class ReservasProgramadasCliente extends StatelessWidget {
  const ReservasProgramadasCliente({super.key});

  static DateTime _asDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static bool _esTerminal(Map<String, dynamic> d) {
    final e = EstadosViaje.normalizar((d['estado'] ?? '').toString());
    if (EstadosViaje.esCancelado(e) || EstadosViaje.esCompletado(e)) {
      return true;
    }
    if (d['completado'] == true) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final fmt = DateFormat("EEE d MMM · HH:mm", 'es');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Mis reservas programadas',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: user == null
          ? const Center(
              child: Text('Inicia sesión',
                  style: TextStyle(color: Colors.white70)),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('viajes')
                  .where('clienteId', isEqualTo: user.uid)
                  .limit(60)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No se pudo cargar la lista. ${snap.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: Colors.greenAccent));
                }
                final docs = snap.data!.docs.where((d) {
                  final m = d.data();
                  if (m['programado'] != true) return false;
                  if (_esTerminal(m)) return false;
                  final tipo = (m['tipoServicio'] ?? '').toString();
                  if (tipo == 'turismo') return false;
                  return true;
                }).toList()
                  ..sort((a, b) {
                    final ta = _asDate(a.data()['fechaHora']);
                    final tb = _asDate(b.data()['fechaHora']);
                    return ta.compareTo(tb);
                  });

                if (docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No tienes reservas programadas activas.\nPrograma un viaje desde el menú.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, height: 1.4),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final m = d.data();
                    final fecha = _asDate(m['fechaHora']);
                    final origen = (m['origen'] ?? '').toString();
                    final destino = (m['destino'] ?? '').toString();
                    final precio = _asDouble(
                        m['precioFinal'] ?? m['precio'] ?? m['total']);
                    final ref = d.id.length >= 6 ? d.id.substring(0, 6) : d.id;
                    return Material(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.event_note,
                                    color: Colors.greenAccent, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    fmt.format(fecha),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                Text(
                                  '#$ref',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$origen → $destino',
                              style: const TextStyle(
                                  color: Colors.white70, height: 1.3),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (precio > 0) ...[
                              const SizedBox(height: 6),
                              Text(
                                FormatosMoneda.rd(precio),
                                style: const TextStyle(
                                  color: Color(0xFF49F18B),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => ViajeProgramadoConfirmacion(
                                        viajeId: d.id),
                                  ),
                                );
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    Colors.greenAccent.withValues(alpha: 0.2),
                                foregroundColor: Colors.greenAccent,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: const BorderSide(
                                      color: Colors.greenAccent, width: 1),
                                ),
                              ),
                              child: const Text('Ver detalles'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
