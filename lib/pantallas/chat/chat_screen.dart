// lib/pantallas/chat/chat_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../servicios/chat_repo.dart';

class ChatScreen extends StatefulWidget {
  final String otroUid;
  final String otroNombre;
  final String? viajeId;

  const ChatScreen({
    super.key,
    required this.otroUid,
    required this.otroNombre,
    this.viajeId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final String miUid;
  late String chatId;
  final _ctrl = TextEditingController();
  bool _chatReady = false;

  @override
  void initState() {
    super.initState();
    final curr = FirebaseAuth.instance.currentUser;
    miUid = curr?.uid ?? '';
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final cid = await ChatRepo.resolveOrCreateChatId(
        uidA: miUid,
        uidB: widget.otroUid,
        viajeId: widget.viajeId,
      );
      if (!mounted) return;
      setState(() {
        chatId = cid;
        _chatReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo preparar el chat: $e')),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    if (!_chatReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preparando el chat… intenta de nuevo')),
      );
      return;
    }
    _ctrl.clear();
    try {
      await ChatRepo.enviar(chatId: chatId, deUid: miUid, texto: t);
    } catch (e) {
      if (!mounted) return;
      _ctrl.text = t;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar: $e')),
      );
    }
  }

  Widget _bubble(BuildContext context, Map<String, dynamic> m) {
    final emisor = (m['de'] ?? m['from'] ?? m['senderUid']) as String? ?? '';
    final soyYo = emisor == miUid;

    final textoRaw = m['texto'];
    final texto =
        (textoRaw is String) ? textoRaw : (textoRaw?.toString() ?? '');

    final ts = m['ts'] ?? m['createdAt'] ?? m['enviadoEn'];
    DateTime? when;
    if (ts is Timestamp) when = ts.toDate();
    if (ts is DateTime) when = ts;
    final hora = when != null
        ? '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}'
        : '';

    final cs = Theme.of(context).colorScheme;
    final bubbleBg = soyYo ? cs.primary : cs.surfaceContainerHighest;
    final fg = soyYo ? cs.onPrimary : cs.onSurface;
    final sub =
        soyYo ? cs.onPrimary.withValues(alpha: 0.75) : cs.onSurfaceVariant;

    return Align(
      alignment: soyYo ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: bubbleBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment:
              soyYo ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (texto.isEmpty)
              Text('—', style: TextStyle(color: sub))
            else
              Text(texto, style: TextStyle(color: fg)),
            if (hora.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(hora, style: TextStyle(color: sub, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text('Chat con ${widget.otroNombre}'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: cs.surfaceTint,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: !_chatReady
                ? Center(child: CircularProgressIndicator(color: cs.primary))
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: ChatRepo.streamMensajes(chatId),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return Center(
                            child:
                                CircularProgressIndicator(color: cs.primary));
                      }
                      if (snap.hasError) {
                        final msg = snap.error.toString();
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'No se pueden cargar mensajes.\n$msg',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.error),
                            ),
                          ),
                        );
                      }
                      if (!snap.hasData) {
                        return const SizedBox.shrink();
                      }
                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return Center(
                          child: Text(
                            'Empieza la conversación',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        );
                      }
                      return ListView.builder(
                        reverse: true,
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final m = docs[i].data();
                          return _bubble(context, m);
                        },
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      style: TextStyle(color: cs.onSurface),
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje…',
                        hintStyle: TextStyle(color: cs.onSurfaceVariant),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.primary, width: 2),
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _send,
                    icon: Icon(Icons.send, color: cs.primary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
