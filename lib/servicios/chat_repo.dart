// lib/servicios/chat_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatRepo {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// ID determinístico para el chat entre dos UIDs (siempre el mismo orden)
  static String chatIdDe(String uidA, String uidB) {
    final a = uidA.trim();
    final b = uidB.trim();
    if (a.compareTo(b) < 0) return '${a}_$b';
    return '${b}_$a';
  }

  /// Crea el doc de chat si no existe (cumpliendo reglas de seguridad)
  static Future<void> crearSiNoExiste({
    required String uidA,
    required String uidB,
    String? viajeId,
  }) async {
    final cid = chatIdDe(uidA, uidB);
    final ref = _db.collection('chats').doc(cid);
    final snap = await ref.get();
    if (snap.exists) return;

    await ref.set({
      'participantes': [uidA, uidB],          // EXACTO: 2 participantes
      if (viajeId != null) 'viajeId': viajeId,
      'lastMessage': '',
      'lastAt': FieldValue.serverTimestamp(),
      'creadoAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: false));
  }

  /// Stream de mensajes en tiempo real (más nuevos primero)
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamMensajes(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('mensajes')
        .orderBy('ts', descending: true)
        .limit(200)
        .snapshots();
  }

  /// Envía un mensaje de texto y actualiza el resumen del chat
  static Future<void> enviar({
    required String chatId,
    required String deUid,
    required String texto,
  }) async {
    final chatRef = _db.collection('chats').doc(chatId);
    final msgRef  = chatRef.collection('mensajes').doc();
    final now     = FieldValue.serverTimestamp();

    // Solo las claves permitidas por las reglas:
    // mensajes: ['de','texto','ts','tipo','leidoPor?']
    // chat: update libre para participantes (usamos lastMessage/lastAt)
    final batch = _db.batch();
    batch.set(msgRef, {
      'de': deUid,
      'texto': texto,
      'ts': now,
      'tipo': 'texto',
      // opcional: 'leidoPor': [deUid],
    });
    batch.update(chatRef, {
      'lastMessage': texto,
      'lastAt': now,
    });
    await batch.commit();
  }

  /// (Opcional) stream del documento del chat
  static Stream<DocumentSnapshot<Map<String, dynamic>>> streamChat(String chatId) {
    return _db.collection('chats').doc(chatId).snapshots();
  }
}
