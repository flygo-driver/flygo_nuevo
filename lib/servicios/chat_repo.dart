import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

class ChatRepo {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String _pairId(String a, String b) {
    a = a.trim();
    b = b.trim();
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

  /// Asegura `chats/{viajeId}` con chofer + encargado (rutas corporativas).
  static Future<void> ensureViajeChatParticipantes({
    required String viajeId,
    required Set<String> participantes,
  }) async {
    final v = viajeId.trim();
    final uids = participantes.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (v.isEmpty || uids.length < 2) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-participants',
        message: 'Faltan participantes para el chat del viaje.',
      );
    }

    final ref = _db.collection('chats').doc(v);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'participantes': uids.toList(),
        'viajeId': v,
        'lastMessage': '',
        'lastAt': FieldValue.serverTimestamp(),
        'creadoAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final raw = snap.data()?['participantes'];
    final existentes = raw is List
        ? raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toSet()
        : <String>{};
    final merged = <String>{...existentes, ...uids};
    if (merged.length == existentes.length &&
        (snap.data()?['viajeId'] ?? '').toString() == v) {
      return;
    }

    await ref.set(
      {
        'participantes': merged.toList(),
        'viajeId': v,
        'lastAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
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

    // Mismo id que [ViajesRepo._ensureChatForTrip]: chats/{viajeId}
    if (v.isNotEmpty) {
      await ViajesRepo.ensureChatDocForViaje(v);
      try {
        await _tryTouch(v);
        debugPrint('[CHAT] using trip chat doc: $v');
        return v;
      } on FirebaseException catch (e) {
        debugPrint('[CHAT] touch trip chat "$v": ${e.code}');
        if (e.code == 'not-found') {
          try {
            await _create(cid: v, uidA: uidA, uidB: uidB, viajeId: v);
            debugPrint('[CHAT] created trip chat: $v');
            return v;
          } on FirebaseException catch (eCreate) {
            debugPrint('[CHAT] create trip chat denied: ${eCreate.code}');
            rethrow;
          }
        }
        try {
          await _tryRepair(cid: v, uidA: uidA, uidB: uidB, viajeId: v);
          return v;
        } on FirebaseException catch (e2) {
          debugPrint('[CHAT] repair trip chat denied: ${e2.code}');
          if (e2.code == 'not-found' || e2.code == 'permission-denied') {
            try {
              await _create(cid: v, uidA: uidA, uidB: uidB, viajeId: v);
              debugPrint('[CHAT] created trip chat after repair: $v');
              return v;
            } on FirebaseException catch (eCreate) {
              debugPrint('[CHAT] create trip chat fallback denied: ${eCreate.code}');
              rethrow;
            }
          }
          rethrow;
        }
      }
    }

    final pair = _pairId(uidA, uidB);
    final candidates = <String>[
      'dm_$pair',
      pair,
    ];

    FirebaseException? lastErr;

    for (final cid in candidates) {
      debugPrint(
          '[CHAT] try cid="$cid"  uidA="$uidA" uidB="$uidB" viajeId="$v"');

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

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamMensajes(
      String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('mensajes')
        .orderBy('ts', descending: true)
        .limit(200)
        .snapshots();
  }

  /// Pocos mensajes para vista previa en viaje (sin ListView anidado largo).
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamMensajesPreview(
    String chatId, {
    int limit = 24,
  }) {
    final int n = limit.clamp(1, 60);
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('mensajes')
        .orderBy('ts', descending: true)
        .limit(n)
        .snapshots();
  }

  static Future<void> enviar({
    required String chatId,
    required String deUid,
    required String texto,
  }) async {
    final chatRef = _db.collection('chats').doc(chatId);
    final msgRef = chatRef.collection('mensajes').doc();

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

  static Stream<DocumentSnapshot<Map<String, dynamic>>> streamChat(
      String chatId) {
    return _db.collection('chats').doc(chatId).snapshots();
  }
}
