// lib/pantallas/chat/chat_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../servicios/chat_repo.dart';

class ChatScreen extends StatefulWidget {
  final String otroUid;     // UID del otro participante (taxista o cliente)
  final String otroNombre;  // Para el título
  final String? viajeId;    // Opcional, para agrupar por viaje

  const ChatScreen({
    Key? key,
    required this.otroUid,
    required this.otroNombre,
    this.viajeId,
  }) : super(key: key);

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
    debugPrint('[CHAT] miUid=$miUid');
    debugPrint('[CHAT] otroUid=${widget.otroUid}');
    debugPrint('[CHAT] viajeId=${widget.viajeId ?? ''}');

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
      debugPrint('[CHAT] READY cid="$cid"');
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

  Future<void> _sendTest() async {
    if (!_chatReady) return;
    try {
      await ChatRepo.enviar(
        chatId: chatId,
        deUid: miUid,
        texto: 'Mensaje de prueba ✅ ${DateTime.now().toIso8601String()}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mensaje de prueba enviado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar prueba: $e')),
      );
    }
  }

  Widget _bubble(Map<String, dynamic> m) {
    final emisor = (m['de'] ?? m['from']) as String? ?? '';
    final soyYo = emisor == miUid;

    final textoRaw = m['texto'];
    final texto = (textoRaw is String) ? textoRaw : (textoRaw?.toString() ?? '');

    final ts = m['ts'] ?? m['createdAt'] ?? m['enviadoEn'];
    DateTime? when;
    if (ts is Timestamp) when = ts.toDate();
    if (ts is DateTime) when = ts;
    final hora = when != null ? '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}' : '';

    return Align(
      alignment: soyYo ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: soyYo ? const Color(0xFF1F8E4E) : const Color(0xFF222222),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: soyYo ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (texto.isEmpty)
              const Text('—', style: TextStyle(color: Colors.white70))
            else
              Text(texto, style: const TextStyle(color: Colors.white)),
            if (hora.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(hora, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Chat con ${widget.otroNombre}', style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Probar envío',
            onPressed: _sendTest,
            icon: const Icon(Icons.bolt, color: Colors.greenAccent),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: !_chatReady
                ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: ChatRepo.streamMensajes(chatId),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
                      }
                      if (snap.hasError) {
                        final msg = snap.error.toString();
                        debugPrint('[CHAT] stream error: $msg');
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'No se pueden cargar mensajes.\n$msg',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        );
                      }
                      if (!snap.hasData) {
                        return const SizedBox.shrink();
                      }
                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(
                          child: Text('Empieza la conversación 👋', style: TextStyle(color: Colors.white54)),
                        );
                      }
                      return ListView.builder(
                        reverse: true,
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final m = docs[i].data();
                          return _bubble(m);
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
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje…',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: const Color(0xFF1A1A1A),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Colors.greenAccent),
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _send,
                    icon: const Icon(Icons.send, color: Colors.greenAccent),
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
