// lib/pantallas/cliente/programar_viaje_multi.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/servicios/places_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/keys.dart' as app_keys; // Para API key del PlacesService

class _LugarSel {
  final String label;
  final double lat;
  final double lon;
  const _LugarSel({required this.label, required this.lat, required this.lon});
}

class ProgramarViajeMulti extends StatefulWidget {
  const ProgramarViajeMulti({super.key});

  @override
  State<ProgramarViajeMulti> createState() => _ProgramarViajeMultiState();
}

class _ProgramarViajeMultiState extends State<ProgramarViajeMulti> {
  _LugarSel? _origen;
  _LugarSel? _destino;
  final List<_LugarSel?> _paradas = <_LugarSel?>[null]; // hasta 3
  DateTime _fechaHora = DateTime.now().add(const Duration(minutes: 30));
  bool _esAhora = true;

  String _tipoVehiculo = 'Carro';
  String _metodoPago = 'Efectivo'; // 'Efectivo' | 'Transferencia'

  bool _cargando = false;

  double _distKm = 0;
  double _precio = 0;
  List<double> _segmentos = const <double>[]; // kms por tramo

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // -------- Buscador bottom sheet (Autocomplete + Details) --------
  Future<_LugarSel?> _buscarLugar(String titulo) async {
    final ctx = context;
    return showModalBottomSheet<_LugarSel?>(
      context: ctx,
      backgroundColor: const Color(0xFF0E0E0E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bc) => _BuscarLugarSheet(titulo: titulo),
    );
  }

