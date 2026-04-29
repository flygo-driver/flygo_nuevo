// Asistente por pasos (pantalla completa) para publicar en Bola Ahorro.
// Misma validación y resultado; usa [bola_pueblo_visual] (misma estética que el tablero).

import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_visual.dart';
import 'package:flygo_nuevo/servicios/bola_pueblo_repo.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/servicios/lugares_service.dart';
import 'package:flygo_nuevo/widgets/campo_lugar_autocomplete.dart';

class BolaPuebloCrearPublicacionResult {
  const BolaPuebloCrearPublicacionResult({
    required this.origen,
    required this.destino,
    required this.distanciaKm,
    required this.fechaSalida,
    required this.nota,
    required this.pasajeros,
    this.origenLat,
    this.origenLon,
    this.destinoLat,
    this.destinoLon,
    this.montoPropuestoRd,
  });

  final String origen;
  final String destino;
  final double distanciaKm;
  final DateTime fechaSalida;
  final String nota;
  final int pasajeros;
  final double? origenLat;
  final double? origenLon;
  final double? destinoLat;
  final double? destinoLon;
  final double? montoPropuestoRd;
}

/// Pantalla completa: Paso 1 ruta → Paso 2 personas/km → Paso 3 precio y salida.
class BolaPuebloCrearPublicacionFlow extends StatefulWidget {
  const BolaPuebloCrearPublicacionFlow({super.key, required this.tipo});

  final String tipo;

  @override
  State<BolaPuebloCrearPublicacionFlow> createState() =>
      _BolaPuebloCrearPublicacionFlowState();
}

