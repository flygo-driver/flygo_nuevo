// lib/pantallas/admin/admin_promos_mxk.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'admin_ui_theme.dart';

class AdminPromosMxK extends StatefulWidget {
  const AdminPromosMxK({super.key});

  @override
  State<AdminPromosMxK> createState() => _AdminPromosMxKState();
}

class _AdminPromosMxKState extends State<AdminPromosMxK> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ✅ Usar 'promociones' para que coincida con TarifaServiceUnificado
  DocumentReference<Map<String, dynamic>> get _ref =>
      _db.collection('config').doc('promociones');

  bool _activa = false;
  int _m = 3;
  int _k = 1;
  int _porcentaje = 15;

  bool _cargando = true;
  bool _guardando = false;

  final TextEditingController _mCtrl = TextEditingController();
  final TextEditingController _kCtrl = TextEditingController();
  final TextEditingController _pCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _mCtrl.dispose();
    _kCtrl.dispose();
    _pCtrl.dispose();
    super.dispose();
  }

  int _toInt(dynamic v, {required int fallback}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);

    try {
      final snap = await _ref.get();
      if (snap.exists) {
        final Map<String, dynamic> d = snap.data()!;

        _activa = (d['activa'] == true);
        _m = _toInt(d['m'], fallback: 3).clamp(1, 999);
        _k = _toInt(d['k'], fallback: 1).clamp(1, 999);
        _porcentaje = _toInt(d['porcentaje'], fallback: 15).clamp(0, 95);
      }

      _mCtrl.text = '$_m';
      _kCtrl.text = '$_k';
      _pCtrl.text = '$_porcentaje';
    } catch (e) {
      debugPrint('Error cargando promos: $e');
      _mCtrl.text = '$_m';
      _kCtrl.text = '$_k';
      _pCtrl.text = '$_porcentaje';
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _setPreset(int m, int k) {
    setState(() {
      _m = m;
      _k = k;
      _mCtrl.text = '$m';
      _kCtrl.text = '$k';

      // ✅ CORREGIDO: Agregar llaves en todas las condiciones if
      if (m == 1 && k == 1) {
        _porcentaje = 50;
      } else if (m == 3 && k == 1) {
        _porcentaje = 75;
      } else if (m == 4 && k == 2) {
        _porcentaje = 66;
      } else if (m == 5 && k == 1) {
        _porcentaje = 83;
      } else if (m == 2 && k == 1) {
        _porcentaje = 66;
      } else if (m == 3 && k == 2) {
        _porcentaje = 60;
      } else if (m == 10 && k == 1) {
        _porcentaje = 91;
      }

      // ✅ CORREGIDO: Quitar llaves innecesarias en interpolación
      _pCtrl.text = '$_porcentaje';
    });
  }

  String get _modo => '${_m}x$_k'; // ✅ CORREGIDO: Quitar llaves innecesarias

  bool get _valoresValidos {
    final int m = int.tryParse(_mCtrl.text.trim()) ?? _m;
    final int k = int.tryParse(_kCtrl.text.trim()) ?? _k;
    final int p = int.tryParse(_pCtrl.text.trim()) ?? _porcentaje;

    return m >= 1 && k >= 1 && p >= 0 && p <= 95;
  }

  Future<void> _guardar() async {
    final int m = int.tryParse(_mCtrl.text.trim()) ?? _m;
    final int k = int.tryParse(_kCtrl.text.trim()) ?? _k;
    final int p = int.tryParse(_pCtrl.text.trim()) ?? _porcentaje;

    final int m2 = m.clamp(1, 999);
    final int k2 = k.clamp(1, 999);
    final int p2 = p.clamp(0, 95);

    setState(() {
      _m = m2;
      _k = k2;
      _porcentaje = p2;
      _guardando = true;
    });

    try {
      final Map<String, dynamic> data = {
        'activa': _activa,
        'tipo': 'mxk',
        'm': _m,
        'k': _k,
        'modo': _modo,
        'porcentaje': _porcentaje,
        'viajesRequeridos': _m,
        'viajesGratis': _k,
        // ✅ CORREGIDO: Quitar llaves innecesarias en interpolación
        'descripcion': '${_m}x$_k - $_porcentaje% descuento',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _ref.set(data, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Promoción guardada correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error guardando: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        iconTheme: IconThemeData(color: AdminUi.appBarFg(context)),
        title: Text('Promociones M×K',
            style: TextStyle(color: AdminUi.onCard(context))),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AdminUi.appBarFg(context)),
            onPressed: _cargar,
            tooltip: 'Recargar',
          ),
        ],
      ),
      body: _cargando
          ? Center(
              child: CircularProgressIndicator(
                  color: AdminUi.progressAccent(context)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                // Info de ubicación
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AdminUi.card(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AdminUi.borderSubtle(context)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: AdminUi.muted(context), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'config/promociones',
                          style: TextStyle(
                            color: AdminUi.muted(context),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Switch activar/desactivar
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AdminUi.card(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AdminUi.borderSubtle(context)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Promo activa',
                              style: TextStyle(
                                color: AdminUi.onCard(context),
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Si está OFF, el sistema cobra precio normal.',
                              style:
                                  TextStyle(color: AdminUi.secondary(context)),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _activa,
                        onChanged: (bool v) => setState(() => _activa = v),
                        activeColor: AdminUi.progressAccent(context),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),
                Divider(color: AdminUi.borderSubtle(context)),

                const SizedBox(height: 14),
                Text(
                  'Presets rápidos',
                  style: TextStyle(
                    color: AdminUi.secondary(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),

                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _presetBtn('1x1 (50%)', 1, 1),
                    _presetBtn('2x1 (66%)', 2, 1),
                    _presetBtn('3x1 (75%)', 3, 1),
                    _presetBtn('4x2 (66%)', 4, 2),
                    _presetBtn('5x1 (83%)', 5, 1),
                    _presetBtn('3x2 (60%)', 3, 2),
                    _presetBtn('10x1 (91%)', 10, 1),
                  ],
                ),

                const SizedBox(height: 22),
                Divider(color: AdminUi.borderSubtle(context)),

                const SizedBox(height: 14),
                Text(
                  'Configuración manual',
                  style: TextStyle(
                    color: AdminUi.secondary(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _numField(
                        label: 'M (con descuento)',
                        controller: _mCtrl,
                        hint: 'Ej: 3',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _numField(
                        label: 'K (normales)',
                        controller: _kCtrl,
                        hint: 'Ej: 1',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),
                _numField(
                  label: 'Porcentaje de descuento',
                  controller: _pCtrl,
                  hint: 'Ej: 15',
                  suffix: '%',
                ),

                const SizedBox(height: 22),

                // Vista previa
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AdminUi.card(context),
                        _activa
                            ? Colors.green.withValues(alpha: 0.1)
                            : AdminUi.inputFill(context),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _activa
                          ? Colors.green.withValues(alpha: 0.3)
                          : AdminUi.borderSubtle(context),
                      width: _activa ? 2 : 1,
                    ),
                  ),
                  child: _buildPreview(),
                ),

                const SizedBox(height: 20),

                // Botón guardar
                SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _guardando || !_valoresValidos ? null : _guardar,
                    icon: const Icon(Icons.save),
                    label: Text(
                      _guardando ? 'Guardando...' : 'GUARDAR PROMOCIÓN',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      disabledBackgroundColor: Colors.grey.shade800,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Información adicional
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AdminUi.inputFill(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AdminUi.borderSubtle(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.lightbulb_outline,
                              color: Colors.amber, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '¿Cómo funciona M×K?',
                            style: TextStyle(
                              color: AdminUi.onCard(context),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '• En cada ciclo de M + K viajes:',
                        style: TextStyle(color: AdminUi.secondary(context)),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Text(
                          '• Los primeros M viajes tienen descuento',
                          style: TextStyle(
                              color: Colors.green.withValues(alpha: 0.9)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Text(
                          '• Los siguientes K viajes pagan tarifa completa',
                          style: TextStyle(
                              color: Colors.blue.withValues(alpha: 0.9)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Ejemplo: 3x1 con 15% descuento\n'
                          'Viajes 1,2,3 → 15% descuento\n'
                          'Viaje 4 → precio completo\n'
                          'Viajes 5,6,7 → 15% descuento\n'
                          'Viaje 8 → precio completo',
                          style: TextStyle(
                            color: AdminUi.secondary(context),
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _presetBtn(String text, int m, int k) {
    final bool selected = (_m == m && _k == k);
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _setPreset(m, k),
      borderRadius: BorderRadius.circular(30),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primary : AdminUi.card(context),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: selected ? cs.primary : AdminUi.borderSubtle(context),
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: selected ? cs.onPrimary : AdminUi.onCard(context),
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _numField({
    required String label,
    required TextEditingController controller,
    required String hint,
    String? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AdminUi.secondary(context),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: TextStyle(color: AdminUi.onCard(context), fontSize: 16),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                color: AdminUi.secondary(context).withValues(alpha: 0.75)),
            suffixText: suffix,
            suffixStyle: TextStyle(color: AdminUi.secondary(context)),
            filled: true,
            fillColor: AdminUi.inputFill(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AdminUi.borderSubtle(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AdminUi.borderSubtle(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary, width: 1.4),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final int m = int.tryParse(_mCtrl.text.trim()) ?? _m;
    final int k = int.tryParse(_kCtrl.text.trim()) ?? _k;
    final int p = int.tryParse(_pCtrl.text.trim()) ?? _porcentaje;

    final int m2 = m.clamp(1, 999);
    final int k2 = k.clamp(1, 999);
    final int p2 = p.clamp(0, 95);

    final int ciclo = m2 + k2;
    final double descuentoEfectivo = (m2 * p2) / (m2 + k2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Vista previa',
              style: TextStyle(
                color: AdminUi.onCard(context),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _activa
                    ? Colors.green.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _activa ? 'ACTIVA' : 'INACTIVA',
                style: TextStyle(
                  color: _activa ? Colors.green : Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Métricas
        Row(
          children: [
            _buildMetricCard(
                'Ciclo', '$ciclo viajes', Icons.repeat, Colors.blue),
            const SizedBox(width: 8),
            _buildMetricCard(
                'Dto. x viaje', '$p2%', Icons.percent, Colors.amber),
            const SizedBox(width: 8),
            _buildMetricCard(
                'Ahorro prom.',
                '${descuentoEfectivo.toStringAsFixed(1)}%',
                Icons.trending_down,
                Colors.green),
          ],
        ),

        const SizedBox(height: 16),

        // Visualización del ciclo
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AdminUi.inputFill(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Secuencia:',
                style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(ciclo.clamp(1, 12), (int i) {
                  final int pos = i + 1;
                  final bool esDesc = pos <= m2;
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: esDesc
                          ? Colors.green.withValues(alpha: 0.2)
                          : Colors.blue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: esDesc ? Colors.green : Colors.blue,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      esDesc ? '#$pos -$p2%' : '#$pos completo',
                      style: TextStyle(
                        color: esDesc ? Colors.green : Colors.blue,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),

        if (_activa) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Los clientes verán el descuento aplicado según su contador de viajes',
                    style: TextStyle(
                        color: AdminUi.secondary(context), fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMetricCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AdminUi.inputFill(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: AdminUi.muted(context),
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
