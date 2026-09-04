import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/servicios/operaciones_mensajes_adm_repo.dart';

/// Cliente: mensaje in-app a operaciones RAI (visible en panel admin en tiempo real).
class ClienteMensajeOperacionesPanel extends StatefulWidget {
  const ClienteMensajeOperacionesPanel({
    super.key,
    required this.viajeId,
    this.origenPantalla = 'espera_conductor',
    this.titulo = 'Escribir a operaciones RAI',
    this.subtitulo =
        'Si no hay conductor cerca o llevas tiempo esperando, cuéntanos aquí. '
        'Operaciones lo ve al instante en el panel admin.',
    this.hintMensaje =
        'Ej.: Llevo 10 min esperando, no aparece ningún conductor cerca…',
  });

  final String viajeId;
  final String origenPantalla;
  final String titulo;
  final String subtitulo;
  final String hintMensaje;

  @override
  State<ClienteMensajeOperacionesPanel> createState() =>
      _ClienteMensajeOperacionesPanelState();
}

class _ClienteMensajeOperacionesPanelState
    extends State<ClienteMensajeOperacionesPanel> {
  final TextEditingController _ctrl = TextEditingController();
  bool _enviando = false;
  bool _enviadoExito = false;
  String? _errorEnvio;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _mostrarAviso(String mensaje, {bool error = false}) {
    final ScaffoldMessengerState? messenger =
        ScaffoldMessenger.maybeOf(context) ??
        ScaffoldMessenger.maybeOf(
          Navigator.of(context, rootNavigator: true).context,
        );
    messenger?.showSnackBar(
      SnackBar(
        content: Text(mensaje),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Colors.red.shade800 : const Color(0xFF2E7D32),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      ),
    );
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    final String texto = _ctrl.text.trim();
    if (texto.isEmpty) {
      setState(() => _errorEnvio = 'Escribe un mensaje antes de enviar.');
      return;
    }

    setState(() {
      _enviando = true;
      _errorEnvio = null;
      _enviadoExito = false;
    });
    try {
      await OperacionesMensajesAdmRepo.enviarMensajeCliente(
        viajeId: widget.viajeId,
        mensaje: texto,
        origenPantalla: widget.origenPantalla,
      );
      if (!mounted) return;
      _ctrl.clear();
      setState(() => _enviadoExito = true);
      _mostrarAviso('Mensaje enviado. Operaciones RAI lo recibe en el panel admin.');
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final String msg = switch (e.code) {
        'permission-denied' =>
          'No se pudo enviar. Cierra la app, vuelve a entrar e inténtalo de nuevo.',
        'failed-precondition' =>
          e.message ?? 'No se pudo enviar en este momento.',
        _ => 'Error al enviar: ${e.message ?? e.code}',
      };
      setState(() => _errorEnvio = msg);
      _mostrarAviso(msg, error: true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final String msg = (e.message ?? '').trim().isNotEmpty
          ? e.message!.trim()
          : 'No se pudo enviar. Intenta de nuevo en unos segundos.';
      setState(() => _errorEnvio = msg);
      _mostrarAviso(msg, error: true);
    } catch (e) {
      if (!mounted) return;
      final String msg =
          e.toString().replaceFirst('StateError: ', '').replaceFirst('ArgumentError: ', '');
      setState(() => _errorEnvio = msg);
      _mostrarAviso(msg, error: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final DateFormat fmt = DateFormat('dd/MM HH:mm');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.35),
        ),
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.titulo,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.subtitulo,
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.35,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 10),
          if (_enviadoExito)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1B5E20).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF43A047).withValues(alpha: 0.55),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Color(0xFF43A047)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Enviado · Operaciones RAI lo verá en el panel admin',
                      style: TextStyle(
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_errorEnvio != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _errorEnvio!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: OperacionesMensajesAdmRepo.streamMensajesClienteViaje(
              widget.viajeId,
            ),
            builder: (
              BuildContext context,
              AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap,
            ) {
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'No se pudo cargar el historial. Puedes enviar un mensaje nuevo.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                );
              }
              final docs = snap.data?.docs ?? const [];
              if (docs.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Tus mensajes a operaciones',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...docs.map((doc) {
                    final m = doc.data();
                    final String texto = (m['mensaje'] ?? '').toString();
                    final dynamic ts = m['createdAt'];
                    DateTime? cuando;
                    if (ts is Timestamp) cuando = ts.toDate();
                    final bool leido = m['leidoPorAdm'] == true;
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.outline
                              .withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(texto),
                          if (cuando != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${fmt.format(cuando)} · '
                              '${leido ? 'Visto por operaciones' : 'Enviado · operaciones lo verá pronto'}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: leido
                                    ? Colors.green.shade700
                                    : theme.colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          if ((m['respuesta'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Operaciones RAI responde',
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (m['respuesta'] ?? '').toString(),
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(height: 1.35),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
          TextField(
            controller: _ctrl,
            maxLines: 3,
            maxLength: OperacionesMensajesAdmRepo.maxMensajeChars,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _enviar(),
            onChanged: (_) {
              if (_enviadoExito || _errorEnvio != null) {
                setState(() {
                  _enviadoExito = false;
                  _errorEnvio = null;
                });
              }
            },
            decoration: InputDecoration(
              hintText: widget.hintMensaje,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _enviando ? null : _enviar,
            icon: _enviando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(
              _enviando
                  ? 'Enviando…'
                  : (_enviadoExito ? '¡Enviado!' : 'Enviar a operaciones'),
            ),
          ),
        ],
      ),
    );
  }
}
