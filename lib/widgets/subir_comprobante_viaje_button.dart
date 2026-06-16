import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/comprobante_transferencia_service.dart';

/// Botón para adjuntar comprobante de transferencia (post-viaje / recibo).
class SubirComprobanteViajeButton extends StatefulWidget {
  const SubirComprobanteViajeButton({super.key, required this.viajeId});

  final String viajeId;

  @override
  State<SubirComprobanteViajeButton> createState() =>
      _SubirComprobanteViajeButtonState();
}

class _SubirComprobanteViajeButtonState extends State<SubirComprobanteViajeButton> {
  bool _subiendo = false;

  Future<void> _subir() async {
    if (_subiendo) return;
    setState(() => _subiendo = true);
    final r = await ComprobanteTransferenciaService.subirYReportar(
      viajeId: widget.viajeId,
    );
    if (!mounted) return;
    setState(() => _subiendo = false);
    ComprobanteTransferenciaService.mostrarFeedback(context, r);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _subiendo ? null : _subir,
        icon: _subiendo
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.upload_file_rounded),
        label: Text(
          _subiendo
              ? 'Subiendo comprobante…'
              : 'Subir comprobante de pago',
        ),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

/// Misma lógica que el comprobante en [FacturaViaje] (solo cliente, transferencia).
bool clienteDebePoderSubirComprobanteTransferencia(Map<String, dynamic> data) {
  if (data['transferenciaConfirmada'] == true) return false;
  final String paymentStatus =
      (data['payment']?['status'] ?? '').toString().trim().toLowerCase();
  if (paymentStatus == 'bank_transfer_rejected') return true;
  final String comprobanteUrl =
      (data['comprobanteTransferenciaUrl'] ?? '').toString();
  return comprobanteUrl.isEmpty;
}