  Future<void> _calcular() async {
    if (_origen == null || _destino == null) {
      _snack('Selecciona origen y destino.');
      return;
    }

    if (!mounted) return;
    setState(() => _cargando = true);
    try {
      final waypoints =
          _paradas.where((e) => e != null).cast<_LugarSel>().toList();

      // Suma de tramos en orden: origen → p1 → p2 → … → destino
      final List<double> segmentosKm = <double>[];
      double totalKm = 0;
      double prevLat = _origen!.lat, prevLon = _origen!.lon;

      for (final w in waypoints) {
        final tramo = DistanciaService.calcularDistancia(
            prevLat, prevLon, w.lat, w.lon);
        if (DistanciaService.tramoEsImposible(tramo)) {
          _snack(
              'Una parada está demasiado lejos del tramo anterior. Revisa direcciones.');
          return;
        }
        segmentosKm.add(tramo);
        totalKm += tramo;
        prevLat = w.lat;
        prevLon = w.lon;
      }

      final tramoFinal = DistanciaService.calcularDistancia(
          prevLat, prevLon, _destino!.lat, _destino!.lon);
      if (DistanciaService.tramoEsImposible(tramoFinal)) {
        _snack(
            'El destino está demasiado lejos del último punto. Revisa direcciones.');
        return;
      }
      segmentosKm.add(tramoFinal);
      totalKm += tramoFinal;

      if (totalKm <= 0) {
        _snack('Distancia inválida.');
        return;
      }

      final precio =
          DistanciaService.calcularPrecio(totalKm, idaYVuelta: false);

      if (!mounted) return;
      setState(() {
        _distKm = double.parse(totalKm.toStringAsFixed(2));
        _precio = precio;
        _segmentos =
            segmentosKm.map((e) => double.parse(e.toStringAsFixed(2))).toList();
      });
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _confirmar() async {
    if (_precio <= 0 || _distKm <= 0) {
      _snack('Primero calcula el precio.');
      return;
    }
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      _snack('Debes iniciar sesión.');
      return;
    }
    if (_origen == null || _destino == null) {
      _snack('Selecciona origen y destino.');
      return;
    }

    if (!mounted) return;
    setState(() => _cargando = true);
    try {
      final List<Map<String, dynamic>> waypoints = <Map<String, dynamic>>[];
      for (final p in _paradas) {
        if (p == null) continue;
        waypoints.add(<String, dynamic>{'lat': p.lat, 'lon': p.lon, 'label': p.label});
      }

      final id = await ViajesRepo.crearViajePendiente(
        uidCliente: u.uid,
        origen: _origen!.label,
        destino: _destino!.label,
        latOrigen: _origen!.lat,
        lonOrigen: _origen!.lon,
        latDestino: _destino!.lat,
        lonDestino: _destino!.lon,
        fechaHora: _esAhora
            ? DateTime.now().add(const Duration(minutes: 10))
            : _fechaHora,
        precio: _precio,
        metodoPago: _metodoPago,
        tipoVehiculo: _tipoVehiculo,
        idaYVuelta: false,
        categoria: 'multi',
        waypoints: waypoints,
        extras: <String, dynamic>{
          'paradas_count': waypoints.length,
          'segmentosKm': _segmentos, // para que el taxista vea los tramos
          'esAhora': _esAhora,
        },
        distanciaKm: _distKm,
      );

      if (!mounted) return;
      _snack('✅ Viaje creado — #${id.substring(0, 6)}');
      if (Navigator.canPop(context)) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // -------- UI --------
  @override
  Widget build(BuildContext context) {
    final f = DateFormat('EEE d MMM • HH:mm', 'es');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Programar viaje (múltiples paradas)',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.greenAccent,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _btnLugar(
                  label: 'Origen',
                  value: _origen?.label,
                  onTap: () async {
                    final sel = await _buscarLugar('Elige el origen');
                    if (!mounted || sel == null) return;
                    setState(() => _origen = sel);
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'Paradas intermedias (opcional)',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 6),
                ..._paradas.asMap().entries.map((e) {
                  final i = e.key;
                  final val = e.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Expanded(
                          child: _btnLugar(
                            label: 'Parada ${i + 1}',
                            value: val?.label,
                            onTap: () async {
                              final sel = await _buscarLugar(
                                  'Elige la parada ${i + 1}');
                              if (!mounted) return;
                              setState(() => _paradas[i] = sel);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              if (_paradas.length > 1) {
                                _paradas.removeAt(i);
                              } else {
                                _paradas[i] = null;
                              }
                            });
                          },
                          icon: const Icon(Icons.remove_circle,
                              color: Colors.white70),
                        ),
                      ],
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _paradas.length < 3
                        ? () => setState(() => _paradas.add(null))
                        : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar parada'),
                  ),
                ),
                const SizedBox(height: 6),
                _btnLugar(
                  label: 'Destino',
                  value: _destino?.label,
                  onTap: () async {
                    final sel = await _buscarLugar('Elige el destino');
                    if (!mounted || sel == null) return;
                    setState(() => _destino = sel);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Toggle Viaje ahora / Programado
                Row(
                  children: <Widget>[
                    const Text('Viaje ahora',
                        style: TextStyle(color: Colors.white70)),
                    const SizedBox(width: 8),
                    Switch(
                      value: _esAhora,
                      activeColor: Colors.greenAccent,
                      onChanged: (v) => setState(() => _esAhora = v),
                    ),
                    const Spacer(),
                    const Text('Vehículo:',
                        style: TextStyle(color: Colors.white70)),
                    const SizedBox(width: 10),
                    DropdownButton<String>(
                      value: _tipoVehiculo,
                      dropdownColor: const Color(0xFF1A1A1A),
                      underline: const SizedBox(),
                      items: const <String>[
                        'Carro',
                        'Jeepeta',
                        'Minivan',
                        'Autobús/Guagua'
                      ]
                          .map(
                            (e) => DropdownMenuItem<String>(
                              value: e,
                              child: Text(
                                e,
                                style:
                                    const TextStyle(color: Colors.white),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _tipoVehiculo = v ?? 'Carro'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (!_esAhora) ...<Widget>[
                  const Text('Fecha/Hora',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () async {
                      final ctx = context; // evita usar otro BuildContext luego
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: _fechaHora,
                        firstDate: DateTime.now(),
                        lastDate:
                            DateTime.now().add(const Duration(days: 90)),
                      );
                      if (!ctx.mounted || d == null) return;
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.fromDateTime(_fechaHora),
                      );
                      if (!ctx.mounted || t == null) return;
                      if (!mounted) return;
                      setState(() {
                        _fechaHora =
                            DateTime(d.year, d.month, d.day, t.hour, t.minute);
                      });
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: Text(f.format(_fechaHora)),
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 14,
                  runSpacing: 8,
                  children: <Widget>[
                    const Text('Método de pago:',
                        style: TextStyle(color: Colors.white70)),
                    DropdownButton<String>(
                      value: _metodoPago,
                      dropdownColor: const Color(0xFF1A1A1A),
                      underline: const SizedBox(),
                      items: const <String>['Efectivo', 'Transferencia']
                          .map(
                            (e) => DropdownMenuItem<String>(
                              value: e,
                              child: Text(
                                e,
                                style:
                                    const TextStyle(color: Colors.white),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _metodoPago = v ?? 'Efectivo'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _cargando ? null : _calcular,
              icon: const Icon(Icons.calculate),
              label: Text(_cargando ? 'Calculando…' : 'Calcular precio'),
            ),
          ),
          const SizedBox(height: 10),
          if (_precio > 0)
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Resumen de ruta',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 6),
                  ..._segmentos.asMap().entries.map((e) {
                    final i = e.key;
                    final km = e.value;
                    final title =
                        (i < (_paradas.whereType<_LugarSel>().length))
                            ? 'Tramo ${i + 1} (origen → parada ${i + 1})'
                            : 'Tramo ${i + 1} (último → destino)';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              title,
                              style:
                                  const TextStyle(color: Colors.white70),
                            ),
                          ),
                          Text(
                            '${km.toStringAsFixed(2)} km',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(color: Colors.white10),
                  Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text('Distancia total',
                            style: TextStyle(color: Colors.white70)),
                      ),
                      Text(FormatosMoneda.km(_distKm),
                          style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          'Total estimado',
                          style: TextStyle(color: Colors.greenAccent),
                        ),
                      ),
                      const Text(''),
                      Text(
                        FormatosMoneda.rd(_precio),
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  (_precio > 0 && !_cargando) ? _confirmar : null,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(_esAhora
                  ? 'Confirmar (viaje ahora)'
                  : 'Confirmar programación'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: child,
    );
  }

  Widget _btnLugar({
    required String label,
    String? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: ' ',
          filled: true,
          fillColor: Color(0xFF1A1A1A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              (value == null || value.trim().isEmpty)
                  ? 'Tocar para buscar…'
                  : value,
              style: TextStyle(
                color: (value == null || value.isEmpty)
                    ? Colors.white54
                    : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- BottomSheet de búsqueda ----------
class _BuscarLugarSheet extends StatefulWidget {
  final String titulo;
  const _BuscarLugarSheet({required this.titulo});

  @override
  State<_BuscarLugarSheet> createState() => _BuscarLugarSheetState();
}

class _BuscarLugarSheetState extends State<_BuscarLugarSheet> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _deb;
  bool _loading = false;
  List<PlacePrediction> _preds = const <PlacePrediction>[];

  // Instancia local de PlacesService (métodos de instancia)
  late final PlacesService _places =
      PlacesService(app_keys.kGooglePlacesApiKey,
          language: 'es', components: const ['country:do']);

  @override
  void dispose() {
    _deb?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      final q = v.trim();
      if (q.isEmpty) {
        setState(() => _preds = const <PlacePrediction>[]);
        return;
      }
      setState(() => _loading = true);
      try {
        final r = await _places.autocomplete(q); // instancia ✅
        if (!mounted) return;
        setState(() => _preds = r);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  Future<void> _select(PlacePrediction p) async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final det = await _places.details(p.placeId); // instancia ✅
      if (!mounted) return;

      // Manejo seguro por si details devuelve null
      if (det == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo obtener el detalle del lugar.')),
        );
        return;
      }

      Navigator.pop(
        context,
        _LugarSel(
          label: det.address,                 // address NO nulo en nuestro servicio
          lat: det.latLng.latitude,           // latLng NO nulo
          lon: det.latLng.longitude,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 14),
            Text(
              widget.titulo,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: TextField(
                controller: _ctrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Escribe dirección o lugar…',
                  filled: true,
                  fillColor: Color(0xFF1A1A1A),
                ),
                onChanged: _onChanged,
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: _preds.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: Colors.white12, height: 1),
                itemBuilder: (_, i) {
                  final p = _preds[i];
                  final full = (p.fullDescription).trim();
                  final pri = (p.primary).trim();
                  final sec = (p.secondary ?? '').trim();
                  final line = full.isNotEmpty
                      ? full
                      : [pri, sec].where((s) => s.isNotEmpty).join(', ');
                  return ListTile(
                    title: Text(
                      line.isNotEmpty ? line : 'Lugar',
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () => _select(p),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
