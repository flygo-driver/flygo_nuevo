// lib/pantallas/taxista/pools_taxista_crear.dart
import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:flygo_nuevo/servicios/pool_repo.dart';
import 'package:flygo_nuevo/widgets/campo_lugar_autocomplete.dart';
import 'package:flygo_nuevo/pantallas/taxista/pools_taxista_lista.dart';
import 'package:url_launcher/url_launcher.dart';

extension _PoolsTaxistaCrearPaletteX on BuildContext {
  ({
    bool isDark,
    Color scaffoldBg,
    Color appBarBg,
    Color foreground,
    Color accent,
    Color accentSoft,
    Color fieldFill,
    Color inputText,
    Color subtitleMuted,
    Color labelMuted,
    Color cardGradA,
    Color cardGradB,
    Color cardBorder,
    Color chipBg,
    Color chipSelectedTint,
    Color chipListTint,
    Color tealBtnBg,
    Color tealBtnFg,
    Color placeholderBox,
    Color faintIcon,
  }) get _poolsCrearPalette {
    final isDark = Theme.of(this).brightness == Brightness.dark;
    return (
      isDark: isDark,
      scaffoldBg: isDark ? const Color(0xFF0B1020) : const Color(0xFFF1F5F9),
      appBarBg: isDark ? const Color(0xFF0B1020) : Colors.white,
      foreground: isDark ? Colors.white : const Color(0xFF101828),
      accent: isDark ? const Color(0xFF6FFFE9) : const Color(0xFF0D9488),
      accentSoft: isDark ? const Color(0xFFBEE9E8) : const Color(0xFF0F766E),
      fieldFill: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF8FAFC),
      inputText: isDark ? Colors.white : const Color(0xFF101828),
      subtitleMuted: isDark ? Colors.white60 : const Color(0xFF667085),
      labelMuted: isDark ? Colors.white70 : const Color(0xFF475467),
      cardGradA: isDark ? const Color(0xFF1C2541) : const Color(0xFFE0F2FE),
      cardGradB: isDark ? const Color(0xFF3A506B) : const Color(0xFFF0F9FF),
      cardBorder: isDark
          ? const Color(0xFF5BC0BE).withValues(alpha: 0.35)
          : const Color(0xFF0D9488).withValues(alpha: 0.35),
      chipBg: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
      chipSelectedTint: isDark
          ? const Color(0xFF6FFFE9).withValues(alpha: 0.25)
          : const Color(0xFF0D9488).withValues(alpha: 0.22),
      chipListTint: const Color(0xFF5BC0BE).withValues(alpha: 0.25),
      tealBtnBg: const Color(0xFF5BC0BE),
      tealBtnFg: isDark ? const Color(0xFF0B1020) : const Color(0xFF042F2E),
      placeholderBox: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFE2E8F0),
      faintIcon: isDark ? Colors.white38 : const Color(0xFF98A2B3),
    );
  }
}

class PoolsTaxistaCrear extends StatefulWidget {
  const PoolsTaxistaCrear({super.key});

  @override
  State<PoolsTaxistaCrear> createState() => _PoolsTaxistaCrearState();
}

class _PoolsTaxistaCrearState extends State<PoolsTaxistaCrear> {
  final _form = GlobalKey<FormState>();
  static const List<String> _tiposSugeridos = <String>[
    'consular',
    'tour',
    'excursion',
    'gira',
    'tour cibaeño',
  ];
  static const List<String> _incluyeSugeridos = <String>[
    'Buggy',
    'Motor',
    'Bote',
    'Comida',
    'Guia',
    'Snorkel',
    'Fotos',
  ];

