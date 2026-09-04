import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_ui.dart';
import 'package:flygo_nuevo/servicios/corporativo_chofer_perfil_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_ruta_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_tarifa_config_service.dart';
import 'package:flygo_nuevo/servicios/lugares_service.dart';
import 'package:flygo_nuevo/widgets/corporativo_chofer_perfil_card.dart';
import 'package:flygo_nuevo/widgets/corporativo_codigo_verificacion_card.dart';
import 'package:flygo_nuevo/utils/corporativo_ciclo_facturacion.dart';
import 'package:flygo_nuevo/utils/corporativo_recurrencia_helper.dart';
import 'package:flygo_nuevo/utils/hora_am_pm.dart';
import 'package:flygo_nuevo/utils/multiparada_ruta_helper.dart';
import 'package:flygo_nuevo/widgets/campo_lugar_autocomplete.dart';
import 'package:flygo_nuevo/utils/corporativo_ruta_enumeracion.dart';
import 'package:flygo_nuevo/widgets/corporativo_ruta_titulo_numerado.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

/// Compat: mismos helpers usados por la lista de rutas.
String corporativoFmtHoraAmPm(TimeOfDay t) => fmtHoraAmPm(t);

String corporativoFmtHoraStrAmPm(String raw) => fmtHoraStrAmPm(raw);

Future<TimeOfDay?> corporativoElegirHoraAmPm(
  BuildContext context, {
  required TimeOfDay initial,
}) =>
    elegirHoraAmPm(context, initial: initial);

class CorporativoPlantillaEditorPage extends StatefulWidget {
  const CorporativoPlantillaEditorPage({
    super.key,
    required this.empresaId,
    required this.empresaNombre,
    this.empresa,
    this.plantilla,
    this.numeroRuta,
  });

  final String empresaId;
  final String empresaNombre;
  final CorporativoEmpresa? empresa;
  final CorporativoPlantilla? plantilla;
  /// Número fijo «Ruta N» (si viene de la lista). Si es null, se calcula en vivo.
  final int? numeroRuta;

  @override
  State<CorporativoPlantillaEditorPage> createState() =>
      _CorporativoPlantillaEditorPageState();
}

