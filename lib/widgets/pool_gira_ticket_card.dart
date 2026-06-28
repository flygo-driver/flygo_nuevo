import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Ticket digital de gira por cupos (QR + datos del pasajero).
class PoolGiraTicketCard extends StatelessWidget {
  const PoolGiraTicketCard({
    super.key,
    required this.tokenEntrada,
    required this.reservaId,
    required this.pasajero,
    required this.giraNombre,
    required this.empresa,
    required this.asientos,
    required this.fechaSalida,
    this.fechaRegreso,
    this.puntoEncuentro = '',
    this.tokenEstado = 'activo',
    this.estiloOscuro = true,
  });

  final String tokenEntrada;
  final String reservaId;
  final String pasajero;
  final String giraNombre;
  final String empresa;
  final int asientos;
  final DateTime fechaSalida;
  final DateTime? fechaRegreso;
  final String puntoEncuentro;
  final String tokenEstado;
  final bool estiloOscuro;

  static const Color _kBorde = Color(0xFFF59E0B);
  static const Color _kFondo = Color(0xFF0A0A0A);

  @override
  Widget build(BuildContext context) {
    final fFecha = DateFormat('EEE d MMM yyyy · HH:mm', 'es');
    final usado = tokenEstado.trim().toLowerCase() == 'usado';
    final anulado = tokenEstado.trim().toLowerCase() == 'anulado';
    final textPrimary = estiloOscuro ? Colors.white : const Color(0xFF101828);
    final textMuted = estiloOscuro ? const Color(0xFF9CA3AF) : const Color(0xFF667085);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: estiloOscuro ? _kFondo : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorde, width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.confirmation_number_outlined, color: _kBorde),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ticket RAI Driver',
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ),
              _estadoChip(usado, anulado),
            ],
          ),
          const SizedBox(height: 14),
          if (!anulado)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: tokenEntrada,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
          const SizedBox(height: 12),
          SelectableText(
            tokenEntrada,
            style: TextStyle(
              color: _kBorde,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Reserva #${reservaId.length > 8 ? reservaId.substring(0, 8) : reservaId}',
            style: TextStyle(color: textMuted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          _fila('Pasajero', pasajero, textPrimary, textMuted),
          _fila('Gira', giraNombre, textPrimary, textMuted),
          if (empresa.isNotEmpty) _fila('Empresa', empresa, textPrimary, textMuted),
          _fila('Asientos', '$asientos', textPrimary, textMuted),
          _fila('Salida', fFecha.format(fechaSalida), textPrimary, textMuted),
          if (fechaRegreso != null)
            _fila('Regreso', fFecha.format(fechaRegreso!), textPrimary, textMuted),
          if (puntoEncuentro.isNotEmpty)
            _fila('Encuentro', puntoEncuentro, textPrimary, textMuted),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: tokenEntrada));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Código copiado')),
              );
            },
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('Copiar código'),
          ),
        ],
      ),
    );
  }

  Widget _estadoChip(bool usado, bool anulado) {
    final String label;
    final Color color;
    if (anulado) {
      label = 'Anulado';
      color = Colors.grey;
    } else if (usado) {
      label = 'Usado';
      color = Colors.blueGrey;
    } else {
      label = 'Confirmado';
      color = const Color(0xFF059669);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11),
      ),
    );
  }

  Widget _fila(String k, String v, Color textPrimary, Color textMuted) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(k, style: TextStyle(color: textMuted, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                color: textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
