import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../servicios/chat_repo.dart';

class ChatScreen extends StatefulWidget {
  final String otroUid;       // el otro participante (taxista o cliente)
  final String otroNombre;    // opcional, para título
  final String? viajeId;      // opcional

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
  late final String chatId;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    miUid = FirebaseAuth.instance.currentUser!.uid;
    chatId = ChatRepo.chatIdDe(miUid, widget.otroUid);
    // asegura chat doc
    ChatRepo.crearSiNoExiste(uidA: miUid, uidB: widget.otroUid, viajeId: widget.viajeId);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Chat con ${widget.otroNombre}', style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ChatRepo.streamMensajes(chatId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
                }
                if (!snap.hasData) return const SizedBox.shrink();

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
                    final soyYo = m['de'] == miUid;
                    return Align(
                      alignment: soyYo ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: soyYo ? Colors.greenAccent : Colors.grey[850],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          (m['texto'] ?? '') as String,
                          style: TextStyle(color: soyYo ? Colors.black : Colors.white),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje…',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Colors.grey[900],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () async {
                      final t = _ctrl.text.trim();
                      if (t.isEmpty) return;
                      _ctrl.clear();
                      await ChatRepo.enviar(chatId: chatId, deUid: miUid, texto: t);
                    },
                    icon: const Icon(Icons.send, color: Colors.greenAccent),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
