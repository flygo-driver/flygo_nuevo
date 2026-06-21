import 'package:flutter/material.dart';

/// Banner informativo de promo M×K para el cliente en cotización.
/// Solo lectura: usa el `promoSnapshot` que ya genera [TarifaServiceUnificado].
class PromoMxKClientePanel extends StatelessWidget {
  const PromoMxKClientePanel({
    super.key,
    this.promoSnapshot,
    this.promoOmitidaPorLargaDistancia = false,
    this.textColor,
    this.mutedColor,
  });

  final Map<String, dynamic>? promoSnapshot;
  final bool promoOmitidaPorLargaDistancia;
  final Color? textColor;
  final Color? mutedColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = textColor ?? cs.onSurface;
    final muted = mutedColor ?? cs.onSurfaceVariant;

    if (promoOmitidaPorLargaDistancia) {
      return _card(
        accent: muted,
        icon: Icons.info_outline_rounded,
        fg: fg,
        muted: muted,
        title: 'Promo RAI en viajes locales',
        body: Text(
          'En trayectos interurbanos no aplica el descuento M×K. '
          'El total mostrado es el precio completo de este viaje.',
          style: TextStyle(color: muted, fontSize: 12.5, height: 1.35),
        ),
      );
    }

    final ui = PromoMxKClienteUi.fromSnapshot(promoSnapshot);
    if (ui == null) return const SizedBox.shrink();

    final Color accent =
        ui.aplicaDescuentoEsteViaje ? Colors.green.shade700 : Colors.amber.shade800;

    return _card(
      accent: accent,
      icon: ui.aplicaDescuentoEsteViaje
          ? Icons.local_offer_rounded
          : Icons.schedule_rounded,
      fg: fg,
      muted: muted,
      title: ui.titulo,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ui.subtitulo,
            style: TextStyle(
              color: fg,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tu secuencia RAI',
            style: TextStyle(
              color: muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List<Widget>.generate(ui.ciclo.clamp(1, 12), (int i) {
              final int pos = i + 1;
              final bool desc = pos <= ui.m;
              final bool actual = pos == ui.posicionCiclo;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: desc
                      ? Colors.green.withValues(alpha: actual ? 0.22 : 0.12)
                      : Colors.blue.withValues(alpha: actual ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: actual
                        ? accent
                        : (desc ? Colors.green : Colors.blue)
                            .withValues(alpha: 0.55),
                    width: actual ? 2 : 1,
                  ),
                ),
                child: Text(
                  desc ? '#$pos −${ui.porcentaje}%' : '#$pos precio normal',
                  style: TextStyle(
                    color: desc ? Colors.green.shade800 : Colors.blue.shade800,
                    fontWeight: actual ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              );
            }),
          ),
          if (ui.mensajeExtra.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              ui.mensajeExtra,
              style: TextStyle(color: muted, fontSize: 12, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card({
    required Color accent,
    required IconData icon,
    required Color fg,
    required Color muted,
    required String title,
    required Widget body,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
  }
}

class PromoMxKClienteUi {
  const PromoMxKClienteUi({
    required this.modo,
    required this.m,
    required this.k,
    required this.porcentaje,
    required this.ciclo,
    required this.posicionCiclo,
    required this.aplicaDescuentoEsteViaje,
  });

  final String modo;
  final int m;
  final int k;
  final int porcentaje;
  final int ciclo;
  final int posicionCiclo;
  final bool aplicaDescuentoEsteViaje;

  String get titulo => 'Promo RAI $modo';

  String get subtitulo {
    if (aplicaDescuentoEsteViaje) {
      return '−$porcentaje% en este viaje · ya incluido en el total';
    }
    return 'Viaje $posicionCiclo de $ciclo · precio normal en este viaje';
  }

  String get mensajeExtra {
    if (aplicaDescuentoEsteViaje) {
      final int fullRestantes = _fullRestantesEnCiclo();
      if (fullRestantes <= 0) return '';
      return 'Después de $m viaje${m == 1 ? '' : 's'} con descuento, '
          'viene $k viaje${k == 1 ? '' : 's'} a precio normal en tu ciclo RAI.';
    }
    return 'Los próximos $m viaje${m == 1 ? '' : 's'} de tu ciclo llevan −$porcentaje%. '
        '¡Sigue usando RAI para aprovecharlo!';
  }

  int _fullRestantesEnCiclo() {
    if (posicionCiclo <= m) return (m - posicionCiclo) + k;
    return ciclo - posicionCiclo;
  }

  static PromoMxKClienteUi? fromSnapshot(Map<String, dynamic>? snap) {
    if (snap == null || snap['activa'] != true) return null;

    int toInt(dynamic v, int fb) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim()) ?? fb;
      return fb;
    }

    final m = toInt(snap['m'], 3).clamp(1, 999);
    final k = toInt(snap['k'], 1).clamp(1, 999);
    final porcentaje = toInt(snap['porcentaje'], 15).clamp(0, 95);
    final ciclo = toInt(snap['ciclo'], m + k).clamp(2, 999);
    final posicion = toInt(snap['posicionCiclo'], 1).clamp(1, ciclo);
    final modo = (snap['modo'] ?? '${m}x$k').toString();

    return PromoMxKClienteUi(
      modo: modo,
      m: m,
      k: k,
      porcentaje: porcentaje,
      ciclo: ciclo,
      posicionCiclo: posicion,
      aplicaDescuentoEsteViaje: snap['aplicaDescuento'] == true,
    );
  }
}
