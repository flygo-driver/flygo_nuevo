import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter/services.dart';

import 'package:flygo_nuevo/legal/legal_urls.dart';
import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/pantallas/corporativo/contrato_corporativo_firma_page.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_dashboard_page.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_gestion_ruta_page.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_historial_page.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_pago_sheet.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_plantilla_editor_page.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_plantillas_lista_page.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_ui.dart';
import 'package:flygo_nuevo/servicios/corporativo_encargado_deep_link.dart';
import 'package:flygo_nuevo/servicios/corporativo_export_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_pago_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_ruta_service.dart';
import 'package:flygo_nuevo/utils/corporativo_ciclo_facturacion.dart';
import 'package:flygo_nuevo/widgets/corporativo_codigo_verificacion_card.dart';
import 'package:flygo_nuevo/widgets/corporativo_empresa_logo_card.dart';
import 'package:flygo_nuevo/widgets/corporativo_proximo_pago_anillo.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';
import 'package:flygo_nuevo/widgets/rai_cuenta_deposito_panel.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hub corporativo: rutas guardadas, historial y cuenta empresa.
class CorporativoHubPage extends StatefulWidget {
  const CorporativoHubPage({super.key});

  @override
  State<CorporativoHubPage> createState() => _CorporativoHubPageState();
}

