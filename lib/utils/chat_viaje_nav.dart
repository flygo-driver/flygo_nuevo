import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/chat/chat_screen.dart';
import 'package:flygo_nuevo/servicios/chat_repo.dart';

/// Navegación unificada al chat de viaje (cliente, taxista, corporativo, turismo).
class ChatViajeNav {
  ChatViajeNav._();

  static Future<void> abrir({
    required BuildContext context,
    required String miUid,
    required String otroUid,
    required String otroNombre,
    String? viajeId,
    Set<String>? participantesExtra,
    bool tituloCompacto = false,
  }) async {
    final mi = miUid.trim();
    final otro = otroUid.trim();
    final v = (viajeId ?? '').trim();
    if (mi.isEmpty) {
      _snack(context, 'Iniciá sesión para usar el chat.');
      return;
    }
    if (otro.isEmpty) {
      _snack(context, 'No hay otro participante para este chat.');
      return;
    }

    try {
      if (v.isNotEmpty) {
        await ChatRepo.prepareViajeChat(
          viajeId: v,
          uidA: mi,
          uidB: otro,
          participantesExtra: participantesExtra,
        );
      } else {
        await ChatRepo.resolveOrCreateChatId(
          uidA: mi,
          uidB: otro,
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      _snack(context, 'No se pudo preparar el chat: $e');
      return;
    }

    if (!context.mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          otroUid: otro,
          otroNombre: otroNombre,
          viajeId: v.isEmpty ? null : v,
          tituloCompacto: tituloCompacto,
        ),
      ),
    );
  }

  static void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
