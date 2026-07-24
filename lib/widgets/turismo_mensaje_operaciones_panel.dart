import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/servicios/turismo_control_adm_repo.dart';

/// Cliente: mensaje in-app a operaciones turismo (visible en panel ADM en tiempo real).
class TurismoMensajeOperacionesPanel extends StatefulWidget {
  const TurismoMensajeOperacionesPanel({
    super.key,
    required this.viajeId,
    this.origenPantalla = 'espera_asignacion',
    this.titulo = 'Escribir a operaciones RAI',
    this.subtitulo =
        'Si no hay chofer con tu vehículo, cuéntanos aquí. Operaciones lo ve al instante.',
  });

  final String viajeId;
  final String origenPantalla;
  final String titulo;
  final String subtitulo;

  @override
  State<TurismoMensajeOperacionesPanel> createState() =>
      _TurismoMensajeOperacionesPanelState();
}

class _TurismoMensajeOperacionesPanelState
    extends State<TurismoMensajeOperacionesPanel> {
  final TextEditingController _ctrl = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    setState(() => _enviando = true);
    try {
      await TurismoControlAdmRepo.enviarMensajeCliente(
        viajeId: widget.viajeId,
        mensaje: _ctrl.text,
        origenPantalla: widget.origenPantalla,
      );
      if (!mounted) return;
      _ctrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mensaje enviado. Operaciones turismo lo recibe en el panel admin.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('StateError: ', ''))),
      );
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
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: TurismoControlAdmRepo.streamMensajesClienteViaje(
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
            maxLength: TurismoControlAdmRepo.maxMensajeChars,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _enviar(),
            decoration: InputDecoration(
              hintText:
                  'Ej.: Necesito jeepeta para 5 personas, no hay disponibles…',
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
            label: Text(_enviando ? 'Enviando…' : 'Enviar a operaciones'),
          ),
        ],
      ),
    );
  }
}
