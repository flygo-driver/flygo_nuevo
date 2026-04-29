import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/utils/formatos_moneda.dart';
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

  /// Color para montos / acentos tipo “ganancia” (legible en claro y oscuro).
  Color _gainColor(ColorScheme cs) {
    return cs.brightness == Brightness.dark
        ? const Color(0xFF69F0AE)
        : const Color(0xFF00796B);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: Center(
          child: Text(
            'No hay sesión activa.',
            style: TextStyle(color: cs.onSurface),
          ),
        ),
      );
    }

    // Tiempo real: todos los viajes completados del taxista
    final stream = FirebaseFirestore.instance
        .collection('viajes')
        .where('uidTaxista', isEqualTo: user.uid)
        .where('completado', isEqualTo: true)
        .snapshots();

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: cs.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Text(
          'Ganancias del Taxista',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        centerTitle: true,
        iconTheme: IconThemeData(color: cs.onSurface),
        actions: const [SaldoGananciasChip()],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          final cs = Theme.of(context).colorScheme;
          final gain = _gainColor(cs);
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: cs.primary),
            );
          }

          if (snap.hasError) {
            return RefreshIndicator(
              color: cs.primary,
              backgroundColor: cs.surface,
              onRefresh: _fakeRefresh,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _SummaryCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline, color: cs.error, size: 36),
                        const SizedBox(height: 12),
                        Text(
                          'Ocurrió un error al cargar las ganancias.',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _fakeRefresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
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

          // 🔥 NUEVO: Acumuladores por tipo de servicio
          int viajesNormales = 0;
          int viajesMotor = 0;
          int viajesTurismo = 0;
          int gananciaNormalesCents = 0;
          int gananciaMotorCents = 0;
          int gananciaTurismoCents = 0;

          for (final d in docs) {
            final m = d.data();

            // Determinar tipo de servicio
            final String tipoServicio = m['tipoServicio'] ?? 'normal';

            // Precio
            final int precioC = _asInt(m['precio_cents']) == 0
                ? _toCents(_asDouble(m['precioFinal'] ?? m['precio']))
                : _asInt(m['precio_cents']);

            // Comisión (si existe en el documento)
            int comisionC = _asInt(m['comision_cents']);

            // Si no hay comisión guardada, calcular según tipo
            if (comisionC == 0) {
              if (tipoServicio == 'turismo') {
                // Turismo: 15% comisión
                comisionC = ((precioC * 15) + 50) ~/ 100;
              } else {
                // Normal/Motor: 20% comisión
                comisionC = ((precioC * 20) + 50) ~/ 100;
              }
            }

            final int gananciaC = precioC - comisionC;

            // Acumular totales
            totalComisionCents += comisionC;
            totalGananciaCents += gananciaC;

            // 🔥 NUEVO: Acumular por tipo
            switch (tipoServicio) {
              case 'motor':
                viajesMotor++;
                gananciaMotorCents += gananciaC;
                break;
              case 'turismo':
                viajesTurismo++;
                gananciaTurismoCents += gananciaC;
                break;
              default:
                viajesNormales++;
                gananciaNormalesCents += gananciaC;
            }
          }

          final viajesCompletados = docs.length;
          final totalGanado = _fromCents(totalGananciaCents);
          final totalComision = _fromCents(totalComisionCents);
          final promedioPorViaje =
              viajesCompletados > 0 ? totalGanado / viajesCompletados : 0.0;

          // ===== UI =====
          if (viajesCompletados == 0 && totalGanado == 0.0) {
            return RefreshIndicator(
              color: cs.primary,
              backgroundColor: cs.surface,
              onRefresh: _fakeRefresh,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _SummaryCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: cs.onSurfaceVariant,
                          size: 36,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Aún no tienes viajes completados.',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Cuando completes tu primer viaje, verás aquí tu ganancia.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: cs.primary,
            backgroundColor: cs.surface,
            onRefresh: _fakeRefresh,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _SummaryCard(
                  child: Row(
                    children: [
                      Icon(Icons.emoji_events, color: gain, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Resumen de Ganancias',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 🔥 NUEVO: Tarjeta de resumen por tipo de servicio
                if (viajesNormales > 0 || viajesMotor > 0 || viajesTurismo > 0)
                  _SummaryCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Desglose por servicio:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Normales
                        if (viajesNormales > 0) ...[
                          _buildTipoRow(
                            context: context,
                            icon: Icons.directions_car,
                            color: gain,
                            label: 'Normales',
                            cantidad: viajesNormales,
                            ganancia: _fromCents(gananciaNormalesCents),
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Motor
                        if (viajesMotor > 0) ...[
                          _buildTipoRow(
                            context: context,
                            icon: Icons.motorcycle,
                            color: Colors.orange.shade700,
                            label: 'Motor',
                            cantidad: viajesMotor,
                            ganancia: _fromCents(gananciaMotorCents),
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Turismo
                        if (viajesTurismo > 0) ...[
                          _buildTipoRow(
                            context: context,
                            icon: Icons.beach_access,
                            color: cs.brightness == Brightness.dark
                                ? Colors.purpleAccent
                                : Colors.deepPurple,
                            label: 'Turismo',
                            cantidad: viajesTurismo,
                            ganancia: _fromCents(gananciaTurismoCents),
                          ),
                        ],
                      ],
                    ),
                  ),

                const SizedBox(height: 14),

                _SummaryCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Viajes completados:',
                        style: TextStyle(
                          fontSize: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$viajesCompletados',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                      Divider(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                        height: 28,
                      ),
                      Text(
                        'Ganancia total:',
                        style: TextStyle(
                          fontSize: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        FormatosMoneda.rd(totalGanado),
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: gain,
                        ),
                      ),
                      Divider(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                        height: 28,
                      ),
                      Text(
                        'Comisión acumulada (FlyGo):',
                        style: TextStyle(
                          fontSize: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        FormatosMoneda.rd(totalComision),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Divider(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                        height: 28,
                      ),
                      Text(
                        'Promedio por viaje:',
                        style: TextStyle(
                          fontSize: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        FormatosMoneda.rd(promedioPorViaje),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Nota: La ganancia refleja únicamente viajes marcados como completados.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),

                // 🔥 NUEVO: Nota sobre comisiones
                const SizedBox(height: 8),
                Text(
                  '• Viajes normales/motor: 80% para taxista, 20% comisión\n'
                  '• Viajes turismo: 85% para taxista, 15% comisión',
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // 🔥 NUEVO: Widget para mostrar fila de desglose por tipo
  Widget _buildTipoRow({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String label,
    required int cantidad,
    required double ganancia,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(
          flex: 1,
          child: Text(
            '$cantidad viaje${cantidad != 1 ? 's' : ''}',
            style: TextStyle(color: cs.onSurface),
            textAlign: TextAlign.right,
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            FormatosMoneda.rd(ganancia),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

// ===================== UI Helpers =====================

class _SummaryCard extends StatelessWidget {
  final Widget child;
  const _SummaryCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(
          alpha: isDark ? 0.55 : 0.65,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: isDark ? 0.35 : 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.45 : 0.55),
        ),
      ),
      child: child,
    );
  }
}
