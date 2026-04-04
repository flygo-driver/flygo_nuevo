// lib/pantallas/admin/admin_promos.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

/// Panel de Promociones M×K (oculto para cliente)
/// Doc: /config/promo_3x1  {activa:bool, porcentaje:int, modo:String "MxK", m:int, k:int}
class AdminPromosPage extends StatefulWidget {
  const AdminPromosPage({super.key});
  @override
  State<AdminPromosPage> createState() => _AdminPromosPageState();
}

class _AdminPromosPageState extends State<AdminPromosPage> {
  final _db = FirebaseFirestore.instance;

  bool _cargando = true;
  bool _activa = false;
  int _porcentaje = 40;
  int _m = 3;
  int _k = 1;

  final _formKey = GlobalKey<FormState>();
  final _porcCtrl = TextEditingController(text: '40');
  final _mCtrl = TextEditingController(text: '3');
  final _kCtrl = TextEditingController(text: '1');

  final List<String> _presets = const ['1x1', '3x1', '4x2', '5x1', '10x1', '3x2'];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _porcCtrl.dispose();
    _mCtrl.dispose();
    _kCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final snap = await _db.doc('config/promo_3x1').get();
      final data = snap.data();

      final bool activa = (data?['activa'] ?? false) == true;
      final int porcentaje = (data?['porcentaje'] ?? 40) as int;

      // Preferir m/k guardados; si faltan, parsear "modo"
      int m = 0, k = 0;
      if (data?['m'] is num) m = (data?['m'] as num).toInt();
      if (data?['k'] is num) k = (data?['k'] as num).toInt();
      if (m <= 0 || k <= 0) {
        final String modo = (data?['modo'] ?? '3x1').toString();
        final (mm, kk) = _parseMxK(modo);
        m = mm; k = kk;
      }

