import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/comprobante_transferencia_service.dart';
import 'package:flygo_nuevo/utils/pools_producto_copy.dart';

/// Paso 2 del pago por transferencia en giras: elegir foto del bauche y enviarla.
class PoolReservaBaucheUploader extends StatefulWidget {
  const PoolReservaBaucheUploader({
    super.key,
    required this.poolId,
    required this.reservaId,
    this.compact = false,
    this.onEnviado,
  });

  final String poolId;
  final String reservaId;
  final bool compact;
  final VoidCallback? onEnviado;

  @override
  State<PoolReservaBaucheUploader> createState() =>
      _PoolReservaBaucheUploaderState();
}

class _PoolReservaBaucheUploaderState extends State<PoolReservaBaucheUploader> {
  Uint8List? _preview;
  bool _eligiendo = false;
  bool _enviando = false;
  bool _enviado = false;

  static const Color _accent = Color(0xFF4ADE80);
  static const Color _muted = Color(0xFF9CA3AF);

  Future<void> _elegirFoto() async {
    if (_eligiendo || _enviando || _enviado) return;
    setState(() => _eligiendo = true);
    try {
      final bytes =
          await ComprobanteTransferenciaService.seleccionarImagenComprobante(
        context,
      );
      if (!mounted || bytes == null) return;
      setState(() => _preview = bytes);
    } finally {
      if (mounted) setState(() => _eligiendo = false);
    }
  }

  Future<void> _enviarBauche() async {
    if (_enviando || _enviado) return;
    final bytes = _preview;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero elegí la foto de tu comprobante (bauche).'),
        ),
      );
      return;
    }

    setState(() => _enviando = true);
    try {
      final r = await ComprobanteTransferenciaService.enviarComprobantePoolReserva(
        poolId: widget.poolId,
        reservaId: widget.reservaId,
        imageBytes: bytes,
      );
      if (!mounted) return;
      ComprobanteTransferenciaService.mostrarFeedbackPoolReserva(context, r);
      if (r.ok) {
        setState(() => _enviado = true);
        widget.onEnviado?.call();
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_enviado) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.shade400),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade400, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                PoolsProductoCopy.clienteBaucheEnviadoOk,
                style: TextStyle(
                  color: Colors.green.shade300,
                  fontWeight: FontWeight.w700,
                  fontSize: widget.compact ? 12 : 13,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.compact) ...[
          const Text(
            PoolsProductoCopy.clienteBauchePasoTitulo,
            style: TextStyle(
              color: _accent,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            PoolsProductoCopy.clienteBauchePasoSubtitulo,
            style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 10),
        ],
        if (_preview != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              _preview!,
              height: widget.compact ? 120 : 160,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Vista previa del bauche',
            style: TextStyle(
              color: _muted,
              fontSize: widget.compact ? 11 : 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton.icon(
          onPressed: (_eligiendo || _enviando) ? null : _elegirFoto,
          icon: _eligiendo
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _preview == null
                      ? Icons.photo_camera_outlined
                      : Icons.refresh,
                  size: 18,
                ),
          label: Text(
            _eligiendo
                ? 'Abriendo cámara…'
                : (_preview == null
                    ? 'Elegir foto del bauche'
                    : 'Cambiar foto'),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: _accent,
            side: const BorderSide(color: _accent),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: (_preview == null || _enviando) ? null : _enviarBauche,
          icon: _enviando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined),
          label: Text(_enviando ? 'Enviando bauche…' : 'Enviar bauche a RAI'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.black,
            disabledBackgroundColor: Colors.white12,
            disabledForegroundColor: _muted,
          ),
        ),
      ],
    );
  }
}
