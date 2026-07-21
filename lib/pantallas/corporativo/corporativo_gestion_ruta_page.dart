import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_plantilla_editor_page.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_ui.dart';
import 'package:flygo_nuevo/servicios/corporativo_ruta_service.dart';
import 'package:flygo_nuevo/utils/feriados_republica_dominicana.dart';
import 'package:flygo_nuevo/widgets/corporativo_ruta_titulo_numerado.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

/// Pantalla inteligente: feriado, pausa, quitar/agregar pasajero.
class CorporativoGestionRutaPage extends StatefulWidget {
  const CorporativoGestionRutaPage({
    super.key,
    required this.empresaId,
    required this.empresaNombre,
    required this.empresa,
    required this.plantilla,
    this.numeroRuta,
  });

  final String empresaId;
  final String empresaNombre;
  final CorporativoEmpresa empresa;
  final CorporativoPlantilla plantilla;
  final int? numeroRuta;

  @override
  State<CorporativoGestionRutaPage> createState() =>
      _CorporativoGestionRutaPageState();
}

class _CorporativoGestionRutaPageState extends State<CorporativoGestionRutaPage> {
  late CorporativoPlantilla _pl;
  late Set<String> _diasFeriado;
  late DateTime _mesVista;
  final _notaCtrl = TextEditingController();
  bool _guardando = false;
  String? _accionSeleccionada;

  late Map<String, String> _feriadosRd;

  @override
  void initState() {
    super.initState();
    _pl = widget.plantilla;
    _diasFeriado = {...widget.plantilla.diasPausaFeriado};
    _mesVista = DateTime(DateTime.now().year, DateTime.now().month);
    _notaCtrl.text = widget.plantilla.pausaNota;
    _feriadosRd = FeriadosRepublicaDominicana.mapaClavesConNombre();
    // Calendario va primero; otras acciones se eligen abajo.
    _accionSeleccionada = null;
  }

  void _aplicarFeriadosOficialesRd({required int anio}) {
    final oficiales = FeriadosRepublicaDominicana.oficialesDelAno(anio);
    setState(() {
      for (final h in oficiales) {
        _diasFeriado.add(FeriadosRepublicaDominicana.clave(h.fecha));
      }
      _accionSeleccionada = CorporativoPausaCausa.feriado;
      if (_notaCtrl.text.trim().isEmpty) {
        _notaCtrl.text = 'Feriados oficiales RD $anio';
      }
    });
  }

  @override
  void dispose() {
    _notaCtrl.dispose();
    super.dispose();
  }

  Future<void> _refrescarPlantilla() async {
    try {
      final snap = await CorporativoRutaService.cargarPlantilla(
        widget.empresaId,
        _pl.id,
      ).timeout(const Duration(seconds: 8));
      if (snap != null && mounted) {
        setState(() {
          _pl = snap;
          _diasFeriado = {...snap.diasPausaFeriado};
          _notaCtrl.text = snap.pausaNota;
        });
      }
    } catch (_) {
      // Best-effort; el stream de la lista ya refresca al volver.
    }
  }

