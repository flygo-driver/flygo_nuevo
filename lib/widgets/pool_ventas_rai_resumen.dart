import 'package:flutter/material.dart';

/// Resumen de cupos vendidos / quedan para el organizador y admin.
class PoolVentasRaiResumen extends StatelessWidget {
  const PoolVentasRaiResumen({
    super.key,
    required this.poolData,
    this.compact = false,
  });

  final Map<String, dynamic> poolData;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cap = ((poolData['capacidad'] ?? 0) as num).toInt();
    final occ = ((poolData['asientosReservados'] ?? 0) as num).toInt();
    final pag = ((poolData['asientosPagados'] ?? 0) as num).toInt();
    final firmes = ((poolData['asientosFirmesSalida'] ?? pag) as num).toInt();
    final topeRai = ((poolData['cuposComisionRai'] ?? 0) as num).toInt();
    final quedan = (cap - occ).clamp(0, cap);
    final progreso = cap <= 0 ? 0.0 : (occ / cap).clamp(0.0, 1.0);

    final Color accent = const Color(0xFF0D9488);
    final Color warn = const Color(0xFFDC6803);
    final Color bg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFF0FDFA);
    final Color border = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : const Color(0xFF99F6E4);

    final bool pocas = quedan > 0 && quedan <= 3;
    final bool lleno = quedan <= 0;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                lleno
                    ? Icons.event_seat_rounded
                    : (pocas ? Icons.warning_amber_rounded : Icons.people_rounded),
                size: 18,
                color: lleno ? warn : accent,
              ),
              const SizedBox(width: 6),
              Text(
                'Ventas en RAI',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF134E4A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progreso,
              minHeight: 8,
              backgroundColor: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
              color: lleno ? warn : accent,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: <Widget>[
              _chip('Reservados', '$occ/$cap', isDark),
              _chip('Pagados', '$pag', isDark),
              _chip(
                'Quedan',
                '$quedan',
                isDark,
                highlight: pocas || lleno,
              ),
              if (topeRai > 0)
                _chip('Vendidos RAI', '$firmes / $topeRai tope', isDark),
            ],
          ),
          if (!compact) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              lleno
                  ? 'Cupos agotados. Revisa reservas pendientes de pago en «Ver reservas».'
                  : (pocas
                      ? 'Quedan pocos cupos. Los datos de RAI son los asientos vendidos y verificados en la app.'
                      : 'Cada venta en la app te notifica al instante. RAI valida transferencias antes de confirmar.'),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: isDark ? Colors.white70 : const Color(0xFF475467),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, String value, bool isDark, {bool highlight = false}) {
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : const Color(0xFF667085),
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: highlight
                  ? const Color(0xFFDC6803)
                  : (isDark ? Colors.white : const Color(0xFF134E4A)),
            ),
          ),
        ],
      ),
    );
  }
}