  // Estado del formulario (con defaults sensatos)
  String _tipo = 'tour';
  String _sentido = 'ida';
  String _origenTown = 'Higüey';
  String _destino = 'Consulado SD';
  String? _destinoPlaceId;
  double? _destinoLat;
  double? _destinoLon;
  String _puntoSalida = '';
  double? _puntoSalidaLat;
  double? _puntoSalidaLon;
  final List<String> _paradas = <String>[];
  String _paradaDraft = '';
  int _paradaInputVersion = 0;
  final List<String> _incluye = <String>[];
  final TextEditingController _incluyeCtrl = TextEditingController();
  String _agenciaNombre = '';
  String _agenciaLogoUrl = '';
  String _bannerUrl = '';
  String _bannerVideoUrl = '';
  String _choferTelefono = '';
  String _choferWhatsApp = '';
  String _bancoNombre = '';
  String _bancoCuenta = '';
  String _bancoTipoCuenta = '';
  String _bancoTitular = '';
  String _servicioBadge = '';
  String _descripcionViaje = '';

  DateTime _fecha = DateTime.now().add(const Duration(days: 1));
  DateTime? _fechaVuelta;

  int _capacidad = 15;
  int _minConf = 8;

  double _precio = 1000;
  double _deposit = 0.30; // 0..1
  double _fee = 0.10; // 0..1 (giras: comision empresa 10%)

  final _agenciaCtrl = TextEditingController();
  final _tipoCtrl = TextEditingController(text: 'tour');
  final _telCtrl = TextEditingController();
  final _waCtrl = TextEditingController();
  final _bancoNombreCtrl = TextEditingController();
  final _bancoCuentaCtrl = TextEditingController();
  final _bancoTipoCtrl = TextEditingController();
  final _bancoTitularCtrl = TextEditingController();
  final _servicioBadgeCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _picker = ImagePicker();
  final FirebaseStorage _storage =
      FirebaseStorage.instanceFor(bucket: 'gs://flygo-rd.firebasestorage.app');
  bool _subiendoLogo = false;
  bool _subiendoBanner = false;
  bool _subiendoBannerVideo = false;

  bool _loading = false;

  @override
  void dispose() {
    _agenciaCtrl.dispose();
    _tipoCtrl.dispose();
    _telCtrl.dispose();
    _waCtrl.dispose();
    _bancoNombreCtrl.dispose();
    _bancoCuentaCtrl.dispose();
    _bancoTipoCtrl.dispose();
    _bancoTitularCtrl.dispose();
    _servicioBadgeCtrl.dispose();
    _descripcionCtrl.dispose();
    _incluyeCtrl.dispose();
    super.dispose();
  }

  String _tipoCanonico(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.contains('excurs')) return 'excursion';
    if (t.contains('consul')) return 'consular';
    if (t.contains('tour') || t.contains('gira')) return 'tour';
    return t.isEmpty ? 'tour' : t;
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
    if (_puntoSalida.trim().isEmpty) {
      _snack('Selecciona un punto de salida válido en el buscador.');
      return;
    }
    if (_destino.trim().isEmpty) {
      _snack('Selecciona un destino válido en el buscador.');
      return;
    }
    if ((_tipoCanonico(_tipo) == 'tour' || _tipoCanonico(_tipo) == 'excursion') &&
        _paradas.isEmpty &&
        _puntoSalida.trim().isEmpty) {
      _snack('Agrega al menos una parada para el tour/excursión.');
      return;
    }
    if (_cleanPhone(_choferTelefono).isEmpty && _cleanPhone(_choferWhatsApp).isEmpty) {
      _snack('Agrega al menos teléfono o WhatsApp del chofer.');
      return;
    }
    final bancoCompleto = _bancoNombre.trim().isNotEmpty &&
        _bancoCuenta.trim().isNotEmpty &&
        _bancoTipoCuenta.trim().isNotEmpty &&
        _bancoTitular.trim().isNotEmpty;
    if (!bancoCompleto) {
      _snack('Completa los datos bancarios para depósitos.');
      return;
    }

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
    final double fee = 0.10;

