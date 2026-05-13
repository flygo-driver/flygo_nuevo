import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flygo_nuevo/pantallas/chat/chat_screen.dart';
import 'package:flygo_nuevo/servicios/chat_repo.dart';

/// Panel compacto estilo inDrive: resalta cuando el otro escribe y abre el chat al tocar.
/// Sin ListView anidado (no roba gestos al [SingleChildScrollView] del viaje en curso).
class ViajeChatMensajesEnVivo extends StatefulWidget {
  const ViajeChatMensajesEnVivo({
    super.key,
    required this.viajeId,
    required this.miUid,
    required this.otroUid,
    required this.otroNombre,
    this.previewLimit = 24,
  });

  final String viajeId;
  final String miUid;
  final String otroUid;
  final String otroNombre;
  final int previewLimit;

  @override
  State<ViajeChatMensajesEnVivo> createState() => _ViajeChatMensajesEnVivoState();
}

class _ViajeChatMensajesEnVivoState extends State<ViajeChatMensajesEnVivo> {
  /// Evita repetir vibración si el mismo snapshot se reconstruye.
  String? _ultimoDocIdConHaptico;

  void _abrirChat(BuildContext context) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          otroUid: widget.otroUid,
          otroNombre: widget.otroNombre,
          viajeId: widget.viajeId,
        ),
      ),
    );
  }

  void _evaluarNuevoDelOtro({
    required String? docId,
    required bool soyYo,
  }) {
    if (!mounted || docId == null || docId.isEmpty || soyYo) return;
    if (_ultimoDocIdConHaptico == docId) return;
    _ultimoDocIdConHaptico = docId;
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.viajeId.isEmpty ||
        widget.miUid.isEmpty ||
        widget.otroUid.isEmpty) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.transparent,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ChatRepo.streamMensajesPreview(
          widget.viajeId,
          limit: widget.previewLimit,
        ),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _cajaEsqueleto(cs);
          }
          if (snap.hasError) {
            return _cajaError(cs);
          }

          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return _cajaVacia(cs, context);
          }

          final latest = docs.first;
          final m = latest.data();
          final emisor =
              (m['de'] ?? m['from'] ?? '').toString().trim();
          final soyYo = emisor == widget.miUid;
          final texto =
              (m['texto'] ?? m['body'] ?? '').toString().trim();
          final ts = m['ts'];
          String hora = '';
          if (ts is Timestamp) {
            final d = ts.toDate();
            hora =
                '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _evaluarNuevoDelOtro(docId: latest.id, soyYo: soyYo);
          });

          final bool alertaOtro = !soyYo;
          final Color borde =
              alertaOtro ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5);
          final Color fondo = alertaOtro
              ? cs.primary.withValues(alpha: 0.12)
              : cs.surfaceContainerHighest.withValues(alpha: 0.35);

          return InkWell(
            onTap: () => _abrirChat(context),
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: fondo,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borde, width: alertaOtro ? 1.8 : 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        alertaOtro ? Icons.mark_chat_unread : Icons.forum_outlined,
                        size: 22,
                        color: alertaOtro ? cs.primary : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alertaOtro
                                  ? '${widget.otroNombre} te escribió'
                                  : 'Mensajes del viaje',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                            if (hora.isNotEmpty)
                              Text(
                                hora,
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _abrirChat(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Abrir',
                          style: TextStyle(
                            color: cs.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    texto.isEmpty ? '—' : texto,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cajaEsqueleto(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Cargando mensajes…',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _cajaError(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Text(
        'No se pudieron cargar mensajes.',
        style: TextStyle(color: cs.error, fontSize: 12),
      ),
    );
  }

  Widget _cajaVacia(ColorScheme cs, BuildContext context) {
    return InkWell(
      onTap: () => _abrirChat(context),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.forum_outlined, size: 22, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sin mensajes aún. Tocá para coordinar pickup o pago.',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.25,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
