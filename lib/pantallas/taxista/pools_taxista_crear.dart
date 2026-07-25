// lib/pantallas/taxista/pools_taxista_crear.dart
import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/pantallas/comun/soporte.dart';
import 'package:flygo_nuevo/servicios/comision_viaje_pct_service.dart';
import 'package:flygo_nuevo/servicios/finance_config_service.dart';
import 'package:flygo_nuevo/servicios/giras_abuso_admin_service.dart';
import 'package:flygo_nuevo/servicios/pool_gira_abuso.dart';
import 'package:flygo_nuevo/servicios/organizador_giras_perfil_data.dart';
import 'package:flygo_nuevo/servicios/pool_repo.dart';
import 'package:flygo_nuevo/widgets/campo_lugar_autocomplete.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';
import 'package:flygo_nuevo/utils/bancos_rd.dart';
import 'package:flygo_nuevo/utils/hora_am_pm.dart';
import 'package:flygo_nuevo/utils/pool_gira_banner_urls.dart';
import 'package:flygo_nuevo/utils/pool_gira_contenido.dart';
import 'package:flygo_nuevo/utils/pools_producto_copy.dart';
import 'package:flygo_nuevo/utils/telefono_viaje.dart';
import 'package:flygo_nuevo/widgets/pool_gira_contenido_form.dart';
import 'package:flygo_nuevo/pantallas/taxista/pools_taxista_lista.dart';

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
      scaffoldBg: isDark ? RaiDsColors.bg : const Color(0xFFF1F5F9),
      appBarBg: isDark ? RaiDsColors.bg : Colors.white,
      foreground: isDark ? Colors.white : const Color(0xFF101828),
      accent: isDark ? const Color(0xFF6FFFE9) : const Color(0xFF0D9488),
      accentSoft: isDark ? const Color(0xFFBEE9E8) : const Color(0xFF0F766E),
      fieldFill: isDark ? RaiDsColors.cardElevated : const Color(0xFFF8FAFC),
      inputText: isDark ? Colors.white : const Color(0xFF101828),
      subtitleMuted: isDark ? RaiDsColors.textMuted : const Color(0xFF667085),
      labelMuted: isDark ? Colors.white70 : const Color(0xFF475467),
      cardGradA: isDark ? RaiDsColors.card : const Color(0xFFE0F2FE),
      cardGradB: isDark ? RaiDsColors.cardElevated : const Color(0xFFF0F9FF),
      cardBorder: isDark
          ? RaiDsColors.border
          : const Color(0xFF0D9488).withValues(alpha: 0.35),
      chipBg: isDark ? RaiDsColors.cardElevated : const Color(0xFFE2E8F0),
      chipSelectedTint: isDark
          ? const Color(0xFF6FFFE9).withValues(alpha: 0.25)
          : const Color(0xFF0D9488).withValues(alpha: 0.22),
      chipListTint: const Color(0xFF5BC0BE).withValues(alpha: 0.25),
      tealBtnBg: const Color(0xFF5BC0BE),
      tealBtnFg: isDark ? const Color(0xFF0B1020) : const Color(0xFF042F2E),
      placeholderBox:
          isDark ? RaiDsColors.cardElevated : const Color(0xFFE2E8F0),
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
    'tour',
    'excursion',
    'gira',
    'tour cibaeño',
  ];

  // Estado del formulario (sin valores prellenados de ruta/destino)
  String _tipo = '';
  String _sentido = 'ida';
  String _origenTown = '';
  String _destino = '';
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
  final List<String> _bannerUrls = <String>[];
  String _bannerVideoUrl = '';
  String _choferTelefono = '';
  String _choferWhatsApp = '';
  String _bancoNombre = '';
  String _bancoCuenta = '';
  String _bancoTipoCuenta = '';
  String _bancoTitular = '';
  String _servicioBadge = '';
  String _descripcionViaje = '';
  PoolGiraContenidoExtra _contenidoExtra = const PoolGiraContenidoExtra();

  DateTime? _fecha;
  DateTime? _fechaVuelta;

  int? _capacidad;
  int? _minConf;
  int? _cuposComisionRai;

  double? _precio;
  double _deposit = 0.30; // 0..1
  double _fee = 0.10; // 0..1 (giras: comision empresa 10%)

  final _agenciaCtrl = TextEditingController();
  final _tipoCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _waCtrl = TextEditingController();
  final _bancoCuentaCtrl = TextEditingController();
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
  bool _recaudoCentral = false;
  bool _agenciaDesdePerfil = false;

  @override
  void initState() {
    super.initState();
    unawaited(ComisionViajePctService.refresh(force: true));
    unawaited(_cargarFlagRecaudoCentral());
    unawaited(_cargarPerfilPublicador());
  }

  Future<void> _cargarPerfilPublicador() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      final d = snap.data() ?? <String, dynamic>{};
      if (!mounted) return;
      setState(() => _aplicarDatosPerfil(d));
    } catch (e) {
      if (kDebugMode) debugPrint('pools_taxista_crear perfil: $e');
    }
  }

  void _aplicarDatosPerfil(Map<String, dynamic> d) {
    final esOrganizador = OrganizadorGirasPerfilData.esOrganizadorGiras(d);

    final agencia = (d['agenciaNombre'] ?? '').toString().trim();
    if (agencia.isNotEmpty && _agenciaNombre.isEmpty) {
      _agenciaNombre = agencia;
      _agenciaCtrl.text = agencia;
      _agenciaDesdePerfil = true;
    }

    if (!esOrganizador) return;

    if (_agenciaLogoUrl.isEmpty) {
      final logo = (d['agenciaLogoUrl'] ?? '').toString().trim();
      final foto = (d['fotoUrl'] ?? '').toString().trim();
      _agenciaLogoUrl = logo.isNotEmpty ? logo : foto;
    }

    final tel = (d['telefono'] ?? '').toString().trim();
    if (_choferTelefono.isEmpty && tel.isNotEmpty) {
      _choferTelefono = tel;
      _telCtrl.text = tel;
    }
    final wa = (d['whatsapp'] ?? d['telefono'] ?? '').toString().trim();
    if (_choferWhatsApp.isEmpty && wa.isNotEmpty) {
      _choferWhatsApp = wa;
      _waCtrl.text = wa;
    }

    final banco = (d['bancoNombre'] ?? '').toString().trim();
    if (_bancoNombre.isEmpty && banco.isNotEmpty) {
      _bancoNombre = banco;
    }
    final cuenta = (d['bancoCuenta'] ?? '').toString().trim();
    if (_bancoCuenta.isEmpty && cuenta.isNotEmpty) {
      _bancoCuenta = cuenta;
      _bancoCuentaCtrl.text = cuenta;
    }
    final tipo = (d['bancoTipoCuenta'] ?? '').toString().trim();
    if (_bancoTipoCuenta.isEmpty && tipo.isNotEmpty) {
      _bancoTipoCuenta = tipo;
    }
    final titular = (d['bancoTitular'] ?? '').toString().trim();
    if (_bancoTitular.isEmpty && titular.isNotEmpty) {
      _bancoTitular = titular;
      _bancoTitularCtrl.text = titular;
    }
  }

  Future<void> _cargarFlagRecaudoCentral() async {
    await FinanceConfigService.ensureStarted();
    if (!mounted) return;
    setState(() {
      _recaudoCentral = FinanceConfigService.poolRecaudoCentralHabilitado;
      if (_recaudoCentral) {
        _deposit = 1.0;
        _fee = PlataformaEconomia.comisionGiraPorcentaje / 100.0;
      }
    });
  }

  @override
  void dispose() {
    _agenciaCtrl.dispose();
    _tipoCtrl.dispose();
    _telCtrl.dispose();
    _waCtrl.dispose();
    _bancoCuentaCtrl.dispose();
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

  /// Tras publicar: volver a «Mis salidas» sin romper el shell en celular.
  /// - Organizador (navigator raíz): solo pop → el tab «Mis giras» ya lista.
  /// - Conductor (navigator anidado en Servicios): pop al tab y abrir Mis salidas.
  void _irAMisSalidasTrasPublicar() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    final rootNav = Navigator.of(context, rootNavigator: true);

    if (identical(nav, rootNav)) {
      if (nav.canPop()) nav.pop();
      return;
    }

    nav.popUntil((route) => route.isFirst);
    nav.push<void>(
      MaterialPageRoute<void>(builder: (_) => const PoolsTaxistaLista()),
    );
  }

  double _prepagoApartadoEstimadoRd() {
    final cap = _capacidad;
    final minC = _minConf;
    final cuposRai = _cuposComisionRai;
    final precio = _precio;
    if (cap == null || minC == null || cuposRai == null || precio == null) {
      return 0;
    }
    final cupos = PoolRepo.cuposReservaComision(
      cuposComisionRai: cuposRai,
      minParaConfirmar: minC,
      capacidad: cap,
    );
    final pct = PlataformaEconomia.comisionGiraPorcentaje / 100.0;
    return cupos * precio * pct;
  }

  Future<void> _pickFecha({required bool esVuelta}) async {
    final base = _fecha ?? DateTime.now().add(const Duration(days: 1));
    final initial = esVuelta ? (_fechaVuelta ?? base.add(const Duration(days: 1))) : base;

    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (!mounted || d == null) return;

    final TimeOfDay? t = await elegirHoraAmPm(
      context,
      initial: const TimeOfDay(hour: 7, minute: 0),
    );
    if (!mounted || t == null) return;

    final DateTime dt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() {
      if (esVuelta) {
        _fechaVuelta = dt;
      } else {
        _fecha = dt;
        // Si cambia salida y la vuelta quedó antes, limpiar vuelta.
        if (_fechaVuelta != null && _fechaVuelta!.isBefore(_fecha!)) {
          _fechaVuelta = null;
        }
      }
    });
  }

  PoolGiraContenidoExtra _contenidoExtraParaGuardar() {
    final p = _puntoSalida.trim();
    if (p.isNotEmpty && _contenidoExtra.direccionExacta.trim().isEmpty) {
      return _contenidoExtra.copyWith(direccionExacta: p);
    }
    return _contenidoExtra;
  }

  void _syncChoferContactoDesdeControllers() {
    _choferTelefono = _telCtrl.text.trim();
    _choferWhatsApp = _waCtrl.text.trim();
  }

  String _choferWhatsAppParaGuardar() {
    _syncChoferContactoDesdeControllers();
    if (_choferWhatsApp.isNotEmpty) return _choferWhatsApp;
    return _choferTelefono;
  }

  Future<void> _crear() async {
    if (_origenTown.trim().isEmpty) {
      _snack('Selecciona el pueblo de origen.');
      return;
    }
    if (_tipo.trim().isEmpty) {
      _snack('Indica el tipo de gira (tour, excursión, consular…).');
      return;
    }
    if (_puntoSalida.trim().isEmpty) {
      _snack('Selecciona un punto de salida válido en el buscador.');
      return;
    }
    if (_destino.trim().isEmpty) {
      _snack('Selecciona un destino válido en el buscador.');
      return;
    }
    if ((_tipoCanonico(_tipo) == 'tour' ||
            _tipoCanonico(_tipo) == 'excursion') &&
        _paradas.isEmpty &&
        _puntoSalida.trim().isEmpty) {
      _snack('Agrega al menos una parada para el tour/excursión.');
      return;
    }
    _syncChoferContactoDesdeControllers();
    if (!telefonoContactoValidoRd(_choferTelefono) &&
        !telefonoContactoValidoRd(_choferWhatsApp)) {
      _snack('Agrega al menos teléfono o WhatsApp del chofer.');
      return;
    }
    final bancoCompleto = _bancoNombre.trim().isNotEmpty &&
        _bancoCuenta.trim().isNotEmpty &&
        _bancoTipoCuenta.trim().isNotEmpty &&
        _bancoTitular.trim().isNotEmpty;
    if (!bancoCompleto) {
      _snack(_recaudoCentral
          ? 'Completa la cuenta donde RAI (Open ASK Service) te transferirá el neto. '
              'El cliente no paga a esa cuenta.'
          : 'Completa la cuenta del organizador para depósitos del cliente y comisión RAI.');
      return;
    }

    if (_bannerUrls.isEmpty && _bannerVideoUrl.trim().isEmpty) {
      _snack(
        'Sube al menos una imagen o video banner para publicar la salida.',
      );
      return;
    }
    if (_agenciaNombre.trim().isEmpty) {
      _snack('Indica el nombre de la agencia o operador en el anuncio.');
      return;
    }

    // Validaciones rápidas previas a guardar
    if (!_form.currentState!.validate()) return;
    _form.currentState!.save();

    if (_fecha == null) {
      _snack('Selecciona fecha y hora de salida.');
      return;
    }
    if (_capacidad == null || _capacidad! < 1) {
      _snack('Indica la capacidad total de la gira.');
      return;
    }
    if (_minConf == null || _minConf! < 0) {
      _snack('Indica el mínimo de pasajeros para confirmar.');
      return;
    }
    if (_cuposComisionRai == null || _cuposComisionRai! < 1) {
      _snack('Indica cuántos cupos venderá RAI.');
      return;
    }
    if (_precio == null || _precio! <= 0) {
      _snack('Indica el precio por asiento.');
      return;
    }

    // Reglas de fechas
    final DateTime ahora = DateTime.now();
    final DateTime salidaMin = ahora.add(const Duration(minutes: 5));
    if (_fecha!.isBefore(salidaMin)) {
      _snack('La salida debe ser al menos en 5 minutos.');
      return;
    }
    if (_sentido == 'ida_y_vuelta') {
      if (_fechaVuelta == null) {
        _snack('Selecciona la fecha de vuelta.');
        return;
      }
      if (_fechaVuelta!.isBefore(_fecha!)) {
        _snack('La vuelta no puede ser antes de la salida.');
        return;
      }
    }
    if (_cuposComisionRai! < 1 || _cuposComisionRai! > _capacidad!) {
      _snack('Cupos RAI para comisión: entre 1 y $_capacidad.');
      return;
    }

    // Porcentajes: recaudo central → 100% depósito y comisión de plataforma (no editables).
    final double dep = _recaudoCentral
        ? 1.0
        : (_deposit > 1 ? _deposit / 100.0 : _deposit);
    final double fee = _recaudoCentral
        ? PlataformaEconomia.comisionGiraPorcentaje / 100.0
        : (_fee > 1 ? _fee / 100.0 : _fee);

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
      final banners = PoolGiraBannerUrls.sanitizeForSave(_bannerUrls);
      final CrearPoolResult creado = await PoolRepo.crearPool(
        tipo: tipoCanon,
        sentido: _sentido,
        origenTown: _origenTown.trim(),
        destino: _destino.trim(),
        fechaSalida: _fecha!,
        fechaVuelta: _sentido == 'ida_y_vuelta' ? _fechaVuelta : null,
        capacidad: _capacidad!,
        minParaConfirmar: _minConf!,
        cuposComisionRai: _cuposComisionRai!,
        precioPorAsiento: _precio!,
        pickupPoints: pickups.isEmpty ? null : pickups,
        depositPct: dep,
        feePct: fee,
        agenciaNombre:
            _agenciaNombre.trim().isEmpty ? null : _agenciaNombre.trim(),
        agenciaLogoUrl:
            _agenciaLogoUrl.trim().isEmpty ? null : _agenciaLogoUrl.trim(),
        bannerUrls: banners.isEmpty ? null : banners,
        bannerUrl: banners.isEmpty ? null : banners.first,
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
        choferWhatsApp: () {
          final wa = _choferWhatsAppParaGuardar().trim();
          return wa.isEmpty ? null : wa;
        }(),
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
        contenidoExtra: _contenidoExtraParaGuardar(),
      );

      if (!mounted) return;
      final aviso = creado.aviso?.trim();
      if (aviso != null && aviso.isNotEmpty) {
        _snack('✅ Viaje creado (#${creado.poolId}). $aviso');
      } else {
        _snack('✅ Viaje creado (#${creado.poolId})');
      }
      _snack(PoolsProductoCopy.avisoTrasPublicar);
      _snack(
        'Para cancelar si hace falta: ${PoolsProductoCopy.salidasMis} → Cancelar salida.',
      );
      _irAMisSalidasTrasPublicar();
    } on PoolGiraAbusoBloqueo catch (b) {
      if (!mounted) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        unawaited(GirasAbusoAdminService.marcarBloqueado(uid));
      }
      _snack('❌ ${b.mensajeUsuario}');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No puedes publicar otra salida'),
          content: Text(b.mensajeUsuario),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const Soporte()),
                );
              },
              child: const Text('Contactar soporte'),
            ),
          ],
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('[PoolsTaxistaCrear] crearPoolGira error: $e');
      }
      if (!mounted) return;
      final msg = (e.message ?? '').trim();
      _snack('❌ ${msg.isNotEmpty ? msg : 'Error al publicar la salida (${e.code}).'}');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PoolsTaxistaCrear] crearPool error: $e');
      }
      if (!mounted) return;
      if (e is FirebaseException && e.code == 'permission-denied') {
        final msg = (e.message ?? '').trim();
        _snack(
          '❌ ${msg.isNotEmpty ? msg : 'No se pudo publicar la salida (permisos). Verifica tu sesión de conductor.'}',
        );
        return;
      }
      final String msg = e is String
          ? e
          : e.toString().replaceFirst('Exception: ', '');
      _snack('❌ $msg');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context._poolsCrearPalette;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: p.scaffoldBg,
      appBar: RaiAppBar(
        title: PoolsProductoCopy.publicarTitulo,
        showBackWhenCanPop: true,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
            _heroBanner(),
            const SizedBox(height: 12),
            _infoPanel(
              icon: Icons.account_balance_outlined,
              title: 'Quién paga el cliente',
              body: PoolsProductoCopy.formQuienPagaCliente(
                recaudoCentral: _recaudoCentral,
              ),
            ),
            const SizedBox(height: 8),
            _infoPanel(
              icon: Icons.checklist_rtl_outlined,
              title: 'Campos obligatorios antes de publicar',
              body:
                  'Tipo de gira · Pueblo origen · Punto de salida · Destino · '
                  'Agencia · Banner (foto o video) · Teléfono o WhatsApp del chofer · '
                  'Capacidad · Mínimo para confirmar · Cupos RAI · Precio por asiento · '
                  'Fecha/hora de salida'
                  '${_sentido == 'ida_y_vuelta' ? ' · Fecha/hora de vuelta' : ''} · '
                  'Datos bancarios del organizador.\n\n'
                  'El precio que indiques es el monto final por persona (ida y vuelta incluida si aplica).',
            ),
            const SizedBox(height: 8),
            _infoPanel(
              icon: Icons.directions_bus_filled_outlined,
              title: 'Tu rol al publicar',
              body: PoolsProductoCopy.formTuRolOrganizador,
            ),
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
                    left: _puebloOrigenDropdown(),
                    right: _textFieldCtrl(
                      controller: _agenciaCtrl,
                      label: 'Agencia / operador',
                      hint: 'Tours RD, Mi Agencia…',
                      helperText: _agenciaDesdePerfil
                          ? 'Cargado desde tu perfil — puedes editarlo'
                          : null,
                      onChanged: (v) {
                        _agenciaNombre = v.trim();
                        if (_agenciaDesdePerfil) {
                          setState(() => _agenciaDesdePerfil = false);
                        }
                      },
                    ),
                  ),
                  _textFieldCtrl(
                    controller: _servicioBadgeCtrl,
                    label: 'Etiqueta corta del viaje (opcional)',
                    hint:
                        'Ej: VIP, Excursión Saona, Viaje grupal Santiago, Promo…',
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
                  const SizedBox(height: 12),
                  _sectionTitle('Detalle profesional de la gira', Icons.article_outlined),
                  PoolGiraContenidoFormSection(
                    initial: _contenidoExtra,
                    ocultarDireccionExacta: true,
                    labelColor: context._poolsCrearPalette.labelMuted,
                    fieldFill: context._poolsCrearPalette.fieldFill,
                    inputText: context._poolsCrearPalette.inputText,
                    accent: context._poolsCrearPalette.accent,
                    onChanged: (v) => _contenidoExtra = v,
                  ),
                  const SizedBox(height: 8),
                  CampoLugarAutocomplete(
                    label: 'Punto de salida',
                    hint: 'Busca punto de encuentro/salida',
                    initialText: _puntoSalida.isEmpty ? null : _puntoSalida,
                    country: 'DO',
                    asistenteDireccionHabilitado: true,
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
                    hint: 'Busca destino de la gira',
                    initialText: _destino.isEmpty ? null : _destino,
                    country: 'DO',
                    asistenteDireccionHabilitado: true,
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
                      onChanged: (v) {
                        final nuevo = v.trim();
                        final anterior = _choferTelefono;
                        _choferTelefono = nuevo;
                        if (_choferWhatsApp.isEmpty ||
                            _choferWhatsApp == anterior) {
                          _choferWhatsApp = nuevo;
                          if (_waCtrl.text.trim() != nuevo) {
                            _waCtrl.text = nuevo;
                          }
                        }
                      },
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
            _sectionTitle(
                'Capacidad y finanzas', Icons.account_balance_wallet_outlined),
            _card(
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Text(
                    '¿Cómo cobra comisión RAI?',
                    style: TextStyle(
                      color: context._poolsCrearPalette.inputText,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  leading: Icon(
                    Icons.help_outline,
                    color: context._poolsCrearPalette.accent,
                    size: 22,
                  ),
                  children: [
                    Text(
                      PoolsProductoCopy.ayudaFinanzas,
                      style: TextStyle(
                        color: context._poolsCrearPalette.subtitleMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      PoolsProductoCopy.formQuienPagaCliente(
                        recaudoCentral: _recaudoCentral,
                      ),
                      style: TextStyle(
                        color: context._poolsCrearPalette.subtitleMuted,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            _card(
              child: Wrap(
                runSpacing: 12,
                children: [
                  _row(
                    left: _num(
                      label: 'Capacidad',
                      initial: _capacidad?.toString() ?? '',
                      hint: 'Ej: 15',
                      onSaved: (v) => _capacidad = int.parse(v),
                      onChanged: (v) {
                        final n = int.tryParse(v.trim());
                        if (n != null) setState(() => _capacidad = n);
                      },
                      min: 1,
                      max: 60,
                    ),
                    right: _num(
                      label: 'Mín. para confirmar',
                      initial: _minConf?.toString() ?? '',
                      hint: 'Ej: 8',
                      onSaved: (v) => _minConf = int.parse(v),
                      onChanged: (v) {
                        final n = int.tryParse(v.trim());
                        if (n != null) setState(() => _minConf = n);
                      },
                      min: 0,
                      max: 60,
                    ),
                  ),
                  _num(
                    label: 'Cupos que venderá RAI (tope comisión)',
                    initial: _cuposComisionRai?.toString() ?? '',
                    hint: 'Ej: 5',
                    onSaved: (v) => _cuposComisionRai = int.parse(v),
                    onChanged: (v) {
                      final n = int.tryParse(v.trim());
                      if (n == null) return;
                      final cap = _capacidad ?? 60;
                      setState(() => _cuposComisionRai = n.clamp(1, cap));
                    },
                    min: 1,
                    max: 60,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      PoolsProductoCopy.comisionRaiFormula(
                        PlataformaEconomia.comisionGiraPorcentaje,
                      ),
                      style: TextStyle(
                        color: context._poolsCrearPalette.subtitleMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      PoolsProductoCopy.formPrepagoAlPublicar(
                        recaudoCentral: _recaudoCentral,
                      ),
                      style: TextStyle(
                        color: context._poolsCrearPalette.subtitleMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                  if (!_recaudoCentral)
                    Builder(
                      builder: (ctx) {
                        final cupos = PoolRepo.cuposReservaComision(
                          cuposComisionRai: _cuposComisionRai ?? 0,
                          minParaConfirmar: _minConf ?? 0,
                          capacidad: _capacidad ?? 0,
                        );
                        final prep = _prepagoApartadoEstimadoRd();
                        final pct = PlataformaEconomia.comisionGiraPorcentaje;
                        final precioTxt = (_precio ?? 0).toStringAsFixed(0);
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: context._poolsCrearPalette.chipBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: context._poolsCrearPalette.cardBorder,
                            ),
                          ),
                          child: Text(
                            'Prepago apartado al publicar (tope, aprox.): RD\$ ${prep.toStringAsFixed(0)} '
                            '($cupos cupos × RD\$ $precioTxt × $pct% máx. en app). '
                            'Al confirmar comisión se cobra solo lo vendido en RAI.',
                            style: TextStyle(
                              color: context._poolsCrearPalette.inputText,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        );
                      },
                    ),
                  if (_recaudoCentral)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: context._poolsCrearPalette.chipSelectedTint,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: context._poolsCrearPalette.cardBorder,
                        ),
                      ),
                      child: Text(
                        '${PoolsProductoCopy.formRecaudoCentralPagoFijo(PlataformaEconomia.comisionGiraPorcentaje)}\n\n'
                        'Tu cuenta bancaria (más abajo) es solo para que RAI te transfiera tu neto.',
                        style: TextStyle(
                          color: context._poolsCrearPalette.inputText,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  if (_recaudoCentral) ...[
                    _num(
                      label: 'Precio por asiento (RD\$)',
                      initial: _precio?.toStringAsFixed(0) ?? '',
                      hint: 'Ej: 2000',
                      onSaved: (v) => _precio = double.parse(v),
                      onChanged: (v) {
                        final n = double.tryParse(v.trim());
                        if (n != null) setState(() => _precio = n);
                      },
                      min: 1,
                    ),
                  ] else ...[
                    _row(
                      left: _num(
                        label: 'Precio por asiento (RD\$)',
                        initial: _precio?.toStringAsFixed(0) ?? '',
                        hint: 'Ej: 2000',
                        onSaved: (v) => _precio = double.parse(v),
                        onChanged: (v) {
                          final n = double.tryParse(v.trim());
                          if (n != null) setState(() => _precio = n);
                        },
                        min: 1,
                      ),
                      right: _num(
                        label: 'Depósito %',
                        initial: (_deposit * 100).toStringAsFixed(0),
                        onSaved: (v) => _deposit = double.parse(v) / 100.0,
                        min: 0,
                        max: 100,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        PoolsProductoCopy.formDepositoPctNota(
                          recaudoCentral: false,
                        ),
                        style: TextStyle(
                          color: context._poolsCrearPalette.subtitleMuted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                    _num(
                      label: 'Fee plataforma %',
                      initial: (_fee * 100).toStringAsFixed(0),
                      onSaved: (v) => _fee = double.parse(v) / 100.0,
                      min: 0,
                      max: 100,
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Precio final por persona. El cliente verá exactamente este monto'
                      '${_sentido == 'ida_y_vuelta' ? ' (ida y vuelta incluidas)' : ''}.',
                      style: TextStyle(
                        color: context._poolsCrearPalette.subtitleMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Fechas y horarios',
                    style: TextStyle(
                      color: context._poolsCrearPalette.inputText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _fechaPicker(
                    label: 'Salida',
                    text: _fecha == null
                        ? 'Seleccionar fecha y hora'
                        : _formatFechaHora(_fecha!),
                    onTap: () => _pickFecha(esVuelta: false),
                  ),
                  if (_sentido == 'ida_y_vuelta') ...[
                    const SizedBox(height: 8),
                    _fechaPicker(
                      label: 'Regreso estimado',
                      text: _fechaVuelta == null
                          ? 'Seleccionar…'
                          : _formatFechaHora(_fechaVuelta!),
                      onTap: () => _pickFecha(esVuelta: true),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    _recaudoCentral
                        ? PoolsProductoCopy.bancoRecibirNetoTitulo
                        : PoolsProductoCopy.bancoLegacyDepositoTitulo,
                    style: TextStyle(
                      color: context._poolsCrearPalette.inputText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (_recaudoCentral) ...[
                    const SizedBox(height: 4),
                    Text(
                      PoolsProductoCopy.bancoRecibirNetoAyuda,
                      style: TextStyle(
                        color: context._poolsCrearPalette.subtitleMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 4),
                    Text(
                      PoolsProductoCopy.bancoLegacyDepositoAyuda,
                      style: TextStyle(
                        color: context._poolsCrearPalette.subtitleMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _bancoNombreDropdown(),
                  const SizedBox(height: 8),
                  _row(
                    left: _textFieldCtrl(
                      controller: _bancoCuentaCtrl,
                      label: 'Número de cuenta',
                      hint: 'Ej: 960-1234567-8',
                      onChanged: (v) => _bancoCuenta = v.trim(),
                    ),
                    right: _bancoTipoCuentaDropdown(),
                  ),
                  const SizedBox(height: 8),
                  _textFieldCtrl(
                    controller: _bancoTitularCtrl,
                    label: _recaudoCentral
                        ? 'Titular de tu cuenta (donde RAI te paga)'
                        : 'Titular cuenta (organizador)',
                    hint: _recaudoCentral
                        ? 'Tu nombre o razón social — no Open ASK Service'
                        : 'Nombre del titular',
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
                  minimumSize: const Size.fromHeight(52),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
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
      child: Row(
        children: [
          const Icon(Icons.beach_access, color: Colors.white, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              PoolsProductoCopy.formHero(recaudoCentral: _recaudoCentral),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoPanel({
    required IconData icon,
    required String title,
    required String body,
  }) {
    final p = context._poolsCrearPalette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.fieldFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: p.accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: p.inputText,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: TextStyle(
                    color: p.subtitleMuted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
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
    String Function(T)? itemLabel,
  }) {
    final p = context._poolsCrearPalette;
    return InputDecorator(
      decoration: InputDecoration(
        filled: true,
        fillColor: p.fieldFill,
        border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12))),
        labelStyle: TextStyle(color: p.labelMuted),
      ).copyWith(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: Text('Seleccionar…', style: TextStyle(color: p.subtitleMuted)),
          dropdownColor: p.fieldFill,
          style: TextStyle(color: p.inputText),
          items: items
              .map((e) => DropdownMenuItem<T>(
                    value: e,
                    child: Text(
                      itemLabel != null ? itemLabel(e) : e.toString(),
                      style: TextStyle(color: p.inputText),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _puebloOrigenDropdown() {
    return _dropdown<String?>(
      label: 'Pueblo (origen)',
      value: _origenTown.isEmpty ? null : _origenTown,
      items: const <String?>[null, ...PoolGiraPueblosOrigen.opciones],
      itemLabel: (v) => v ?? 'Seleccionar pueblo…',
      onChanged: (v) => setState(() => _origenTown = v ?? ''),
    );
  }

  Widget _bancoNombreDropdown() {
    return _dropdown<String?>(
      label: 'Banco',
      value: _bancoNombre.isEmpty ? null : _bancoNombre,
      items: const <String?>[null, ...BancosRd.nombres],
      itemLabel: (v) => v ?? 'Seleccionar banco…',
      onChanged: (v) => setState(() => _bancoNombre = v ?? ''),
    );
  }

  Widget _bancoTipoCuentaDropdown() {
    return _dropdown<String?>(
      label: 'Tipo de cuenta',
      value: _bancoTipoCuenta.isEmpty ? null : _bancoTipoCuenta,
      items: const <String?>[null, ...BancosRd.tiposCuentaGira],
      itemLabel: (v) => v ?? 'Ahorros o Corriente…',
      onChanged: (v) => setState(() => _bancoTipoCuenta = v ?? ''),
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
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Requerido' : null,
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
              style:
                  TextStyle(color: p.accentSoft, fontWeight: FontWeight.w800),
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
          children: PoolGiraContenidoCatalog.incluyeOpciones
              .map((e) => FilterChip(
                    avatar: Icon(e.icon, size: 16, color: p.accent),
                    label: Text(e.label),
                    selected: _incluye.contains(e.label),
                    selectedColor: p.chipSelectedTint,
                    checkmarkColor: p.isDark ? Colors.white : p.tealBtnFg,
                    labelStyle: TextStyle(
                      color: _incluye.contains(e.label) ? p.inputText : p.labelMuted,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: p.chipBg,
                    onSelected: (sel) {
                      setState(() {
                        if (sel) {
                          if (!_incluye.contains(e.label)) _incluye.add(e.label);
                        } else {
                          _incluye.remove(e.label);
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
                  hintText:
                      'Ej: Almuerzo buffet, fotos profesionales, entrada al parque',
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

  Widget _textFieldCtrl({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helperText,
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
        helperText: helperText,
        helperStyle: TextStyle(
          color: p.subtitleMuted,
          fontSize: 11,
          height: 1.2,
        ),
        labelStyle: TextStyle(color: p.labelMuted),
        hintStyle: TextStyle(color: p.subtitleMuted),
        filled: true,
        fillColor: p.fieldFill,
        border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
      onChanged: onChanged,
    );
  }

  Future<void> _abrirLlamadaChofer() async {
    _syncChoferContactoDesdeControllers();
    final raw = telefonoChoferGiraLlamada(_choferTelefono, _choferWhatsApp);
    if (!telefonoContactoValidoRd(raw)) {
      _snack('Ingresa un telefono valido del chofer.');
      return;
    }
    final ok = await telefonoAbrirLlamada(raw);
    if (!ok) _snack('No se pudo abrir llamada.');
  }

  Future<void> _abrirWhatsAppChofer() async {
    _syncChoferContactoDesdeControllers();
    final raw = telefonoChoferGiraWhatsApp(_choferTelefono, _choferWhatsApp);
    if (!telefonoContactoValidoRd(raw)) {
      _snack('Ingresa un WhatsApp/telefono valido del chofer.');
      return;
    }
    final ok = await telefonoAbrirWhatsApp(raw);
    if (!ok) _snack('No se pudo abrir WhatsApp.');
  }

  Widget _num({
    required String label,
    required String initial,
    required void Function(String) onSaved,
    void Function(String)? onChanged,
    String? hint,
    double? min,
    double? max,
  }) {
    final p = context._poolsCrearPalette;
    return TextFormField(
      initialValue: initial,
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      style: TextStyle(color: p.inputText),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: p.labelMuted),
        hintStyle: TextStyle(color: p.subtitleMuted),
        filled: true,
        fillColor: p.fieldFill,
        border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12))),
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
    return Material(
      color: p.fieldFill,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.cardBorder),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today, color: p.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(color: p.labelMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.foreground,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: p.faintIcon),
            ],
          ),
        ),
      ),
    );
  }

  String _formatFechaHora(DateTime dt) => fmtFechaHoraAmPm(dt, conAnio: true);

  Widget _agenciaLogoPicker() {
    final p = context._poolsCrearPalette;
    final hasLogo = _agenciaLogoUrl.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Logo de agencia (opcional)',
            style: TextStyle(color: p.labelMuted)),
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
                label: Text(_subiendoLogo
                    ? 'Subiendo…'
                    : (hasLogo ? 'Cambiar logo' : 'Subir logo')),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bannerPicker() {
    final p = context._poolsCrearPalette;
    final photos = List<String>.from(_bannerUrls);
    final hasPhotos = photos.isNotEmpty;
    final hasVideo = _bannerVideoUrl.trim().isNotEmpty;
    final canAddPhoto = photos.length < PoolGiraBannerUrls.maxCount;
    final previewUrl = hasPhotos ? photos.first : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fotos y video promocional',
          style: TextStyle(
            color: p.labelMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Hasta ${PoolGiraBannerUrls.maxCount} fotos del banner + video opcional. '
          'Sube al menos una foto o un video.',
          style: TextStyle(color: p.subtitleMuted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            height: 148,
            color: p.placeholderBox,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasPhotos)
                  Image.network(
                    previewUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.image_not_supported,
                      color: p.faintIcon,
                      size: 36,
                    ),
                  )
                else if (hasVideo)
                  Center(
                    child: Icon(
                      Icons.play_circle_outline,
                      color: p.accent,
                      size: 56,
                    ),
                  )
                else
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.photo_library_outlined,
                            color: p.faintIcon, size: 40),
                        const SizedBox(height: 6),
                        Text(
                          'Agrega fotos del tour',
                          style: TextStyle(color: p.faintIcon, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                if (hasPhotos && photos.length > 1)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${photos.length} fotos',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                if (hasVideo && hasPhotos)
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
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length + (canAddPhoto ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              if (i < photos.length) {
                return _bannerThumbTile(
                  url: photos[i],
                  index: i,
                  palette: p,
                );
              }
              return _bannerAddThumbTile(palette: p);
            },
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: (_subiendoBanner || !canAddPhoto)
              ? null
              : _subirBannerViaje,
          icon: _subiendoBanner
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_photo_alternate_outlined),
          label: Text(
            _subiendoBanner
                ? 'Subiendo…'
                : (hasPhotos
                    ? 'Agregar otra foto (${photos.length}/${PoolGiraBannerUrls.maxCount})'
                    : 'Subir foto del banner'),
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
                : (hasVideo
                    ? 'Cambiar video promocional'
                    : 'Subir video promocional'),
          ),
        ),
        if (hasVideo)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _subiendoBannerVideo
                  ? null
                  : () => setState(() => _bannerVideoUrl = ''),
              child: const Text('Quitar video'),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          'Fotos: hasta 5 MB c/u, horizontal recomendado. Video: hasta 40 MB; preferí MP4 (H.264): en Android los .MOV de iPhone a veces no se reproducen en la app.',
          style: TextStyle(color: p.subtitleMuted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _bannerThumbTile({
    required String url,
    required int index,
    required ({
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
    }) palette,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 92,
            height: 92,
            color: palette.placeholderBox,
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.broken_image,
                color: palette.faintIcon,
              ),
            ),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: Material(
            color: Colors.red.shade700,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _subiendoBanner ? null : () => _quitarBannerFoto(index),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
        if (index == 0)
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Principal',
                style: TextStyle(
                  color: palette.tealBtnFg,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _bannerAddThumbTile({
    required ({
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
    }) palette,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _subiendoBanner ? null : _subirBannerViaje,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: palette.fieldFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: palette.accent.withValues(alpha: 0.45),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo_outlined, color: palette.accent, size: 28),
              const SizedBox(height: 4),
              Text(
                'Agregar',
                style: TextStyle(
                  color: palette.accentSoft,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _quitarBannerFoto(int index) {
    if (index < 0 || index >= _bannerUrls.length) return;
    setState(() => _bannerUrls.removeAt(index));
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
          asistenteDireccionHabilitado: true,
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
      final ref =
          _storage.ref().child('agencias').child(uid).child('logo_$ts.jpg');
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
    if (_bannerUrls.length >= PoolGiraBannerUrls.maxCount) {
      _snack(
        'Ya tienes ${PoolGiraBannerUrls.maxCount} fotos. Quita una para agregar otra.',
      );
      return;
    }
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
      final ref = _storage
          .ref()
          .child('viajes_pool')
          .child(uid)
          .child('banner_$ts.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() => _bannerUrls.add(url));
      _snack('✅ Foto ${_bannerUrls.length}/${PoolGiraBannerUrls.maxCount} cargada');
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
      final ref = _storage
          .ref()
          .child('viajes_pool')
          .child(uid)
          .child('banner_video_$ts.$ext');
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
