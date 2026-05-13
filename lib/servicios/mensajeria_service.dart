// ignore_for_file: avoid_print

import 'package:flygo_nuevo/servicios/chat_repo.dart';

/// Envío de mensajes del viaje (Firestore `chats/{viajeId}/mensajes`).
/// La push al destinatario la envía la Cloud Function [onChatMensajeCreatedPush].
class MensajeriaService {
  MensajeriaService._();

  static Future<void> enviarMensajeViaje({
    required String viajeId,
    required String deUid,
    required String texto,
  }) async {
    final t = texto.trim();
    if (t.isEmpty) return;
    print('[CHAT_NOTIFICACION] enviar viajeId=$viajeId len=${t.length}');
    await ChatRepo.enviar(chatId: viajeId, deUid: deUid, texto: t);
  }
}
