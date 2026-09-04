import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

class ChatRepo {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static void _log(String msg) {
    // ignore: avoid_print
    print('[CHAT] $msg');
  }

  static bool _esPermissionDenied(FirebaseException e) =>
      e.code == 'permission-denied' || e.code == 'permission_denied';

  /// Admin SDK: crea/actualiza chats/{viajeId} (evita permission-denied en cliente).
  static Future<bool> _ensureChatViajeViaCloud(String viajeId) async {
    final String v = viajeId.trim();
    if (v.isEmpty) return false;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('ensureChatViajeDoc');
      await callable.call(<String, dynamic>{'viajeId': v});
      _log('CF ensureChatViajeDoc ok viajeId=$v');
      return true;
    } on FirebaseFunctionsException catch (e) {
      _log('ensureChatViajeDoc CF: ${e.code} ${e.message}');
      if (e.code == 'not-found' || e.code == 'unimplemented') {
        return false;
      }
      rethrow;
    }
  }

  static Future<void> _ensureChatDocViaje(String viajeId) async {
    final v = viajeId.trim();
    if (v.isEmpty) return;
    final cfOk = await _ensureChatViajeViaCloud(v);
    if (cfOk) return;
    try {
      await ViajesRepo.ensureChatDocForViaje(v);
    } on FirebaseException catch (e) {
      if (!_esPermissionDenied(e)) rethrow;
      _log('ensure local denied → retry CF ensureChatViajeDoc');
      final ok = await _ensureChatViajeViaCloud(v);
      if (!ok) rethrow;
    }
  }

  /// Asegura `chats/{viajeId}` (CF primero). Uso en asignación admin / claim.
  static Future<void> ensureViajeChatDoc(String viajeId) =>
      _ensureChatDocViaje(viajeId);

  /// Prepara chat de viaje: CF + participantes extra (corporativo) + resolve.
  static Future<String> prepareViajeChat({
    required String viajeId,
    required String uidA,
    required String uidB,
    Set<String>? participantesExtra,
  }) async {
    final v = viajeId.trim();
    if (participantesExtra != null && participantesExtra.length >= 2 && v.isNotEmpty) {
      final cfOk = await _ensureChatViajeViaCloud(v);
      try {
        await ensureViajeChatParticipantes(
          viajeId: v,
          participantes: participantesExtra,
        );
      } on FirebaseException catch (e) {
        if (!_esPermissionDenied(e)) rethrow;
        if (!cfOk) {
          await _ensureChatViajeViaCloud(v);
        }
      } catch (_) {
        if (!cfOk) rethrow;
      }
    }
    return resolveOrCreateChatId(uidA: uidA, uidB: uidB, viajeId: v.isEmpty ? null : v);
  }

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

    final cfOk = await _ensureChatViajeViaCloud(v);
    try {
      await _mergeParticipantesChat(v, uids);
    } on FirebaseException catch (e) {
      if (!_esPermissionDenied(e)) rethrow;
      if (!cfOk) {
        final ok = await _ensureChatViajeViaCloud(v);
        if (!ok) rethrow;
      }
      try {
        await _mergeParticipantesChat(v, uids);
      } on FirebaseException catch (e2) {
        if (!_esPermissionDenied(e2)) rethrow;
      }
    }
  }

  static Future<void> _mergeParticipantesChat(String viajeId, Set<String> uids) async {
    final ref = _db.collection('chats').doc(viajeId);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'participantes': uids.toList(),
        'viajeId': viajeId,
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
        (snap.data()?['viajeId'] ?? '').toString() == viajeId) {
      return;
    }

    await ref.set(
      {
        'participantes': merged.toList(),
        'viajeId': viajeId,
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
      final cfOk = await _ensureChatViajeViaCloud(v);
      if (!cfOk) {
        await _ensureChatDocViaje(v);
      }
      if (cfOk) {
        _log('using trip chat via CF: $v');
        return v;
      }
      try {
        await _tryTouch(v);
        _log('using trip chat doc: $v');
        return v;
      } on FirebaseException catch (e) {
        _log('touch trip chat "$v": ${e.code}');
        if (_esPermissionDenied(e)) {
          final ok = await _ensureChatViajeViaCloud(v);
          if (ok) {
            _log('touch denied but CF ok, using: $v');
            return v;
          }
          rethrow;
        }
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