      setState(() {
        _activa = activa;
        _porcentaje = porcentaje;
        _m = m;
        _k = k;
        _porcCtrl.text = _porcentaje.toString();
        _mCtrl.text = _m.toString();
        _kCtrl.text = _k.toString();
        _cargando = false;
      });
    } catch (e) {
      setState(() => _cargando = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar la configuración: $e')),
      );
    }
  }

  (int, int) _parseMxK(String s) {
    final reg = RegExp(r'^(\d+)\s*x\s*(\d+)$');
    final m = reg.firstMatch(s.trim().toLowerCase());
    final mm = (m != null) ? int.tryParse(m.group(1)!) ?? 3 : 3;
    final kk = (m != null) ? int.tryParse(m.group(2)!) ?? 1 : 1;
    return (mm.clamp(1, 50), kk.clamp(1, 50));
  }

  void _applyPreset(String preset) {
    final (mm, kk) = _parseMxK(preset);
    setState(() {
      _m = mm;
      _k = kk;
      _mCtrl.text = _m.toString();
      _kCtrl.text = _k.toString();
    });
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final porc = int.tryParse(_porcCtrl.text.trim()) ?? 40;
    final m = int.tryParse(_mCtrl.text.trim()) ?? 3;
    final k = int.tryParse(_kCtrl.text.trim()) ?? 1;
    final modo = '${m}x$k';

    try {
      await _db.doc('config/promo_3x1').set({
        'activa': _activa,
        'porcentaje': porc,
        'modo': modo, // compat
        'm': m,       // preferido por ViajesRepo
        'k': k,       // preferido por ViajesRepo
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Configuración guardada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error al guardar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Promociones (M×K)', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    const Text('Config global: /config/promo_3x1',
                        style: TextStyle(color: Colors.white54)),
                    const SizedBox(height: 12),

                    SwitchListTile(
                      value: _activa,
                      onChanged: (v) => setState(() => _activa = v),
                      title: const Text('Promo activa', style: TextStyle(color: Colors.white)),
                      subtitle: const Text(
                        'Si está OFF, el sistema cobra precio normal.',
                        style: TextStyle(color: Colors.white60),
                      ),
                      activeColor: Colors.greenAccent,
                    ),

                    const SizedBox(height: 12),
                    const Text('Presets rápidos', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 8),

                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: _presets.map((p) {
                        return ChoiceChip(
                          label: Text(p),
                          selected: false,
                          onSelected: (_) => _applyPreset(p),
                          selectedColor: Colors.greenAccent,
                          backgroundColor: Colors.white12,
                          labelStyle: const TextStyle(color: Colors.white),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 8),

                    const Text('Config manual M×K', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 8),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _mCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'M (con descuento)',
                              helperText: 'Ej: 3 → 3 viajes con descuento',
                              labelStyle: TextStyle(color: Colors.white70),
                              helperStyle: TextStyle(color: Colors.white38),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white24),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white54),
                              ),
                            ),
                            validator: (v) {
                              final n = int.tryParse(v?.trim() ?? '');
                              if (n == null) return 'Número válido';
                              if (n < 1 || n > 50) return 'Rango 1–50';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _kCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'K (normales)',
                              helperText: 'Ej: 1 → 1 viaje normal',
                              labelStyle: TextStyle(color: Colors.white70),
                              helperStyle: TextStyle(color: Colors.white38),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white24),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white54),
                              ),
                            ),
                            validator: (v) {
                              final n = int.tryParse(v?.trim() ?? '');
                              if (n == null) return 'Número válido';
                              if (n < 1 || n > 50) return 'Rango 1–50';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _porcCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Porcentaje de descuento',
                        helperText: 'Ej: 40 = 40% OFF (paga 60%)',
                        labelStyle: TextStyle(color: Colors.white70),
                        helperStyle: TextStyle(color: Colors.white38),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white54),
                        ),
                        suffixText: '%',
                        suffixStyle: TextStyle(color: Colors.white70),
                      ),
                      validator: (v) {
                        final n = int.tryParse(v?.trim() ?? '');
                        if (n == null) return 'Número válido';
                        if (n < 1 || n > 90) return 'Recomendado: 1–90';
                        return null;
                      },
                      onChanged: (v) {
                        final n = int.tryParse(v.trim());
                        if (n != null) _porcentaje = n;
                      },
                    ),

                    const SizedBox(height: 24),
                    _PreviewCard(
                      activa: _activa,
                      m: _m,
                      k: _k,
                      porcentaje: int.tryParse(_porcCtrl.text.trim()) ?? _porcentaje,
                    ),

                    const SizedBox(height: 24),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _guardar,
                        icon: const Icon(Icons.save),
                        label: const Text('Guardar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final bool activa;
  final int m; // con descuento
  final int k; // normales
  final int porcentaje;

  const _PreviewCard({
    required this.activa,
    required this.m,
    required this.k,
    required this.porcentaje,
  });

  @override
  Widget build(BuildContext context) {
    final L = (m + k).clamp(1, 100);
    final factor = (100 - porcentaje) / 100.0;

    return Card(
      color: Colors.grey[900],
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Previsualización', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Estado: ${activa ? 'ACTIVA' : 'INACTIVA'}'),
              Text('Modo: ${m}x$k  → ciclo $L ( $m con descuento + $k normales )'),
              Text('Descuento: $porcentaje%  → paga ${(factor * 100).toStringAsFixed(0)}%'),
              const SizedBox(height: 12),
              const Text('Ciclo (posiciones):'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: List.generate(L, (i) {
                  final idx = i + 1;
                  final conDesc = (idx <= m);
                  return Chip(
                    label: Text('#$idx ${conDesc ? '-$porcentaje%' : 'normal'}'),
                    // reemplazo de withOpacity -> withValues (Flutter 3.24+)
                    backgroundColor: conDesc
                        ? Colors.green.withValues(alpha: 0.22)
                        : Colors.white12,
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