class _CorporativoHubPageState extends State<CorporativoHubPage> {
  int _tab = 0;
  String? _empresaId;
  CorporativoEmpresa? _empresa;
  bool _cargando = true;
  String? _errorCarga;
  bool _encargadoHabilitado = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      CorporativoEncargadoDeepLinkBridge.ingestUri(Uri.base);
    }
    _cargar();
  }

  @override
  void dispose() {
    CorporativoEncargadoDeepLinkBridge.unbindHub();
    super.dispose();
  }

  bool get _hubDeepLinkListo =>
      !_cargando &&
      _empresaId != null &&
      _empresa != null &&
      _empresa!.contratoDigitalFirmado;

  void _programarVinculoDeepLink() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hubDeepLinkListo) return;
      CorporativoEncargadoDeepLinkBridge.bindHub(
        isReady: () => mounted && _hubDeepLinkListo,
        onOpen: _abrirDeepLinkEncargado,
      );
    });
  }

  Future<void> _abrirDeepLinkEncargado(
    CorporativoEncargadoDeepLink link,
  ) async {
    if (!mounted || _empresaId == null || _empresa == null) return;
    final empId = _empresaId!;
    final empresa = _empresa!;
    final empLink = (link.empresaId ?? '').trim();
    if (empLink.isNotEmpty && empLink != empId) return;

    setState(() => _tab = 0);

    CorporativoPlantilla? pl;
    try {
      pl = await CorporativoRutaService.cargarPlantilla(
        empId,
        link.plantillaId,
      ).timeout(const Duration(seconds: 12));
    } catch (_) {}
    if (!mounted) return;
    if (pl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontró la ruta del aviso. Revisá en Rutas.'),
        ),
      );
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    switch (link.destino) {
      case CorporativoEncargadoDestino.gestion:
        await Navigator.of(context, rootNavigator: true).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => CorporativoGestionRutaPage(
              empresaId: empId,
              empresaNombre: empresa.nombre,
              empresa: empresa,
              plantilla: pl!,
            ),
          ),
        );
      case CorporativoEncargadoDestino.editor:
        await Navigator.of(context, rootNavigator: true).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => CorporativoPlantillaEditorPage(
              empresaId: empId,
              empresaNombre: empresa.nombre,
              empresa: empresa,
              plantilla: pl,
            ),
          ),
        );
      case CorporativoEncargadoDestino.rutas:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '«${pl.nombre}» — revisá el panel Rutas de hoy.',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
    }
  }

  Future<void> _cerrarSesion() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/login/corporativo', (r) => false);
  }

  Future<void> _cargar({String? empresaIdConocido}) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (mounted) {
          setState(() {
            _cargando = false;
            _errorCarga = 'Tu sesión expiró. Volvé a entrar como encargado corporativo.';
            _encargadoHabilitado = false;
          });
        }
        return;
      }
      final idHint = (empresaIdConocido ?? '').trim();
      var empresaId = idHint.isNotEmpty
          ? idHint
          : await CorporativoRutaService.empresaIdDelUsuario(uid)
              .timeout(const Duration(seconds: 12));
      CorporativoEmpresa? empresa;
      if (empresaId != null && empresaId.trim().isNotEmpty) {
        empresaId = empresaId.trim();
        empresa = await CorporativoRutaService.cargarEmpresaEncargado(
          empresaId,
          fromServer: idHint.isNotEmpty,
          uidEncargado: uid,
          recienCreada: idHint.isNotEmpty,
        ).timeout(const Duration(seconds: 15));
      }
      final habilitado =
          empresa != null && empresa.encargadoUids.contains(uid);
      if (mounted) {
        setState(() {
          _encargadoHabilitado = habilitado;
          _empresaId = habilitado ? empresaId : null;
          _empresa = empresa;
          _cargando = false;
          _errorCarga = habilitado
              ? null
              : (idHint.isNotEmpty
                  ? 'La empresa se creó pero no se pudo abrir. '
                      'Tocá «Ya me habilitaron · Reintentar».'
                  : 'Tu cuenta no está habilitada como encargado corporativo. '
                      'Pedí a RAI que te agregue con el correo con el que entraste.');
        });
        if (empresa != null && _esNombreDemo(empresa.nombre)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _dialogEditarEmpresa(forzarNombreReal: true);
          });
        }
        if (empresa != null && empresa.contratoDigitalFirmado) {
          _programarVinculoDeepLink();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _encargadoHabilitado = false;
          final msg = e.toString().toLowerCase();
          final permiso = msg.contains('permission-denied') ||
              msg.contains('permission_denied');
          _errorCarga = permiso
              ? 'Tu cuenta no está habilitada como encargado corporativo. '
                  'Pedí a RAI (Admin → Empresas corporativas) que te agregue '
                  'con este correo.'
              : 'No se pudo abrir corporativo. Reintenta.\n($e)';
        });
      }
    }
  }

  Future<void> _aplicarEmpresaRegistrada(String empresaId) async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _errorCarga = null;
    });
    await _cargar(empresaIdConocido: empresaId);
    if (!mounted) return;
    if (_empresaId == null || _empresa == null) {
      final msg = _errorCarga ??
          'No se pudo abrir la empresa recién creada. Tocá «Reintentar».';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<String?> _dialogRegistrarEmpresa() async {
    final nombreCtrl = TextEditingController();
    final docCtrl = TextEditingController();
    final telCtrl = TextEditingController();
    final emailCtrl = TextEditingController(
      text: FirebaseAuth.instance.currentUser?.email ?? '',
    );
    final dirCtrl = TextEditingController();
    var tipoDoc = 'rnc';
    String? errorDlg;
    var guardando = false;

    final empresaId = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: !guardando,
      builder: (ctx) {
        final p = ctx.corporativoPalette;
        InputDecoration dec(String label, {String? hint}) => InputDecoration(
              labelText: label,
              hintText: hint,
              hintStyle: TextStyle(color: p.muted.withValues(alpha: 0.7)),
              labelStyle: TextStyle(color: p.muted),
              filled: true,
              fillColor: p.isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF8FAFC),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: p.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: p.primary, width: 1.6),
              ),
            );
        return StatefulBuilder(
          builder: (ctx, setDlg) => AlertDialog(
            backgroundColor: p.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: p.cardBorder),
            ),
            title: Text(
              'Registrar empresa',
              style: TextStyle(
                color: p.onCard,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Estos datos quedan guardados y se usan al crear rutas.',
                    style: TextStyle(color: p.muted, fontSize: 13, height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nombreCtrl,
                    enabled: !guardando,
                    style: TextStyle(color: p.onCard),
                    decoration: dec(
                      'Nombre empresa *',
                      hint: 'Escribe el nombre de tu empresa',
                    ),
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) {
                      if (errorDlg != null) setDlg(() => errorDlg = null);
                    },
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'rnc', label: Text('RNC')),
                      ButtonSegment(value: 'cedula', label: Text('Cédula')),
                    ],
                    selected: {tipoDoc},
                    onSelectionChanged: guardando
                        ? null
                        : (s) => setDlg(() {
                              tipoDoc = s.first;
                              errorDlg = null;
                            }),
                    style: ButtonStyle(
                      foregroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return p.onPrimary;
                        }
                        return p.onCard;
                      }),
                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return p.ctaBg;
                        }
                        return p.primarySoft;
                      }),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: docCtrl,
                    enabled: !guardando,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: p.onCard),
                    decoration: dec(
                      tipoDoc == 'cedula' ? 'Cédula *' : 'RNC *',
                      hint: tipoDoc == 'cedula'
                          ? '11 dígitos'
                          : '9 u 11 dígitos',
                    ),
                    onChanged: (_) {
                      if (errorDlg != null) setDlg(() => errorDlg = null);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: telCtrl,
                    enabled: !guardando,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(color: p.onCard),
                    decoration: dec('Teléfono empresa'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailCtrl,
                    enabled: !guardando,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: p.onCard),
                    decoration: dec('Correo empresa'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: dirCtrl,
                    enabled: !guardando,
                    style: TextStyle(color: p.onCard),
                    decoration: dec('Dirección / punto de recogida'),
                  ),
                  if (errorDlg != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorDlg!,
                      style: TextStyle(color: p.danger, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              TextButton(
                onPressed:
                    guardando ? null : () => Navigator.pop(ctx),
                child: Text('Cancelar', style: TextStyle(color: p.muted)),
              ),
              FilledButton(
                onPressed: guardando
                    ? null
                    : () async {
                        final nombre = nombreCtrl.text.trim();
                        final doc = docCtrl.text.replaceAll(RegExp(r'\D'), '');
                        if (nombre.length < 2) {
                          setDlg(
                            () => errorDlg = 'Escribe el nombre de la empresa.',
                          );
                          return;
                        }
                        final minDoc = tipoDoc == 'cedula' ? 11 : 9;
                        if (doc.length < minDoc) {
                          setDlg(
                            () => errorDlg = tipoDoc == 'cedula'
                                ? 'La cédula debe tener 11 dígitos.'
                                : 'El RNC debe tener al menos 9 dígitos.',
                          );
                          return;
                        }
                        final uid = FirebaseAuth.instance.currentUser?.uid;
                        if (uid == null) {
                          setDlg(
                            () => errorDlg =
                                'Tu sesión expiró. Volvé a entrar e intentá de nuevo.',
                          );
                          return;
                        }
                        setDlg(() {
                          guardando = true;
                          errorDlg = null;
                        });
                        try {
                          final id = await CorporativoRutaService.registrarEmpresa(
                            uidEncargado: uid,
                            nombreEmpresa: nombre,
                            tipoDocumento: tipoDoc,
                            documentoLegal: doc,
                            telefonoEmpresa: telCtrl.text.trim(),
                            emailEmpresa: emailCtrl.text.trim(),
                            direccion: dirCtrl.text.trim(),
                          );
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx, id);
                        } catch (e) {
                          if (!ctx.mounted) return;
                          final raw = e.toString().toLowerCase();
                          final permiso = raw.contains('permission-denied') ||
                              raw.contains('permission_denied');
                          setDlg(() {
                            guardando = false;
                            errorDlg = permiso
                                ? 'No tienes permiso para crear la empresa. '
                                    'Cerrá sesión, volvé a entrar e intentá de nuevo.'
                                : 'No se pudo crear la empresa: $e';
                          });
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: p.ctaBg,
                  foregroundColor: p.ctaFg,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(guardando ? 'Creando…' : 'Continuar'),
              ),
            ],
          ),
        );
      },
    );

    nombreCtrl.dispose();
    docCtrl.dispose();
    telCtrl.dispose();
    emailCtrl.dispose();
    dirCtrl.dispose();

    final id = (empresaId ?? '').trim();
    if (id.isEmpty) return null;
    return id;
  }

  bool _esNombreDemo(String nombre) {
    final t = nombre.trim().toLowerCase();
    return t == 'empresa demo rai' ||
        t.contains('demo rai') ||
        t == 'empresa demo';
  }

  Future<void> _dialogEditarEmpresa({bool forzarNombreReal = false}) async {
    final empresa = _empresa;
    final empresaId = _empresaId;
    if (empresa == null || empresaId == null) return;

    final nombreCtrl = TextEditingController(
      text: _esNombreDemo(empresa.nombre) ? '' : empresa.nombre,
    );
    final docCtrl = TextEditingController(text: empresa.documentoLegal);
    final telCtrl = TextEditingController(text: empresa.telefonoEmpresa);
    final emailCtrl = TextEditingController(text: empresa.emailEmpresa);
    final dirCtrl = TextEditingController(text: empresa.direccion);
    var tipoDoc =
        empresa.tipoDocumento.trim().isEmpty ? 'rnc' : empresa.tipoDocumento;
    String? errorDlg;
    var guardando = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: !forzarNombreReal,
      builder: (ctx) {
        final p = ctx.corporativoPalette;
        InputDecoration dec(String label, {String? hint}) => InputDecoration(
              labelText: label,
              hintText: hint,
              hintStyle: TextStyle(color: p.muted.withValues(alpha: 0.7)),
              labelStyle: TextStyle(color: p.muted),
              filled: true,
              fillColor: p.isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF8FAFC),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: p.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: p.primary, width: 1.6),
              ),
            );
        return StatefulBuilder(
          builder: (ctx, setDlg) => AlertDialog(
            backgroundColor: p.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: p.cardBorder),
            ),
            title: Text(
              forzarNombreReal
                  ? 'Pon el nombre real de tu empresa'
                  : 'Corregir datos de la empresa',
              style: TextStyle(
                color: p.onCard,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (forzarNombreReal) ...[
                    Text(
                      'Se quitó el nombre de prueba. Escribe el nombre comercial '
                      'real de tu empresa.',
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ] else ...[
                    Text(
                      'Podés corregir nombre, RNC/cédula y datos de contacto. '
                      'Si necesitás una empresa distinta, contactá a RAI.',
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    controller: nombreCtrl,
                    style: TextStyle(color: p.onCard),
                    decoration: dec(
                      'Nombre empresa *',
                      hint: 'Escribe el nombre de tu empresa',
                    ),
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) {
                      if (errorDlg != null) setDlg(() => errorDlg = null);
                    },
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'rnc', label: Text('RNC')),
                      ButtonSegment(value: 'cedula', label: Text('Cédula')),
                    ],
                    selected: {tipoDoc},
                    onSelectionChanged: (s) => setDlg(() => tipoDoc = s.first),
                    style: ButtonStyle(
                      foregroundColor:
                          WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return p.onPrimary;
                        }
                        return p.onCard;
                      }),
                      backgroundColor:
                          WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return p.ctaBg;
                        }
                        return p.primarySoft;
                      }),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: docCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: p.onCard),
                    decoration: dec(
                      tipoDoc == 'cedula' ? 'Cédula' : 'RNC',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: telCtrl,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(color: p.onCard),
                    decoration: dec('Teléfono empresa'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: p.onCard),
                    decoration: dec('Correo empresa'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: dirCtrl,
                    style: TextStyle(color: p.onCard),
                    decoration: dec('Dirección / punto de recogida'),
                  ),
                  if (errorDlg != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorDlg!,
                      style: TextStyle(color: p.danger, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              if (!forzarNombreReal)
                TextButton(
                  onPressed:
                      guardando ? null : () => Navigator.pop(ctx, false),
                  child: Text('Cancelar', style: TextStyle(color: p.muted)),
                ),
              FilledButton(
                onPressed: guardando
                    ? null
                    : () async {
                        final nombre = nombreCtrl.text.trim();
                        if (nombre.length < 2) {
                          setDlg(
                            () => errorDlg =
                                'Escribe el nombre de la empresa.',
                          );
                          return;
                        }
                        if (_esNombreDemo(nombre)) {
                          setDlg(
                            () => errorDlg =
                                'Usa el nombre real de tu empresa, no uno de prueba.',
                          );
                          return;
                        }
                        setDlg(() {
                          guardando = true;
                          errorDlg = null;
                        });
                        try {
                          await CorporativoRutaService.actualizarDatosEmpresa(
                            empresaId: empresaId,
                            nombreEmpresa: nombre,
                            tipoDocumento: tipoDoc,
                            documentoLegal: docCtrl.text.trim(),
                            telefonoEmpresa: telCtrl.text.trim(),
                            emailEmpresa: emailCtrl.text.trim(),
                            direccion: dirCtrl.text.trim(),
                          );
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          setDlg(() {
                            guardando = false;
                            errorDlg = 'No se pudo guardar: $e';
                          });
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: p.ctaBg,
                  foregroundColor: p.ctaFg,
                ),
                child: Text(guardando ? 'Guardando…' : 'Guardar'),
              ),
            ],
          ),
        );
      },
    );

    nombreCtrl.dispose();
    docCtrl.dispose();
    telCtrl.dispose();
    emailCtrl.dispose();
    dirCtrl.dispose();

    if (ok == true && mounted) {
      await _cargar();
    }
  }

  void _nuevaPlantilla() {
    final empresaId = _empresaId;
    if (empresaId == null) return;
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CorporativoPlantillaEditorPage(
          empresaId: empresaId,
          empresaNombre: _empresa?.nombre ?? '',
          empresa: _empresa,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;

    if (_cargando) {
      return corporativoResponsive(
        child: Scaffold(
          backgroundColor: p.scaffold,
          appBar: const RaiAppBar(
            title: 'Corporativo RAI',
            centerTitle: true,
            showBackWhenCanPop: true,
          ),
          body: Center(
            child: CircularProgressIndicator(color: p.primary),
          ),
        ),
      );
    }

    if (_empresaId == null || _empresa == null) {
      final email = FirebaseAuth.instance.currentUser?.email ?? '';
      return corporativoResponsive(
        child: Scaffold(
        backgroundColor: p.scaffold,
        appBar: const RaiAppBar(
          title: 'Corporativo RAI',
          centerTitle: true,
          showBackWhenCanPop: true,
        ),
        body: Container(
          width: double.infinity,
          decoration: BoxDecoration(gradient: p.heroGrad),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                return Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 32 : 20,
                      vertical: 24,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: corporativoCard(
                        context,
                        padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
                        borderColor: p.primary.withValues(alpha: 0.35),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  gradient: p.ctaGrad,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: p.ctaBg.withValues(alpha: 0.35),
                                      blurRadius: 18,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.apartment_rounded,
                                  color: Colors.white,
                                  size: 36,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'RAI Corporativo',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: p.onCard,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _errorCarga ??
                                  (_encargadoHabilitado
                                      ? 'Configura tu empresa para usar rutas corporativas.'
                                      : 'Registra tu empresa para programar rutas, '
                                          'ver el historial y gestionar la cuenta con RAI.'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _errorCarga != null ? p.danger : p.muted,
                                height: 1.45,
                                fontSize: 14,
                                fontWeight: _errorCarga != null
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            if (email.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: p.primarySoft,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: p.primary.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.mail_outline_rounded,
                                      size: 18,
                                      color: p.accent,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        email,
                                        style: TextStyle(
                                          color: p.onCard,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 22),
                            corporativoCtaButton(
                              context: context,
                              label: 'Registrar mi empresa',
                              icon: Icons.add_business_rounded,
                              onPressed: () async {
                                final id = await _dialogRegistrarEmpresa();
                                if (id == null || !mounted) return;
                                await _aplicarEmpresaRegistrada(id);
                              },
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Nombre, RNC o cédula y datos de contacto. '
                              'Luego firmás el contrato digital.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: p.muted,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 18),
                            corporativoSecondaryButton(
                              context: context,
                              label: 'Entrar con otra cuenta',
                              icon: Icons.logout_rounded,
                              onPressed: _cerrarSesion,
                            ),
                            const SizedBox(height: 6),
                            TextButton(
                              onPressed: () {
                                setState(() => _cargando = true);
                                _cargar();
                              },
                              child: Text(
                                'Ya me habilitaron · Reintentar',
                                style: TextStyle(
                                  color: p.accent,
                                  fontWeight: FontWeight.w700,
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
          ),
        ),
      ),
      );
    }

    if (!_empresa!.contratoDigitalFirmado) {
      return corporativoResponsive(
        child: ContratoCorporativoFirmaPage(
          empresaId: _empresaId!,
          nombreEmpresa: _empresa!.nombre,
          onFirmado: () async {
            if (!mounted) return;
            setState(() => _cargando = true);
            try {
              // Releer del servidor para no quedar trabado en la pantalla de firma.
              CorporativoEmpresa? emp =
                  await CorporativoRutaService.cargarEmpresa(
                _empresaId!,
                fromServer: true,
              );
              if (emp != null && !emp.contratoDigitalFirmado) {
                await Future<void>.delayed(const Duration(milliseconds: 600));
                emp = await CorporativoRutaService.cargarEmpresa(
                  _empresaId!,
                  fromServer: true,
                );
              }
              if (!mounted) return;
              setState(() {
                if (emp != null) {
                  _empresa = emp;
                  _encargadoHabilitado = true;
                  _empresaId = emp.id.isNotEmpty ? emp.id : _empresaId;
                }
                _cargando = false;
              });
              if (emp != null && emp.contratoDigitalFirmado) {
                _programarVinculoDeepLink();
              }
            } catch (_) {
              if (!mounted) return;
              setState(() => _cargando = false);
              await _cargar();
            }
          },
        ),
      );
    }

    return StreamBuilder<CorporativoEmpresa?>(
      stream: CorporativoRutaService.streamEmpresa(_empresaId!),
      initialData: _empresa,
      builder: (context, empresaSnap) {
        final empresa = empresaSnap.data ?? _empresa!;
        final periodo = empresa.periodoActual;
        final fmtMonto = NumberFormat.currency(
          locale: 'es_DO',
          symbol: 'RD\$',
          decimalDigits: 0,
        );
        final fmtFecha = DateFormat('EEE d MMM yyyy', 'es');
        final uid = FirebaseAuth.instance.currentUser?.uid;
        final perfilEnc = uid != null ? empresa.perfilEncargado(uid) : null;
        final encargadoLabel = perfilEnc?.nombre.isNotEmpty == true
            ? perfilEnc!.nombre
            : (empresa.encargadoUids.contains(uid ?? '')
                ? (FirebaseAuth.instance.currentUser?.displayName ??
                    FirebaseAuth.instance.currentUser?.email ??
                    'Encargado')
                : 'Encargado');

        return corporativoResponsive(
          child: Scaffold(
          backgroundColor: p.scaffold,
          appBar: RaiAppBar(
            title: 'Corporativo RAI',
            centerTitle: true,
            showBackWhenCanPop: true,
            actions: [
              IconButton(
                tooltip: 'Cerrar sesión',
                onPressed: _cerrarSesion,
                icon: Icon(Icons.logout_rounded, color: p.muted),
              ),
              if (_tab == 0)
                IconButton(
                  tooltip: 'Nueva ruta',
                  onPressed: _nuevaPlantilla,
                  icon: Icon(Icons.add_rounded, color: p.primary),
                ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final headerMax = (constraints.maxHeight * 0.40).clamp(120.0, 300.0);
              return Column(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: headerMax),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: corporativoCard(
                              context,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CorporativoEmpresaLogoCard(
                                        empresaId: empresa.id,
                                        nombreEmpresa: empresa.nombre,
                                        logoUrl: empresa.logoUrl,
                                        compacto: true,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: corporativoEllipsis(
                                                    empresa.nombre,
                                                    maxLines: 2,
                                                    style: TextStyle(
                                                      color: p.onCard,
                                                      fontWeight: FontWeight.w800,
                                                      fontSize: 17,
                                                    ),
                                                  ),
                                                ),
                                                IconButton(
                                                  tooltip: 'Editar empresa',
                                                  onPressed: () =>
                                                      _dialogEditarEmpresa(),
                                                  icon: Icon(
                                                    Icons.edit_outlined,
                                                    color: p.primary,
                                                    size: 20,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            if (empresa.documentoLegal.isNotEmpty)
                                              corporativoEllipsis(
                                                '${empresa.etiquetaDocumento}: ${empresa.documentoLegal}',
                                                maxLines: 1,
                                                style: TextStyle(
                                                  color: p.muted,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            corporativoEllipsis(
                                              'Encargado: $encargadoLabel',
                                              maxLines: 1,
                                              style: TextStyle(
                                                color: p.onCard,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: () => _dialogEditarEmpresa(),
                                      icon: Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                        color: p.primary,
                                      ),
                                      label: Text(
                                        'Corregir datos de la empresa',
                                        style: TextStyle(
                                          color: p.primary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 4,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '¿Otra empresa distinta? Contactá a RAI para activarla.',
                                    style: TextStyle(
                                      color: p.muted,
                                      fontSize: 11,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  LayoutBuilder(
                                    builder: (context, chipBox) {
                                      final narrow = chipBox.maxWidth < 340;
                                      final chips = [
                                        _resumenChip(
                                          context,
                                          icon: Icons.payments_outlined,
                                          label: 'Acumulado',
                                          valor: fmtMonto.format(
                                            periodo?.montoTotalRd ?? 0,
                                          ),
                                          destacado: true,
                                        ),
                                        _resumenChip(
                                          context,
                                          icon: Icons.route_outlined,
                                          label: 'Viajes',
                                          valor:
                                              '${periodo?.viajesCount ?? 0}',
                                        ),
                                      ];
                                      if (narrow) {
                                        return Column(
                                          children: [
                                            chips[0],
                                            const SizedBox(height: 8),
                                            chips[1],
                                          ],
                                        );
                                      }
                                      return Row(
                                        children: [
                                          Expanded(child: chips[0]),
                                          const SizedBox(width: 8),
                                          Expanded(child: chips[1]),
                                        ],
                                      );
                                    },
                                  ),
                                  if (periodo?.fin != null) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.event_available_outlined,
                                          size: 16,
                                          color: p.accent,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: corporativoEllipsis(
                                            'Pago / corte: ${fmtFecha.format(periodo!.fin!)}',
                                            maxLines: 2,
                                            style: TextStyle(
                                              color: p.accent,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (!empresa.activa)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.business_outlined,
                                      color: Colors.red.shade700, size: 22),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Tu empresa ya no está activa en RAI corporativo. '
                                      'Podés revisar historial y liquidaciones; para volver '
                                      'a operar contactá a RAI.',
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
                            )
                          else if (!empresa.contratoVigente)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.hourglass_top_rounded,
                                      color: Colors.orange, size: 22),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      empresa.contratoDigitalFirmado
                                          ? 'Contrato firmado. Pendiente: RAI debe activar el servicio '
                                              'para publicar rutas al chofer. Mientras, podés configurar rutas y pasajeros.'
                                          : 'Contrato pendiente de activación por RAI. '
                                              'Podés configurar rutas; la publicación arranca cuando RAI active el servicio.',
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
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: _tab,
                      children: [
                        CorporativoDashboardPage(
                          empresaId: _empresaId!,
                          empresa: empresa,
                        ),
                        CorporativoPlantillasListaPage(
                          empresaId: _empresaId!,
                          empresa: empresa,
                        ),
                        CorporativoHistorialPage(empresaId: _empresaId!),
                        _CuentaCorporativoTab(
                          empresaId: _empresaId!,
                          onEmpresaDadaDeBaja: () =>
                              _cargar(empresaIdConocido: _empresaId),
                          onCerrarSesion: _cerrarSesion,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            backgroundColor: p.card,
            indicatorColor: p.primarySoft,
            surfaceTintColor: Colors.transparent,
            height: 64,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined, color: p.muted),
                selectedIcon: Icon(Icons.dashboard, color: p.primary),
                label: 'Inicio',
              ),
              NavigationDestination(
                icon: Icon(Icons.route_outlined, color: p.muted),
                selectedIcon: Icon(Icons.route, color: p.primary),
                label: 'Rutas',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_outlined, color: p.muted),
                selectedIcon: Icon(Icons.history, color: p.primary),
                label: 'Historial',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined, color: p.muted),
                selectedIcon: Icon(Icons.receipt_long, color: p.primary),
                label: 'Cuenta',
              ),
            ],
          ),
        ),
        );
      },
    );
  }

  Widget _resumenChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String valor,
    bool destacado = false,
  }) {
    final p = context.corporativoPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: destacado ? p.primarySoft : p.scaffold,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: destacado ? p.primary : p.muted),
          const SizedBox(height: 4),
          corporativoEllipsis(
            label,
            maxLines: 1,
            style: TextStyle(color: p.muted, fontSize: 10),
          ),
          corporativoEllipsis(
            valor,
            maxLines: 1,
            style: TextStyle(
              color: destacado ? p.primary : p.onCard,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _CuentaCorporativoTab extends StatefulWidget {
  const _CuentaCorporativoTab({
    required this.empresaId,
    this.onEmpresaDadaDeBaja,
    this.onCerrarSesion,
  });

  final String empresaId;
  final VoidCallback? onEmpresaDadaDeBaja;
  final Future<void> Function()? onCerrarSesion;

  @override
  State<_CuentaCorporativoTab> createState() => _CuentaCorporativoTabState();
}

class _CuentaCorporativoTabState extends State<_CuentaCorporativoTab> {
  bool _exportando = false;
  String? _exportandoLiqId;
  bool _guardandoCondicionesPago = false;
  bool _dandoDeBaja = false;

  DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  Future<({
    List<Map<String, dynamic>> historial,
    List<Map<String, dynamic>> liqsPend,
    List<Map<String, dynamic>> liqsPagadas,
  })> _datosExportacion() async {
    final liqs = await CorporativoRutaService.streamLiquidaciones(
      widget.empresaId,
    ).first;
    final hist = await CorporativoRutaService.streamHistorial(
      widget.empresaId,
    ).first;
    final histExp = CorporativoRutaService.historialParaExport(hist);
    final liqsExp = CorporativoRutaService.liquidacionesParaExport(liqs);
    final pend = liqsExp
        .where(
          (l) =>
              (l['estado'] ?? '').toString().trim().toLowerCase() ==
              'pendiente_cobro',
        )
        .toList(growable: false);
    final pagadas = liqsExp
        .where((l) => (l['estado'] ?? '').toString().trim().toLowerCase() == 'pagado')
        .toList(growable: false);
    return (historial: histExp, liqsPend: pend, liqsPagadas: pagadas);
  }

  Future<void> _descargarFactura({
    required CorporativoEmpresa empresa,
    required FormatoLiquidacion formato,
    bool soloPeriodoActual = false,
  }) async {
    setState(() => _exportando = true);
    try {
      final datos = await _datosExportacion();
      await CorporativoExportService.descargarFacturaLiquidacion(
        empresa: empresa,
        periodo: empresa.periodoActual,
        historial: datos.historial,
        liquidacionesPendientes: datos.liqsPend,
        liquidacionesPagadas: datos.liqsPagadas,
        formato: formato,
        soloPeriodoActual: soloPeriodoActual,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo descargar: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Future<void> _descargarLiquidacionArchivada({
    required CorporativoEmpresa empresa,
    required Map<String, dynamic> liquidacion,
    required FormatoLiquidacion formato,
  }) async {
    final liqId = (liquidacion['_id'] ?? '').toString();
    setState(() => _exportandoLiqId = liqId);
    try {
      final datos = await _datosExportacion();
      await CorporativoExportService.descargarLiquidacionArchivada(
        empresa: empresa,
        liquidacion: liquidacion,
        formato: formato,
        historial: datos.historial,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo descargar: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportandoLiqId = null);
    }
  }

  void _mostrarOpcionesDescarga(
    BuildContext context,
    CorporativoEmpresa empresa, {
    Map<String, dynamic>? liquidacionArchivada,
  }) {
    final p = context.corporativoPalette;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                liquidacionArchivada == null
                    ? 'Descargar factura a liquidar'
                    : 'Descargar liquidación archivada',
                style: TextStyle(
                  color: p.onCard,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Para contabilidad y auditoría interna. '
                'Incluye cotejo de viajes y total acumulado.',
                style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.table_chart_outlined, color: p.primary),
                title: Text('Excel / CSV', style: TextStyle(color: p.onCard)),
                subtitle: Text(
                  'Importar en hoja de cálculo',
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Future<void>.delayed(const Duration(milliseconds: 120));
                  if (!mounted) return;
                  if (liquidacionArchivada != null) {
                    await _descargarLiquidacionArchivada(
                      empresa: empresa,
                      liquidacion: liquidacionArchivada,
                      formato: FormatoLiquidacion.csv,
                    );
                  } else {
                    await _descargarFactura(
                      empresa: empresa,
                      formato: FormatoLiquidacion.csv,
                    );
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.picture_as_pdf_outlined, color: p.primary),
                title: Text('Imprimible / PDF', style: TextStyle(color: p.onCard)),
                subtitle: Text(
                  'HTML para imprimir o guardar como PDF',
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Future<void>.delayed(const Duration(milliseconds: 120));
                  if (!mounted) return;
                  if (liquidacionArchivada != null) {
                    await _descargarLiquidacionArchivada(
                      empresa: empresa,
                      liquidacion: liquidacionArchivada,
                      formato: FormatoLiquidacion.html,
                    );
                  } else {
                    await _descargarFactura(
                      empresa: empresa,
                      formato: FormatoLiquidacion.html,
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    final fmtFecha = DateFormat('d MMM yyyy', 'es');
    final fmtMonto = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$',
      decimalDigits: 0,
    );

    return StreamBuilder<CorporativoEmpresa?>(
      stream: CorporativoRutaService.streamEmpresa(widget.empresaId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: p.primary));
        }
        final empresa = snap.data;
        if (empresa == null) {
          return Center(
            child: Text('Empresa no encontrada.', style: TextStyle(color: p.muted)),
          );
        }

        final periodo = empresa.periodoActual;
        final choferes = periodo?.porChofer.values.toList() ?? [];
        choferes.sort((a, b) => b.montoRd.compareTo(a.montoRd));
        final codigoPeriodo = (periodo?.codigoAcceso ?? '').trim();

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: CorporativoRutaService.streamLiquidacionesPendientes(
            widget.empresaId,
          ),
          builder: (context, liqPendSnap) {
            if (liqPendSnap.hasError) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  CorporativoCodigoVerificacionCard(
                    codigo: codigoPeriodo,
                    etiquetaCiclo: CorporativoCicloFacturacion.descripcion(
                      empresa.facturacionCicloDias,
                    ),
                  ),
                  const SizedBox(height: 16),
                  corporativoCard(
                    context,
                    child: Text(
                      'Estado de cuenta disponible, pero no se pudieron cargar '
                      'liquidaciones archivadas. Reintentá o pedí a RAI revisar permisos.\n'
                      '(${liqPendSnap.error})',
                      style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              );
            }
            final liqsPend = liqPendSnap.data ?? [];
            final deudaArchivada =
                CorporativoRutaService.sumaLiquidacionesPendientes(liqsPend);
            final totalDeuda = (periodo?.montoTotalRd ?? 0) + deudaArchivada;

            return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CorporativoEmpresaLogoCard(
              empresaId: widget.empresaId,
              nombreEmpresa: empresa.nombre,
              logoUrl: empresa.logoUrl,
            ),
            const SizedBox(height: 16),
            Text(
              'Estado de cuenta',
              style: TextStyle(
                color: p.onCard,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Liquidaciones, cortes y pagos a RAI',
              style: TextStyle(color: p.muted, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 14),
            CorporativoCodigoVerificacionCard(
              codigo: codigoPeriodo,
              etiquetaCiclo: CorporativoCicloFacturacion.descripcion(
                empresa.facturacionCicloDias,
              ),
              validoHasta: periodo?.fin,
              activo: periodo?.codigoActivo ?? false,
              estadoEtiqueta: (periodo?.codigoActivo ?? false)
                  ? 'Activo'
                  : 'Expirado — pagá para renovar',
            ),
            if (periodo?.fin != null) ...[
              const SizedBox(height: 16),
              CorporativoProximoPagoAnillo(
                fechaCorte: periodo!.fin!,
                fechaInicioPeriodo: periodo.inicio,
                cicloDias: empresa.facturacionCicloDias,
                montoRd: totalDeuda,
                formaPagoRai: empresa.formaPagoRai,
                onReportarPago: totalDeuda > 0
                    ? () async {
                        final ok = await mostrarPagoCorporativoSheet(
                          context: context,
                          empresaId: widget.empresaId,
                          empresa: empresa,
                          montoSugerido: totalDeuda,
                        );
                        if (ok == true && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Bauche enviado a RAI. Te confirmaremos cuando validen el pago.',
                              ),
                              backgroundColor: Colors.green.shade800,
                            ),
                          );
                        }
                      }
                    : null,
              ),
            ],
            const SizedBox(height: 16),
            corporativoCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estado de cuenta',
                    style: TextStyle(
                      color: p.onCard,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Facturación ${CorporativoCicloFacturacion.descripcion(empresa.facturacionCicloDias)}'
                    ' · ${CorporativoCicloFacturacion.etiquetaFormaPago(empresa.formaPagoRai)}',
                    style: TextStyle(color: p.muted, fontSize: 12),
                  ),
                  if (empresa.documentoLegal.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${empresa.etiquetaDocumento}: ${empresa.documentoLegal}',
                      style: TextStyle(
                        color: p.onCard,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _filaCuenta(
                    context,
                    'Viajes realizados',
                    '${periodo?.viajesCount ?? 0}',
                  ),
                  _filaCuenta(
                    context,
                    'Total período actual',
                    fmtMonto.format(periodo?.montoTotalRd ?? 0),
                    destacado: true,
                  ),
                  if (deudaArchivada > 0)
                    _filaCuenta(
                      context,
                      'Períodos anteriores pendientes',
                      fmtMonto.format(deudaArchivada),
                      destacado: true,
                    ),
                  if (totalDeuda > 0)
                    _filaCuenta(
                      context,
                      'Total a pagar a RAI',
                      fmtMonto.format(totalDeuda),
                      destacado: true,
                    ),
                  if (periodo?.inicio != null && periodo?.fin != null) ...[
                    const SizedBox(height: 8),
                    _filaCuenta(
                      context,
                      'Desde',
                      fmtFecha.format(periodo!.inicio!),
                    ),
                    _filaCuenta(
                      context,
                      'Próximo corte',
                      fmtFecha.format(periodo.fin!),
                    ),
                  ],
                ],
              ),
            ),
            if (choferes.isNotEmpty) ...[
              const SizedBox(height: 16),
              corporativoSectionTitle(context, 'Por chofer asignado'),
              corporativoCard(
                context,
                child: Column(
                  children: [
                    for (final ch in choferes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Icon(Icons.person_outline, color: p.primary, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ch.nombre,
                                    style: TextStyle(
                                      color: p.onCard,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '${ch.viajes} viaje${ch.viajes == 1 ? '' : 's'}',
                                    style: TextStyle(color: p.muted, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              fmtMonto.format(ch.montoRd),
                              style: TextStyle(
                                color: p.onCard,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            corporativoCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    empresa.nombre,
                    style: TextStyle(
                      color: p.onCard,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _filaCuenta(context, 'Encargados', '${empresa.encargadoUids.length}'),
                  const SizedBox(height: 8),
                  Text(
                    'Cada viaje completado suma al período. Al corte, RAI te envía el monto total a pagar por todas las rutas y choferes.',
                    style: TextStyle(color: p.muted, fontSize: 13, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            corporativoCard(
              context,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.description_outlined, color: p.primary),
                title: Text(
                  'Contrato de servicio corporativo',
                  style: TextStyle(
                    color: p.onCard,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  empresa.contratoDigitalFirmado
                      ? 'Firmado · v${empresa.contratoCorporativoVersion}'
                      : 'Pendiente de firma',
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
                trailing: Icon(Icons.open_in_new, color: p.muted, size: 20),
                onTap: () => abrirContratoCorporativoWeb(context),
              ),
            ),
            const SizedBox(height: 16),
            corporativoCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.receipt_long_outlined, color: p.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Factura a liquidar — auditoría',
                          style: TextStyle(
                            color: p.onCard,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Descarga el cotejo de lo acumulado (${CorporativoCicloFacturacion.etiqueta(empresa.facturacionCicloDias).toLowerCase()}) '
                    'con detalle de viajes, desglose por chofer y total a pagar a RAI. '
                    'Úsalo en tu contabilidad interna.',
                    style: TextStyle(color: p.muted, fontSize: 12, height: 1.4),
                  ),
                  if (totalDeuda > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: p.primarySoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Total consolidado a pagar a RAI: ${fmtMonto.format(totalDeuda)}',
                        style: TextStyle(
                          color: p.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _exportando
                          ? null
                          : () => _mostrarOpcionesDescarga(context, empresa),
                      icon: _exportando
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_outlined, size: 18),
                      label: Text(
                        _exportando
                            ? 'Preparando documento…'
                            : 'Descargar liquidación / factura',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _cardFrecuenciaLiquidacionRai(empresa),
            const SizedBox(height: 16),
            corporativoCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_balance_outlined, color: p.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Pagar a RAI',
                          style: TextStyle(
                            color: p.onCard,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Liquidación empresarial · '
                    '${CorporativoCicloFacturacion.descripcion(empresa.facturacionCicloDias)} · '
                    '${CorporativoCicloFacturacion.etiquetaFormaPago(empresa.formaPagoRai)}. '
                    'Transferí el monto a la cuenta RAI y adjuntá el bauche para validación.',
                    style: TextStyle(color: p.muted, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: p.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monto a liquidar',
                          style: TextStyle(color: p.muted, fontSize: 11),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fmtMonto.format(totalDeuda),
                          style: TextStyle(
                            color: p.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                          ),
                        ),
                        if (totalDeuda <= 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Aún no hay viajes cobrables en el período. '
                              'Igual podés abrir la cuenta RAI y probar el envío de bauche.',
                              style: TextStyle(
                                color: p.muted,
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  RaiCuentaDepositoPanel(
                    titulo: 'Cuenta empresarial RAI',
                    subtitulo:
                        'Open ASK Service SRL · pago de liquidación corporativa',
                    mostrarNota: true,
                    padding: const EdgeInsets.all(12),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final ok = await mostrarPagoCorporativoSheet(
                          context: context,
                          empresaId: widget.empresaId,
                          empresa: empresa,
                          montoSugerido: totalDeuda > 0 ? totalDeuda : 0,
                        );
                        if (ok == true && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Bauche enviado a RAI. Te confirmaremos cuando validen el pago.',
                              ),
                              backgroundColor: Colors.green.shade800,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: Text(
                        totalDeuda > 0
                            ? 'Enviar bauche · ${fmtMonto.format(totalDeuda)}'
                            : 'Ver cuenta RAI (sin factura pendiente)',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: CorporativoPagoService.streamPagos(widget.empresaId),
              builder: (context, pagoSnap) {
                final pagos = pagoSnap.data ?? [];
                if (pagos.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    corporativoSectionTitle(context, 'Pagos enviados a RAI'),
                    corporativoCard(
                      context,
                      child: Column(
                        children: pagos.take(5).map((pago) {
                          final monto =
                              (pago['montoRd'] as num?)?.toDouble() ?? 0;
                          final metodo = (pago['metodoPago'] ?? '').toString();
                          final estado = (pago['estado'] ?? '').toString();
                          final url =
                              (pago['comprobanteUrl'] ?? '').toString().trim();
                          final ref = (pago['referenciaBancaria'] ?? '')
                              .toString()
                              .trim();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${fmtMonto.format(monto)} · ${CorporativoMetodosPago.etiqueta(metodo)}',
                                        style: TextStyle(
                                          color: p.onCard,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        CorporativoPagoService.etiquetaEstado(
                                          estado,
                                        ),
                                        style: TextStyle(
                                          color: estado == 'validado'
                                              ? p.success
                                              : estado == 'rechazado'
                                                  ? Colors.red.shade700
                                                  : Colors.orange.shade800,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (ref.isNotEmpty)
                                        Text(
                                          'Ref: $ref',
                                          style: TextStyle(
                                            color: p.muted,
                                            fontSize: 11,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (url.isNotEmpty)
                                  IconButton(
                                    tooltip: 'Ver bauche',
                                    onPressed: () async {
                                      final uri = Uri.tryParse(url);
                                      if (uri != null) {
                                        await launchUrl(
                                          uri,
                                          mode: LaunchMode.externalApplication,
                                        );
                                      }
                                    },
                                    icon: Icon(
                                      Icons.image_outlined,
                                      color: p.primary,
                                      size: 20,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            corporativoSectionTitle(context, 'Liquidaciones anteriores'),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: CorporativoRutaService.streamLiquidaciones(widget.empresaId),
              builder: (context, liqSnap) {
                final liqs = liqSnap.data ?? [];
                if (liqs.isEmpty) {
                  return corporativoCard(
                    context,
                    child: Text(
                      'Sin liquidaciones archivadas aún.',
                      style: TextStyle(color: p.muted, fontSize: 13),
                    ),
                  );
                }
                return corporativoCard(
                  context,
                  child: Column(
                    children: liqs.take(6).map((lq) {
                      final monto = (lq['montoTotalRd'] as num?)?.toDouble() ?? 0;
                      final viajes = (lq['viajesCount'] as num?)?.toInt() ?? 0;
                      final estado = (lq['estado'] ?? '').toString().toLowerCase();
                      final ini = _ts(lq['periodoInicio']);
                      final fin = _ts(lq['periodoFin']);
                      final rango = ini != null && fin != null
                          ? '${fmtFecha.format(ini)} → ${fmtFecha.format(fin)}'
                          : 'Período archivado';
                      final etiquetaEstado = estado == 'pagado'
                          ? 'Pagado'
                          : estado == 'pendiente_cobro'
                              ? 'Pendiente de cobro'
                              : 'Pendiente';
                      final liqId = (lq['_id'] ?? '').toString();
                      final descargando = _exportandoLiqId == liqId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    rango,
                                    style: TextStyle(
                                      color: p.onCard,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '$viajes viaje(s) · ${fmtMonto.format(monto)}',
                                    style: TextStyle(color: p.muted, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              etiquetaEstado,
                              style: TextStyle(
                                color: estado == 'pagado'
                                    ? p.success
                                    : Colors.orange.shade800,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (estado == 'pendiente_cobro' && monto > 0)
                              IconButton(
                                tooltip: 'Pagar y enviar bauche',
                                onPressed: () => mostrarPagoCorporativoSheet(
                                  context: context,
                                  empresaId: widget.empresaId,
                                  empresa: empresa,
                                  montoSugerido: monto,
                                  liquidacionId: liqId,
                                  tituloPeriodo: 'Liquidación $rango',
                                ),
                                icon: Icon(
                                  Icons.payments_outlined,
                                  color: p.primary,
                                  size: 20,
                                ),
                              ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Descargar para auditoría',
                              onPressed: descargando || liqId.isEmpty
                                  ? null
                                  : () => _mostrarOpcionesDescarga(
                                        context,
                                        empresa,
                                        liquidacionArchivada: lq,
                                      ),
                              icon: descargando
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: p.primary,
                                      ),
                                    )
                                  : Icon(Icons.download_outlined, color: p.primary, size: 20),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            _cardDarDeBajaEmpresa(empresa, totalDeuda),
            const SizedBox(height: 16),
            _cardCerrarSesionEncargado(),
          ],
            );
          },
        );
      },
    );
  }

  Widget _cardCerrarSesionEncargado() {
    final p = context.corporativoPalette;
    return corporativoCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.logout_rounded, color: p.muted, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cerrar sesión',
                  style: TextStyle(
                    color: p.onCard,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Salís de la cuenta encargado y volvés a la pantalla de entrada. '
            'No cancela el servicio corporativo de la empresa.',
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.onCerrarSesion == null
                  ? null
                  : () => widget.onCerrarSesion!(),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Cerrar sesión'),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.onCard,
                side: BorderSide(color: p.cardBorder),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardDarDeBajaEmpresa(
    CorporativoEmpresa empresa,
    double deudaPendienteRd,
  ) {
    final p = context.corporativoPalette;
    final fmtMonto = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');

    if (!empresa.activa) {
      return corporativoCard(
        context,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: p.muted, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Esta empresa ya fue dada de baja del servicio corporativo RAI. '
                'Para reactivarla contactá a tu ejecutivo.',
                style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    return corporativoCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.logout_rounded, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Salir del servicio RAI',
                  style: TextStyle(
                    color: p.onCard,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Si tu empresa ya no quiere operar en RAI corporativo, podés darla de baja. '
            'Se cancelan envíos de hoy pendientes, se eliminan las rutas guardadas '
            'y los choferes dejan de recibir asignaciones. El historial y liquidaciones '
            'pendientes se conservan.',
            style: TextStyle(color: p.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _dandoDeBaja
                  ? null
                  : () => _darDeBajaEmpresa(empresa, deudaPendienteRd, fmtMonto),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade800,
                side: BorderSide(color: Colors.red.shade300),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _dandoDeBaja
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.red.shade800,
                      ),
                    )
                  : const Icon(Icons.business_center_outlined, size: 18),
              label: Text(
                _dandoDeBaja
                    ? 'Procesando baja…'
                    : 'Dar de baja mi empresa en RAI',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _darDeBajaEmpresa(
    CorporativoEmpresa empresa,
    double deudaPendienteRd,
    NumberFormat fmtMonto,
  ) async {
    final motivo = await confirmarDarDeBajaEmpresaCorporativo(
      context,
      nombreEmpresa: empresa.nombre,
      deudaPendienteRd: deudaPendienteRd,
      fmtMonto: fmtMonto,
    );
    if (motivo == null || !mounted) return;

    setState(() => _dandoDeBaja = true);
    try {
      final res = await CorporativoRutaService.darDeBajaEmpresa(
        empresaId: widget.empresaId,
        motivo: motivo.isEmpty ? null : motivo,
      );
      if (!mounted) return;
      final extra = res.viajesCancelados > 0
          ? ' Se cancelaron ${res.viajesCancelados} envío(s) de hoy.'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tu empresa ya no está en RAI corporativo.$extra '
            'Para volver a operar contactá a RAI.',
          ),
          backgroundColor: Colors.green.shade800,
          duration: const Duration(seconds: 5),
        ),
      );
      widget.onEmpresaDadaDeBaja?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _dandoDeBaja = false);
    }
  }

  Widget _cardFrecuenciaLiquidacionRai(CorporativoEmpresa empresa) {
    final p = context.corporativoPalette;
    final ciclo =
        CorporativoCicloFacturacion.normalizarDias(empresa.facturacionCicloDias);
    var forma = empresa.formaPagoRai.trim().toLowerCase();
    if (forma.isEmpty || !CorporativoCicloFacturacion.formaPagoValida(forma)) {
      forma = 'transferencia';
    }
    final esPreset = CorporativoCicloFacturacion.esPreset(ciclo);

    return corporativoCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_outlined, color: p.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Condiciones de facturación con RAI',
                  style: TextStyle(
                    color: p.onCard,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              if (_guardandoCondicionesPago)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Modelo de negocio B2B para empresas reales: elegí cada cuánto '
            'RAI corta y liquida la cuenta de transporte de tu empresa '
            '(semanal, quincenal o mensual). La frecuencia se aplica al '
            'próximo período de facturación.',
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 14),
          Text(
            'Ciclo de liquidación empresarial',
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
                  onSelected: _guardandoCondicionesPago
                      ? null
                      : (_) => _guardarCondicionesPagoRapido(
                            empresa: empresa,
                            dias: pre.dias,
                            formaPagoRai: forma,
                          ),
                ),
              ChoiceChip(
                label: Text(
                  esPreset ? 'Cada N días…' : 'Personalizado ($ciclo días)',
                ),
                selected: !esPreset,
                onSelected: _guardandoCondicionesPago
                    ? null
                    : (_) => _dialogCondicionesPagoRai(empresa),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Forma de pago',
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
              for (final f in CorporativoCicloFacturacion.formasPago)
                ChoiceChip(
                  label: Text(f.label),
                  selected: forma == f.id,
                  selectedColor:
                      CorporativoCicloFacturacion.colorFormaPago(f.id),
                  backgroundColor:
                      CorporativoCicloFacturacion.colorFormaPagoFondo(f.id),
                  side: BorderSide(
                    color: CorporativoCicloFacturacion.colorFormaPago(f.id),
                  ),
                  labelStyle: TextStyle(
                    color: forma == f.id
                        ? Colors.white
                        : CorporativoCicloFacturacion.colorFormaPago(f.id),
                    fontWeight: FontWeight.w700,
                  ),
                  checkmarkColor: Colors.white,
                  onSelected: _guardandoCondicionesPago
                      ? null
                      : (_) => _guardarCondicionesPagoRapido(
                            empresa: empresa,
                            dias: ciclo,
                            formaPagoRai: f.id,
                          ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Vigente: ${CorporativoCicloFacturacion.descripcion(ciclo)} · '
            '${CorporativoCicloFacturacion.etiquetaFormaPago(forma)}. '
            'Al corte, se genera la liquidación pendiente y se abre el '
            'siguiente ciclo con esta frecuencia.',
            style: TextStyle(color: p.muted, fontSize: 11, height: 1.3),
          ),
        ],
      ),
    );
  }

  Future<void> _guardarCondicionesPagoRapido({
    required CorporativoEmpresa empresa,
    required int dias,
    required String formaPagoRai,
  }) async {
    if (_guardandoCondicionesPago) return;
    final mismoCiclo =
        CorporativoCicloFacturacion.normalizarDias(empresa.facturacionCicloDias) ==
            CorporativoCicloFacturacion.normalizarDias(dias);
    final mismaForma =
        empresa.formaPagoRai.trim().toLowerCase() == formaPagoRai.trim().toLowerCase();
    if (mismoCiclo && mismaForma) return;

    setState(() => _guardandoCondicionesPago = true);
    try {
      await CorporativoRutaService.actualizarCondicionesPagoRai(
        empresaId: empresa.id,
        facturacionCicloDias: dias,
        formaPagoRai: formaPagoRai,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Liquidación: ${CorporativoCicloFacturacion.descripcion(dias)} · '
            '${CorporativoCicloFacturacion.etiquetaFormaPago(formaPagoRai)}',
          ),
          backgroundColor: Colors.teal.shade800,
        ),
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
      if (mounted) setState(() => _guardandoCondicionesPago = false);
    }
  }

  Future<void> _dialogCondicionesPagoRai(CorporativoEmpresa empresa) async {
    final p = context.corporativoPalette;
    var ciclo = CorporativoCicloFacturacion.normalizarDias(
      empresa.facturacionCicloDias,
    );
    var presetKey = CorporativoCicloFacturacion.esPreset(ciclo)
        ? ciclo
        : -1; // -1 = personalizado
    final diasCtrl = TextEditingController(
      text: '$ciclo',
    );
    var forma = empresa.formaPagoRai.trim().toLowerCase();
    if (forma.isEmpty || !CorporativoCicloFacturacion.formaPagoValida(forma)) {
      forma = 'transferencia';
    }
    String? error;
    var guardando = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            return AlertDialog(
              backgroundColor: p.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: p.cardBorder),
              ),
              title: Text(
                'Facturación empresarial',
                style: TextStyle(
                  color: p.onCard,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Ciclo de liquidación (días entre cortes)',
                      style: TextStyle(
                        color: p.onCard,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final pre in CorporativoCicloFacturacion.presets)
                          ChoiceChip(
                            label: Text(pre.label),
                            selected: presetKey == pre.dias,
                            onSelected: (_) => setDlg(() {
                              presetKey = pre.dias;
                              ciclo = pre.dias;
                              diasCtrl.text = '${pre.dias}';
                              error = null;
                            }),
                          ),
                        ChoiceChip(
                          label: const Text('Cada N días'),
                          selected: presetKey == -1,
                          onSelected: (_) => setDlg(() {
                            presetKey = -1;
                            error = null;
                          }),
                        ),
                      ],
                    ),
                    if (presetKey == -1) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: diasCtrl,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: p.onCard),
                        decoration: InputDecoration(
                          labelText: 'Días entre cortes',
                          helperText:
                              '${CorporativoCicloFacturacion.diasMin}–${CorporativoCicloFacturacion.diasMax}',
                          labelStyle: TextStyle(color: p.muted),
                          helperStyle: TextStyle(color: p.muted, fontSize: 11),
                          filled: true,
                          fillColor: p.isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (t) {
                          final n = int.tryParse(t.trim());
                          if (n != null) {
                            setDlg(() {
                              ciclo = CorporativoCicloFacturacion.normalizarDias(n);
                              error = null;
                            });
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      'Forma de pago preferida',
                      style: TextStyle(
                        color: p.onCard,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final f in CorporativoCicloFacturacion.formasPago)
                          ChoiceChip(
                            label: Text(f.label),
                            selected: forma == f.id,
                            selectedColor:
                                CorporativoCicloFacturacion.colorFormaPago(f.id),
                            backgroundColor:
                                CorporativoCicloFacturacion.colorFormaPagoFondo(
                              f.id,
                            ),
                            side: BorderSide(
                              color: CorporativoCicloFacturacion.colorFormaPago(
                                f.id,
                              ),
                            ),
                            labelStyle: TextStyle(
                              color: forma == f.id
                                  ? Colors.white
                                  : CorporativoCicloFacturacion.colorFormaPago(
                                      f.id,
                                    ),
                              fontWeight: FontWeight.w700,
                            ),
                            checkmarkColor: Colors.white,
                            onSelected: (_) => setDlg(() {
                              forma = f.id;
                              error = null;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No cambia el corte que está abierto ahora. Solo define '
                      'cómo se abre el siguiente período y cómo tienen que pagar.',
                      style: TextStyle(color: p.muted, fontSize: 12, height: 1.3),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(error!, style: TextStyle(color: p.danger, fontSize: 13)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: guardando ? null : () => Navigator.pop(ctx, false),
                  child: Text('Cancelar', style: TextStyle(color: p.muted)),
                ),
                FilledButton(
                  onPressed: guardando
                      ? null
                      : () async {
                          final dias = presetKey == -1
                              ? CorporativoCicloFacturacion.normalizarDias(
                                  int.tryParse(diasCtrl.text.trim()),
                                )
                              : CorporativoCicloFacturacion.normalizarDias(
                                  presetKey,
                                );
                          setDlg(() {
                            guardando = true;
                            error = null;
                          });
                          try {
                            await CorporativoRutaService
                                .actualizarCondicionesPagoRai(
                              empresaId: empresa.id,
                              facturacionCicloDias: dias,
                              formaPagoRai: forma,
                            );
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (e) {
                            setDlg(() {
                              guardando = false;
                              error = 'No se pudo guardar: $e';
                            });
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: p.ctaBg,
                    foregroundColor: p.ctaFg,
                  ),
                  child: Text(guardando ? 'Guardando…' : 'Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    diasCtrl.dispose();
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Condiciones de pago a RAI actualizadas'),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  Widget _filaCuenta(
    BuildContext context,
    String k,
    String v, {
    bool destacado = false,
  }) {
    final p = context.corporativoPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, box) {
          final narrow = box.maxWidth < 320;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k, style: TextStyle(color: p.muted, fontSize: 12)),
                const SizedBox(height: 2),
                corporativoEllipsis(
                  v,
                  maxLines: 2,
                  style: TextStyle(
                    color: p.onCard,
                    fontWeight: destacado ? FontWeight.w800 : FontWeight.w600,
                    fontSize: destacado ? 17 : 13,
                  ),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                flex: 5,
                child: corporativoEllipsis(
                  k,
                  maxLines: 2,
                  style: TextStyle(color: p.muted, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 6,
                child: corporativoEllipsis(
                  v,
                  maxLines: 2,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: p.onCard,
                    fontWeight: destacado ? FontWeight.w800 : FontWeight.w600,
                    fontSize: destacado ? 17 : 13,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
