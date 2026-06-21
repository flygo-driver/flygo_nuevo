import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/turismo_control_adm_repo.dart';

/// Cliente: mensaje in-app a operaciones turismo (visible en panel ADM en tiempo real).
class TurismoMensajeOperacionesPanel extends StatefulWidget {
  const TurismoMensajeOperacionesPanel({
    super.key,
    required this.viajeId,
    this.origenPantalla = 'espera_asignacion',
    this.titulo = 'Escribir a operaciones RAI',
    this.subtitulo =
        'Si no hay chofer disponible, cuéntanos aquí. Operaciones lo ve al instante.',
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
          content: Text('Mensaje enviado. Operaciones lo revisará pronto.'),
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
          TextField(
            controller: _ctrl,
            maxLines: 3,
            maxLength: TurismoControlAdmRepo.maxMensajeChars,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _enviar(),
            decoration: InputDecoration(
              hintText: 'Ej.: Necesito jeepeta para 5 personas mañana 8am…',
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