class _BolaPuebloCrearPublicacionFlowState
    extends State<BolaPuebloCrearPublicacionFlow> {
  int _paso = 0;

  final TextEditingController _kmCtrl = TextEditingController(text: '25');
  final TextEditingController _montoCtrl = TextEditingController();
  final TextEditingController _notaCtrl = TextEditingController();
  DateTime _fecha = DateTime.now().add(const Duration(hours: 2));
  int _pasajeros = 1;
  bool _montoUserTouched = false;

  String _origenStr = '';
  String _destinoStr = '';
  DetalleLugar? _origenDet;
  DetalleLugar? _destinoDet;

  @override
  void initState() {
    super.initState();
    _syncMontoDesdeKm();
  }

  @override
  void dispose() {
    _kmCtrl.dispose();
    _montoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  void _syncMontoDesdeKm() {
    final km = double.tryParse(_kmCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    final p = BolaPuebloRepo.previewMontosPublicacion(km);
    if (p.ofertaMaxRd <= 0) return;
    if (!_montoUserTouched) {
      _montoCtrl.text = p.tarifaBaseBolaRd.toStringAsFixed(0);
    }
    setState(() {});
  }

  void _recalcKm() {
    if (_origenDet != null && _destinoDet != null) {
      final km = DistanciaService.calcularDistancia(
        _origenDet!.lat,
        _origenDet!.lon,
        _destinoDet!.lat,
        _destinoDet!.lon,
      );
      if (km > 0 && km <= 500) {
        _kmCtrl.text = km.toStringAsFixed(0);
        _syncMontoDesdeKm();
      }
    }
  }

  Future<void> _pickFechaHora() async {
    final base = Theme.of(context);
    final pickerTheme = base.copyWith(
      colorScheme: base.colorScheme.copyWith(primary: BolaPuebloTheme.accent),
    );
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      initialDate: _fecha,
      builder: (c, child) => Theme(data: pickerTheme, child: child!),
    );
    if (!mounted) return;
    if (d == null) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_fecha),
      builder: (c, child) => Theme(data: pickerTheme, child: child!),
    );
    if (!mounted) return;
    if (t == null) return;
    setState(() {
      _fecha = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
        .showSnackBar(BolaPuebloTheme.snack(context, msg, error: error));
  }

  String _fmtSalidaTs(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm ${d.year} $hh:$mi';
  }

  bool _validarPaso0() {
    if (_origenStr.trim().isEmpty || _destinoStr.trim().isEmpty) {
      _snack('Indicá origen y destino.', error: true);
      return false;
    }
    return true;
  }

  bool _validarPaso1() {
    if (!_validarPaso0()) return false;
    final km = double.tryParse(_kmCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    if (km <= 0) {
      _snack('Distancia inválida. Ajustá los km o elegí lugares con mapa.',
          error: true);
      return false;
    }
    return true;
  }

  void _publicar() {
    if (!_validarPaso1()) return;
    final km = double.tryParse(_kmCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    final p = BolaPuebloRepo.previewMontosPublicacion(km);
    final rawMonto = _montoCtrl.text.trim().replaceAll(',', '.');
    double? montoPropuesto;
    if (rawMonto.isEmpty) {
      montoPropuesto = null;
    } else {
      final v = double.tryParse(rawMonto) ?? 0;
      if (v <= 0) {
        _snack(
            'Indica un monto válido o dejá el campo vacío para usar la sugerida.',
            error: true);
        return;
      }
      if (v < p.ofertaMinRd || v > p.ofertaMaxRd) {
        _snack(
          'El monto debe estar entre RD\$${p.ofertaMinRd.toStringAsFixed(0)} y RD\$${p.ofertaMaxRd.toStringAsFixed(0)}.',
          error: true,
        );
        return;
      }
      montoPropuesto = double.parse(v.toStringAsFixed(2));
    }
    final o = _origenStr.trim();
    final d = _destinoStr.trim();
    final bool coordsCompletas = _origenDet != null && _destinoDet != null;
    Navigator.of(context).pop(
      BolaPuebloCrearPublicacionResult(
        origen: o,
        destino: d,
        distanciaKm: km,
        fechaSalida: _fecha,
        nota: _notaCtrl.text.trim(),
        pasajeros: _pasajeros.clamp(1, 8),
        origenLat: coordsCompletas ? _origenDet!.lat : null,
        origenLon: coordsCompletas ? _origenDet!.lon : null,
        destinoLat: coordsCompletas ? _destinoDet!.lat : null,
        destinoLon: coordsCompletas ? _destinoDet!.lon : null,
        montoPropuestoRd: montoPropuesto,
      ),
    );
  }

  void _atras() {
    if (_paso > 0) {
      setState(() => _paso--);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _avanzar() {
    if (_paso == 0) {
      if (!_validarPaso0()) return;
      setState(() => _paso = 1);
      return;
    }
    if (_paso == 1) {
      if (!_validarPaso1()) return;
      setState(() => _paso = 2);
    }
  }

  ({IconData icon, String title, String subtitle}) _heroForPaso() {
    switch (_paso) {
      case 0:
        return (
          icon: Icons.route_rounded,
          title: 'Tu ruta',
          subtitle:
              'Elegí origen y destino con autocompletado. En el siguiente paso definís pasajeros y distancia para calcular el rango de precios.',
        );
      case 1:
        return (
          icon: Icons.groups_rounded,
          title: 'Detalle del viaje',
          subtitle:
              'Indicá cuántas personas van y la distancia en km (se completa sola si elegís lugares con coordenadas).',
        );
      default:
        return (
          icon: Icons.payments_rounded,
          title: 'Precio y salida',
          subtitle:
              'Tu monto queda dentro del rango permitido. Elegí fecha y hora estimada; al publicar, la bola aparece en el tablero en vivo.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BolaPuebloColors.of(context);
    final tituloTipo =
        widget.tipo == 'pedido' ? 'Pedir bola' : 'Voy para — tu ruta';
    final kmPreview =
        double.tryParse(_kmCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    final prPreview = BolaPuebloRepo.previewMontosPublicacion(kmPreview);
    final montoHelper = prPreview.ofertaMaxRd <= 0
        ? 'Ajustá la distancia para ver el rango'
        : 'Entre RD\$${prPreview.ofertaMinRd.toStringAsFixed(0)} y RD\$${prPreview.ofertaMaxRd.toStringAsFixed(0)}';
    final hero = _heroForPaso();

    return Theme(
      data: BolaPuebloTheme.dialogTheme(context),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, dynamic result) {
          if (didPop) return;
          _atras();
        },
        child: Scaffold(
          backgroundColor: c.bgDeep,
          appBar: AppBar(
            backgroundColor: c.appBarScrim,
            elevation: 0,
            foregroundColor: c.onSurface,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: _paso == 0 ? 'Cerrar' : 'Atrás',
              onPressed: _atras,
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(tituloTipo, style: BolaPuebloUi.screenTitleBola(context)),
                Text(
                  'Paso ${_paso + 1} de 3',
                  style: TextStyle(
                    color: c.onMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              BolaPuebloUi.crearPublicacionStepStrip(context, _paso),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                  children: <Widget>[
                    BolaPuebloUi.crearPublicacionHero(
                      context,
                      icon: hero.icon,
                      title: hero.title,
                      subtitle: hero.subtitle,
                    ),
                    const SizedBox(height: 22),
                    if (_paso == 0) ...<Widget>[
                      BolaPuebloUi.actionPanel(
                        context,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            BolaPuebloUi.sectionLabel(
                                context, 'Origen y destino'),
                            Text(
                              'Buscá en República Dominicana. Si ves sugerencias, tocá una para fijar coordenadas.',
                              style: BolaPuebloUi.panelBody(context),
                            ),
                            const SizedBox(height: 14),
                            CampoLugarAutocomplete(
                              label: 'Estoy en',
                              hint: 'Pueblo, ciudad o dirección',
                              country: 'DO',
                              showQuickSuggestions: true,
                              showCategories: false,
                              minChars: 2,
                              fieldAccent: BolaPuebloTheme.accent,
                              fieldFill: c.surfaceRaised,
                              onPlaceSelected: (DetalleLugar det) {
                                setState(() {
                                  _origenDet = det;
                                  _origenStr = det.displayLabel;
                                  _recalcKm();
                                });
                              },
                              onTextChanged: (String t) {
                                setState(() {
                                  _origenStr = t;
                                  _origenDet = null;
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            CampoLugarAutocomplete(
                              label: 'Voy para',
                              hint: 'Pueblo, ciudad o dirección',
                              country: 'DO',
                              showQuickSuggestions: true,
                              showCategories: false,
                              minChars: 2,
                              fieldAccent: BolaPuebloTheme.accentSecondary,
                              fieldFill: c.surfaceRaised,
                              onPlaceSelected: (DetalleLugar det) {
                                setState(() {
                                  _destinoDet = det;
                                  _destinoStr = det.displayLabel;
                                  _recalcKm();
                                });
                              },
                              onTextChanged: (String t) {
                                setState(() {
                                  _destinoStr = t;
                                  _destinoDet = null;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_paso == 1) ...<Widget>[
                      BolaPuebloUi.actionPanel(
                        context,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            BolaPuebloUi.sectionLabel(context, 'Pasajeros'),
                            SegmentedButton<int>(
                              segments: const <ButtonSegment<int>>[
                                ButtonSegment<int>(value: 1, label: Text('1')),
                                ButtonSegment<int>(value: 2, label: Text('2')),
                                ButtonSegment<int>(value: 3, label: Text('3')),
                                ButtonSegment<int>(value: 4, label: Text('4')),
                              ],
                              selected: <int>{_pasajeros},
                              onSelectionChanged: (Set<int> s) {
                                if (s.isEmpty) return;
                                setState(() => _pasajeros = s.first);
                              },
                              style: SegmentedButton.styleFrom(
                                backgroundColor: c.surfaceRaised,
                                foregroundColor: c.onSurface,
                                selectedBackgroundColor: BolaPuebloTheme.accent,
                                selectedForegroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 18),
                            BolaPuebloUi.sectionLabel(
                                context, 'Distancia (km)'),
                            TextField(
                              controller: _kmCtrl,
                              style: TextStyle(color: c.onSurface),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (_) => _syncMontoDesdeKm(),
                              decoration: const InputDecoration(
                                labelText: 'Distancia estimada',
                                hintText:
                                    'Se rellena si elegís origen y destino con mapa',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_paso == 2) ...<Widget>[
                      Builder(
                        builder: (BuildContext ctx) {
                          final double km = double.tryParse(
                                  _kmCtrl.text.trim().replaceAll(',', '.')) ??
                              0;
                          final pr =
                              BolaPuebloRepo.previewMontosPublicacion(km);
                          return BolaPuebloUi.actionPanel(
                            context,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                BolaPuebloUi.sectionLabel(
                                    context, 'Rango de negociación'),
                                Text(
                                  widget.tipo == 'pedido'
                                      ? 'Los conductores ofertarán dentro de este rango. Podés ajustar tu cifra antes de publicar.'
                                      : 'Los pasajeros verán tu referencia y podrán proponer otro monto dentro del rango.',
                                  style: BolaPuebloUi.panelBody(context),
                                ),
                                if (pr.ofertaMaxRd > 0) ...<Widget>[
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: BolaPuebloTheme.accent.withValues(
                                          alpha: c.isDark ? 0.14 : 0.12),
                                      borderRadius: BorderRadius.circular(
                                          BolaPuebloUi.radiusSmall),
                                      border: Border.all(
                                        color: BolaPuebloTheme.accent
                                            .withValues(alpha: 0.38),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          'Rango RD\$${pr.ofertaMinRd.toStringAsFixed(0)} – RD\$${pr.ofertaMaxRd.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            color: c.onSurface,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Mercado ref. RD\$${pr.tarifaNormalRd.toStringAsFixed(0)} · '
                                          'Sugerida bola RD\$${pr.tarifaBaseBolaRd.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            color: c.onMuted,
                                            fontSize: 12,
                                            height: 1.35,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                BolaPuebloUi.sectionLabel(
                                    context, 'Tu cifra (RD\$)'),
                                TextField(
                                  controller: _montoCtrl,
                                  style: TextStyle(
                                    color: c.onSurface,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  onChanged: (_) {
                                    _montoUserTouched = true;
                                    setState(() {});
                                  },
                                  decoration: InputDecoration(
                                    hintText: 'Vacío = sugerida bola',
                                    helperText: montoHelper,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                BolaPuebloUi.sectionLabel(
                                    context, 'Nota opcional'),
                                TextField(
                                  controller: _notaCtrl,
                                  style: TextStyle(color: c.onSurface),
                                  decoration: const InputDecoration(
                                    hintText:
                                        'Ej.: equipaje grande, punto de encuentro…',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                BolaPuebloUi.sectionLabel(
                                    context, 'Salida estimada'),
                                Material(
                                  color: c.surfaceRaised,
                                  borderRadius: BorderRadius.circular(
                                      BolaPuebloUi.radiusButton),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(
                                        BolaPuebloUi.radiusButton),
                                    onTap: _pickFechaHora,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 16),
                                      child: Row(
                                        children: <Widget>[
                                          const Icon(Icons.event_rounded,
                                              color: BolaPuebloTheme.accent),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: <Widget>[
                                                Text(
                                                  'Tocá para cambiar',
                                                  style: TextStyle(
                                                      color: c.onMuted,
                                                      fontSize: 12),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  _fmtSalidaTs(_fecha),
                                                  style: TextStyle(
                                                    color: c.onSurface,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(Icons.edit_calendar_outlined,
                                              color: c.onMuted),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              SafeArea(
                minimum: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                child: Material(
                  elevation: 8,
                  shadowColor:
                      Colors.black.withValues(alpha: c.isDark ? 0.45 : 0.12),
                  color: c.surface.withValues(alpha: 0.98),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: _paso < 2
                          ? FilledButton(
                              style: BolaPuebloUi.filledPrimary,
                              onPressed: _avanzar,
                              child: const Text('Continuar'),
                            )
                          : FilledButton(
                              style: BolaPuebloUi.filledPrimary,
                              onPressed: _publicar,
                              child: const Text('Publicar en el tablero'),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
