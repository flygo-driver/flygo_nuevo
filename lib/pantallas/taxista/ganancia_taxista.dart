// lib/pantallas/taxista/ganancia_taxista.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/widgets/taxista_drawer.dart';
import 'package:flygo_nuevo/widgets/saldo_ganancias_chip.dart';

class GananciaTaxista extends StatefulWidget {
  const GananciaTaxista({super.key});

  @override
  State<GananciaTaxista> createState() => GananciaTaxistaState();
}

class GananciaTaxistaState extends State<GananciaTaxista> {
  // ===== Helpers numéricos exactos (centavos) =====
  int _toCents(num v) => (v * 100).round();
  double _fromCents(int c) => c / 100.0;

  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  Future<void> _fakeRefresh() async {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('No hay sesión activa.')),
      );
    }

    // Tiempo real: solo viajes completados del taxista.
    // Si Firestore pide índice, acepta el link "Create index".
    final stream = FirebaseFirestore.instance
        .collection('viajes')
        .where('uidTaxista', isEqualTo: user.uid)
        .where('completado', isEqualTo: true)
        .snapshots();

    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const TaxistaDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            tooltip: 'Menú',
          ),
        ),
        title: const Text(
          'Ganancias del Taxista',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [SaldoGananciasChip()],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            );
          }

          if (snap.hasError) {
            return RefreshIndicator(
              color: Colors.greenAccent,
              backgroundColor: Colors.black,
              onRefresh: _fakeRefresh,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const _SummaryCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 36),
                        SizedBox(height: 12),
                        Text(
                          'Ocurrió un error al cargar las ganancias.',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _fakeRefresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final docs = snap.data?.docs ?? [];

          // ===== Acumuladores exactos en centavos =====
          int totalComisionCents = 0;
          int totalGananciaCents = 0;

          for (final d in docs) {
            final m = d.data();

            // Si *_cents faltan, calculamos 80/20 desde precioFinal o precio.
            final int precioC = _asInt(m['precio_cents']) == 0
                ? _toCents(_asDouble(m['precioFinal'] ?? m['precio']))
                : _asInt(m['precio_cents']);

            final int comisionC = _asInt(m['comision_cents']) == 0
                ? ((precioC * 20) + 50) ~/ 100 // redondeo justo
                : _asInt(m['comision_cents']);

            final int gananciaC = _asInt(m['ganancia_cents']) == 0
                ? (precioC - comisionC)
                : _asInt(m['ganancia_cents']);

            totalComisionCents += comisionC;
            totalGananciaCents += gananciaC;
          }

          final viajesCompletados = docs.length;
          final totalGanado = _fromCents(totalGananciaCents);
          final totalComision = _fromCents(totalComisionCents);
          final promedioPorViaje =
              viajesCompletados > 0 ? totalGanado / viajesCompletados : 0.0;

          // ===== UI =====
          if (viajesCompletados == 0 && totalGanado == 0.0) {
            return RefreshIndicator(
              color: Colors.greenAccent,
              backgroundColor: Colors.black,
              onRefresh: _fakeRefresh,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: const [
                  _SummaryCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.white70, size: 36),
                        SizedBox(height: 12),
                        Text(
                          'Aún no tienes viajes completados.',
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Cuando completes tu primer viaje, verás aquí tu ganancia.',
                          style: TextStyle(color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: Colors.greenAccent,
            backgroundColor: Colors.black,
            onRefresh: _fakeRefresh,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const _SummaryCard(
                  child: Row(
                    children: [
                      Icon(Icons.emoji_events,
                          color: Colors.greenAccent, size: 40),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Resumen de Ganancias',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _SummaryCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Viajes completados:',
                          style:
                              TextStyle(fontSize: 16, color: Colors.white70)),
                      const SizedBox(height: 6),
                      Text(
                        '$viajesCompletados',
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Divider(color: Colors.white12, height: 28),

                      const Text('Ganancia total:',
                          style:
                              TextStyle(fontSize: 16, color: Colors.white70)),
                      const SizedBox(height: 6),
                      Text(
                        FormatosMoneda.rd(totalGanado),
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: Colors.greenAccent,
                        ),
                      ),
                      const Divider(color: Colors.white12, height: 28),

                      const Text('Comisión acumulada (FlyGo):',
                          style:
                              TextStyle(fontSize: 16, color: Colors.white70)),
                      const SizedBox(height: 6),
                      Text(
                        FormatosMoneda.rd(totalComision),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const Divider(color: Colors.white12, height: 28),

                      const Text('Promedio por viaje:',
                          style:
                              TextStyle(fontSize: 16, color: Colors.white70)),
                      const SizedBox(height: 6),
                      Text(
                        FormatosMoneda.rd(promedioPorViaje),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Nota: La ganancia refleja únicamente viajes marcados como completados.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ===================== UI Helpers =====================

class _SummaryCard extends StatelessWidget {
  final Widget child;
  const _SummaryCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }
}
