import 'package:flutter/material.dart';

import 'package:flygo_nuevo/widgets/viaje_chat_mensajes_en_vivo.dart';

/// Vista previa del chat flotante sobre el mapa (estilo inDrive).
class ViajeChatMapaOverlay extends StatelessWidget {
  const ViajeChatMapaOverlay({
    super.key,
    required this.viajeId,
    required this.miUid,
    required this.otroUid,
    required this.otroNombre,
    this.bottom = 12,
    this.left = 12,
    this.right = 12,
    this.esCorporativo = false,
    this.visible = true,
    this.previewLimit = 12,
  });

  final String viajeId;
  final String miUid;
  final String otroUid;
  final String otroNombre;
  final double bottom;
  final double left;
  final double right;
  final bool esCorporativo;
  final bool visible;
  final int previewLimit;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final v = viajeId.trim();
    final mi = miUid.trim();
    final otro = otroUid.trim();
    if (v.isEmpty || mi.isEmpty || otro.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: left,
      right: right,
      bottom: bottom,
      child: Material(
        color: Colors.transparent,
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ViajeChatMensajesEnVivo(
          viajeId: v,
          miUid: mi,
          otroUid: otro,
          otroNombre: otroNombre,
          esCorporativo: esCorporativo,
          previewLimit: previewLimit,
        ),
      ),
    );
  }
}
