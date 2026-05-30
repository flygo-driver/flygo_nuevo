import 'package:flutter/material.dart';

import 'package:flygo_nuevo/data/reportes_viaje_data.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';

/// Taxista reporta al cliente tras viaje completado.
class ReportarClienteViaje extends StatefulWidget {
  const ReportarClienteViaje({super.key, required this.viaje});

  final Viaje viaje;

  @override
  State<ReportarClienteViaje> createState() => _ReportarClienteViajeState();
}

class _ReportarClienteViajeState extends State<ReportarClienteViaje> {
  static const List<String> _motivos = <String>[
    'Cliente agresivo',
    'No pago',
    'Destrozo del vehiculo',
    'Conducta inapropiada',
    'Otro',
  ];

  String _motivo = _motivos.first;
  final TextEditingController _comentarioCtrl = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _comentarioCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_guardando) return;
    final String comentario = _comentarioCtrl.text.trim();
    if (comentario.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe un comentario para continuar.')),
      );
      return;
    }
    setState(() => _guardando = true);
    try {
      await ReportesViajeData.reportarProblemaSeguro(
        viajeId: widget.viaje.id,
        motivo: _motivo,
        comentario: comentario,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reporte enviado. Administración lo revisará.')),
      );
      Navigator.of(context, rootNavigator: true).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar el reporte: $e')),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Reportar pasajero'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Tu reporte será revisado por administración. '
            'Pueden aplicar medidas al pasajero si corresponde.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _motivo,
            decoration: const InputDecoration(labelText: 'Motivo'),
            items: _motivos
                .map((String m) => DropdownMenuItem<String>(value: m, child: Text(m)))
                .toList(),
            onChanged: (String? v) => setState(() => _motivo = v ?? _motivo),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _comentarioCtrl,
            minLines: 4,
            maxLines: 8,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Detalle',
              hintText: 'Describe lo ocurrido…',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _guardando ? null : _enviar,
            icon: _guardando
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onPrimary,
                    ),
                  )
                : const Icon(Icons.send),
            label: Text(_guardando ? 'Enviando…' : 'Enviar reporte'),
          ),
        ],
      ),
    );
  }
}
