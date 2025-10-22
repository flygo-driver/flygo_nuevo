import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ChatRepo {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String _pairId(String a, String b) {
    a = a.trim(); b = b.trim();
    return a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';
  }

  static Future<bool> _tryTouch(String cid) async {
    final ref = _db.collection('chats').doc(cid);
    await ref.update({'lastAt': FieldValue.serverTimestamp()});
    return true;
  }

  /// Intenta “reparar” un chat existente poniendo participantes=[uidA,uidB]
  /// y seteando viajeId/lastAt según tus reglas:
  /// keys().hasOnly(['participantes','viajeId','lastMessage','lastAt','creadoAt'])
  static Future<bool> _tryRepair({
    required String cid,
    required String uidA,
    required String uidB,
    required String viajeId,
  }) async {
    final ref = _db.collection('chats').doc(cid);
    await ref.update({
      'participantes': [uidA, uidB],
      'viajeId': viajeId,
      'lastAt': FieldValue.serverTimestamp(),
    });
    debugPrint('[CHAT] repaired participantes on "$cid"');
    return true;
  }

  /// Crea el chat cumpliendo reglas (keys exactas).
  static Future<void> _create({
    required String cid,
    required String uidA,
    required String uidB,
    required String viajeId,
  }) async {
    final ref = _db.collection('chats').doc(cid);
    await ref.set({
      'participantes': [uidA, uidB],
      'viajeId': viajeId,
      'lastMessage': '',
      'lastAt': FieldValue.serverTimestamp(),
      'creadoAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: false));
  }

  /// Devuelve un chatId válido. Hace:
  /// 1) update lastAt
  /// 2) si permiso-denegado -> intenta "repair"
  /// 3) si not-found -> create
  static Future<String> resolveOrCreateChatId({
    required String uidA,
    required String uidB,
    String? viajeId,
  }) async {
    uidA = uidA.trim();
    uidB = uidB.trim();
    final v = (viajeId ?? '').trim();

    if (uidA.isEmpty || uidB.isEmpty) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-uid',
        message: 'UID vacío: uidA="$uidA" uidB="$uidB"',
      );
    }

    final pair = _pairId(uidA, uidB);
    final candidates = <String>[
      if (v.isNotEmpty) 'ride_${v}_$pair',
      if (v.isNotEmpty) 'ride_$v',
      'dm_$pair',
      pair,
    ];

    FirebaseException? lastErr;

    for (final cid in candidates) {
      debugPrint('[CHAT] try cid="$cid"  uidA="$uidA" uidB="$uidB" viajeId="$v"');

      // 1) tocar si existe y tengo permiso
      try {
        final ok = await _tryTouch(cid);
        if (ok) {
          debugPrint('[CHAT] using existing (touch ok): $cid');
          return cid;
        }
      } on FirebaseException catch (e) {
        // 2) si NOT_FOUND -> intento crear
        if (e.code == 'not-found') {
          try {
            await _create(cid: cid, uidA: uidA, uidB: uidB, viajeId: v);
            debugPrint('[CHAT] created: $cid');
            return cid;
          } on FirebaseException catch (e2) {
            debugPrint('[CHAT] create denied on "$cid": ${e2.code}');
            lastErr = e2;
            continue;
          }
        }

        // 3) si PERMISSION_DENIED (u otro) -> intento REPAIR
        try {
          await _tryRepair(cid: cid, uidA: uidA, uidB: uidB, viajeId: v);
          debugPrint('[CHAT] repaired & using: $cid');
          return cid;
        } on FirebaseException catch (e3) {
          debugPrint('[CHAT] repair denied on "$cid": ${e3.code}');
          lastErr = e3;
          continue;
        }
      } catch (e) {
        debugPrint('[CHAT] unexpected on "$cid": $e');
      }
    }

    throw lastErr ??
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unknown',
          message: 'No se pudo preparar el chat.',
        );
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamMensajes(String chatId) {
    return _db
        .collection('chats').doc(chatId)
        .collection('mensajes')
        .orderBy('ts', descending: true)
        .limit(200)
        .snapshots();
  }

  static Future<void> enviar({
    required String chatId,
    required String deUid,
    required String texto,
  }) async {
    final chatRef = _db.collection('chats').doc(chatId);
    final msgRef  = chatRef.collection('mensajes').doc();

    await _db.runTransaction((tx) async {
      tx.set(msgRef, {
        'de': deUid,
        'texto': texto,
        'ts': FieldValue.serverTimestamp(),
        'tipo': 'texto',
        // opcional permitido por reglas:
        // 'leidoPor': [deUid],
      });
      tx.update(chatRef, {
        'lastMessage': texto,
        'lastAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> streamChat(String chatId) {
    return _db.collection('chats').doc(chatId).snapshots();
  }
}
