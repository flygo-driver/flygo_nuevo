import 'package:flutter/material.dart';
import 'package:flygo_nuevo/utils/pool_gira_contenido.dart';

/// Sección de formulario extendido para crear/editar giras por cupos.
class PoolGiraContenidoFormSection extends StatefulWidget {
  const PoolGiraContenidoFormSection({
    super.key,
    required this.initial,
    required this.labelColor,
    required this.fieldFill,
    required this.inputText,
    required this.accent,
    required this.onChanged,
    this.ocultarDireccionExacta = false,
  });

  final PoolGiraContenidoExtra initial;
  final Color labelColor;
  final Color fieldFill;
  final Color inputText;
  final Color accent;
  final ValueChanged<PoolGiraContenidoExtra> onChanged;
  /// En crear gira el punto de salida ya está arriba — evita duplicar campo.
  final bool ocultarDireccionExacta;

  @override
  State<PoolGiraContenidoFormSection> createState() =>
      _PoolGiraContenidoFormSectionState();
}

class _PoolGiraContenidoFormSectionState
    extends State<PoolGiraContenidoFormSection> {
  late final TextEditingController _nombreGiraCtrl;
  late final TextEditingController _esloganCtrl;
  late final TextEditingController _provinciaCtrl;
  late final TextEditingController _municipioCtrl;
  late final TextEditingController _duracionCtrl;
  late final TextEditingController _direccionCtrl;
  late final TextEditingController _referenciaCtrl;
  late final TextEditingController _noIncluyeCtrl;
  late final TextEditingController _queLlevarCtrl;
  late final TextEditingController _reglasCtrl;
  late final TextEditingController _observacionesCtrl;
  late final TextEditingController _edadMinCtrl;
  late final TextEditingController _maxCompraCtrl;

  late bool _ninosPermitidos;
  late bool _mascotasPermitidas;
  final List<PoolGiraItinerarioItem> _itinerario = <PoolGiraItinerarioItem>[];
  final List<PoolGiraPuntoRecogida> _puntosRecogida = <PoolGiraPuntoRecogida>[];

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _nombreGiraCtrl = TextEditingController(text: i.nombreGira);
    _esloganCtrl = TextEditingController(text: i.eslogan);
    _provinciaCtrl = TextEditingController(text: i.provincia);
    _municipioCtrl = TextEditingController(text: i.municipio);
    _duracionCtrl = TextEditingController(text: i.duracionTexto);
    _direccionCtrl = TextEditingController(text: i.direccionExacta);
    _referenciaCtrl = TextEditingController(text: i.referenciaLugar);
    _noIncluyeCtrl = TextEditingController(text: i.noIncluye);
    _queLlevarCtrl = TextEditingController(text: i.queDebeLlevar);
    _reglasCtrl = TextEditingController(text: i.reglas);
    _observacionesCtrl = TextEditingController(text: i.observaciones);
    _edadMinCtrl = TextEditingController(
      text: i.edadMinima != null ? '${i.edadMinima}' : '',
    );
    _maxCompraCtrl = TextEditingController(text: '${i.maxAsientosPorCompra}');
    _ninosPermitidos = i.ninosPermitidos;
    _mascotasPermitidas = i.mascotasPermitidas;
    _itinerario.addAll(i.itinerario);
    _puntosRecogida.addAll(i.puntosRecogida);
  }

  @override
  void dispose() {
    _nombreGiraCtrl.dispose();
    _esloganCtrl.dispose();
    _provinciaCtrl.dispose();
    _municipioCtrl.dispose();
    _duracionCtrl.dispose();
    _direccionCtrl.dispose();
    _referenciaCtrl.dispose();
    _noIncluyeCtrl.dispose();
    _queLlevarCtrl.dispose();
    _reglasCtrl.dispose();
    _observacionesCtrl.dispose();
    _edadMinCtrl.dispose();
    _maxCompraCtrl.dispose();
    super.dispose();
  }

  PoolGiraContenidoExtra _buildExtra() {
    final edad = int.tryParse(_edadMinCtrl.text.trim());
    final maxC = int.tryParse(_maxCompraCtrl.text.trim()) ?? 10;
    return PoolGiraContenidoExtra(
      nombreGira: _nombreGiraCtrl.text,
      eslogan: _esloganCtrl.text,
      provincia: _provinciaCtrl.text,
      municipio: _municipioCtrl.text,
      duracionTexto: _duracionCtrl.text,
      direccionExacta: _direccionCtrl.text,
      referenciaLugar: _referenciaCtrl.text,
      noIncluye: _noIncluyeCtrl.text,
      queDebeLlevar: _queLlevarCtrl.text,
      reglas: _reglasCtrl.text,
      observaciones: _observacionesCtrl.text,
      edadMinima: edad,
      ninosPermitidos: _ninosPermitidos,
      mascotasPermitidas: _mascotasPermitidas,
      maxAsientosPorCompra: maxC.clamp(1, 99),
      itinerario: List<PoolGiraItinerarioItem>.from(_itinerario),
      puntosRecogida: List<PoolGiraPuntoRecogida>.from(_puntosRecogida),
    );
  }

  void _emit() => widget.onChanged(_buildExtra());

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: widget.labelColor),
        filled: true,
        fillColor: widget.fieldFill,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );

  Widget _area(String label, TextEditingController c, {int lines = 3}) {
    return TextFormField(
      controller: c,
      maxLines: lines,
      style: TextStyle(color: widget.inputText),
      decoration: _dec(label),
      onChanged: (_) => _emit(),
    );
  }

  void _addItinerarioRow() {
    setState(() {
      _itinerario.add(const PoolGiraItinerarioItem(hora: '', actividad: ''));
    });
    _emit();
  }

  void _addPuntoRecogidaRow() {
    setState(() {
      _puntosRecogida.add(const PoolGiraPuntoRecogida(hora: '', lugar: ''));
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _nombreGiraCtrl,
          style: TextStyle(color: widget.inputText),
          decoration: _dec('Nombre de la gira', hint: 'Ej: Saona VIP todo incluido'),
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _esloganCtrl,
          style: TextStyle(color: widget.inputText),
          decoration: _dec('Eslogan (opcional)'),
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _provinciaCtrl,
                style: TextStyle(color: widget.inputText),
                decoration: _dec('Provincia'),
                onChanged: (_) => _emit(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _municipioCtrl,
                style: TextStyle(color: widget.inputText),
                decoration: _dec('Municipio'),
                onChanged: (_) => _emit(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _duracionCtrl,
          style: TextStyle(color: widget.inputText),
          decoration: _dec('Duración', hint: 'Ej: Día completo, 8 horas'),
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 10),
        if (!widget.ocultarDireccionExacta) ...[
          TextFormField(
            controller: _direccionCtrl,
            style: TextStyle(color: widget.inputText),
            decoration: _dec('Dirección exacta del punto de encuentro'),
            onChanged: (_) => _emit(),
          ),
          const SizedBox(height: 10),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'El punto de salida lo defines arriba en «Datos del viaje».',
              style: TextStyle(
                color: widget.labelColor,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        TextFormField(
          controller: _referenciaCtrl,
          style: TextStyle(color: widget.inputText),
          decoration: _dec('Referencia del lugar'),
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _maxCompraCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(color: widget.inputText),
                decoration: _dec('Máx. asientos por compra'),
                onChanged: (_) => _emit(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _edadMinCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(color: widget.inputText),
                decoration: _dec('Edad mínima (opc.)'),
                onChanged: (_) => _emit(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Niños permitidos',
              style: TextStyle(color: widget.inputText, fontSize: 14)),
          value: _ninosPermitidos,
          activeThumbColor: widget.accent,
          onChanged: (v) {
            setState(() => _ninosPermitidos = v);
            _emit();
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Mascotas permitidas',
              style: TextStyle(color: widget.inputText, fontSize: 14)),
          value: _mascotasPermitidas,
          activeThumbColor: widget.accent,
          onChanged: (v) {
            setState(() => _mascotasPermitidas = v);
            _emit();
          },
        ),
        const SizedBox(height: 8),
        _area('Lo que NO incluye', _noIncluyeCtrl),
        const SizedBox(height: 10),
        _area('Qué debe llevar el pasajero', _queLlevarCtrl),
        const SizedBox(height: 10),
        _area('Reglas de la gira', _reglasCtrl),
        const SizedBox(height: 10),
        _area('Observaciones importantes', _observacionesCtrl, lines: 2),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.alt_route, color: widget.accent, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Recorrido de recogida',
                style: TextStyle(
                  color: widget.inputText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _addPuntoRecogidaRow,
              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
              label: const Text('Agregar parada'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            'Paradas y hora por donde pasas a buscar clientes antes de salir '
            'al destino. Ej: 4:30 AM Lucerna · 6:00 AM Megacentro · 8:00 AM Sambil.',
            style: TextStyle(
              color: widget.labelColor,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
        for (var i = 0; i < _puntosRecogida.length; i++) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 88,
                child: TextFormField(
                  initialValue: _puntosRecogida[i].hora,
                  style: TextStyle(color: widget.inputText, fontSize: 13),
                  decoration: _dec('Hora', hint: '4:30 AM'),
                  onChanged: (v) {
                    _puntosRecogida[i] = PoolGiraPuntoRecogida(
                      hora: v,
                      lugar: _puntosRecogida[i].lugar,
                    );
                    _emit();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: _puntosRecogida[i].lugar,
                  style: TextStyle(color: widget.inputText, fontSize: 13),
                  decoration: _dec('Lugar de recogida', hint: 'Ej: Lucerna'),
                  onChanged: (v) {
                    _puntosRecogida[i] = PoolGiraPuntoRecogida(
                      hora: _puntosRecogida[i].hora,
                      lugar: v,
                    );
                    _emit();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Quitar',
                onPressed: () {
                  setState(() => _puntosRecogida.removeAt(i));
                  _emit();
                },
                icon: Icon(Icons.close, color: widget.labelColor, size: 20),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.schedule, color: widget.accent, size: 18),
            const SizedBox(width: 6),
            Text(
              'Itinerario',
              style: TextStyle(
                color: widget.inputText,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _addItinerarioRow,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Agregar horario'),
            ),
          ],
        ),
        for (var i = 0; i < _itinerario.length; i++) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 88,
                child: TextFormField(
                  initialValue: _itinerario[i].hora,
                  style: TextStyle(color: widget.inputText, fontSize: 13),
                  decoration: _dec('Hora', hint: '07:00 AM'),
                  onChanged: (v) {
                    _itinerario[i] = PoolGiraItinerarioItem(
                      hora: v,
                      actividad: _itinerario[i].actividad,
                    );
                    _emit();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: _itinerario[i].actividad,
                  style: TextStyle(color: widget.inputText, fontSize: 13),
                  decoration: _dec('Actividad'),
                  onChanged: (v) {
                    _itinerario[i] = PoolGiraItinerarioItem(
                      hora: _itinerario[i].hora,
                      actividad: v,
                    );
                    _emit();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Quitar',
                onPressed: () {
                  setState(() => _itinerario.removeAt(i));
                  _emit();
                },
                icon: Icon(Icons.close, color: widget.labelColor, size: 20),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
