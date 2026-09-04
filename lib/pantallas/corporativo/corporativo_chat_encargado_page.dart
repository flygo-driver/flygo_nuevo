import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/chat/chat_screen.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_ui.dart';
import 'package:flygo_nuevo/servicios/chat_repo.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

/// Chat encargado ↔ chofer (sin exponer teléfonos personales).
class CorporativoChatEncargadoPage extends StatefulWidget {
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
  State<CorporativoChatEncargadoPage> createState() =>
      _CorporativoChatEncargadoPageState();
}

class _CorporativoChatEncargadoPageState
    extends State<CorporativoChatEncargadoPage> {
  Future<_ChatCorpInit>? _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _prepararChat();
  }

  Future<_ChatCorpInit> _prepararChat() async {
    final encargadoUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (encargadoUid.isEmpty) {
      throw StateError('Iniciá sesión para usar el chat.');
    }

    String choferUid = widget.choferUid.trim();
    String choferNombre = widget.choferNombre.trim();

    final vSnap = await FirebaseFirestore.instance
        .collection('viajes')
        .doc(widget.viajeId)
        .get();
    final viaje = vSnap.data();
    if (viaje != null) {
      final operativo =
          CorporativoTaxistaService.choferOperativoUidViajeCorporativo(viaje);
      if (operativo.isNotEmpty) choferUid = operativo;
      final nombreViaje =
          (viaje['nombreTaxista'] ?? viaje['corporativoChoferNombre'] ?? '')
              .toString()
              .trim();
      if (nombreViaje.isNotEmpty) choferNombre = nombreViaje;
    }

    if (choferUid.isEmpty) {
      throw StateError(
        'Aún no hay chofer asignado a este viaje. Esperá la asignación de RAI.',
      );
    }

    await ChatRepo.prepareViajeChat(
      viajeId: widget.viajeId,
      uidA: encargadoUid,
      uidB: choferUid,
      participantesExtra: {encargadoUid, choferUid},
    );

    return _ChatCorpInit(
      choferUid: choferUid,
      choferNombre: choferNombre.isNotEmpty ? choferNombre : 'Chofer',
    );
  }

  void _reintentar() {
    setState(() => _initFuture = _prepararChat());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    return Scaffold(
      backgroundColor: p.scaffold,
      appBar: RaiAppBar(
        title: widget.choferNombre.isNotEmpty
            ? widget.choferNombre
            : 'Chat con chofer',
      ),
      body: FutureBuilder<_ChatCorpInit>(
        future: _initFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || snap.data == null) {
            final msg = snap.error?.toString() ?? 'No se pudo abrir el chat.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 48, color: p.muted),
                    const SizedBox(height: 16),
                    Text(
                      msg,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.onCard, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _reintentar,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }
          final data = snap.data!;
          return ChatScreen(
            otroUid: data.choferUid,
            otroNombre: data.choferNombre,
            viajeId: widget.viajeId,
          );
        },
      ),
    );
  }
}

class _ChatCorpInit {
  const _ChatCorpInit({
    required this.choferUid,
    required this.choferNombre,
  });

  final String choferUid;
  final String choferNombre;
}
