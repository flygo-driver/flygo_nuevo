// lib/pantallas/chat/chat_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/utils/ux_log.dart';
import '../../servicios/chat_repo.dart';
import '../../servicios/mensajeria_service.dart';

class ChatScreen extends StatefulWidget {
  final String otroUid;
  final String otroNombre;
  final String? viajeId;

  /// Si true, el AppBar muestra solo [otroNombre] (sin prefijo «Chat con»).
  final bool tituloCompacto;

  const ChatScreen({
    super.key,
    required this.otroUid,
    required this.otroNombre,
    this.viajeId,
    this.tituloCompacto = false,
  });

  static const int kMaxMensajeLen = 800;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  String miUid = '';
  String chatId = '';
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _chatReady = false;
  bool _chatError = false;
  String? _chatErrorMsg;
  bool _sending = false;
  int _lastDocCount = 0;
  StreamSubscription<User?>? _authSub;

  void _onCtrlChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    miUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _ctrl.addListener(_onCtrlChanged);
    if (miUid.isNotEmpty) {
      unawaited(_prepare());
    } else {
      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (!mounted || _chatReady || _chatError) return;
        final uid = user?.uid ?? '';
        if (uid.isEmpty) return;
        miUid = uid;
        unawaited(_prepare());
      });
    }
  }

  Future<void> _prepare() async {
    if (miUid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _chatError = true;
        _chatErrorMsg = 'Iniciá sesión para usar el chat.';
      });
      return;
    }
    if (widget.otroUid.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _chatError = true;
        _chatErrorMsg = 'No hay otro participante para este chat.';
      });
      return;
    }
    try {
      final cid = await ChatRepo.resolveOrCreateChatId(
        uidA: miUid,
        uidB: widget.otroUid,
        viajeId: widget.viajeId,
      );
      if (!mounted) return;
      setState(() {
        chatId = cid;
        _chatReady = true;
        _chatError = false;
        _chatErrorMsg = null;
      });
    } catch (e, st) {
      uxLog('CHAT', 'prepare falló', e);
      if (kDebugMode) {
        debugPrintStack(stackTrace: st);
      }
      if (!mounted) return;
      setState(() {
        _chatError = true;
        _chatErrorMsg = 'No se pudo preparar el chat: $e';
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final t = _ctrl.text.trim();
    if (t.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe un mensaje antes de enviar')),
      );
      return;
    }
    if (t.length > ChatScreen.kMaxMensajeLen) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mensaje demasiado largo (máx. 800 caracteres).',
          ),
        ),
      );
      return;
    }
    if (!_chatReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preparando el chat… intenta de nuevo')),
      );
      return;
    }
    setState(() => _sending = true);
    _ctrl.clear();
    try {
      await MensajeriaService.enviarMensajeViaje(
        viajeId: chatId,
        deUid: miUid,
        texto: t,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mensaje enviado'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e, st) {
      uxLog('CHAT', 'enviar falló', e);
      if (kDebugMode) {
        debugPrintStack(stackTrace: st);
      }
      if (!mounted) return;
      _ctrl.text = t;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _bubble(BuildContext context, Map<String, dynamic> m) {
    final emisor = (m['de'] ?? m['from'] ?? m['senderUid']) as String? ?? '';
    final soyYo = emisor == miUid;

    final textoRaw = m['texto'];
    final texto =
        (textoRaw is String) ? textoRaw : (textoRaw?.toString() ?? '');

    final ts = m['ts'] ?? m['createdAt'] ?? m['enviadoEn'];
    DateTime? when;
    if (ts is Timestamp) when = ts.toDate();
    if (ts is DateTime) when = ts;
    final hora = when != null
        ? '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}'
        : '';

    final cs = Theme.of(context).colorScheme;
    final bubbleBg = soyYo ? cs.primary : cs.surfaceContainerHighest;
    final fg = soyYo ? cs.onPrimary : cs.onSurface;
    final sub =
        soyYo ? cs.onPrimary.withValues(alpha: 0.75) : cs.onSurfaceVariant;

    return Align(
      alignment: soyYo ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: bubbleBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment:
              soyYo ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (texto.isEmpty)
              Text('—', style: TextStyle(color: sub))
            else
              Text(texto, style: TextStyle(color: fg)),
            if (hora.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(hora, style: TextStyle(color: sub, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          widget.tituloCompacto
              ? widget.otroNombre
              : 'Chat con ${widget.otroNombre}',
        ),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: cs.surfaceTint,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: _chatError
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              size: 48, color: cs.error),
                          const SizedBox(height: 16),
                          Text(
                            _chatErrorMsg ?? 'No se pudo abrir el chat.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.error, height: 1.4),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: () {
                              setState(() {
                                _chatError = false;
                                _chatErrorMsg = null;
                              });
                              unawaited(_prepare());
                            },
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  )
                : !_chatReady
                ? Center(child: CircularProgressIndicator(color: cs.primary))
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: ChatRepo.streamMensajes(chatId),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return Center(
                            child:
                                CircularProgressIndicator(color: cs.primary));
                      }
                      if (snap.hasError) {
                        final msg = snap.error.toString();
                        uxLog('CHAT', 'stream mensajes error', snap.error);
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'No se pueden cargar mensajes.\n$msg',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.error),
                            ),
                          ),
                        );
                      }
                      if (!snap.hasData) {
                        return const SizedBox.shrink();
                      }
                      final docs = snap.data!.docs;
                      final int n = docs.length;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        if (n > _lastDocCount &&
                            _lastDocCount > 0 &&
                            _scrollCtrl.hasClients &&
                            _scrollCtrl.offset < 120) {
                          unawaited(
                            _scrollCtrl.animateTo(
                              0,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                            ),
                          );
                        }
                        _lastDocCount = n;
                      });
                      if (docs.isEmpty) {
                        return Center(
                          child: Text(
                            'Empieza la conversación',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        );
                      }
                      return ListView.builder(
                        controller: _scrollCtrl,
                        reverse: true,
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final m = docs[i].data();
                          return _bubble(context, m);
                        },
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      enabled: !_sending,
                      maxLength: ChatScreen.kMaxMensajeLen,
                      buildCounter: (
                        context, {
                        required int currentLength,
                        required bool isFocused,
                        required int? maxLength,
                      }) =>
                          const SizedBox.shrink(),
                      style: TextStyle(color: cs.onSurface),
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje…',
                        hintStyle: TextStyle(color: cs.onSurfaceVariant),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.primary, width: 2),
                        ),
                      ),
                      onSubmitted: (_) {
                        if (!_sending &&
                            _ctrl.text.trim().isNotEmpty) {
                          unawaited(_send());
                        }
                      },
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _sending
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary,
                            ),
                          ),
                        )
                      : IconButton.filledTonal(
                          onPressed: (_sending || _ctrl.text.trim().isEmpty)
                              ? null
                              : () => unawaited(_send()),
                          icon: Icon(Icons.send, color: cs.primary),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
