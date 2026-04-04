import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/data/reportes_viaje_data.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';

class ReportarViaje extends StatefulWidget {
  const ReportarViaje({super.key, required this.viaje});

  final Viaje viaje;

  @override
  State<ReportarViaje> createState() => _ReportarViajeState();
}

class _ReportarViajeState extends State<ReportarViaje> {
  static const List<String> _motivos = <String>[
    'Mal servicio',
    'Conduccion peligrosa',
    'Conducta inapropiada',
    'Cobro incorrecto',
    'Vehiculo en mal estado',
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
    final uidCliente = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uidCliente.isEmpty) return;
    final comentario = _comentarioCtrl.text.trim();
    if (comentario.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe un comentario para continuar.')),
      );
      return;
    }
    setState(() => _guardando = true);
    try {
      await ReportesViajeData.crearReporte(
        viajeId: widget.viaje.id,
        uidCliente: uidCliente,
        uidTaxista: widget.viaje.uidTaxista,
        motivo: _motivo,
        comentario: comentario,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reporte enviado correctamente.')),
      );
      Navigator.of(context).pop(true);
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
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = cs.onSurface;
    final muted = onSurface.withValues(alpha: 0.72);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: theme.appBarTheme.elevation ?? 0,
        title: Text(
          'Reportar viaje',
          style: TextStyle(
            color: theme.appBarTheme.foregroundColor ?? onSurface,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Selecciona el motivo y describe lo ocurrido. Tu reporte será revisado por administración.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _motivo,
            dropdownColor: cs.surface,
            decoration: InputDecoration(
              labelText: 'Motivo',
              labelStyle: TextStyle(color: onSurface.withValues(alpha: 0.8)),
            ),
            style: TextStyle(color: onSurface),
            items: _motivos
                .map((m) => DropdownMenuItem<String>(value: m, child: Text(m)))
                .toList(),
            onChanged: (v) => setState(() => _motivo = v ?? _motivo),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _comentarioCtrl,
            minLines: 4,
            maxLines: 8,
            maxLength: 500,
            style: TextStyle(color: onSurface),
            decoration: InputDecoration(
              labelText: 'Comentario',
              hintText: 'Describe lo ocurrido en este viaje...',
              labelStyle: TextStyle(color: onSurface.withValues(alpha: 0.8)),
              hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.45)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _guardando ? null : _enviar,
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: isDark ? Colors.black87 : Colors.white,
              ),
              icon: _guardando
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isDark ? Colors.black87 : Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(_guardando ? 'Enviando...' : 'Enviar reporte'),
            ),
          ),
        ],
      ),
    );
  }
}
