import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/chat/chat_screen.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_ui.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

/// Chat encargado ↔ chofer (sin exponer teléfonos personales).
class CorporativoChatEncargadoPage extends StatelessWidget {
  const CorporativoChatEncargadoPage({
    super.key,
    required this.viajeId,
    required this.choferUid,
    required this.choferNombre,
    this.empresaNombre = '',
  });

  final String viajeId;
  final String choferUid;
  final String choferNombre;
  final String empresaNombre;

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    return Scaffold(
      backgroundColor: p.scaffold,
      appBar: RaiAppBar(
        title: choferNombre.isNotEmpty ? choferNombre : 'Chat con chofer',
      ),
      body: FutureBuilder<void>(
        future: ViajesRepo.ensureChatDocForViaje(viajeId),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return ChatScreen(
            otroUid: choferUid,
            otroNombre: choferNombre,
            viajeId: viajeId,
          );
        },
      ),
    );
  }
}
