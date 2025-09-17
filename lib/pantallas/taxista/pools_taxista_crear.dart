// lib/pantallas/taxista/pools_taxista_crear.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flygo_nuevo/servicios/pool_repo.dart';

class PoolsTaxistaCrear extends StatefulWidget {
  const PoolsTaxistaCrear({super.key});

  @override
  State<PoolsTaxistaCrear> createState() => _PoolsTaxistaCrearState();
}

class _PoolsTaxistaCrearState extends State<PoolsTaxistaCrear> {
  final _form = GlobalKey<FormState>();

  // Estado del formulario (con defaults sensatos)
  String _tipo = 'consular';
  String _sentido = 'ida';
  String _origenTown = 'Higüey';
  String _destino = 'Consulado SD';

  DateTime _fecha = DateTime.now().add(const Duration(days: 1));
  DateTime? _fechaVuelta;

  int _capacidad = 15;
  int _minConf = 8;

  double _precio = 1000;
  double _deposit = 0.30; // 0..1
  double _fee = 0.12; // 0..1

  final _pickupCtrl = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _pickupCtrl.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pickFecha({required bool esVuelta}) async {
    final initial = esVuelta
        ? (_fechaVuelta ?? _fecha.add(const Duration(days: 1)))
        : _fecha;

    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (!mounted || d == null) return;

    final TimeOfDay? t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 7, minute: 0),
    );
    if (!mounted || t == null) return;

    final DateTime dt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() {
      if (esVuelta) {
        _fechaVuelta = dt;
      } else {
        _fecha = dt;
        // Si cambia salida y la vuelta quedó antes, limpiar vuelta.
        if (_fechaVuelta != null && _fechaVuelta!.isBefore(_fecha)) {
          _fechaVuelta = null;
        }
      }
    });
  }

  Future<void> _crear() async {
    // Validaciones rápidas previas a guardar
    if (!_form.currentState!.validate()) return;
    _form.currentState!.save();

    // Reglas de fechas
    final DateTime ahora = DateTime.now();
    final DateTime salidaMin = ahora.add(const Duration(minutes: 5));
    if (_fecha.isBefore(salidaMin)) {
      _snack('La salida debe ser al menos en 5 minutos.');
      return;
    }
    if (_sentido == 'ida_y_vuelta') {
      if (_fechaVuelta == null) {
        _snack('Selecciona la fecha de vuelta.');
        return;
      }
      if (_fechaVuelta!.isBefore(_fecha)) {
        _snack('La vuelta no puede ser antes de la salida.');
        return;
      }
    }

    // Porcentajes (aseguramos fracción 0..1 aunque vengan como 30..100)
    final double dep = _deposit > 1 ? _deposit / 100.0 : _deposit;
    final double fee = _fee > 1 ? _fee / 100.0 : _fee;

    setState(() => _loading = true);
    try {
      final List<String> pickups = <String>[];
      final String p = _pickupCtrl.text.trim();
      if (p.isNotEmpty) pickups.add(p);

      final String id = await PoolRepo.crearPool(
        tipo: _tipo,
        sentido: _sentido,
        origenTown: _origenTown.trim(),
        destino: _destino.trim(),
        fechaSalida: _fecha,
        fechaVuelta: _sentido == 'ida_y_vuelta' ? _fechaVuelta : null,
        capacidad: _capacidad,
        minParaConfirmar: _minConf,
        precioPorAsiento: _precio.toDouble(),
        pickupPoints: pickups.isEmpty ? null : pickups,
        depositPct: dep,
        feePct: fee,
      );

      if (!mounted) return;
      _snack('✅ Viaje creado (#$id)');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _snack('❌ ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateFormat f = DateFormat('EEE d MMM - HH:mm', 'es');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Crear viaje por cupos',
          style: TextStyle(
            color: Colors.greenAccent,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card(
              child: Wrap(
                runSpacing: 12,
                children: [
                  _row(
                    left: _dropdown<String>(
                      label: 'Tipo',
                      value: _tipo,
                      items: const ['consular', 'tour'],
                      onChanged: (v) => setState(() => _tipo = v ?? 'consular'),
                    ),
                    right: _dropdown<String>(
                      label: 'Sentido',
                      value: _sentido,
                      items: const ['ida', 'vuelta', 'ida_y_vuelta'],
                      onChanged: (v) => setState(() => _sentido = v ?? 'ida'),
                    ),
                  ),
                  _row(
                    left: _text(
                      label: 'Pueblo (origen)',
                      initial: _origenTown,
                      onSaved: (v) => _origenTown = v,
                    ),
                    right: _text(
                      label: 'Destino',
                      initial: _destino,
                      onSaved: (v) => _destino = v,
                    ),
                  ),
                  _textFieldCtrl(
                    controller: _pickupCtrl,
                    label: 'Punto de encuentro (opcional)',
                    hint: 'Parque Central de …',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _card(
              child: Wrap(
                runSpacing: 12,
                children: [
                  _row(
                    left: _num(
                      label: 'Capacidad',
                      initial: _capacidad.toString(),
                      onSaved: (v) => _capacidad = int.parse(v),
                      min: 1,
                      max: 60,
                    ),
                    right: _num(
                      label: 'Mín. para confirmar',
                      initial: _minConf.toString(),
                      onSaved: (v) => _minConf = int.parse(v),
                      min: 0,
                      max: 60,
                    ),
                  ),
                  _row(
                    left: _num(
                      label: 'Precio por asiento (RD\$)',
                      initial: _precio.toStringAsFixed(0),
                      onSaved: (v) => _precio = double.parse(v),
                      min: 100,
                    ),
                    right: _num(
                      label: 'Depósito %',
                      initial: (_deposit * 100).toStringAsFixed(0),
                      onSaved: (v) => _deposit = double.parse(v) / 100.0,
                      min: 0,
                      max: 100,
                    ),
                  ),
                  _row(
                    left: _num(
                      label: 'Fee plataforma %',
                      initial: (_fee * 100).toStringAsFixed(0),
                      onSaved: (v) => _fee = double.parse(v) / 100.0,
                      min: 0,
                      max: 100,
                    ),
                    right: _fechaPicker(
                      label: 'Fecha salida',
                      text: f.format(_fecha),
                      onTap: () => _pickFecha(esVuelta: false),
                    ),
                  ),
                  if (_sentido == 'ida_y_vuelta')
                    _fechaPicker(
                      label: 'Fecha vuelta',
                      text: _fechaVuelta == null ? 'Seleccionar…' : f.format(_fechaVuelta!),
                      onTap: () => _pickFecha(esVuelta: true),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _crear,
                icon: const Icon(Icons.save),
                label: Text(_loading ? 'Creando…' : 'Crear viaje'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /* ======= UI helpers ======= */

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: child,
    );
  }

  Widget _row({required Widget left, required Widget right}) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required void Function(T?) onChanged,
  }) {
    return InputDecorator(
      decoration: const InputDecoration(
        filled: true,
        fillColor: Color(0xFF1A1A1A),
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ).copyWith(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          dropdownColor: const Color(0xFF1A1A1A),
          items: items
              .map((e) => DropdownMenuItem<T>(
                    value: e,
                    child: Text(e.toString(), style: const TextStyle(color: Colors.white)),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _text({
    required String label,
    required String initial,
    required void Function(String) onSaved,
  }) {
    return TextFormField(
      initialValue: initial,
      style: const TextStyle(color: Colors.white),
      decoration: const InputDecoration(
        filled: true,
        fillColor: Color(0xFF1A1A1A),
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ).copyWith(labelText: label),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
      onSaved: (v) => onSaved(v!.trim()),
    );
  }

  Widget _textFieldCtrl({
    required TextEditingController controller,
    required String label,
    String? hint,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
    );
  }

  Widget _num({
    required String label,
    required String initial,
    required void Function(String) onSaved,
    double? min,
    double? max,
  }) {
    return TextFormField(
      initialValue: initial,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Requerido';
        final double? n = double.tryParse(v.trim());
        if (n == null) return 'Número inválido';
        if (min != null && n < min) return 'Min: ${min.toStringAsFixed(0)}';
        if (max != null && n > max) return 'Max: ${max.toStringAsFixed(0)}';
        return null;
      },
      onSaved: (v) => onSaved(v!.trim()),
    );
  }

  Widget _fechaPicker({
    required String label,
    required String text,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.calendar_today),
          label: Text(text),
        ),
      ],
    );
  }
}
