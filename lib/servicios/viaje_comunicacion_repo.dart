// ignore_for_file: avoid_print

import 'package:cloud_functions/cloud_functions.dart';

/// Aviso al otro participante del viaje (FCM vía callable; no sustituye la llamada real).
class ViajeComunicacionRepo {
  ViajeComunicacionRepo._();

  static Future<void> notificarIntentoComunicacion({
    required String viajeId,
    required String tipo,
  }) async {
    final v = viajeId.trim();
    if (v.isEmpty) return;
    final t = tipo.trim().toLowerCase();
    final norm = t == 'whatsapp' ? 'whatsapp' : 'llamada';
    print('[CHAT_NOTIFICACION] callable notifyViajeComunicacionIntento viaje=$v tipo=$norm');
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('notifyViajeComunicacionIntento')
          .call(<String, dynamic>{'viajeId': v, 'tipo': norm});
    } catch (e) {
      print('[CHAT_NOTIFICACION] callable error: $e');
    }
  }
}
