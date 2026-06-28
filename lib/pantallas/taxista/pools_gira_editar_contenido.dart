import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/pool_repo.dart';
import 'package:flygo_nuevo/utils/bancos_rd.dart';
import 'package:flygo_nuevo/utils/pool_gira_contenido.dart';
import 'package:flygo_nuevo/widgets/campo_lugar_autocomplete.dart';
import 'package:flygo_nuevo/widgets/pool_gira_contenido_form.dart';
import 'package:intl/intl.dart';

/// Editar publicación de gira sin perder reservas ni pagos aprobados.
class PoolsGiraEditarContenido extends StatefulWidget {
  const PoolsGiraEditarContenido({super.key, required this.poolId});

  final String poolId;

  @override
  State<PoolsGiraEditarContenido> createState() =>
      _PoolsGiraEditarContenidoState();
}

class _PoolsGiraEditarContenidoState extends State<PoolsGiraEditarContenido> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _pool = <String, dynamic>{};

  String _origenTown = '';
  String _puntoSalida = '';
  String _destino = '';
  String _agenciaNombre = '';
  String _servicioBadge = '';
  String _descripcionViaje = '';
  String _bancoNombre = '';
  String _bancoCuenta = '';
  String _bancoTipoCuenta = '';
  String _bancoTitular = '';
  double _precio = 0;
  int _capacidad = 0;
  DateTime? _fechaSalida;
  DateTime? _fechaVuelta;
  String _sentido = 'ida';
  bool _recaudoCentral = false;
  PoolGiraContenidoExtra _contenido = const PoolGiraContenidoExtra();
  final List<String> _incluye = <String>[];

  final _agenciaCtrl = TextEditingController();
  final _servicioBadgeCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  final _capacidadCtrl = TextEditingController();
  final _bancoCuentaCtrl = TextEditingController();
  final _bancoTitularCtrl = TextEditingController();
  final _incluyeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _agenciaCtrl.dispose();
    _servicioBadgeCtrl.dispose();
    _descripcionCtrl.dispose();
    _precioCtrl.dispose();
    _capacidadCtrl.dispose();
    _bancoCuentaCtrl.dispose();
    _bancoTitularCtrl.dispose();
    _incluyeCtrl.dispose();
    super.dispose();
  }

  DateTime? _parsePoolTs(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  void _hydrateFromPool(Map<String, dynamic> d) {
    _pool = d;
    _origenTown = (d['origenTown'] ?? '').toString().trim();
    _puntoSalida = (d['puntoSalida'] ?? '').toString().trim();
    _destino = (d['destino'] ?? '').toString().trim();
    _agenciaNombre = (d['agenciaNombre'] ?? '').toString().trim();
    _servicioBadge = (d['servicioBadge'] ?? '').toString().trim();
    _descripcionViaje = (d['descripcionViaje'] ?? '').toString().trim();
    _bancoNombre = (d['bancoNombre'] ?? '').toString().trim();
    _bancoCuenta = (d['bancoCuenta'] ?? '').toString().trim();
    _bancoTipoCuenta = (d['bancoTipoCuenta'] ?? '').toString().trim();
    _bancoTitular = (d['bancoTitular'] ?? '').toString().trim();
    _precio = (d['precioPorAsiento'] as num?)?.toDouble() ?? 0;
    _capacidad = (d['capacidad'] as num?)?.toInt() ?? 0;
    _fechaSalida = _parsePoolTs(d['fechaSalida']);
    _fechaVuelta = _parsePoolTs(d['fechaVuelta']);
    _sentido = (d['sentido'] ?? 'ida').toString().trim().toLowerCase();
    _recaudoCentral =
        (d['recaudoModelo'] ?? '').toString().trim().toLowerCase() == 'central';
    _contenido = PoolGiraContenidoExtra.fromMap(d);
    _incluye
      ..clear()
      ..addAll(
        d['incluye'] is List
            ? List<String>.from(
                (d['incluye'] as List).map((e) => e.toString()),
              )
            : const <String>[],
      );

    _agenciaCtrl.text = _agenciaNombre;
    _servicioBadgeCtrl.text = _servicioBadge;
    _descripcionCtrl.text = _descripcionViaje;
    _precioCtrl.text = _precio > 0 ? _precio.toStringAsFixed(0) : '';
    _capacidadCtrl.text = _capacidad > 0 ? '$_capacidad' : '';
    _bancoCuentaCtrl.text = _bancoCuenta;
    _bancoTitularCtrl.text = _bancoTitular;
  }

  Future<void> _cargar() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('viajes_pool')
          .doc(widget.poolId)
          .get();
      if (!snap.exists) {
        setState(() {
          _error = 'Gira no encontrada.';
          _loading = false;
        });
        return;
      }
      setState(() {
        _hydrateFromPool(snap.data() ?? <String, dynamic>{});
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickFecha({required bool esVuelta}) async {
    final initial = esVuelta
        ? (_fechaVuelta ?? (_fechaSalida ?? DateTime.now()).add(const Duration(days: 1)))
        : (_fechaSalida ?? DateTime.now());

    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (!mounted || d == null) return;

    final TimeOfDay initialTime = esVuelta
        ? TimeOfDay.fromDateTime(_fechaVuelta ?? initial)
        : TimeOfDay.fromDateTime(_fechaSalida ?? initial);

    final TimeOfDay? t = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (!mounted || t == null) return;

    final DateTime dt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() {
      if (esVuelta) {
        _fechaVuelta = dt;
      } else {
        _fechaSalida = dt;
        if (_fechaVuelta != null && _fechaVuelta!.isBefore(_fechaSalida!)) {
          _fechaVuelta = null;
        }
      }
    });
  }

  PoolGiraContenidoExtra _contenidoExtraParaGuardar() {
    final p = _puntoSalida.trim();
    if (p.isNotEmpty && _contenido.direccionExacta.trim().isEmpty) {
      return _contenido.copyWith(direccionExacta: p);
    }
    return _contenido;
  }

  String _fmtFecha(DateTime? dt) {
    if (dt == null) return 'Seleccionar';
    return DateFormat('EEE d MMM, HH:mm', 'es').format(dt);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _guardar() async {
    if (_origenTown.trim().isEmpty) {
      _snack('Selecciona el pueblo de origen.');
      return;
    }
    if (_destino.trim().isEmpty) {
      _snack('Indica el destino.');
      return;
    }
    if (_puntoSalida.trim().isEmpty) {
      _snack('Indica el punto de salida.');
      return;
    }
    if (_fechaSalida == null) {
      _snack('Selecciona fecha y hora de salida.');
      return;
    }
    final precio = double.tryParse(_precioCtrl.text.trim()) ?? 0;
    final capacidad = int.tryParse(_capacidadCtrl.text.trim()) ?? 0;
    if (precio <= 0) {
      _snack('Precio por asiento inválido.');
      return;
    }
    if (capacidad <= 0) {
      _snack('Capacidad inválida.');
      return;
    }
    if (_recaudoCentral) {
      final bancoOk = _bancoNombre.trim().isNotEmpty &&
          _bancoCuenta.trim().isNotEmpty &&
          _bancoTipoCuenta.trim().isNotEmpty &&
          _bancoTitular.trim().isNotEmpty;
      if (!bancoOk) {
        _snack('Completa los datos bancarios para recaudo central.');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final tieneVuelta = _sentido == 'ida_y_vuelta';
      await PoolRepo.actualizarPoolGiraContenido(
        poolId: widget.poolId,
        contenidoExtra: _contenidoExtraParaGuardar(),
        origenTown: _origenTown.trim(),
        agenciaNombre: _agenciaNombre.trim().isEmpty ? null : _agenciaNombre.trim(),
        agenciaLogoUrl: (_pool['agenciaLogoUrl'] ?? '').toString(),
        bannerUrl: (_pool['bannerUrl'] ?? '').toString(),
        bannerVideoUrl: (_pool['bannerVideoUrl'] ?? '').toString(),
        puntoSalida: _puntoSalida.trim(),
        destino: _destino.trim(),
        servicioBadge:
            _servicioBadge.trim().isEmpty ? null : _servicioBadge.trim(),
        descripcionViaje:
            _descripcionViaje.trim().isEmpty ? null : _descripcionViaje.trim(),
        incluye: _incluye.isEmpty ? null : List<String>.from(_incluye),
        pickupPoints: _puntoSalida.trim().isEmpty
            ? null
            : <String>[_puntoSalida.trim()],
        bancoNombre: _bancoNombre.trim().isEmpty ? null : _bancoNombre.trim(),
        bancoCuenta: _bancoCuenta.trim().isEmpty ? null : _bancoCuenta.trim(),
        bancoTipoCuenta:
            _bancoTipoCuenta.trim().isEmpty ? null : _bancoTipoCuenta.trim(),
        bancoTitular:
            _bancoTitular.trim().isEmpty ? null : _bancoTitular.trim(),
        precioPorAsiento: precio,
        capacidad: capacidad,
        fechaSalida: _fechaSalida,
        fechaVuelta: tieneVuelta ? _fechaVuelta : null,
        clearFechaVuelta: !tieneVuelta,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Publicación actualizada. Los pasajeros conservan su reserva.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _sectionTitle(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: isDark ? Colors.white : const Color(0xFF101828),
        ),
      ),
    );
  }

  InputDecoration _fieldDeco(String label, {bool isDark = false}) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF8FAFC),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _puebloOrigenDropdown(bool isDark) {
    return DropdownButtonFormField<String?>(
      decoration: _fieldDeco('Pueblo (origen)', isDark: isDark),
      value: _origenTown.isEmpty ? null : _origenTown,
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Seleccionar')),
        ...PoolGiraPueblosOrigen.opciones.map(
          (p) => DropdownMenuItem<String?>(value: p, child: Text(p)),
        ),
      ],
      onChanged: (v) => setState(() => _origenTown = v ?? ''),
    );
  }

  Widget _bancoNombreDropdown(bool isDark) {
    return DropdownButtonFormField<String?>(
      decoration: _fieldDeco('Banco', isDark: isDark),
      value: _bancoNombre.isEmpty ? null : _bancoNombre,
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Seleccionar')),
        ...BancosRd.nombres.map(
          (b) => DropdownMenuItem<String?>(value: b, child: Text(b)),
        ),
      ],
      onChanged: (v) => setState(() => _bancoNombre = v ?? ''),
    );
  }

  Widget _bancoTipoCuentaDropdown(bool isDark) {
    return DropdownButtonFormField<String?>(
      decoration: _fieldDeco('Tipo de cuenta', isDark: isDark),
      value: _bancoTipoCuenta.isEmpty ? null : _bancoTipoCuenta,
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Seleccionar')),
        ...BancosRd.tiposCuentaGira.map(
          (t) => DropdownMenuItem<String?>(value: t, child: Text(t)),
        ),
      ],
      onChanged: (v) => setState(() => _bancoTipoCuenta = v ?? ''),
    );
  }

  Widget _incluyeField(bool isDark, Color accent) {
    void addIncluye(String raw) {
      final v = raw.trim();
      if (v.isEmpty || _incluye.contains(v)) return;
      setState(() {
        _incluye.add(v);
        _incluyeCtrl.clear();
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Incluye (opcional)',
          style: TextStyle(
            color: isDark ? Colors.white70 : const Color(0xFF475467),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _incluyeCtrl,
                decoration: _fieldDeco('Agregar ítem', isDark: isDark),
                onSubmitted: addIncluye,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () => addIncluye(_incluyeCtrl.text),
              icon: const Icon(Icons.add),
              color: accent,
            ),
          ],
        ),
        if (_incluye.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _incluye
                .map(
                  (e) => Chip(
                    label: Text(e),
                    onDeleted: () => setState(() => _incluye.remove(e)),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFF6FFFE9) : const Color(0xFF0D9488);
    final labelColor = isDark ? Colors.white70 : const Color(0xFF475467);
    final fieldFill = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF8FAFC);
    final inputText = isDark ? Colors.white : const Color(0xFF101828);
    final tipo = (_pool['tipo'] ?? '').toString();
    final nombreGira = (_pool['nombreGira'] ?? _servicioBadge).toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar y republicar'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _guardar,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Republicar'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Los cambios se publican al instante. Reservas y pagos aprobados se conservan. '
                      'Si cambias fecha u hora, los pasajeros reciben aviso.',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : const Color(0xFF667085),
                        height: 1.4,
                      ),
                    ),
                    if (nombreGira.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        nombreGira,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: inputText,
                        ),
                      ),
                      if (tipo.isNotEmpty)
                        Text(
                          '$tipo · $_sentido',
                          style: TextStyle(color: labelColor, fontSize: 13),
                        ),
                    ],
                    const SizedBox(height: 16),
                    _sectionTitle('Ruta y origen'),
                    _puebloOrigenDropdown(isDark),
                    const SizedBox(height: 12),
                    CampoLugarAutocomplete(
                      label: 'Punto de salida',
                      hint: 'Busca punto de encuentro/salida',
                      initialText: _puntoSalida.isEmpty ? null : _puntoSalida,
                      country: 'DO',
                      asistenteDireccionHabilitado: true,
                      onTextChanged: (v) => _puntoSalida = v.trim(),
                      onPlaceSelected: (det) =>
                          _puntoSalida = det.displayLabel.trim(),
                    ),
                    const SizedBox(height: 12),
                    CampoLugarAutocomplete(
                      label: 'Destino',
                      hint: 'Busca destino de la gira',
                      initialText: _destino.isEmpty ? null : _destino,
                      country: 'DO',
                      asistenteDireccionHabilitado: true,
                      onTextChanged: (v) => _destino = v.trim(),
                      onPlaceSelected: (det) =>
                          _destino = det.displayLabel.trim(),
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('Información del viaje'),
                    TextField(
                      controller: _agenciaCtrl,
                      decoration: _fieldDeco('Agencia (opcional)', isDark: isDark),
                      style: TextStyle(color: inputText),
                      onChanged: (v) => _agenciaNombre = v.trim(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _servicioBadgeCtrl,
                      decoration: _fieldDeco(
                        'Etiqueta corta del viaje (opcional)',
                        isDark: isDark,
                      ),
                      style: TextStyle(color: inputText),
                      onChanged: (v) => _servicioBadge = v.trim(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descripcionCtrl,
                      decoration: _fieldDeco(
                        'Detalles y recomendaciones',
                        isDark: isDark,
                      ),
                      style: TextStyle(color: inputText),
                      maxLines: 4,
                      onChanged: (v) => _descripcionViaje = v.trim(),
                    ),
                    const SizedBox(height: 12),
                    _incluyeField(isDark, accent),
                    const SizedBox(height: 20),
                    _sectionTitle('Detalle profesional'),
                    PoolGiraContenidoFormSection(
                      initial: _contenido,
                      ocultarDireccionExacta: true,
                      labelColor: labelColor,
                      fieldFill: fieldFill,
                      inputText: inputText,
                      accent: accent,
                      onChanged: (v) => _contenido = v,
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('Fechas'),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Salida', style: TextStyle(color: labelColor)),
                      subtitle: Text(
                        _fmtFecha(_fechaSalida),
                        style: TextStyle(
                          color: inputText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () => _pickFecha(esVuelta: false),
                    ),
                    if (_sentido == 'ida_y_vuelta')
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Vuelta', style: TextStyle(color: labelColor)),
                        subtitle: Text(
                          _fmtFecha(_fechaVuelta),
                          style: TextStyle(
                            color: inputText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: const Icon(Icons.calendar_today_outlined),
                        onTap: () => _pickFecha(esVuelta: true),
                      ),
                    const SizedBox(height: 20),
                    _sectionTitle('Precio y cupos'),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _precioCtrl,
                            keyboardType: TextInputType.number,
                            decoration: _fieldDeco(
                              'Precio por asiento (RD\$)',
                              isDark: isDark,
                            ),
                            style: TextStyle(color: inputText),
                            onChanged: (v) =>
                                _precio = double.tryParse(v.trim()) ?? 0,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _capacidadCtrl,
                            keyboardType: TextInputType.number,
                            decoration: _fieldDeco('Capacidad', isDark: isDark),
                            style: TextStyle(color: inputText),
                            onChanged: (v) =>
                                _capacidad = int.tryParse(v.trim()) ?? 0,
                          ),
                        ),
                      ],
                    ),
                    if (_recaudoCentral) ...[
                      const SizedBox(height: 20),
                      _sectionTitle('Datos bancarios (recaudo central)'),
                      _bancoNombreDropdown(isDark),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _bancoCuentaCtrl,
                              decoration: _fieldDeco('Número de cuenta', isDark: isDark),
                              style: TextStyle(color: inputText),
                              onChanged: (v) => _bancoCuenta = v.trim(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: _bancoTipoCuentaDropdown(isDark),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _bancoTitularCtrl,
                        decoration: _fieldDeco('Titular de la cuenta', isDark: isDark),
                        style: TextStyle(color: inputText),
                        onChanged: (v) => _bancoTitular = v.trim(),
                      ),
                    ],
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _saving ? null : _guardar,
                      icon: const Icon(Icons.publish_outlined),
                      label: const Text('Guardar cambios y volver a publicar'),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }
}