  Future<void> _run(Future<void> Function() op) async {
    if (_guardando) return;
    if (_pl.id.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ruta sin ID. Guardá la plantilla primero.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _guardando = true);
    try {
      await op();
      await _refrescarPlantilla();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cambio guardado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _toggleDia(DateTime day) {
    final key = CorporativoRutaService.claveDia(day);
    setState(() {
      if (_diasFeriado.contains(key)) {
        _diasFeriado.remove(key);
      } else {
        _diasFeriado.add(key);
      }
      _accionSeleccionada = CorporativoPausaCausa.feriado;
    });
  }

  Future<void> _guardarFeriados() async {
    await _run(() => CorporativoRutaService.guardarDiasPausaFeriado(
          empresaId: widget.empresaId,
          plantillaId: _pl.id,
          dias: _diasFeriado.toList(),
          nota: _notaCtrl.text.trim(),
        ));
  }

  /// Mismo control: si la ruta está activa → pausa; si está pausada → reactiva.
  Future<void> _togglePausaTotal() async {
    final reactivar = !_pl.activa;
    await _run(() => CorporativoRutaService.setPlantillaActiva(
          empresaId: widget.empresaId,
          plantillaId: _pl.id,
          activa: reactivar,
          causa: reactivar
              ? CorporativoPausaCausa.reactivar
              : CorporativoPausaCausa.pausaTotal,
          nota: _notaCtrl.text.trim(),
        ));
    if (mounted) {
      setState(() => _accionSeleccionada = CorporativoPausaCausa.pausaTotal);
    }
  }

  Future<void> _togglePasajero(CorporativoPasajero pas) async {
    final activo = !pas.activo;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final p = context.corporativoPalette;
        return AlertDialog(
          title: Text(activo ? '¿Volver a buscarlo?' : '¿Quitar de la ruta?'),
          content: Text(
            activo
                ? '«${pas.nombre}» volverá a la ruta y el chofer lo buscará '
                    'en los días operativos.'
                : '«${pas.nombre}» dejará de ser parte de esta ruta. '
                    'Los demás pasajeros activos sí se buscan. '
                    'Ese día no se le cobra parada a él.',
            style: TextStyle(color: p.muted, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(activo ? 'Reactivar' : 'Quitar'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    await _run(() => CorporativoRutaService.setPasajeroActivoEnPlantilla(
          empresaId: widget.empresaId,
          plantillaId: _pl.id,
          pasajeros: _pl.pasajeros,
          pasajeroId: pas.id,
          activo: activo,
          nota: _notaCtrl.text.trim(),
        ));
  }

  void _abrirEditor({bool agregarPasajero = false}) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CorporativoPlantillaEditorPage(
          empresaId: widget.empresaId,
          empresaNombre: widget.empresaNombre,
          empresa: widget.empresa,
          plantilla: _pl,
          numeroRuta: widget.numeroRuta,
        ),
      ),
    ).then((_) => _refrescarPlantilla());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    final fmtMes = DateFormat('MMMM yyyy', 'es');
    final estado = CorporativoRutaService.resumenEstadoOperativo(_pl);
    final buscaHoy = CorporativoRutaService.correHoy(_pl);

    return Scaffold(
      backgroundColor: p.scaffold,
      appBar: const RaiAppBar(
        title: 'Gestión de ruta',
        centerTitle: true,
        showBackWhenCanPop: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          corporativoCard(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CorporativoRutaTituloNumerado(
                  empresaId: widget.empresaId,
                  plantilla: _pl,
                  numeroConocido: widget.numeroRuta,
                  tituloStyle: TextStyle(
                    color: p.onCard,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  estado,
                  style: TextStyle(
                    color: buscaHoy ? p.success : Colors.orange.shade800,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: buscaHoy
                        ? p.success.withValues(alpha: 0.12)
                        : Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    buscaHoy
                        ? 'Hoy SÍ se busca el grupo / pasajeros activos.'
                        : 'Hoy NO se busca el grupo (pausa, feriado o no opera).',
                    style: TextStyle(
                      color: p.onCard,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Calendario primero y siempre visible al abrir «Pausa / feriado».
          corporativoSectionTitle(context, 'Calendario RD · feriados'),
          corporativoCard(
              context,
              child: Column(
                children: [
                  Text(
                    'Tocá un día → queda con ✕ (ese día no toca). '
                    'Tocá otra vez para quitarlo. Después: Guardar días feriado. '
                    'Los días ✕ se ven también en la tarjeta de la ruta.',
                    style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _aplicarFeriadosOficialesRd(
                          anio: DateTime.now().year,
                        ),
                        icon: const Icon(Icons.flag_outlined, size: 18),
                        label: Text('Feriados RD ${DateTime.now().year}'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _aplicarFeriadosOficialesRd(
                          anio: DateTime.now().year + 1,
                        ),
                        icon: const Icon(Icons.next_plan_outlined, size: 18),
                        label: Text('Feriados RD ${DateTime.now().year + 1}'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _leyenda(Colors.deepOrange, '✕ Pausado · no toca'),
                      const SizedBox(width: 12),
                      _leyenda(Colors.red.shade300, 'Feriado oficial RD'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => setState(() {
                          _mesVista = DateTime(
                            _mesVista.year,
                            _mesVista.month - 1,
                          );
                        }),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          fmtMes.format(_mesVista),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: p.onCard,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          _mesVista = DateTime(
                            _mesVista.year,
                            _mesVista.month + 1,
                          );
                        }),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  _CalendarioFeriado(
                    mes: _mesVista,
                    seleccionados: _diasFeriado,
                    oficialesRd: _feriadosRd,
                    onToggle: _toggleDia,
                  ),
                  if (_diasFeriado.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Marcados en esta ruta: ${_diasFeriado.length} día(s)',
                        style: TextStyle(
                          color: p.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notaCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Nota / causa (opcional)',
                      hintText: 'Ej. Independencia · cierre planta',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _guardando ? null : _guardarFeriados,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: Text(
                        _guardando
                            ? 'Guardando…'
                            : 'Guardar días feriado',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          corporativoSectionTitle(context, 'Otras acciones'),
          _accionCard(
            id: CorporativoPausaCausa.pausaTotal,
            icon: _pl.activa
                ? Icons.pause_circle_outline
                : Icons.play_circle_outline,
            titulo: _pl.activa
                ? 'Pausar toda la ruta'
                : 'Reactivar toda la ruta',
            detalle: _pl.activa
                ? CorporativoPausaCausa.efectoBusqueda(
                    CorporativoPausaCausa.pausaTotal,
                  )
                : 'La ruta está pausada. Confirmá abajo para volver a operar '
                    'y que el chofer busque al grupo.',
            selectedColor: _pl.activa ? null : Colors.teal,
          ),
          _accionCard(
            id: CorporativoPausaCausa.quitarPasajero,
            icon: Icons.person_off_outlined,
            titulo: 'Quitar o reactivar un pasajero',
            detalle:
                'Si ya no es parte de la ruta, quítalo. Si vuelve, reactívalo. '
                'El resto de la ruta sigue igual.',
          ),
          _accionCard(
            id: CorporativoPausaCausa.agregarPasajero,
            icon: Icons.person_add_alt_1,
            titulo: 'Agregar otro pasajero',
            detalle:
                'Abre el editor para sumar un destino nuevo a la ruta.',
          ),
          const SizedBox(height: 12),
          if (_accionSeleccionada == CorporativoPausaCausa.pausaTotal) ...[
            corporativoCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _pl.activa
                        ? CorporativoPausaCausa.efectoBusqueda(
                            CorporativoPausaCausa.pausaTotal,
                          )
                        : 'Al reactivar, la ruta vuelve a publicarse en los días '
                            'que opera (salvo feriados marcados).',
                    style: TextStyle(color: p.muted, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _notaCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: _pl.activa
                          ? 'Causa de la pausa'
                          : 'Nota (opcional)',
                      hintText: _pl.activa
                          ? 'Ej. Planta cerrada por inventario'
                          : 'Ej. Ya operamos de nuevo',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _guardando ? null : _togglePausaTotal,
                    icon: Icon(
                      _pl.activa
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          _pl.activa ? Colors.deepOrange : Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    label: Text(
                      _pl.activa
                          ? 'Confirmar pausa total'
                          : 'Confirmar reactivar ruta',
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_accionSeleccionada == CorporativoPausaCausa.quitarPasajero) ...[
            corporativoSectionTitle(context, 'Pasajeros de la ruta'),
            corporativoCard(
              context,
              child: Column(
                children: [
                  Text(
                    'Activo = se busca. Inactivo = ya no es parte de la ruta.',
                    style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
                  ),
                  const SizedBox(height: 8),
                  ..._pl.pasajeros.map((pas) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        pas.activo ? Icons.person : Icons.person_off,
                        color: pas.activo ? p.primary : p.muted,
                      ),
                      title: Text(
                        pas.nombre,
                        style: TextStyle(
                          color: p.onCard,
                          fontWeight: FontWeight.w600,
                          decoration:
                              pas.activo ? null : TextDecoration.lineThrough,
                        ),
                      ),
                      subtitle: Text(
                        pas.activo
                            ? 'Se busca · ${pas.destinoLabel}'
                            : 'Fuera de la ruta · no se busca',
                        style: TextStyle(color: p.muted, fontSize: 12),
                      ),
                      trailing: TextButton(
                        onPressed:
                            _guardando ? null : () => _togglePasajero(pas),
                        child: Text(pas.activo ? 'Quitar' : 'Reactivar'),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
          if (_accionSeleccionada == CorporativoPausaCausa.agregarPasajero) ...[
            corporativoCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Vas a agregar otro pasajero/destino a esta ruta. '
                    'El precio se recalcula al guardar.',
                    style: TextStyle(color: p.muted, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _abrirEditor(agregarPasajero: true),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Abrir editor de ruta'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _leyenda(Color color, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(texto, style: TextStyle(fontSize: 11, color: context.corporativoPalette.muted)),
      ],
    );
  }

  Widget _accionCard({
    required String id,
    required IconData icon,
    required String titulo,
    required String detalle,
    Color? selectedColor,
  }) {
    final p = context.corporativoPalette;
    final sel = _accionSeleccionada == id;
    final accent = selectedColor ?? p.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: sel ? accent.withValues(alpha: 0.12) : p.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() {
            // Segundo toque sobre la misma acción: deselecciona (no deja “pegado”).
            _accionSeleccionada = sel ? null : id;
          }),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          color: p.onCard,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        detalle,
                        style: TextStyle(
                          color: p.muted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  sel ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: accent,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarioFeriado extends StatelessWidget {
  const _CalendarioFeriado({
    required this.mes,
    required this.seleccionados,
    required this.oficialesRd,
    required this.onToggle,
  });

  final DateTime mes;
  final Set<String> seleccionados;
  final Map<String, String> oficialesRd;
  final ValueChanged<DateTime> onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    final first = DateTime(mes.year, mes.month, 1);
    final daysInMonth = DateTime(mes.year, mes.month + 1, 0).day;
    final startWeekday = first.weekday;
    final cells = <Widget>[
      for (final d in ['L', 'M', 'X', 'J', 'V', 'S', 'D'])
        Center(
          child: Text(
            d,
            style: TextStyle(
              color: p.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      for (var i = 1; i < startWeekday; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        Builder(
          builder: (context) {
            final date = DateTime(mes.year, mes.month, day);
            final key = CorporativoRutaService.claveDia(date);
            final sel = seleccionados.contains(key);
            final oficial = oficialesRd[key];
            final esOficial = oficial != null;
            final esPasado = date.isBefore(
              DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
            );
            // Se puede quitar un ✕ aunque el día ya pasó; no marcar días pasados nuevos.
            final puedeTocar = !esPasado || sel;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: puedeTocar ? () => onToggle(date) : null,
                borderRadius: BorderRadius.circular(8),
                child: Tooltip(
                  message: sel
                      ? '✕ No toca · ${oficial ?? 'pausado en esta ruta'}'
                      : (oficial ?? (esPasado ? 'Día pasado' : 'Marcar feriado')),
                  // Evita que el primer toque en web/móvil se “coma” el tap.
                  triggerMode: TooltipTriggerMode.longPress,
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: sel
                          ? Colors.deepOrange.withValues(alpha: 0.92)
                          : (esOficial
                              ? Colors.red.withValues(alpha: 0.18)
                              : (esPasado
                                  ? p.muted.withValues(alpha: 0.08)
                                  : Colors.transparent)),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: sel
                            ? Colors.deepOrange.shade800
                            : (esOficial
                                ? Colors.red.shade300
                                : p.cardBorder.withValues(alpha: 0.5)),
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      alignment: Alignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            color: sel
                                ? Colors.white
                                : (esPasado
                                    ? p.muted
                                    : (esOficial
                                        ? Colors.red.shade800
                                        : p.onCard)),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        if (sel)
                          const Positioned(
                            top: 0,
                            right: 1,
                            child: Text(
                              '✕',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 8,
                                height: 1,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 7,
      // Un poco más alto que ancho para ✕ + número sin overflow.
      childAspectRatio: 0.85,
      children: cells,
    );
  }
}
