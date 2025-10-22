// lib/widgets/viaje_card.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ViajeCard extends StatelessWidget {
  final String origen;
  final String destino;
  final DateTime? fechaHora;
  final double precio;
  final double? gananciaTaxista;
  final double? distanciaKm;
  final String metodoPago;
  final String tipoVehiculo;
  final bool programado;         // true = PROGRAMADO, false = AHORA
  final String? estado;          // opcional: aceptado / en_curso...
  final VoidCallback? onTap;
  final bool showAceptar;        // ← en vistas de taxista suele venir true
  final VoidCallback? onAceptar;
  final Widget? trailing;

  const ViajeCard({
    super.key,
    required this.origen,
    required this.destino,
    required this.precio,
    this.fechaHora,
    this.gananciaTaxista,
    this.distanciaKm,
    this.metodoPago = 'Efectivo',
    this.tipoVehiculo = 'Carro',
    this.programado = false,
    this.estado,
    this.onTap,
    this.showAceptar = false,
    this.onAceptar,
    this.trailing,
  });

  // ================== Helpers ==================
  static final _money = NumberFormat.currency(
    locale: 'es_DO',
    symbol: 'RD\$',
    decimalDigits: 2,
  );

  String _rd(double v) => _money.format(v < 0 ? 0 : v);

  String _km(double? v) {
    if (v == null || v <= 0) return '— km';
    return v >= 100 ? '${v.toStringAsFixed(0)} km' : '${v.toStringAsFixed(1)} km';
  }

  String _fecha(DateTime? dt) {
    if (dt == null) return '—';
    return DateFormat('EEE d MMM, HH:mm', 'es').format(dt);
  }

  // ---- RESUMEN DE DIRECCIÓN (RD) ----
  String _resumirDireccionRD(String raw) {
    if (raw.trim().isEmpty) return '—';

    // Quitar país / ruido
    var s = raw
        .replaceAll(RegExp(r'\bRep(ú|u)blica Dominicana\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bDominican Republic\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bRD\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(', ,', ',')
        .trim();

    // Normalizaciones útiles
    final low = s.toLowerCase();
    if (low.contains('aeropuerto') && (low.contains('las america') || low.contains('aila'))) {
      final ciudad = _extraerCiudad(s);
      final right = ciudad.isEmpty ? '' : ' • $ciudad';
      return 'Aeropuerto Las Américas (AILA)$right';
    }

    // Quitar “Santo Domingo D.N.” variantes
    s = s.replaceAll(RegExp(r'Santo Domingo\s*D\.?N\.?', caseSensitive: false), 'Santo Domingo');

    final partes = s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (partes.isEmpty) return '—';

    var principal = partes.first;
    var secundaria = _extraerCiudad(s);

    principal = _ellipsis(principal, 30);
    secundaria = _ellipsis(secundaria, 22);

    if (secundaria.isEmpty) return principal;
    return '$principal • $secundaria';
  }

  String _extraerCiudad(String s) {
    final partes = s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (partes.isEmpty) return '';
    for (var i = partes.length - 1; i >= 0; i--) {
      final p = partes[i];
      final l = p.toLowerCase();
      final esPais = l.contains('república dominicana') || l.contains('dominican republic') || l == 'rd';
      if (!esPais) return p;
    }
    return '';
  }

  String _ellipsis(String s, int max) {
    final t = s.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max - 1)}…';
  }

  IconData _iconoPago(String m) {
    final x = m.toLowerCase();
    if (x.contains('tarj')) return Icons.credit_card;
    if (x.contains('trans')) return Icons.swap_horiz_rounded;
    return Icons.payments_outlined;
  }

  IconData _iconoVeh(String v) {
    final x = v.toLowerCase();
    if (x.contains('suv')) return Icons.directions_car_filled_rounded;
    if (x.contains('mini')) return Icons.airport_shuttle_rounded;
    return Icons.directions_car_rounded;
  }

  Color _chipColor() => programado ? Colors.orangeAccent : Colors.greenAccent;

  // ================== UI ==================
  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).brightness == Brightness.dark
        ? Colors.grey[900]
        : Colors.white;

    final precioTxt = _rd(precio);
    final ganaTxt = (gananciaTaxista != null && gananciaTaxista! > 0)
        ? _rd(gananciaTaxista!)
        : null;

    // Vista TAXISTA (donde se acepta): ocultar TOTAL y mostrar SOLO ganancia
    final bool vistaTaxista = showAceptar && ganaTxt != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Chips arriba
              Row(
                children: [
                  _EstadoChip(
                    label: programado ? 'PROGRAMADO' : 'AHORA',
                    secundario: (estado ?? '').isNotEmpty ? estado!.toUpperCase() : null,
                    color: _chipColor(),
                  ),
                  const Spacer(),
                  if (fechaHora != null)
                    Row(
                      children: [
                        const Icon(Icons.schedule, size: 16, color: Colors.white70),
                        const SizedBox(width: 6),
                        Text(
                          _fecha(fechaHora),
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Bloque direcciones
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Column(
                      children: [
                        _punto(Colors.greenAccent),
                        _linea(),
                        _punto(Colors.redAccent),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _oneLine(
                            _resumirDireccionRD(origen),
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _oneLine(
                            _resumirDireccionRD(destino),
                            const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      child: Text(
                        _km(distanciaKm),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Footer
              Row(
                children: [
                  _pill(icon: _iconoVeh(tipoVehiculo), text: tipoVehiculo),
                  const SizedBox(width: 8),
                  _pill(icon: _iconoPago(metodoPago), text: metodoPago),
                  const Spacer(),

                  // ===== SOLO cambio aquí =====
                  if (!vistaTaxista) ...[
                    // Vista normal (cliente / listas): Total visible
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          precioTxt,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (ganaTxt != null)
                          Text(
                            'Gana: $ganaTxt',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                      ],
                    ),
                  ] else ...[
                   // Vista taxista (showAceptar=true): SOLO ganancia en super grande
Text(
  ganaTxt, // ← quita el '!'
  textAlign: TextAlign.right,
  style: const TextStyle(
    color: Color(0xFF49F18B),
    fontSize: 40,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.5,
  ),
),
 ],

                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),

              if (showAceptar) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onAceptar,
                    icon: const Icon(Icons.done_all),
                    label: const Text('Aceptar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.green,
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---- mini widgets ----
  Widget _oneLine(String text, TextStyle style) => Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      );

  Widget _pill({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _punto(Color c) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  Widget _linea() => Container(
        width: 2,
        height: 26,
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

class _EstadoChip extends StatelessWidget {
  final String label;
  final String? secundario;
  final Color color;
  const _EstadoChip({required this.label, required this.color, this.secundario});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.20),
        border: Border.all(color: color.withValues(alpha: 0.70)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(Icons.trip_origin, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          if ((secundario ?? '').isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              secundario!,
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
