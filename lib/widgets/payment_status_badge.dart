import 'package:flutter/material.dart';

/// Widget que muestra una etiqueta visual con el estado del pago.
/// Se puede usar en taxista, cliente, historial, etc.
class PaymentStatusBadge extends StatelessWidget {
  final String status; // none, authorized, captured, cash_collected, failed
  final EdgeInsets padding;
  final double fontSize;

  const PaymentStatusBadge({
    super.key,
    required this.status,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.fontSize = 12,
  });

  Color _getColor() {
    switch (status) {
      case 'authorized':
        return Colors.orange; // Pago autorizado pero no capturado
      case 'captured':
        return Colors.green; // Pago completado
      case 'cash_collected':
        return Colors.blue; // Efectivo recibido
      case 'failed':
        return Colors.red; // Error o fallo
      default:
        return Colors.grey; // Estado desconocido o none
    }
  }

  String _getLabel() {
    switch (status) {
      case 'authorized':
        return 'Autorizado';
      case 'captured':
        return 'Pagado';
      case 'cash_collected':
        return 'Efectivo recibido';
      case 'failed':
        return 'Fallido';
      default:
        return 'Sin pago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _getColor();
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c, width: 1),
      ),
      child: Text(
        _getLabel(),
        style: TextStyle(
          color: c,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
