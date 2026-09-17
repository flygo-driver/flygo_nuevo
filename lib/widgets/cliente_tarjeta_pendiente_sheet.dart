import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flygo_nuevo/pantallas/comun/factura_viaje.dart';
import 'package:flygo_nuevo/pantallas/comun/soporte.dart';
import 'package:flygo_nuevo/servicios/cliente_cobro_tarjeta_pendiente_service.dart';
import 'package:flygo_nuevo/widgets/cliente_mensaje_operaciones_panel.dart';

const String _kWhatsappSoporteTarjetaPendiente = '+18293792133';

/// Cliente bloqueado por tarjeta sin cobrar: factura + mensaje a operaciones/soporte.
class ClienteTarjetaPendienteSheet {
  ClienteTarjetaPendienteSheet._();

  static Future<void> mostrar(
    BuildContext context, {
    String? viajeId,
  }) async {
    String? idViaje = viajeId?.trim();
    if (idViaje == null || idViaje.isEmpty) {
      idViaje =
          await ClienteCobroTarjetaPendienteService.resolverViajeIdTarjetaPendiente();
    }

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        return _ClienteTarjetaPendienteSheetBody(viajeId: idViaje);
      },
    );
  }
}

class _ClienteTarjetaPendienteSheetBody extends StatefulWidget {
  const _ClienteTarjetaPendienteSheetBody({this.viajeId});

  final String? viajeId;

  @override
  State<_ClienteTarjetaPendienteSheetBody> createState() =>
      _ClienteTarjetaPendienteSheetBodyState();
}

class _ClienteTarjetaPendienteSheetBodyState
    extends State<_ClienteTarjetaPendienteSheetBody> {
  bool _mostrarMensajeOperaciones = false;
  bool _abriendoFactura = false;

  Future<void> _abrirFactura() async {
    if (_abriendoFactura) return;
    setState(() => _abriendoFactura = true);
    try {
      final String? id = widget.viajeId?.trim();
      if (id == null || id.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No encontramos la factura pendiente. Escribe a soporte y te ayudamos.',
            ),
          ),
        );
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      await FacturaViaje.mostrar(
        context,
        viajeId: id,
        role: 'cliente',
      );
    } finally {
      if (mounted) setState(() => _abriendoFactura = false);
    }
  }

  Future<void> _abrirSoporteExterno() async {
    final String refViaje = (widget.viajeId ?? '').trim();
    final String texto = refViaje.isEmpty
        ? 'Hola RAI, tengo un pago con tarjeta pendiente y no puedo pedir otro viaje. ¿Me ayudan?'
        : 'Hola RAI, tengo un pago con tarjeta pendiente en el viaje #$refViaje '
            'y no puedo pedir otro viaje. ¿Me ayudan?';
    final Uri wa = Uri.parse(
      'https://wa.me/$_kWhatsappSoporteTarjetaPendiente?text=${Uri.encodeComponent(texto)}',
    );
    final bool ok = await launchUrl(wa, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const Soporte()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool tieneViaje =
        (widget.viajeId ?? '').trim().isNotEmpty;
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.credit_card_off_outlined,
                  color: Colors.deepOrange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pago con tarjeta pendiente',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Solo pasa cuando RAI no pudo cobrar la tarjeta al cerrar un viaje. '
                      'Abrí la factura para completar el pago o escríbenos si crees que es un error.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.4,
                        color: cs.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (tieneViaje)
            FilledButton.icon(
              onPressed: _abriendoFactura ? null : _abrirFactura,
              icon: _abriendoFactura
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.receipt_long_outlined),
              label: const Text('Ver factura pendiente'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: tieneViaje
                ? () => setState(
                      () => _mostrarMensajeOperaciones =
                          !_mostrarMensajeOperaciones,
                    )
                : _abrirSoporteExterno,
            icon: Icon(
              tieneViaje ? Icons.support_agent_outlined : Icons.chat_outlined,
            ),
            label: Text(
              tieneViaje
                  ? (_mostrarMensajeOperaciones
                      ? 'Ocultar mensaje a operaciones'
                      : 'Escribir a operaciones RAI')
                  : 'Contactar soporte',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          if (tieneViaje) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _abrirSoporteExterno,
              icon: const Icon(Icons.chat_outlined, size: 20),
              label: const Text('WhatsApp o correo de soporte'),
            ),
          ],
          if (_mostrarMensajeOperaciones && tieneViaje) ...[
            const SizedBox(height: 12),
            ClienteMensajeOperacionesPanel(
              viajeId: widget.viajeId!,
              origenPantalla: 'tarjeta_pendiente_bloqueo',
              titulo: 'Cuéntanos qué pasó',
              subtitulo:
                  'Operaciones RAI ve tu mensaje al instante. Si ya pagaste o fue un error, '
                  'indícanos el viaje y revisamos el cobro.',
              hintMensaje:
                  'Ej.: Ya pagué con tarjeta pero sigue pendiente / Fue un error del taxista…',
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}