    setState(() => _loading = true);
    try {
      final List<String> pickups = <String>[];
      final String p = _puntoSalida.trim();
      if (p.isNotEmpty) pickups.add(p);
      for (final s in _paradas) {
        final t = s.trim();
        if (t.isEmpty) continue;
        if (!pickups.contains(t)) pickups.add(t);
      }

      final tipoInput = _tipo.trim();
      final tipoCanon = _tipoCanonico(tipoInput);
      final String id = await PoolRepo.crearPool(
        tipo: tipoCanon,
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
        agenciaNombre: _agenciaNombre.trim().isEmpty ? null : _agenciaNombre.trim(),
        agenciaLogoUrl: _agenciaLogoUrl.trim().isEmpty ? null : _agenciaLogoUrl.trim(),
        bannerUrl: _bannerUrl.trim().isEmpty ? null : _bannerUrl.trim(),
        bannerVideoUrl:
            _bannerVideoUrl.trim().isEmpty ? null : _bannerVideoUrl.trim(),
        puntoSalida: _puntoSalida.trim(),
        puntoSalidaLat: _puntoSalidaLat,
        puntoSalidaLon: _puntoSalidaLon,
        destinoPlaceId: _destinoPlaceId,
        destinoLat: _destinoLat,
        destinoLon: _destinoLon,
        choferTelefono:
            _choferTelefono.trim().isEmpty ? null : _choferTelefono.trim(),
        choferWhatsApp:
            _choferWhatsApp.trim().isEmpty ? null : _choferWhatsApp.trim(),
        bancoNombre: _bancoNombre.trim().isEmpty ? null : _bancoNombre.trim(),
        bancoCuenta: _bancoCuenta.trim().isEmpty ? null : _bancoCuenta.trim(),
        bancoTipoCuenta:
            _bancoTipoCuenta.trim().isEmpty ? null : _bancoTipoCuenta.trim(),
        bancoTitular:
            _bancoTitular.trim().isEmpty ? null : _bancoTitular.trim(),
        servicioBadge: _servicioBadge.trim().isNotEmpty
            ? _servicioBadge.trim()
            : tipoInput,
        tipoPersonalizado: tipoInput,
        incluye: _incluye,
        descripcionViaje:
            _descripcionViaje.trim().isEmpty ? null : _descripcionViaje.trim(),
      );

      if (!mounted) return;
      _snack('✅ Viaje creado (#$id)');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PoolsTaxistaLista()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) _snack('❌ ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateFormat f = DateFormat('EEE d MMM - HH:mm', 'es');
    final p = context._poolsCrearPalette;

    return Scaffold(
      backgroundColor: p.scaffoldBg,
      appBar: AppBar(
        backgroundColor: p.appBarBg,
        foregroundColor: p.foreground,
        elevation: p.isDark ? 0 : 0.5,
        title: Text(
          'Crear viaje por cupos 🏝️',
          style: TextStyle(
            color: p.accent,
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
            _heroBanner(),
            const SizedBox(height: 12),
            _sectionTitle('Datos del viaje', Icons.luggage_outlined),
            _card(
              child: Wrap(
                runSpacing: 12,
                children: [
                  _row(
                    left: _tipoField(),
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
                    right: _textFieldCtrl(
                      controller: _agenciaCtrl,
                      label: 'Agencia (opcional)',
                      hint: 'Tours RD, Mi Agencia…',
                      onChanged: (v) => _agenciaNombre = v.trim(),
                    ),
                  ),
                  _textFieldCtrl(
                    controller: _servicioBadgeCtrl,
                    label: 'Etiqueta corta del viaje (opcional)',
                    hint: 'Ej: VIP, Gira Especial, Promo Semana Santa...',
                    onChanged: (v) => _servicioBadge = v.trim(),
                  ),
                  _textFieldCtrl(
                    controller: _descripcionCtrl,
                    label: 'Detalles y recomendaciones del viaje',
                    hint:
                        'Ej: actividades, comidas, entradas, transporte, que debe llevar el cliente, recomendaciones...',
                    maxLines: 4,
                    onChanged: (v) => _descripcionViaje = v.trim(),
                  ),
                  _incluyeField(),
                  CampoLugarAutocomplete(
                    label: 'Punto de salida',
                    hint: 'Busca punto de encuentro/salida',
                    initialText: _puntoSalida.isEmpty ? null : _puntoSalida,
                    country: 'DO',
                    onTextChanged: (v) {
                      _puntoSalida = v.trim();
                    },
                    onPlaceSelected: (det) {
                      _puntoSalida = det.displayLabel.trim();
                      _puntoSalidaLat = det.lat;
                      _puntoSalidaLon = det.lon;
                    },
                  ),
                  const SizedBox(height: 8),
                  CampoLugarAutocomplete(
                    label: 'Destino',
                    hint: 'Busca destino',
                    initialText: _destino,
                    country: 'DO',
                    onTextChanged: (v) => _destino = v.trim(),
                    onPlaceSelected: (det) {
                      _destino = det.displayLabel.trim();
                      _destinoPlaceId = det.placeId;
                      _destinoLat = det.lat;
                      _destinoLon = det.lon;
                    },
                  ),
                  const SizedBox(height: 8),
                  if (_tipoCanonico(_tipo) == 'tour' ||
                      _tipoCanonico(_tipo) == 'excursion') ...[
                    _paradasEditor(),
                    const SizedBox(height: 8),
                  ],
                  _agenciaLogoPicker(),
                  const SizedBox(height: 8),
                  _bannerPicker(),
                  const SizedBox(height: 8),
                  _row(
                    left: _textFieldCtrl(
                      controller: _telCtrl,
                      label: 'Telefono chofer',
                      hint: '8091234567',
                      onChanged: (v) => _choferTelefono = v.trim(),
                    ),
                    right: _textFieldCtrl(
                      controller: _waCtrl,
                      label: 'WhatsApp chofer',
                      hint: '8091234567',
                      onChanged: (v) => _choferWhatsApp = v.trim(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _abrirLlamadaChofer(),
                        icon: const Icon(Icons.call),
                        label: const Text('Tel chofer'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _abrirWhatsAppChofer(),
                        icon: const Icon(Icons.chat),
                        label: const Text('WhatsApp'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _sectionTitle('Capacidad y finanzas', Icons.account_balance_wallet_outlined),
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
                  const SizedBox(height: 8),
                  _textFieldCtrl(
                    controller: _bancoNombreCtrl,
                    label: 'Banco para deposito',
                    hint: 'BANRESERVAS',
                    onChanged: (v) => _bancoNombre = v.trim(),
                  ),
                  const SizedBox(height: 8),
                  _row(
                    left: _textFieldCtrl(
                      controller: _bancoCuentaCtrl,
                      label: 'Cuenta',
                      hint: '960-1234567-8',
                      onChanged: (v) => _bancoCuenta = v.trim(),
                    ),
                    right: _textFieldCtrl(
                      controller: _bancoTipoCtrl,
                      label: 'Tipo cuenta',
                      hint: 'Corriente/Ahorros',
                      onChanged: (v) => _bancoTipoCuenta = v.trim(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _textFieldCtrl(
                    controller: _bancoTitularCtrl,
                    label: 'Titular cuenta',
                    hint: 'Nombre del titular',
                    onChanged: (v) => _bancoTitular = v.trim(),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC857),
                  foregroundColor: const Color(0xFF1C1F2A),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /* ======= UI helpers ======= */

  Widget _card({required Widget child}) {
    final p = context._poolsCrearPalette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [p.cardGradA, p.cardGradB],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.isDark ? 0.2 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _heroBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF8A5B), Color(0xFFFFC75F), Color(0xFF00C9A7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(Icons.beach_access, color: Colors.white, size: 30),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Crea una gira inolvidable: define ruta, paradas y cupos.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, IconData icon) {
    final p = context._poolsCrearPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: p.accent, size: 18),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: p.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
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
    final p = context._poolsCrearPalette;
    return InputDecorator(
      decoration: InputDecoration(
        filled: true,
        fillColor: p.fieldFill,
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        labelStyle: TextStyle(color: p.labelMuted),
      ).copyWith(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          dropdownColor: p.fieldFill,
          style: TextStyle(color: p.inputText),
          items: items
              .map((e) => DropdownMenuItem<T>(
                    value: e,
                    child: Text(e.toString(), style: TextStyle(color: p.inputText)),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _tipoField() {
    final p = context._poolsCrearPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _tipoCtrl,
          style: TextStyle(color: p.inputText),
          decoration: InputDecoration(
            labelText: 'Tipo (lista o manual)',
            hintText: 'Ej: tour, excursion, tour cibaeño...',
            labelStyle: TextStyle(color: p.labelMuted),
            hintStyle: TextStyle(color: p.subtitleMuted),
            filled: true,
            fillColor: p.fieldFill,
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          onChanged: (v) => _tipo = v.trim(),
        ),
        const SizedBox(height: 4),
        Text(
          'Puedes elegir una sugerencia o escribir tu tipo personalizado.',
          style: TextStyle(color: p.subtitleMuted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _tiposSugeridos.map((tipoSug) {
            return ActionChip(
              label: Text(tipoSug, style: TextStyle(color: p.inputText)),
              backgroundColor: p.chipBg,
              onPressed: () {
                setState(() {
                  _tipoCtrl.text = tipoSug;
                  _tipo = tipoSug;
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _incluyeField() {
    final p = context._poolsCrearPalette;
    void addIncluye(String raw) {
      final v = raw.trim();
      if (v.isEmpty) return;
      if (_incluye.contains(v)) return;
      setState(() {
        _incluye.add(v);
        _incluyeCtrl.clear();
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.checklist_rounded, color: p.accent, size: 18),
            const SizedBox(width: 6),
            Text(
              'Todo lo que incluye este tipo de viaje',
              style: TextStyle(color: p.accentSoft, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Marca lo que aplica y agrega extras manuales para que el cliente sepa exactamente que recibira.',
          style: TextStyle(color: p.subtitleMuted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _incluyeSugeridos
              .map((e) => FilterChip(
                    label: Text(e),
                    selected: _incluye.contains(e),
                    selectedColor: p.chipSelectedTint,
                    checkmarkColor: p.isDark ? Colors.white : p.tealBtnFg,
                    labelStyle: TextStyle(
                      color: _incluye.contains(e) ? p.inputText : p.labelMuted,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: p.chipBg,
                    onSelected: (sel) {
                      setState(() {
                        if (sel) {
                          if (!_incluye.contains(e)) _incluye.add(e);
                        } else {
                          _incluye.remove(e);
                        }
                      });
                    },
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _incluyeCtrl,
                style: TextStyle(color: p.inputText),
                decoration: InputDecoration(
                  labelText: 'Agregar incluye personalizado',
                  hintText: 'Ej: Almuerzo buffet, fotos profesionales, entrada al parque',
                  labelStyle: TextStyle(color: p.labelMuted),
                  hintStyle: TextStyle(color: p.subtitleMuted),
                  filled: true,
                  fillColor: p.fieldFill,
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => addIncluye(_incluyeCtrl.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC857),
                foregroundColor: const Color(0xFF1C1F2A),
              ),
              child: const Text('Agregar a la lista'),
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
                    labelStyle: TextStyle(color: p.inputText),
                    backgroundColor: p.chipListTint,
                    onDeleted: () => setState(() => _incluye.remove(e)),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _text({
    required String label,
    required String initial,
    required void Function(String) onSaved,
  }) {
    final p = context._poolsCrearPalette;
    return TextFormField(
      initialValue: initial,
      style: TextStyle(color: p.inputText),
      decoration: InputDecoration(
        filled: true,
        fillColor: p.fieldFill,
        labelStyle: TextStyle(color: p.labelMuted),
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ).copyWith(labelText: label),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
      onSaved: (v) => onSaved(v!.trim()),
    );
  }

  Widget _textFieldCtrl({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    final p = context._poolsCrearPalette;
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(color: p.inputText),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: p.labelMuted),
        hintStyle: TextStyle(color: p.subtitleMuted),
        filled: true,
        fillColor: p.fieldFill,
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
      onChanged: onChanged,
    );
  }

  String _cleanPhone(String raw) {
    final v = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (v.startsWith('1') && v.length == 11) return v;
    if (v.length == 10) return '1$v';
    return '';
  }

  Future<void> _abrirLlamadaChofer() async {
    final p = _cleanPhone(_choferTelefono);
    if (p.isEmpty) {
      _snack('Ingresa un telefono valido del chofer.');
      return;
    }
    final ok = await launchUrl(
      Uri.parse('tel:+$p'),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) _snack('No se pudo abrir llamada.');
  }

  Future<void> _abrirWhatsAppChofer() async {
    final p = _cleanPhone(_choferWhatsApp.isNotEmpty ? _choferWhatsApp : _choferTelefono);
    if (p.isEmpty) {
      _snack('Ingresa un WhatsApp/telefono valido del chofer.');
      return;
    }
    final waApp = Uri.parse('whatsapp://send?phone=%2B$p&text=');
    final waWeb = Uri.parse('https://wa.me/$p');
    final ok1 = await launchUrl(waApp, mode: LaunchMode.externalApplication);
    if (ok1) return;
    final ok2 = await launchUrl(waWeb, mode: LaunchMode.externalApplication);
    if (!ok2) _snack('No se pudo abrir WhatsApp.');
  }

  Widget _num({
    required String label,
    required String initial,
    required void Function(String) onSaved,
    double? min,
    double? max,
  }) {
    final p = context._poolsCrearPalette;
    return TextFormField(
      initialValue: initial,
      keyboardType: TextInputType.number,
      style: TextStyle(color: p.inputText),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: p.labelMuted),
        filled: true,
        fillColor: p.fieldFill,
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
    final p = context._poolsCrearPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: p.labelMuted)),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: onTap,
          icon: Icon(Icons.calendar_today, color: p.accent),
          label: Text(text, style: TextStyle(color: p.foreground)),
        ),
      ],
    );
  }

  Widget _agenciaLogoPicker() {
    final p = context._poolsCrearPalette;
    final hasLogo = _agenciaLogoUrl.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Logo de agencia (opcional)', style: TextStyle(color: p.labelMuted)),
        const SizedBox(height: 8),
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 56,
                height: 56,
                color: p.placeholderBox,
                child: hasLogo
                    ? Image.network(
                        _agenciaLogoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(Icons.image_not_supported, color: p.faintIcon),
                      )
                    : Icon(Icons.business, color: p.faintIcon),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _subiendoLogo ? null : _subirLogoAgencia,
                icon: _subiendoLogo
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload),
                label: Text(_subiendoLogo ? 'Subiendo…' : (hasLogo ? 'Cambiar logo' : 'Subir logo')),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bannerPicker() {
    final p = context._poolsCrearPalette;
    final hasBanner = _bannerUrl.trim().isNotEmpty;
    final hasVideo = _bannerVideoUrl.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Banner e imagen / video promocional (opcional)', style: TextStyle(color: p.labelMuted)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            height: 120,
            color: p.placeholderBox,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasBanner)
                  Image.network(
                    _bannerUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.image_not_supported, color: p.faintIcon, size: 36),
                  )
                else if (hasVideo)
                  Center(
                    child: Icon(Icons.play_circle_outline, color: p.accent, size: 56),
                  )
                else
                  Center(
                    child: Text('Sin banner ni video', style: TextStyle(color: p.faintIcon)),
                  ),
                if (hasVideo && hasBanner)
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Icon(Icons.videocam, color: p.accent, size: 28),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _subiendoBanner ? null : _subirBannerViaje,
          icon: _subiendoBanner
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.photo_library_outlined),
          label: Text(
            _subiendoBanner ? 'Subiendo…' : (hasBanner ? 'Cambiar imagen banner' : 'Subir imagen banner'),
          ),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: _subiendoBannerVideo ? null : _subirBannerVideo,
          icon: _subiendoBannerVideo
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.video_library_outlined),
          label: Text(
            _subiendoBannerVideo
                ? 'Subiendo video…'
                : (hasVideo ? 'Cambiar video promocional' : 'Subir video promocional'),
          ),
        ),
        if (hasVideo)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _subiendoBannerVideo ? null : () => setState(() => _bannerVideoUrl = ''),
              child: const Text('Quitar video'),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          'Imagen: hasta 5 MB, horizontal recomendado. Video: hasta 40 MB; preferí MP4 (H.264): en Android los .MOV de iPhone a veces no se reproducen en la app.',
          style: TextStyle(color: p.subtitleMuted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _paradasEditor() {
    void addParada(String raw) {
      final p = raw.trim();
      if (p.isEmpty) return;
      if (_paradas.contains(p)) {
        _snack('Esa parada ya está agregada.');
        return;
      }
      setState(() {
        _paradas.add(p);
        _paradaDraft = '';
        _paradaInputVersion++;
      });
      _snack('Parada agregada: $p');
    }

    final pal = context._poolsCrearPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paradas del tour/excursión 🚌',
          style: TextStyle(color: pal.accentSoft, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        CampoLugarAutocomplete(
          key: ValueKey('parada_input_$_paradaInputVersion'),
          label: 'Agregar parada',
          hint: 'Busca una parada (ej: Boca Chica, Juan Dolio...)',
          country: 'DO',
          initialText: _paradaDraft.isEmpty ? null : _paradaDraft,
          onTextChanged: (v) => _paradaDraft = v,
          onPlaceSelected: (det) {
            addParada(det.displayLabel);
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: () {
              addParada(_paradaDraft);
            },
            icon: const Icon(Icons.add),
            label: const Text('Agregar manual'),
            style: ElevatedButton.styleFrom(
              backgroundColor: pal.tealBtnBg,
              foregroundColor: pal.tealBtnFg,
            ),
          ),
        ),
        if (_paradas.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _paradas
                .map(
                  (parada) => Chip(
                    label: Text(parada),
                    backgroundColor: pal.chipSelectedTint,
                    labelStyle: TextStyle(color: pal.inputText),
                    onDeleted: () {
                      setState(() => _paradas.remove(parada));
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Future<void> _subirLogoAgencia() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (x == null) return;
    setState(() => _subiendoLogo = true);
    try {
      final bytes = await x.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        _snack('La imagen pesa más de 5MB.');
        return;
      }
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage.ref().child('agencias').child(uid).child('logo_$ts.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() => _agenciaLogoUrl = url);
      _snack('✅ Logo cargado');
    } catch (e) {
      _snack('❌ Error subiendo logo: $e');
    } finally {
      if (mounted) setState(() => _subiendoLogo = false);
    }
  }

  Future<void> _subirBannerViaje() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
      maxHeight: 630,
    );
    if (x == null) return;
    setState(() => _subiendoBanner = true);
    try {
      final bytes = await x.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        _snack('El banner pesa más de 5MB.');
        return;
      }
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage.ref().child('viajes_pool').child(uid).child('banner_$ts.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() => _bannerUrl = url);
      _snack('✅ Banner cargado');
    } catch (e) {
      _snack('❌ Error subiendo banner: $e');
    } finally {
      if (mounted) setState(() => _subiendoBanner = false);
    }
  }

  static String _contentTypeVideo(String pathLower) {
    final l = pathLower.toLowerCase();
    if (l.endsWith('.mov')) return 'video/quicktime';
    if (l.endsWith('.webm')) return 'video/webm';
    return 'video/mp4';
  }

  static String _extVideo(String pathLower) {
    final l = pathLower.toLowerCase();
    if (l.endsWith('.mov')) return 'mov';
    if (l.endsWith('.webm')) return 'webm';
    return 'mp4';
  }

  Future<void> _subirBannerVideo() async {
    final x = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 3),
    );
    if (x == null) return;
    setState(() => _subiendoBannerVideo = true);
    try {
      final file = File(x.path);
      if (!await file.exists()) {
        _snack('No se pudo leer el archivo de video.');
        return;
      }
      final len = await file.length();
      if (len > 40 * 1024 * 1024) {
        _snack('El video pesa más de 40MB. Elige uno más corto o comprímelo.');
        return;
      }
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = _extVideo(x.path);
      final ref = _storage.ref().child('viajes_pool').child(uid).child('banner_video_$ts.$ext');
      await ref.putFile(
        file,
        SettableMetadata(contentType: _contentTypeVideo(x.path)),
      );
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() => _bannerVideoUrl = url);
      _snack('✅ Video promocional cargado');
    } catch (e) {
      _snack('❌ Error subiendo video: $e');
    } finally {
      if (mounted) setState(() => _subiendoBannerVideo = false);
    }
  }
}