class _CorporativoPlantillaEditorPageState
    extends State<CorporativoPlantillaEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _encargadoCtrl = TextEditingController();
  final _clienteCtrl = TextEditingController();
  final _referenciaCtrl = TextEditingController();
  final _origenCtrl = TextEditingController();

  double _origenLat = 0;
  double _origenLon = 0;
  bool _esFijo = true;
  bool _publicacionAuto = true;
  String _patron = CorporativoPatronRecurrencia.lunVie;
  TimeOfDay _horaGrupo = const TimeOfDay(hour: 7, minute: 0);
  final Set<int> _dias = {1, 2, 3, 4, 5};
  List<CorporativoPasajero> _pasajeros = [];
  bool _guardando = false;
  bool _eliminando = false;
  late DateTime _fechaInicioServicio;
  int _cicloFacturacionDias = CorporativoCicloFacturacion.defaultDias;
  String _formaPagoRai = 'transferencia';
  CorporativoPlantilla? _plantillaRemota;
  StreamSubscription<CorporativoPlantilla?>? _plantillaSub;

  CorporativoPlantilla? get _plantillaChofer =>
      _plantillaRemota ?? widget.plantilla;

  @override
  void initState() {
    super.initState();
    CorporativoTarifaConfigService.refresh(force: true).then((_) {
      if (mounted) setState(() {});
    });
    final pl = widget.plantilla;
    if (pl != null) {
      _nombreCtrl.text = pl.nombre;
      _encargadoCtrl.text = pl.encargadoNombre;
      _clienteCtrl.text = pl.clienteNombre;
      _referenciaCtrl.text = pl.referencia;
      _origenCtrl.text = pl.origenLabel;
      _origenLat = pl.origenLat;
      _origenLon = pl.origenLon;
      _esFijo = pl.esFijo;
      _publicacionAuto = pl.publicacionAutomatica;
      _patron = pl.patronRecurrencia;
      _pasajeros = List.from(pl.pasajeros);
      final norm = normalizarHoraHHmm(pl.horaRecogidaGrupo) ?? '07:00';
      final parts = norm.split(':');
      _horaGrupo = TimeOfDay(
        hour: int.tryParse(parts.first) ?? 7,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      );
      _dias
        ..clear()
        ..addAll(pl.diasSemana);
      if (pl.id.isNotEmpty) {
        _plantillaSub = CorporativoRutaService.streamPlantilla(
          widget.empresaId,
          pl.id,
        ).listen((remota) {
          if (!mounted || remota == null) return;
          setState(() => _plantillaRemota = remota);
        });
      }
    } else {
      _prefillDesdeEmpresa();
      unawaited(_resolverOrigenEmpresaSiFalta());
    }
    _initFechaInicioYPago();
    _asegurarCodigoEmpleados();
  }

  void _initFechaInicioYPago() {
    final emp = widget.empresa;
    if (emp != null) {
      _cicloFacturacionDias =
          CorporativoCicloFacturacion.normalizarDias(emp.facturacionCicloDias);
      var forma = emp.formaPagoRai.trim().toLowerCase();
      if (forma.isEmpty || !CorporativoCicloFacturacion.formaPagoValida(forma)) {
        forma = 'transferencia';
      }
      _formaPagoRai = forma;
    }
    final DateTime? parsed = CorporativoCicloFacturacion.parseFechaCalendario(
      widget.plantilla?.fechaInicioServicio,
    );
    final DateTime now = DateTime.now();
    _fechaInicioServicio =
        parsed ?? DateTime(now.year, now.month, now.day);
  }

  Future<void> _elegirFechaInicioServicio() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaInicioServicio,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      helpText: '¿Cuándo arranca el servicio?',
      locale: const Locale('es'),
    );
    if (picked == null || !mounted) return;
    setState(() => _fechaInicioServicio =
        DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _dialogCicloPersonalizadoDias() async {
    final p = context.corporativoPalette;
    final ctrl = TextEditingController(text: '$_cicloFacturacionDias');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.card,
        title: Text('Cada cuántos días', style: TextStyle(color: p.onCard)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Días entre liquidaciones (${CorporativoCicloFacturacion.diasMin}–${CorporativoCicloFacturacion.diasMax})',
            hintText: 'Ej. 1 = diario, 7 = semanal',
            labelStyle: TextStyle(color: p.muted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final dias = CorporativoCicloFacturacion.normalizarDias(
      int.tryParse(ctrl.text.trim()),
    );
    setState(() => _cicloFacturacionDias = dias);
  }

  void _prefillDesdeEmpresa() {
    final empresa = widget.empresa;
    if (empresa == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final perfil = empresa.perfilEncargado(uid);
    final user = FirebaseAuth.instance.currentUser;

    if (_clienteCtrl.text.isEmpty) {
      _clienteCtrl.text = empresa.nombre;
    }
    if (_referenciaCtrl.text.isEmpty && empresa.referenciaRutas.isNotEmpty) {
      _referenciaCtrl.text = empresa.referenciaRutas;
    }
    if (_encargadoCtrl.text.isEmpty) {
      final nombre = perfil?.nombre.isNotEmpty == true
          ? perfil!.nombre
          : (user?.displayName ?? '');
      _encargadoCtrl.text = nombre;
    }
    if (_origenCtrl.text.isEmpty && empresa.direccion.isNotEmpty) {
      _origenCtrl.text = empresa.direccion;
    }
  }

  /// Si el origen vino de la ficha de empresa (solo texto), obtiene GPS al cargar.
  Future<void> _resolverOrigenEmpresaSiFalta() async {
    if (_origenValido) return;
    final texto = _origenCtrl.text.trim();
    if (texto.length < 3) return;
    try {
      final det = await LugaresService.instance.detalle(
        'geocoded:${texto.toLowerCase()}',
        hintDireccion: texto,
      );
      if (det == null ||
          !MultiparadaRutaHelper.coordsValidas(det.lat, det.lon)) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _origenCtrl.text = det.displayLabel;
        _origenLat = det.lat;
        _origenLon = det.lon;
      });
      if (_pasajerosActivosCount > 0) {
        _snack(
          'Origen confirmado. Tarifa recalculada con '
          '$_pasajerosActivosCount pasajero(s) activo(s).',
        );
      }
    } catch (_) {}
  }

  Future<void> _asegurarCodigoEmpleados() async {
    try {
      await CorporativoRutaService.codigoAccesoPeriodoEmpresa(widget.empresaId);
    } catch (_) {}
  }

  @override
  void dispose() {
    _plantillaSub?.cancel();
    _nombreCtrl.dispose();
    _encargadoCtrl.dispose();
    _clienteCtrl.dispose();
    _referenciaCtrl.dispose();
    _origenCtrl.dispose();
    super.dispose();
  }

  bool get _origenValido =>
      MultiparadaRutaHelper.coordsValidas(_origenLat, _origenLon);

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool _exigirOrigenConfirmado({String? accion}) {
    if (_origenValido) return true;
    final acc = (accion ?? 'continuar').trim();
    if (_origenCtrl.text.trim().isNotEmpty) {
      _snack(
        'Seleccioná el origen tocando una sugerencia del buscador '
        'antes de $acc.',
      );
    } else {
      _snack(
        'Primero definí el origen (punto de recogida) tocando una '
        'dirección del buscador.',
      );
    }
    return false;
  }

  void _onOrigenConfirmado(DetalleLugar det) {
    setState(() {
      _origenCtrl.text = det.displayLabel;
      _origenLat = det.lat;
      _origenLon = det.lon;
    });
    if (_pasajerosActivosCount > 0) {
      _snack(
        'Origen confirmado. Tarifa recalculada con '
        '$_pasajerosActivosCount pasajero(s) activo(s).',
      );
    }
  }

  Widget _seccionInicioServicioYPago(BuildContext context) {
    final p = context.corporativoPalette;
    final fmt = DateFormat('EEE d MMM yyyy', 'es');
    final ciclo = CorporativoCicloFacturacion.normalizarDias(_cicloFacturacionDias);
    final esPreset = CorporativoCicloFacturacion.esPreset(ciclo);
    final hoy = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final iniciaFuturo = _fechaInicioServicio.isAfter(hoy);

    return corporativoCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.primary.withValues(alpha: 0.25)),
            ),
            child: Text(
              'La liquidación a RAI es de toda la empresa (un solo bauche). '
              'Aquí defines desde cuándo opera esta ruta; abajo ajustas el ciclo '
              'de cobro que comparten todas tus rutas.',
              style: TextStyle(color: p.onCard, fontSize: 12, height: 1.35),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.route_outlined, size: 18, color: p.primary),
              const SizedBox(width: 8),
              Text(
                'Esta ruta',
                style: TextStyle(
                  color: p.onCard,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Primer día en que esta línea puede publicarse y buscar pasajeros.',
            style: TextStyle(color: p.muted, fontSize: 12, height: 1.3),
          ),
          const SizedBox(height: 10),
          Text(
            'Fecha de inicio del servicio',
            style: TextStyle(
              color: p.onCard,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _elegirFechaInicioServicio,
            icon: const Icon(Icons.event_outlined),
            label: Text(fmt.format(_fechaInicioServicio)),
          ),
          if (iniciaFuturo) ...[
            const SizedBox(height: 6),
            Text(
              'Hasta esa fecha esta ruta no se publica ni opera (aunque el patrón diga L–V).',
              style: TextStyle(
                color: Colors.orange.shade700,
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Divider(color: Colors.white.withValues(alpha: 0.12)),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.business_outlined, size: 18, color: p.accent),
              const SizedBox(width: 8),
              Text(
                'Toda la empresa',
                style: TextStyle(
                  color: p.onCard,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Todos los viajes de todas las rutas suman en la misma cuenta. '
            'También puedes cambiar esto en la pestaña Cuenta.',
            style: TextStyle(color: p.muted, fontSize: 12, height: 1.3),
          ),
          const SizedBox(height: 12),
          Text(
            '¿Cada cuánto liquidan con RAI?',
            style: TextStyle(
              color: p.onCard,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final pre in CorporativoCicloFacturacion.presets)
                ChoiceChip(
                  label: Text('${pre.label} (${pre.dias} días)'),
                  selected: ciclo == pre.dias,
                  selectedColor: p.primary,
                  labelStyle: TextStyle(
                    color: ciclo == pre.dias ? Colors.white : p.onCard,
                    fontWeight: FontWeight.w700,
                  ),
                  checkmarkColor: Colors.white,
                  onSelected: (_) =>
                      setState(() => _cicloFacturacionDias = pre.dias),
                ),
              ChoiceChip(
                label: Text(
                  esPreset ? 'Personalizado…' : 'Cada $ciclo días',
                ),
                selected: !esPreset,
                onSelected: (_) => unawaited(_dialogCicloPersonalizadoDias()),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Forma de pago a RAI',
            style: TextStyle(
              color: p.onCard,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final fp in CorporativoCicloFacturacion.formasPago)
                ChoiceChip(
                  label: Text(fp.label),
                  selected: _formaPagoRai == fp.id,
                  selectedColor:
                      CorporativoCicloFacturacion.colorFormaPago(fp.id),
                  labelStyle: TextStyle(
                    color: _formaPagoRai == fp.id ? Colors.white : p.onCard,
                    fontWeight: FontWeight.w700,
                  ),
                  checkmarkColor: Colors.white,
                  onSelected: (_) => setState(() => _formaPagoRai = fp.id),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Vigente para ${widget.empresaNombre}: '
            '${CorporativoCicloFacturacion.descripcion(ciclo)} · '
            '${CorporativoCicloFacturacion.etiquetaFormaPago(_formaPagoRai)}. '
            'El cambio de ciclo aplica al próximo corte (pestaña Cuenta).',
            style: TextStyle(color: p.muted, fontSize: 11, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _seccionChofer(BuildContext context) {
    final p = context.corporativoPalette;
    final pl = _plantillaChofer;
    final plantillaId = pl?.id ?? '';
    if (plantillaId.isEmpty) {
      return corporativoCard(
        context,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.hourglass_top_rounded, color: Colors.orange),
          title: Text(
            'Conductor pendiente de asignación',
            style: TextStyle(
              color: p.onCard,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            'RAI asigna el chofer antes de publicar la ruta. '
            'Aquí verás nombre, placa, cédula y vehículo.',
            style: TextStyle(color: p.muted, fontSize: 12),
          ),
        ),
      );
    }

    final tieneChofer = pl?.choferPreferidoUid != null &&
        pl!.choferPreferidoUid!.isNotEmpty;
    if (!tieneChofer) {
      return corporativoCard(
        context,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.hourglass_top_rounded, color: Colors.orange),
          title: Text(
            'Conductor pendiente de asignación',
            style: TextStyle(
              color: p.onCard,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            'RAI asigna el chofer antes de publicar la ruta.',
            style: TextStyle(color: p.muted, fontSize: 12),
          ),
        ),
      );
    }

    final perfilGuardado = pl.choferAsignadoPerfil;
    if (perfilGuardado != null && perfilGuardado.asignado) {
      return CorporativoChoferPerfilCard(perfil: perfilGuardado);
    }

    return FutureBuilder<CorporativoChoferPerfil?>(
      future: CorporativoChoferPerfilService.cargarPorUid(
        pl.choferPreferidoUid!,
      ),
      builder: (context, perfilSnap) {
        final perfil = perfilSnap.data;
        if (perfil != null) {
          return CorporativoChoferPerfilCard(perfil: perfil);
        }
        return corporativoCard(
          context,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircularProgressIndicator(strokeWidth: 2),
            title: Text(
              pl.choferPreferidoNombre ?? 'Conductor RAI',
              style: TextStyle(
                color: p.onCard,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      },
    );
  }

  bool get _puedeCalcularTarifa =>
      CorporativoRutaService.puedeCalcularTarifa(_buildPlantilla());

  double get _tarifaAutomaticaViaje =>
      CorporativoRutaService.estimarTarifaPlantilla(
        plantilla: _buildPlantilla(),
      );

  CorporativoTarifaDesglose get _desgloseTarifa =>
      CorporativoRutaService.desgloseTarifaAutomatica(_buildPlantilla());

  double? get _precioAcordadoGuardado {
    final v = _plantillaChofer?.precioAcordado ?? widget.plantilla?.precioAcordado ?? 0;
    return v > 0 ? v : null;
  }

  int get _paradasConCoords => _pasajeros
      .where((p) =>
          p.activo && MultiparadaRutaHelper.coordsValidas(p.lat, p.lon))
      .length;

  int get _pasajerosActivosCount => _pasajeros.where((p) => p.activo).length;

  bool get _pasajerosGpsCompletos =>
      _pasajerosActivosCount > 0 &&
      _paradasConCoords == _pasajerosActivosCount;

  bool get _rutaGpsLista => _origenValido && _pasajerosGpsCompletos;

  String _fmtRd(double monto) => NumberFormat.currency(
        locale: 'es_DO',
        symbol: 'RD\$',
        decimalDigits: 0,
      ).format(monto);

  CorporativoPlantilla _buildPlantilla({String id = ''}) {
    final horaStr =
        '${_horaGrupo.hour.toString().padLeft(2, '0')}:${_horaGrupo.minute.toString().padLeft(2, '0')}';
    return CorporativoPlantilla(
      id: id.isNotEmpty ? id : (widget.plantilla?.id ?? ''),
      empresaId: widget.empresaId,
      nombre: _nombreCtrl.text.trim(),
      encargadoNombre: _encargadoCtrl.text.trim(),
      clienteNombre: _clienteCtrl.text.trim(),
      referencia: _referenciaCtrl.text.trim(),
      origenLabel: _origenCtrl.text.trim(),
      origenLat: _origenLat,
      origenLon: _origenLon,
      pasajeros: _pasajeros,
      esFijo: _esFijo,
      publicacionAutomatica: _publicacionAuto,
      horaRecogidaGrupo: horaStr,
      patronRecurrencia: _patron,
      diasSemana: _dias.toList()..sort(),
      fechaInicioServicio:
          CorporativoCicloFacturacion.claveFechaCalendario(_fechaInicioServicio),
      fechaAnclaInterdiaria: _patron == CorporativoPatronRecurrencia.interdiaria
          ? CorporativoCicloFacturacion.claveFechaCalendario(_fechaInicioServicio)
          : widget.plantilla?.fechaAnclaInterdiaria,
      choferPreferidoNombre: _plantillaChofer?.choferPreferidoNombre,
      choferPreferidoTelefono: _plantillaChofer?.choferPreferidoTelefono,
      choferPreferidoUid: _plantillaChofer?.choferPreferidoUid,
      choferAsignadoPerfil: _plantillaChofer?.choferAsignadoPerfil,
      precioAcordado: widget.plantilla?.precioAcordado ?? 0,
      ultimoViajeId: widget.plantilla?.ultimoViajeId,
      ultimaNotificacionFijaKey: widget.plantilla?.ultimaNotificacionFijaKey,
      ultimaPublicacionFijaKey: widget.plantilla?.ultimaPublicacionFijaKey,
    );
  }

  Future<void> _agregarPasajero() async {
    if (!_exigirOrigenConfirmado(accion: 'agregar pasajeros')) return;
    final p = context.corporativoPalette;
    final result = await showModalBottomSheet<CorporativoPasajero>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: p.card,
      builder: (ctx) => _PasajeroFormSheet(
        titulo: 'Agregar pasajero',
        orden: _pasajeros.fold<int>(
              0, (m, p) => p.orden > m ? p.orden : m) +
            1,
        biasLat: MultiparadaRutaHelper.coordsValidas(_origenLat, _origenLon)
            ? _origenLat
            : null,
        biasLon: MultiparadaRutaHelper.coordsValidas(_origenLat, _origenLon)
            ? _origenLon
            : null,
      ),
    );
    if (result == null) return;
    setState(() => _pasajeros.add(result));
  }

  Future<void> _editarPasajero(int index) async {
    if (index < 0 || index >= _pasajeros.length) return;
    if (!_exigirOrigenConfirmado(accion: 'editar pasajeros')) return;
    final actual = _pasajeros[index];
    final p = context.corporativoPalette;
    final result = await showModalBottomSheet<CorporativoPasajero>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: p.card,
      builder: (ctx) => _PasajeroFormSheet(
        titulo: 'Editar pasajero',
        inicial: actual,
        orden: actual.orden > 0 ? actual.orden : index + 1,
        biasLat: MultiparadaRutaHelper.coordsValidas(_origenLat, _origenLon)
            ? _origenLat
            : null,
        biasLon: MultiparadaRutaHelper.coordsValidas(_origenLat, _origenLon)
            ? _origenLon
            : null,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index < _pasajeros.length) _pasajeros[index] = result;
    });
  }

  Future<void> _abrirMaps() async {
    if (!_origenValido) {
      _snack('Primero selecciona el origen tocando una opción del buscador.');
      return;
    }
    if (_pasajeros.where((p) => p.activo).isEmpty) {
      _snack('Agrega al menos un pasajero activo para ver la ruta.');
      return;
    }
    try {
      final pl = _buildPlantilla();
      await CorporativoRutaService.abrirRutaEnMaps(pl);
    } catch (e) {
      _snack('No se pudo abrir Maps: $e');
    }
  }

  Future<void> _abrirWazeOrigen() async {
    if (!_origenValido && _origenCtrl.text.trim().length < 3) {
      _snack(
        'Escribe y selecciona el origen en el buscador antes de abrir Waze.',
      );
      return;
    }
    try {
      final pl = _buildPlantilla();
      await CorporativoRutaService.abrirRecogidaEnWaze(pl);
    } catch (e) {
      _snack('No se pudo abrir Waze: $e');
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_exigirOrigenConfirmado(accion: 'guardar la ruta')) return;

    // Laptop/web: a veces el texto queda pero las coords no (clic en sugerencia).
    if (!MultiparadaRutaHelper.coordsValidas(_origenLat, _origenLon)) {
      final texto = _origenCtrl.text.trim();
      if (texto.length >= 3) {
        _snack('Confirmando dirección de recogida…');
        final det = await LugaresService.instance.detalle(
          'geocoded:${texto.toLowerCase()}',
          hintDireccion: texto,
        );
        if (det != null &&
            MultiparadaRutaHelper.coordsValidas(det.lat, det.lon)) {
          setState(() {
            _origenCtrl.text = det.displayLabel;
            _origenLat = det.lat;
            _origenLon = det.lon;
          });
        }
      }
    }

    if (!MultiparadaRutaHelper.coordsValidas(_origenLat, _origenLon)) {
      _snack('Selecciona el origen tocando una dirección de la lista.');
      return;
    }
    if (_pasajeros.where((p) => p.activo).isEmpty) {
      _snack('Agrega al menos un pasajero activo con destino.');
      return;
    }
    final gpsErr =
        CorporativoRutaService.validarPlantillaGps(_buildPlantilla());
    if (gpsErr != null) {
      _snack(gpsErr);
      return;
    }

    setState(() => _guardando = true);
    try {
      try {
        await CorporativoRutaService.actualizarCondicionesPagoRai(
          empresaId: widget.empresaId,
          facturacionCicloDias: _cicloFacturacionDias,
          formaPagoRai: _formaPagoRai,
        );
      } catch (e) {
        debugPrint('[CORP] condiciones pago RAI no guardadas (no bloquea ruta): $e');
      }
      final codigo = await CorporativoRutaService.leerCodigoAccesoPeriodoEmpresa(
        widget.empresaId,
      );
      await CorporativoRutaService.guardarPlantilla(
        _buildPlantilla(),
        anterior: _plantillaChofer ?? widget.plantilla,
      );
      if (!mounted) return;
      final monto = _tarifaAutomaticaViaje;
      final p = context.corporativoPalette;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: p.card,
            title: Text(
              'Ruta guardada',
              style: TextStyle(color: p.onCard, fontWeight: FontWeight.w800),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  codigo.length == 6
                      ? 'Código de referencia del período (opcional para empleados):'
                      : 'La ruta quedó guardada. El chofer la verá en Mis rutas corporativas.',
                  style: TextStyle(color: p.muted, fontSize: 13, height: 1.35),
                ),
                if (codigo.length == 6) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      codigo,
                      style: TextStyle(
                        color: p.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 28,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Tarifa estimada: ${_fmtRd(monto)}',
                  style: TextStyle(
                    color: p.onCard,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Si hay chofer asignado, los cambios se sincronizan en unos segundos.',
                  style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Listo'),
              ),
            ],
          );
        },
      );
      if (!mounted) return;
      Navigator.pop(context);
    } on FirebaseException catch (e) {
      _snack(
        e.code == 'permission-denied'
            ? 'Sin permiso para guardar la ruta. Verificá que tu usuario '
                'esté como encargado de esta empresa.'
            : 'Error de Firestore: ${e.message ?? e.code}',
      );
    } catch (e, st) {
      debugPrint('[CORP] guardar ruta error: $e\n$st');
      final msg = e is String
          ? e
          : e is FirebaseException
              ? (e.code == 'permission-denied'
                  ? 'Sin permiso para guardar la ruta. Verificá que tu usuario '
                      'esté como encargado de esta empresa.'
                  : 'Error de Firestore: ${e.message ?? e.code}')
              : e is TypeError
                  ? 'Error al preparar los datos de la ruta. '
                      'Recargá la página e intentá de nuevo.'
                  : 'No se pudo guardar: $e';
      _snack(msg);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _eliminarRuta() async {
    final pl = widget.plantilla;
    if (pl == null || _eliminando) return;
    setState(() => _eliminando = true);
    try {
      final ok = await ejecutarEliminarRutaCorporativo(
        context,
        empresaId: widget.empresaId,
        plantilla: pl,
      );
      if (ok && mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _eliminando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.plantilla == null) {
      return _editorScaffold(context, numeroRuta: 0);
    }
    final conocido = widget.numeroRuta;
    if (conocido != null && conocido > 0) {
      return _editorScaffold(context, numeroRuta: conocido);
    }
    return StreamBuilder<List<CorporativoPlantilla>>(
      stream: CorporativoRutaService.streamPlantillas(widget.empresaId),
      builder: (context, snap) {
        final pl = widget.plantilla!;
        final n = CorporativoRutaEnumeracion.numeroDe(
          snap.data ?? [pl],
          pl.id,
        );
        return _editorScaffold(context, numeroRuta: n);
      },
    );
  }

  String _tituloAppBar(int numeroRuta) {
    if (widget.plantilla == null) return 'Nueva ruta';
    if (numeroRuta > 0) {
      return 'Editar ${CorporativoRutaEnumeracion.etiquetaNumero(numeroRuta)}';
    }
    return 'Editar ruta';
  }

  Widget _editorScaffold(BuildContext context, {required int numeroRuta}) {
    final p = context.corporativoPalette;
    final proxima = widget.plantilla != null
        ? CorporativoRutaService.proximaRecogida(_buildPlantilla())
        : null;

    return Scaffold(
      backgroundColor: p.scaffold,
      appBar: RaiAppBar(
        title: _tituloAppBar(numeroRuta),
        centerTitle: true,
        showBackWhenCanPop: true,
        actions: widget.plantilla != null
            ? [
                IconButton(
                  tooltip: 'Eliminar ruta',
                  onPressed: _eliminando ? null : _eliminarRuta,
                  icon: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ]
            : null,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            StreamBuilder<CorporativoEmpresa?>(
              stream: CorporativoRutaService.streamEmpresa(widget.empresaId),
              builder: (context, empSnap) {
                final codigo =
                    (empSnap.data?.periodoActual?.codigoAcceso ?? '').trim();
                if (codigo.length != 6) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CorporativoCodigoVerificacionCard(codigo: codigo),
                    const SizedBox(height: 8),
                    Text(
                      'Desde que programas la ruta, pásale este código a los empleados '
                      'que suben en esta recogida.',
                      style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
            corporativoCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.empresaNombre,
                      style: TextStyle(
                          color: p.accent, fontWeight: FontWeight.w700)),
                  if (widget.plantilla != null && numeroRuta > 0) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CorporativoRutaNumeroBadge(numero: numeroRuta),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                CorporativoRutaEnumeracion.titulo(
                                  widget.plantilla!,
                                  numeroRuta,
                                ),
                                style: TextStyle(
                                  color: p.onCard,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Este número es el que ves en Rutas (Ruta 1, Ruta 2…). '
                                'El nombre de abajo es solo una etiqueta interna.',
                                style: TextStyle(
                                  color: p.muted,
                                  fontSize: 11,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _encargadoCtrl,
                    style: TextStyle(color: p.onCard),
                    decoration: InputDecoration(
                      labelText: 'Tu nombre (encargado)',
                      labelStyle: TextStyle(color: p.muted),
                      prefixIcon: Icon(Icons.person_outline, color: p.primary),
                    ),
                    validator: (v) =>
                        (v ?? '').trim().length < 2 ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _clienteCtrl,
                    style: TextStyle(color: p.onCard),
                    decoration: InputDecoration(
                      labelText: 'Nombre cliente / empresa facturada',
                      labelStyle: TextStyle(color: p.muted),
                      prefixIcon:
                          Icon(Icons.apartment_outlined, color: p.primary),
                    ),
                    validator: (v) =>
                        (v ?? '').trim().length < 2 ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _referenciaCtrl,
                    style: TextStyle(color: p.onCard),
                    decoration: InputDecoration(
                      labelText: 'Referencia interna',
                      labelStyle: TextStyle(color: p.muted),
                      hintText: 'Ej: TURNO-AM · SECTOR-NORTE',
                      hintStyle: TextStyle(color: p.muted),
                      prefixIcon: Icon(Icons.tag_outlined, color: p.primary),
                    ),
                    validator: (v) =>
                        (v ?? '').trim().length < 2 ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _nombreCtrl,
                    style: TextStyle(color: p.onCard),
                    decoration: InputDecoration(
                      labelText: 'Etiqueta de la ruta (ej. Mañana, Tarde)',
                      labelStyle: TextStyle(color: p.muted),
                      hintText: 'Ej: Recogida empleados zona norte',
                    ),
                    validator: (v) =>
                        (v ?? '').trim().length < 2 ? 'Requerido' : null,
                  ),
                ],
              ),
            ),
            corporativoSectionTitle(
              context,
              'Paso 1 · Origen de recogida (obligatorio)',
            ),
            corporativoCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Primero definí dónde recoge el chofer. Sin origen confirmado '
                    'no se calcula la tarifa ni se pueden agregar pasajeros.',
                    style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  CampoLugarAutocomplete(
                    label: 'Dirección de recogida',
                    hint: 'Calle, avenida, sector… (como Google Maps)',
                    country: 'DO',
                    minChars: 2,
                    modoPantallaMapa: true,
                    esCampoOrigen: true,
                    asistenteDireccionHabilitado: true,
                    initialText:
                        _origenCtrl.text.isEmpty ? null : _origenCtrl.text,
                    onTextChanged: (v) {
                      _origenCtrl.text = v;
                      if (v.trim().isEmpty) {
                        setState(() {
                          _origenLat = 0;
                          _origenLon = 0;
                        });
                      }
                    },
                    onPlaceSelected: _onOrigenConfirmado,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _origenValido
                          ? p.success.withValues(alpha: 0.12)
                          : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _origenValido
                            ? p.success.withValues(alpha: 0.45)
                            : Colors.orange.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _origenValido
                              ? Icons.check_circle_outline
                              : Icons.location_off_outlined,
                          color: _origenValido ? p.success : Colors.orange,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _origenValido
                                    ? 'Origen confirmado'
                                    : 'Origen pendiente',
                                style: TextStyle(
                                  color: p.onCard,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _origenValido
                                    ? _origenCtrl.text.trim()
                                    : (_origenCtrl.text.trim().isNotEmpty
                                        ? 'Escribiste una dirección pero no la seleccionaste. '
                                            'Toca una sugerencia de la lista.'
                                        : 'Busca y selecciona el punto donde suben los empleados.'),
                                style: TextStyle(
                                  color: p.muted,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Hora de recogida en empresa',
                        style: TextStyle(color: p.onCard)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          corporativoFmtHoraAmPm(_horaGrupo),
                          style: TextStyle(
                            color: p.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 26,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _horaGrupo.period == DayPeriod.pm
                              ? 'Noche/tarde (PM) · interno ${_horaGrupo.hour.toString().padLeft(2, '0')}:${_horaGrupo.minute.toString().padLeft(2, '0')}'
                              : 'Mañana (AM) · interno ${_horaGrupo.hour.toString().padLeft(2, '0')}:${_horaGrupo.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(color: p.muted, fontSize: 12),
                        ),
                        Text(
                          'En RD: tocá AM o PM. Ej. 7:50 de la noche = 7:50 PM (no AM).',
                          style: TextStyle(color: p.muted, fontSize: 11),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    trailing: Icon(Icons.access_time_filled, color: p.primary),
                    onTap: () async {
                      final picked = await elegirHoraAmPm(
                        context,
                        initial: _horaGrupo,
                        helpText:
                            'Hora de recogida (AM = mañana · PM = tarde/noche)',
                      );
                      if (picked != null) setState(() => _horaGrupo = picked);
                    },
                  ),
                ],
              ),
            ),
            corporativoSectionTitle(
              context,
              'Paso 2 · Pasajeros y destinos',
            ),
            corporativoCard(
              context,
              child: Column(
                children: [
                  if (!_origenValido) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            color: Colors.orange.shade800,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Confirmá el origen (Paso 1) antes de agregar pasajeros. '
                              'Así la tarifa incluye todo el recorrido.',
                              style: TextStyle(
                                color: p.onCard,
                                fontSize: 12,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    'Cada pasajero: nombre, sector, referencia, destino y hora estimada de llegada.',
                    style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _pasajerosGpsCompletos
                          ? p.success.withValues(alpha: 0.12)
                          : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _pasajerosGpsCompletos
                            ? p.success.withValues(alpha: 0.45)
                            : Colors.orange.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _pasajerosGpsCompletos
                              ? Icons.check_circle_outline
                              : Icons.gps_not_fixed,
                          color: _pasajerosGpsCompletos ? p.success : Colors.orange,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _pasajerosActivosCount == 0
                                    ? 'Sin pasajeros activos'
                                    : '$_paradasConCoords / $_pasajerosActivosCount pasajeros con GPS',
                                style: TextStyle(
                                  color: p.onCard,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _pasajerosActivosCount == 0
                                    ? 'Agrega al menos un pasajero y confirma cada destino en el buscador.'
                                    : _pasajerosGpsCompletos
                                        ? 'Todos los destinos activos tienen ubicación. '
                                            'El chofer podrá navegar parada a parada.'
                                        : 'Falta GPS en ${_pasajerosActivosCount - _paradasConCoords} pasajero(s). '
                                            'Edita cada uno y toca una opción del buscador.',
                                style: TextStyle(
                                  color: p.muted,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(_pasajeros.length, (i) {
                    final pas = _pasajeros[i];
                    final gpsOk = !pas.activo ||
                        MultiparadaRutaHelper.coordsValidas(pas.lat, pas.lon);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: pas.activo ? p.primarySoft : p.muted.withValues(alpha: 0.2),
                        child: Text('${i + 1}',
                            style: TextStyle(
                                color: p.primary, fontWeight: FontWeight.w800)),
                      ),
                      title: Text(pas.nombre,
                          style: TextStyle(
                            color: p.onCard,
                            fontWeight: FontWeight.w600,
                            decoration: pas.activo
                                ? null
                                : TextDecoration.lineThrough,
                          )),
                      subtitle: Text(
                        '${pas.sector}${pas.referencia.isNotEmpty ? ' · ref ${pas.referencia}' : ''}\n'
                        '→ ${pas.destinoLabel}'
                        '${pas.horaDejada.isNotEmpty ? ' · llegada ~${corporativoFmtHoraStrAmPm(pas.horaDejada)}' : ''}'
                        '${pas.activo && !gpsOk ? '\nDestino sin GPS — edita y elige del buscador' : ''}',
                        style: TextStyle(
                          color: pas.activo && !gpsOk ? Colors.orange : p.muted,
                          fontSize: 12,
                        ),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') {
                            _editarPasajero(i);
                            return;
                          }
                          setState(() {
                            if (v == 'toggle') {
                              _pasajeros[i] =
                                  pas.copyWith(activo: !pas.activo);
                            } else if (v == 'delete') {
                              _pasajeros.removeAt(i);
                            }
                          });
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'toggle',
                            child: Text(
                                pas.activo ? 'Quitar del viaje' : 'Reactivar'),
                          ),
                          const PopupMenuItem(
                              value: 'edit', child: Text('Editar')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('Eliminar')),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  corporativoCtaButton(
                    context: context,
                    label: 'Agregar pasajero',
                    icon: Icons.person_add_alt_1,
                    onPressed: _origenValido ? _agregarPasajero : null,
                  ),
                ],
              ),
            ),
            corporativoSectionTitle(context, 'Monto por viaje'),
            corporativoCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'La factura es lo que paga la empresa a RAI. '
                    'El neto del chofer es el 90% del precio base (comisión RAI 10%). '
                    'Al guardar, el precio base queda fijo hasta que cambies origen, '
                    'destinos o pasajeros.',
                    style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  if (_puedeCalcularTarifa) ...[
                    Text(
                      'Estimado según recorrido actual',
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _fmtRd(_tarifaAutomaticaViaje),
                      style: TextStyle(
                        color: p.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 36,
                      ),
                    ),
                    Text(
                      'Factura empresa (incl. impuesto transferencia)',
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    _filaFacturacion(
                      context,
                      icon: Icons.local_taxi_outlined,
                      titulo: 'Neto chofer estimado (90%)',
                      valor: _fmtRd(_desgloseTarifa.pagoChoferRd),
                      destacado: true,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_paradasConCoords parada(s) en orden · '
                      'recorrido ~${_desgloseTarifa.kmCotizados.toStringAsFixed(1)} km '
                      '(empresa → cada bajada, tramos mínimos incluidos)',
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                    if (_precioAcordadoGuardado != null) ...[
                      const SizedBox(height: 16),
                      Divider(color: Colors.white.withValues(alpha: 0.12)),
                      const SizedBox(height: 12),
                      Text(
                        'Precio fijado en operación (guardado)',
                        style: TextStyle(
                          color: p.onCard,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Builder(
                        builder: (context) {
                          final liq = CorporativoRutaService
                              .liquidacionDesdePrecioAcordado(
                            _precioAcordadoGuardado!,
                          );
                          final facturaGuardada = liq.montoTotalFacturaRd;
                          final netoGuardado = liq.pagoChoferRd;
                          final diff = (_tarifaAutomaticaViaje - facturaGuardada)
                              .abs();
                          final desactualizado =
                              diff > 50 || diff / facturaGuardada > 0.03;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _filaFacturacion(
                                context,
                                icon: Icons.receipt_long_outlined,
                                titulo: 'Factura empresa',
                                valor: _fmtRd(facturaGuardada),
                              ),
                              const SizedBox(height: 6),
                              _filaFacturacion(
                                context,
                                icon: Icons.local_taxi_outlined,
                                titulo: 'Neto chofer (lo que ve en su app)',
                                valor: _fmtRd(netoGuardado),
                                destacado: true,
                              ),
                              if (desactualizado) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.orange.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Text(
                                    'El recorrido actual da ${_fmtRd(_tarifaAutomaticaViaje)} '
                                    'de factura, distinto al precio guardado. '
                                    'Guardá la ruta para actualizar lo que verá el chofer.',
                                    style: TextStyle(
                                      color: Colors.orange.shade800,
                                      fontSize: 12,
                                      height: 1.35,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
                  ] else
                    Text(
                      !_origenValido
                          ? 'Confirma el origen tocando una sugerencia del buscador '
                              'para calcular la tarifa.'
                          : _paradasConCoords == 0
                              ? 'Agrega al menos un pasajero con destino del buscador '
                                  'para calcular el monto del recorrido.'
                              : 'Completa origen y destinos para ver el monto.',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            corporativoSectionTitle(
              context,
              'Operación de esta ruta · Cobro de la empresa',
            ),
            _seccionInicioServicioYPago(context),
            corporativoSectionTitle(context, 'Repetición (alarma + publicación)'),
            corporativoCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Ruta fija programada',
                        style: TextStyle(
                            color: p.onCard, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'RAI publica el viaje y asigna el conductor de la plataforma.',
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                    value: _esFijo,
                    activeThumbColor: p.primary,
                    onChanged: (v) => setState(() => _esFijo = v),
                  ),
                  if (_esFijo) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Publicar automáticamente',
                          style: TextStyle(color: p.onCard)),
                      subtitle: Text(
                        '90 min antes RAI publica la ruta al conductor asignado.',
                        style: TextStyle(color: p.muted, fontSize: 12),
                      ),
                      value: _publicacionAuto,
                      onChanged: (v) => setState(() => _publicacionAuto = v),
                    ),
                    const SizedBox(height: 8),
                    Text('¿Qué días?', style: TextStyle(color: p.muted, fontSize: 12)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: CorporativoPatronRecurrencia.todos.map((pat) {
                        final sel = _patron == pat;
                        return FilterChip(
                          label: Text(CorporativoPatronRecurrencia.etiqueta(pat),
                              style: TextStyle(fontSize: 11)),
                          selected: sel,
                          onSelected: (_) => setState(() {
                            _patron = pat;
                            if (pat == CorporativoPatronRecurrencia.lunVie) {
                              _dias
                                ..clear()
                                ..addAll([1, 2, 3, 4, 5]);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    if (_patron == CorporativoPatronRecurrencia.personalizado) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: List.generate(7, (i) {
                          final d = i + 1;
                          const labels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
                          return FilterChip(
                            label: Text(labels[i]),
                            selected: _dias.contains(d),
                            onSelected: (v) => setState(() {
                              if (v) {
                                _dias.add(d);
                              } else {
                                _dias.remove(d);
                              }
                            }),
                          );
                        }),
                      ),
                    ],
                    if (proxima != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Próxima recogida: ${DateFormat('EEE d MMM · HH:mm', 'es').format(proxima)}',
                        style: TextStyle(color: p.success, fontSize: 12),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            corporativoSectionTitle(context, 'Navegación'),
            corporativoCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Verifica origen y paradas. Maps abre la ruta completa; '
                    'Waze lleva al punto de recogida.',
                    style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, box) {
                      final narrow = box.maxWidth < 360;
                      final hayActivos =
                          _pasajeros.any((pas) => pas.activo);
                      final mapsBtn = corporativoSecondaryButton(
                        context: context,
                        label: 'Maps ruta completa',
                        icon: Icons.map_outlined,
                        onPressed: _origenValido && hayActivos
                            ? _abrirMaps
                            : null,
                      );
                      final wazeBtn = corporativoSecondaryButton(
                        context: context,
                        label: 'Waze recogida',
                        icon: Icons.navigation_outlined,
                        onPressed: (_origenValido ||
                                _origenCtrl.text.trim().length >= 3)
                            ? _abrirWazeOrigen
                            : null,
                      );
                      if (narrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            mapsBtn,
                            const SizedBox(height: 8),
                            wazeBtn,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: mapsBtn),
                          const SizedBox(width: 8),
                          Expanded(child: wazeBtn),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            corporativoSectionTitle(context, 'Conductor RAI'),
            _seccionChofer(context),
            corporativoSectionTitle(context, 'Acumulado en tu cuenta'),
            corporativoCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Cada viaje de esta ruta suma en la cuenta de toda la empresa. '
                    'Al completarse, aparece en la pestaña Cuenta (liquidación compartida).',
                    style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  StreamBuilder<CorporativoEmpresa?>(
                    stream: CorporativoRutaService.streamEmpresa(widget.empresaId),
                    initialData: widget.empresa,
                    builder: (context, empSnap) {
                      final periodo = empSnap.data?.periodoActual;
                      if (periodo == null) {
                        return Text(
                          'Aún no hay viajes en el período. El primero que completes '
                          'aparecerá en Cuenta.',
                          style: TextStyle(color: p.muted, fontSize: 12),
                        );
                      }
                      final fmtFecha = DateFormat('EEE d MMM yyyy', 'es');
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _filaFacturacion(
                            context,
                            icon: Icons.receipt_long_outlined,
                            titulo: 'Acumulado del período actual',
                            valor: _fmtRd(periodo.montoTotalRd),
                            destacado: true,
                          ),
                          Text(
                            '${periodo.viajesCount} viaje(s) · '
                            'corte cada ${empSnap.data?.facturacionCicloDias ?? 15} días',
                            style: TextStyle(color: p.muted, fontSize: 11),
                          ),
                          if (periodo.fin != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Pagar a RAI antes del: ${fmtFecha.format(periodo.fin!)}',
                              style: TextStyle(
                                color: p.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_pasajerosActivosCount > 0 || !_origenValido)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(
                      _rutaGpsLista && _origenValido
                          ? Icons.verified_outlined
                          : Icons.info_outline,
                      size: 18,
                      color: _rutaGpsLista && _origenValido
                          ? p.success
                          : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        !_origenValido
                            ? 'Confirma el origen antes de guardar.'
                            : _rutaGpsLista
                                ? 'Ruta lista: origen + $_paradasConCoords parada(s) con GPS.'
                                : 'GPS incompleto: $_paradasConCoords / $_pasajerosActivosCount pasajeros.',
                        style: TextStyle(
                          color: _rutaGpsLista && _origenValido
                              ? p.success
                              : Colors.orange.shade800,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            corporativoCtaButton(
              context: context,
              label: _guardando
                  ? 'Guardando…'
                  : _puedeCalcularTarifa
                      ? 'Guardar ruta · ${_fmtRd(_tarifaAutomaticaViaje)}/viaje'
                      : 'Guardar ruta programada',
              icon: Icons.save_outlined,
              onPressed: _guardando ? null : _guardar,
            ),
            if (widget.plantilla != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _eliminando ? null : _eliminarRuta,
                icon: Icon(
                  Icons.delete_outline,
                  color: context.corporativoPalette.danger,
                ),
                label: Text(
                  _eliminando ? 'Eliminando…' : 'Eliminar ruta completa',
                  style: TextStyle(color: context.corporativoPalette.danger),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filaFacturacion(
    BuildContext context, {
    required IconData icon,
    required String titulo,
    required String valor,
    bool destacado = false,
  }) {
    final p = context.corporativoPalette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: p.primary, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: TextStyle(color: p.muted, fontSize: 11),
              ),
              const SizedBox(height: 2),
              Text(
                valor,
                style: TextStyle(
                  color: destacado ? p.primary : p.onCard,
                  fontWeight: destacado ? FontWeight.w800 : FontWeight.w600,
                  fontSize: destacado ? 18 : 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PasajeroFormSheet extends StatefulWidget {
  const _PasajeroFormSheet({
    required this.titulo,
    required this.orden,
    this.inicial,
    this.biasLat,
    this.biasLon,
  });

  final String titulo;
  final int orden;
  final CorporativoPasajero? inicial;
  final double? biasLat;
  final double? biasLon;

  @override
  State<_PasajeroFormSheet> createState() => _PasajeroFormSheetState();
}

class _PasajeroFormSheetState extends State<_PasajeroFormSheet> {
  final _nombre = TextEditingController();
  final _sector = TextEditingController();
  final _referencia = TextEditingController();
  final _destino = TextEditingController();
  TimeOfDay? _horaDejada;
  double _lat = 0;
  double _lon = 0;

  @override
  void initState() {
    super.initState();
    final i = widget.inicial;
    if (i != null) {
      _nombre.text = i.nombre;
      _sector.text = i.sector;
      _referencia.text = i.referencia;
      _destino.text = i.destinoLabel;
      _lat = i.lat;
      _lon = i.lon;
      if (i.horaDejada.isNotEmpty) {
        final p = i.horaDejada.split(':');
        _horaDejada = TimeOfDay(
          hour: int.tryParse(p.first) ?? 8,
          minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0,
        );
      }
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _sector.dispose();
    _referencia.dispose();
    _destino.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    void snack(String msg) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }

    return Material(
      color: p.card,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.titulo,
                  style: TextStyle(
                    color: p.onCard,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nombre,
                  style: TextStyle(color: p.onCard),
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Nombre pasajero *',
                    labelStyle: TextStyle(color: p.muted),
                    filled: true,
                    fillColor: p.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _sector,
                  style: TextStyle(color: p.onCard),
                  decoration: InputDecoration(
                    labelText: 'Sector / área',
                    labelStyle: TextStyle(color: p.muted),
                    filled: true,
                    fillColor: p.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _referencia,
                  style: TextStyle(color: p.onCard),
                  decoration: InputDecoration(
                    labelText: 'Referencia pasajero (opcional)',
                    labelStyle: TextStyle(color: p.muted),
                    filled: true,
                    fillColor: p.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                CampoLugarAutocomplete(
                  label: 'Destino (donde se deja)',
                  hint: 'Busca en mapa, escribe o usa RAI',
                  country: 'DO',
                  modoPantallaMapa: true,
                  asistenteDireccionHabilitado: true,
                  biasLat: widget.biasLat,
                  biasLon: widget.biasLon,
                  esCampoOrigen: false,
                  initialText: _destino.text.isEmpty ? null : _destino.text,
                  onTextChanged: (v) => _destino.text = v,
                  onPlaceSelected: (det) {
                    setState(() {
                      _destino.text = det.displayLabel;
                      _lat = det.lat;
                      _lon = det.lon;
                    });
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Hora estimada de llegada',
                    style: TextStyle(color: p.muted, fontSize: 13),
                  ),
                  subtitle: Text(
                    _horaDejada != null
                        ? corporativoFmtHoraAmPm(_horaDejada!)
                        : 'Opcional · reloj AM / PM',
                    style: TextStyle(
                      color: p.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  trailing: Icon(Icons.access_time_filled, color: p.primary),
                  onTap: () async {
                    final picked = await corporativoElegirHoraAmPm(
                      context,
                      initial:
                          _horaDejada ?? const TimeOfDay(hour: 8, minute: 0),
                    );
                    if (picked != null) setState(() => _horaDejada = picked);
                  },
                ),
                const SizedBox(height: 12),
                corporativoCtaButton(
                  context: context,
                  label: 'Listo',
                  icon: Icons.check,
                  onPressed: () {
                    if (_nombre.text.trim().length < 2) {
                      snack('Escribe el nombre del pasajero.');
                      return;
                    }
                    if (!MultiparadaRutaHelper.coordsValidas(_lat, _lon)) {
                      snack(
                        'Selecciona el destino tocando una opción del buscador.',
                      );
                      return;
                    }
                    String hora = '';
                    if (_horaDejada != null) {
                      hora =
                          '${_horaDejada!.hour.toString().padLeft(2, '0')}:${_horaDejada!.minute.toString().padLeft(2, '0')}';
                    }
                    Navigator.pop(
                      context,
                      CorporativoPasajero(
                        id: widget.inicial?.id ??
                            CorporativoRutaService.nuevoPasajeroId(),
                        nombre: _nombre.text.trim(),
                        sector: _sector.text.trim(),
                        referencia: _referencia.text.trim(),
                        destinoLabel: _destino.text.trim(),
                        lat: _lat,
                        lon: _lon,
                        horaDejada: hora,
                        orden: widget.orden,
                        activo: widget.inicial?.activo ?? true,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
