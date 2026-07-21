import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/servicios/corporativo_admin_service.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_corporativo_plantillas.dart';
import 'package:flygo_nuevo/utils/corporativo_ciclo_facturacion.dart';
import 'package:flygo_nuevo/widgets/admin_app_bar.dart';
import 'package:flygo_nuevo/widgets/admin_guia_uso.dart';
import 'package:flygo_nuevo/widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';

/// Admin: alta de empresas corporativas, activar contrato y gestión de encargados.
class AdminCorporativoEmpresasPage extends StatefulWidget {
  const AdminCorporativoEmpresasPage({super.key});

  @override
  State<AdminCorporativoEmpresasPage> createState() =>
      _AdminCorporativoEmpresasPageState();
}

class _EmpresaFormData {
  _EmpresaFormData({
    this.nombre = '',
    this.tipoDocumento = 'rnc',
    this.documentoLegal = '',
    this.telefonoEmpresa = '',
    this.emailEmpresa = '',
    this.direccion = '',
    this.encargadoEmail = '',
    this.encargadoUid = '',
    this.encargadoNombre = '',
    this.encargadoCedula = '',
    this.encargadoTelefono = '',
    this.cicloDias = 15,
    this.formaPagoRai = 'transferencia',
    this.contratoMeses = 12,
    this.tarifaViajeContratadaRd = 0,
  });

  final String nombre;
  final String tipoDocumento;
  final String documentoLegal;
  final String telefonoEmpresa;
  final String emailEmpresa;
  final String direccion;
  final String encargadoEmail;
  final String encargadoUid;
  final String encargadoNombre;
  final String encargadoCedula;
  final String encargadoTelefono;
  final int cicloDias;
  final String formaPagoRai;
  final int contratoMeses;
  final double tarifaViajeContratadaRd;

  factory _EmpresaFormData.fromEmpresa(CorporativoEmpresa e) {
    final enc = e.encargadoUids.isNotEmpty
        ? e.perfilEncargado(e.encargadoUids.first)
        : null;
    final forma = e.formaPagoRai.trim().isEmpty
        ? 'transferencia'
        : e.formaPagoRai.trim().toLowerCase();
    return _EmpresaFormData(
      nombre: e.nombre,
      tipoDocumento: e.tipoDocumento,
      documentoLegal: e.documentoLegal,
      telefonoEmpresa: e.telefonoEmpresa,
      emailEmpresa: e.emailEmpresa,
      direccion: e.direccion,
      encargadoUid: e.encargadoUids.isNotEmpty ? e.encargadoUids.first : '',
      encargadoEmail: enc?.email ?? '',
      encargadoNombre: enc?.nombre ?? '',
      encargadoCedula: enc?.cedula ?? '',
      encargadoTelefono: enc?.telefono ?? '',
      cicloDias: e.facturacionCicloDias,
      formaPagoRai: forma,
      tarifaViajeContratadaRd: e.tarifaViajeContratadaRd,
    );
  }
}

class _AdminCorporativoEmpresasPageState extends State<AdminCorporativoEmpresasPage> {
  String? _procesandoId;
  final _filtroCtrl = TextEditingController();
  String _filtro = '';

  final _fmtFecha = DateFormat('d MMM yyyy', 'es');

  @override
  void dispose() {
    _filtroCtrl.dispose();
    super.dispose();
  }

  bool _empresaCoincideFiltro(CorporativoEmpresa e, String raw) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return true;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (e.nombre.toLowerCase().contains(q)) return true;
    if (e.documentoLegal.toLowerCase().contains(q)) return true;
    if (digits.length >= 4 && e.documentoLegal.contains(digits)) return true;
    if (e.telefonoEmpresa.toLowerCase().contains(q)) return true;
    if (e.emailEmpresa.toLowerCase().contains(q)) return true;
    if (e.direccion.toLowerCase().contains(q)) return true;
    for (final p in e.encargadosConPerfil) {
      if (p.nombre.toLowerCase().contains(q)) return true;
      if (p.email.toLowerCase().contains(q)) return true;
      if (p.telefono.toLowerCase().contains(q)) return true;
      if (p.cedula.toLowerCase().contains(q)) return true;
      if (digits.length >= 4 && p.telefono.contains(digits)) return true;
      if (digits.length >= 4 && p.cedula.contains(digits)) return true;
    }
    return false;
  }

  Future<_EmpresaFormData?> _dialogEmpresa({
    required String titulo,
    _EmpresaFormData? inicial,
    bool incluirEncargado = true,
    bool incluirContrato = true,
  }) async {
    final nombreCtrl = TextEditingController(text: inicial?.nombre ?? '');
    final docCtrl = TextEditingController(text: inicial?.documentoLegal ?? '');
    final telEmpCtrl = TextEditingController(text: inicial?.telefonoEmpresa ?? '');
    final emailEmpCtrl = TextEditingController(text: inicial?.emailEmpresa ?? '');
    final dirCtrl = TextEditingController(text: inicial?.direccion ?? '');
    final busquedaCtrl = TextEditingController(
      text: inicial?.encargadoEmail.isNotEmpty == true
          ? inicial!.encargadoEmail
          : (inicial?.encargadoNombre ?? ''),
    );
    final encEmailCtrl = TextEditingController(text: inicial?.encargadoEmail ?? '');
    final encNombreCtrl = TextEditingController(text: inicial?.encargadoNombre ?? '');
    final encCedulaCtrl = TextEditingController(text: inicial?.encargadoCedula ?? '');
    final encTelCtrl = TextEditingController(text: inicial?.encargadoTelefono ?? '');
    final cicloCtrl = TextEditingController(
      text: '${inicial?.cicloDias ?? 15}',
    );
    final mesesCtrl = TextEditingController(
      text: '${inicial?.contratoMeses ?? 12}',
    );
    final tarifaCtrl = TextEditingController(
      text: (inicial?.tarifaViajeContratadaRd ?? 0) > 0
          ? (inicial!.tarifaViajeContratadaRd).toStringAsFixed(0)
          : '',
    );
    var tipoDoc = inicial?.tipoDocumento ?? 'rnc';
    var formaPagoRai = (inicial?.formaPagoRai.trim().isNotEmpty == true)
        ? inicial!.formaPagoRai.trim().toLowerCase()
        : 'transferencia';
    String? encargadoUid = inicial?.encargadoUid;
    String? lookupMsg;
    var buscando = false;
    List<CorporativoUsuarioCandidato> candidatos = [];
    List<CorporativoEmpresaCandidato> empresasHit = [];

    void aplicarCandidato(CorporativoUsuarioCandidato c) {
      encargadoUid = c.uid;
      if (c.email.isNotEmpty) encEmailCtrl.text = c.email;
      if (c.nombre.isNotEmpty) encNombreCtrl.text = c.nombre;
      if (c.cedula.isNotEmpty) encCedulaCtrl.text = c.cedula;
      if (c.telefono.isNotEmpty) encTelCtrl.text = c.telefono;
      if (c.empresaNombre.isNotEmpty && nombreCtrl.text.trim().isEmpty) {
        nombreCtrl.text = c.empresaNombre;
      }
    }

    final result = await showDialog<_EmpresaFormData>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AdminUi.dialogSurface(ctx),
          title: Text(titulo, style: TextStyle(color: AdminUi.onCard(ctx))),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Datos de la empresa (nombre comercial / RNC). '
                    'Buscá el encargado por nombre, correo, cédula, teléfono '
                    'o por la empresa a la que ya está vinculado.',
                    style: TextStyle(
                      color: AdminUi.secondary(ctx),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre empresa *'),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'rnc', label: Text('RNC')),
                      ButtonSegment(value: 'cedula', label: Text('Cédula')),
                    ],
                    selected: {tipoDoc},
                    onSelectionChanged: (s) => setDlg(() => tipoDoc = s.first),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: docCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: tipoDoc == 'cedula' ? 'Cédula *' : 'RNC *',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: telEmpCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Teléfono empresa'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailEmpCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo empresa'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: dirCtrl,
                    decoration: const InputDecoration(labelText: 'Dirección / sede'),
                  ),
                  if (incluirEncargado) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Encargado corporativo',
                      style: TextStyle(
                        color: AdminUi.onCard(ctx),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: busquedaCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Buscar encargado',
                              hintText: 'Nombre, correo, cédula, tel o empresa',
                              prefixIcon: Icon(Icons.search),
                            ),
                            textCapitalization: TextCapitalization.none,
                            onSubmitted: (_) async {
                              // trigger same as button via setDlg path below
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: buscando
                              ? null
                              : () async {
                                  final q = busquedaCtrl.text.trim();
                                  if (q.length < 2) {
                                    setDlg(
                                      () => lookupMsg = 'Mínimo 2 caracteres',
                                    );
                                    return;
                                  }
                                  setDlg(() {
                                    buscando = true;
                                    lookupMsg = 'Buscando…';
                                    candidatos = [];
                                    empresasHit = [];
                                  });
                                  try {
                                    final res = await CorporativoAdminService
                                        .buscarCorporativo(busqueda: q);
                                    setDlg(() {
                                      candidatos = res.usuarios;
                                      empresasHit = res.empresas;
                                      if (res.usuarios.length == 1) {
                                        aplicarCandidato(res.usuarios.first);
                                        lookupMsg =
                                            'Seleccionado: ${res.usuarios.first.nombre.isNotEmpty ? res.usuarios.first.nombre : res.usuarios.first.email}';
                                      } else if (res.usuarios.isEmpty &&
                                          res.empresas.isEmpty) {
                                        lookupMsg =
                                            'Sin resultados. Debe existir en RAI '
                                            '(Google/correo/tel).';
                                      } else {
                                        lookupMsg =
                                            '${res.usuarios.length} persona(s)'
                                            '${res.empresas.isNotEmpty ? ' · ${res.empresas.length} empresa(s)' : ''}. Elegí una.';
                                      }
                                    });
                                  } catch (e) {
                                    setDlg(() => lookupMsg = '$e');
                                  } finally {
                                    setDlg(() => buscando = false);
                                  }
                                },
                          child: buscando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Buscar'),
                        ),
                      ],
                    ),
                    if (lookupMsg != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        lookupMsg!,
                        style: TextStyle(
                          color: lookupMsg!.startsWith('Seleccionado')
                              ? Colors.teal
                              : AdminUi.secondary(ctx),
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (empresasHit.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Empresas encontradas',
                        style: TextStyle(
                          color: AdminUi.onCard(ctx),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      ...empresasHit.map(
                        (emp) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.business_outlined, size: 20),
                          title: Text(emp.empresaNombre),
                          subtitle: Text(
                            [
                              if (emp.documentoLegal.isNotEmpty)
                                emp.documentoLegal,
                              emp.activa ? 'activa' : 'desactivada',
                            ].join(' · '),
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () {
                            if (nombreCtrl.text.trim().isEmpty) {
                              nombreCtrl.text = emp.empresaNombre;
                            }
                            if (docCtrl.text.trim().isEmpty &&
                                emp.documentoLegal.isNotEmpty) {
                              docCtrl.text = emp.documentoLegal;
                            }
                            setDlg(() {
                              lookupMsg =
                                  'Empresa «${emp.empresaNombre}» — elegí encargado abajo si aparece';
                            });
                          },
                        ),
                      ),
                    ],
                    if (candidatos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...candidatos.map((c) {
                        final sel = encargadoUid == c.uid;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: sel ? Colors.teal : AdminUi.borderSubtle(ctx),
                            ),
                            color: sel
                                ? Colors.teal.withValues(alpha: 0.08)
                                : null,
                          ),
                          child: ListTile(
                            dense: true,
                            onTap: () => setDlg(() {
                              aplicarCandidato(c);
                              lookupMsg =
                                  'Seleccionado: ${c.nombre.isNotEmpty ? c.nombre : c.email}';
                            }),
                            leading: Icon(
                              sel
                                  ? Icons.check_circle
                                  : Icons.person_outline,
                              color: sel ? Colors.teal : AdminUi.muted(ctx),
                            ),
                            title: Text(
                              c.nombre.isNotEmpty ? c.nombre : 'Usuario RAI',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              c.subtitulo,
                              style: TextStyle(
                                color: AdminUi.secondary(ctx),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: encEmailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo encargado',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: encNombreCtrl,
                      decoration: const InputDecoration(labelText: 'Nombre encargado'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: encCedulaCtrl,
                      decoration: const InputDecoration(labelText: 'Cédula encargado'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: encTelCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Teléfono encargado'),
                    ),
                  ],
                  if (incluirContrato) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: cicloCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Ciclo facturación (días)',
                        helperText: '7=semanal · 15=quincenal · 30=mensual (1–90)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Forma de pago a RAI',
                        style: TextStyle(
                          color: AdminUi.secondary(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final f in CorporativoCicloFacturacion.formasPago)
                          ChoiceChip(
                            label: Text(
                              f.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: formaPagoRai == f.id
                                    ? Colors.white
                                    : CorporativoCicloFacturacion.colorFormaPago(
                                        f.id,
                                      ),
                              ),
                            ),
                            selected: formaPagoRai == f.id,
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
                            checkmarkColor: Colors.white,
                            onSelected: (_) =>
                                setDlg(() => formaPagoRai = f.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: mesesCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Duración contrato (meses)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: tarifaCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tarifa contratada / viaje RD\$',
                        hintText: 'Ej: 4500 (opcional al crear)',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (nombreCtrl.text.trim().length < 2 ||
                    docCtrl.text.trim().length < 9) {
                  setDlg(() => lookupMsg = 'Completa nombre y RNC/cédula');
                  return;
                }
                if (incluirEncargado &&
                    encEmailCtrl.text.trim().isEmpty &&
                    (encargadoUid == null || encargadoUid!.isEmpty)) {
                  setDlg(
                    () => lookupMsg =
                        'Buscá y seleccioná el encargado (nombre, correo, tel…)',
                  );
                  return;
                }
                Navigator.pop(
                  ctx,
                  _EmpresaFormData(
                    nombre: nombreCtrl.text.trim(),
                    tipoDocumento: tipoDoc,
                    documentoLegal: docCtrl.text.trim(),
                    telefonoEmpresa: telEmpCtrl.text.trim(),
                    emailEmpresa: emailEmpCtrl.text.trim(),
                    direccion: dirCtrl.text.trim(),
                    encargadoEmail: encEmailCtrl.text.trim(),
                    encargadoUid: encargadoUid ?? '',
                    encargadoNombre: encNombreCtrl.text.trim(),
                    encargadoCedula: encCedulaCtrl.text.trim(),
                    encargadoTelefono: encTelCtrl.text.trim(),
                    cicloDias: CorporativoCicloFacturacion.normalizarDias(
                      int.tryParse(cicloCtrl.text),
                    ),
                    formaPagoRai: formaPagoRai,
                    contratoMeses: int.tryParse(mesesCtrl.text) ?? 12,
                    tarifaViajeContratadaRd:
                        double.tryParse(tarifaCtrl.text.trim()) ?? 0,
                  ),
                );
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  Future<void> _crearEmpresa() async {
    final data = await _dialogEmpresa(
      titulo: 'Nueva empresa corporativa',
      incluirEncargado: true,
      incluirContrato: true,
    );
    if (data == null || !mounted) return;

    setState(() => _procesandoId = '__crear__');
    try {
      final id = await CorporativoAdminService.crearEmpresa(
        nombreEmpresa: data.nombre,
        encargadoUid: data.encargadoUid,
        encargadoEmail: data.encargadoEmail,
        tipoDocumento: data.tipoDocumento,
        documentoLegal: data.documentoLegal,
        telefonoEmpresa: data.telefonoEmpresa,
        emailEmpresa: data.emailEmpresa,
        direccion: data.direccion,
        encargadoNombre: data.encargadoNombre,
        encargadoCedula: data.encargadoCedula,
        encargadoTelefono: data.encargadoTelefono,
        facturacionCicloDias: data.cicloDias,
        formaPagoRai: data.formaPagoRai,
        contratoMeses: data.contratoMeses,
      );
      if (data.tarifaViajeContratadaRd > 0 ||
          data.formaPagoRai.trim().isNotEmpty) {
        await CorporativoAdminService.actualizarEmpresa(
          empresaId: id,
          tarifaViajeContratadaRd: data.tarifaViajeContratadaRd > 0
              ? data.tarifaViajeContratadaRd
              : null,
          formaPagoRai: data.formaPagoRai,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Empresa «${data.nombre}» creada. '
            'Encargado: ${data.encargadoNombre.isNotEmpty ? data.encargadoNombre : data.encargadoEmail}. '
            'Activa el contrato para que opere.',
          ),
          backgroundColor: Colors.green.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade800),
      );
    } finally {
      if (mounted) setState(() => _procesandoId = null);
    }
  }

  Future<void> _editarEmpresa(CorporativoEmpresa empresa) async {
    final data = await _dialogEmpresa(
      titulo: 'Editar empresa',
      inicial: _EmpresaFormData.fromEmpresa(empresa),
      incluirEncargado: false,
      incluirContrato: true,
    );
    if (data == null || !mounted) return;

    setState(() => _procesandoId = empresa.id);
    try {
      await CorporativoAdminService.actualizarEmpresa(
        empresaId: empresa.id,
        nombreEmpresa: data.nombre,
        tipoDocumento: data.tipoDocumento,
        documentoLegal: data.documentoLegal,
        telefonoEmpresa: data.telefonoEmpresa,
        emailEmpresa: data.emailEmpresa,
        direccion: data.direccion,
        facturacionCicloDias: data.cicloDias,
        formaPagoRai: data.formaPagoRai,
        tarifaViajeContratadaRd: data.tarifaViajeContratadaRd,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Empresa actualizada (ciclo, forma de pago y tarifa)'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade800),
      );
    } finally {
      if (mounted) setState(() => _procesandoId = null);
    }
  }

  Future<void> _activarContrato(CorporativoEmpresa empresa) async {
    final vigente = empresa.contratoVigente;
    final tarifaCtrl = TextEditingController(
      text: empresa.tarifaViajeContratadaRd > 0
          ? empresa.tarifaViajeContratadaRd.toStringAsFixed(0)
          : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminUi.dialogSurface(ctx),
        title: Text(
          vigente ? 'Cambiar tarifa contratada' : 'Activar contrato',
          style: TextStyle(color: AdminUi.onCard(ctx)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              vigente
                  ? '${empresa.nombre}\nActualiza la tarifa por viaje acordada.'
                  : '${empresa.nombre}\nDefine la tarifa por viaje acordada con la empresa.',
              style: TextStyle(color: AdminUi.secondary(ctx), height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tarifaCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Tarifa por viaje RD\$',
                hintText: 'Ej: 4500',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(vigente ? 'Guardar tarifa' : 'Activar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _procesandoId = empresa.id);
    try {
      if (vigente) {
        await CorporativoAdminService.actualizarEmpresa(
          empresaId: empresa.id,
          tarifaViajeContratadaRd: double.tryParse(tarifaCtrl.text.trim()) ?? 0,
        );
      } else {
        await CorporativoAdminService.activarContrato(
          empresaId: empresa.id,
          tarifaViajeContratadaRd: double.tryParse(tarifaCtrl.text.trim()) ?? 0,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            vigente
                ? 'Tarifa actualizada: ${empresa.nombre}'
                : 'Contrato activado: ${empresa.nombre}',
          ),
          backgroundColor: Colors.green.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade800),
      );
    } finally {
      if (mounted) setState(() => _procesandoId = null);
    }
  }

  Future<void> _agregarEncargado(CorporativoEmpresa empresa) async {
    final busquedaCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final nombreCtrl = TextEditingController();
    final cedulaCtrl = TextEditingController();
    final telCtrl = TextEditingController();
    String? encargadoUid;
    String? lookupMsg;
    var buscando = false;
    List<CorporativoUsuarioCandidato> candidatos = [];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AdminUi.dialogSurface(ctx),
          title: const Text('Agregar encargado'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Empresa: ${empresa.nombre}',
                  style: TextStyle(
                    color: AdminUi.secondary(ctx),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: busquedaCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Buscar',
                          hintText: 'Nombre, correo, cédula, tel o empresa',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: buscando
                          ? null
                          : () async {
                              final q = busquedaCtrl.text.trim();
                              if (q.length < 2) {
                                setDlg(() => lookupMsg = 'Mínimo 2 caracteres');
                                return;
                              }
                              setDlg(() {
                                buscando = true;
                                lookupMsg = 'Buscando…';
                                candidatos = [];
                              });
                              try {
                                final res =
                                    await CorporativoAdminService.buscarCorporativo(
                                  busqueda: q,
                                );
                                setDlg(() {
                                  candidatos = res.usuarios;
                                  if (res.usuarios.length == 1) {
                                    final c = res.usuarios.first;
                                    encargadoUid = c.uid;
                                    emailCtrl.text = c.email;
                                    nombreCtrl.text = c.nombre;
                                    cedulaCtrl.text = c.cedula;
                                    telCtrl.text = c.telefono;
                                    lookupMsg =
                                        'Seleccionado: ${c.nombre.isNotEmpty ? c.nombre : c.email}';
                                  } else if (res.usuarios.isEmpty) {
                                    lookupMsg = 'Sin resultados';
                                  } else {
                                    lookupMsg =
                                        '${res.usuarios.length} resultados — elegí uno';
                                  }
                                });
                              } catch (e) {
                                setDlg(() => lookupMsg = '$e');
                              } finally {
                                setDlg(() => buscando = false);
                              }
                            },
                      child: buscando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Buscar'),
                    ),
                  ],
                ),
                if (lookupMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(lookupMsg!, style: const TextStyle(fontSize: 11)),
                  ),
                if (candidatos.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...candidatos.map((c) {
                    final sel = encargadoUid == c.uid;
                    return ListTile(
                      dense: true,
                      selected: sel,
                      onTap: () => setDlg(() {
                        encargadoUid = c.uid;
                        emailCtrl.text = c.email;
                        nombreCtrl.text = c.nombre;
                        cedulaCtrl.text = c.cedula;
                        telCtrl.text = c.telefono;
                        lookupMsg =
                            'Seleccionado: ${c.nombre.isNotEmpty ? c.nombre : c.email}';
                      }),
                      leading: Icon(
                        sel ? Icons.check_circle : Icons.person_outline,
                        color: sel ? Colors.teal : null,
                      ),
                      title: Text(
                        c.nombre.isNotEmpty ? c.nombre : 'Usuario RAI',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(c.subtitulo, style: const TextStyle(fontSize: 11)),
                    );
                  }),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cedulaCtrl,
                  decoration: const InputDecoration(labelText: 'Cédula'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: telCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Agregar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _procesandoId = empresa.id);
    try {
      await CorporativoAdminService.agregarEncargado(
        empresaId: empresa.id,
        encargadoUid: encargadoUid ?? '',
        encargadoEmail: emailCtrl.text,
        encargadoNombre: nombreCtrl.text,
        encargadoCedula: cedulaCtrl.text,
        encargadoTelefono: telCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Encargado agregado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade800),
      );
    } finally {
      if (mounted) setState(() => _procesandoId = null);
    }
  }

  Future<void> _sincronizarEncargados(CorporativoEmpresa empresa) async {
    setState(() => _procesandoId = empresa.id);
    try {
      await CorporativoAdminService.sincronizarEncargados(empresa.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Encargados de «${empresa.nombre}» actualizados desde su perfil RAI',
          ),
          backgroundColor: Colors.teal.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade800),
      );
    } finally {
      if (mounted) setState(() => _procesandoId = null);
    }
  }

  Future<void> _desactivarEmpresa(CorporativoEmpresa empresa) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminUi.dialogSurface(ctx),
        title: const Text('Desactivar empresa'),
        content: Text(
          '¿Desactivar «${empresa.nombre}»?\n\n'
          'Deja de operar (contrato y publicación). '
          'No se borra el historial ni las rutas; podés reactivarla después.',
          style: TextStyle(color: AdminUi.secondary(ctx), height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _procesandoId = empresa.id);
    try {
      await CorporativoAdminService.desactivarEmpresa(empresa.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Empresa «${empresa.nombre}» desactivada'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade800),
      );
    } finally {
      if (mounted) setState(() => _procesandoId = null);
    }
  }

  Future<void> _reactivarEmpresa(CorporativoEmpresa empresa) async {
    setState(() => _procesandoId = empresa.id);
    try {
      await CorporativoAdminService.reactivarEmpresa(empresa.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '«${empresa.nombre}» reactivada. Activá el contrato si hace falta.',
          ),
          backgroundColor: Colors.green.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade800),
      );
    } finally {
      if (mounted) setState(() => _procesandoId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      appBar: const AdminAppBar(title: 'Empresas corporativas', guiaId: AdminGuiaIds.empresasCorp),
      drawer: const AdminDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _procesandoId == '__crear__' ? null : _crearEmpresa,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Nueva empresa'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('empresas_corporativas')
            .limit(80)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Text(
                'Sin empresas. Creá una con «Nueva empresa».',
                style: TextStyle(color: AdminUi.secondary(context)),
              ),
            );
          }

          final empresas = docs.map(CorporativoEmpresa.fromDoc).toList()
            ..sort((a, b) {
              if (a.activa != b.activa) return a.activa ? -1 : 1;
              return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
            });
          final filtradas = empresas
              .where((e) => _empresaCoincideFiltro(e, _filtro))
              .toList(growable: false);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Text(
                'Servicio contratado (como giras)',
                style: TextStyle(
                  color: AdminUi.onCard(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Filtrá por empresa, RNC, encargado, correo o teléfono. '
                'Al crear/vincular, Buscar acepta nombre, correo, cédula, tel o empresa.',
                style: TextStyle(
                  color: AdminUi.secondary(context),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _filtroCtrl,
                decoration: InputDecoration(
                  labelText: 'Buscar en la lista',
                  hintText: 'Empresa, encargado, correo, RNC, teléfono…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _filtro.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _filtroCtrl.clear();
                            setState(() => _filtro = '');
                          },
                        ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _filtro = v),
              ),
              const SizedBox(height: 16),
              if (filtradas.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Ninguna empresa coincide con «$_filtro».',
                    style: TextStyle(color: AdminUi.secondary(context)),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ...filtradas.map(_tarjeta),
            ],
          );
        },
      ),
    );
  }

  Widget _tarjeta(CorporativoEmpresa e) {
    final procesando = _procesandoId == e.id;
    final vigente = e.contratoVigente;
    final encargados = e.encargadosConPerfil;
    return Opacity(
      opacity: e.activa ? 1 : 0.72,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AdminUi.card(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: !e.activa
                ? Colors.red.withValues(alpha: 0.35)
                : vigente
                    ? Colors.teal.withValues(alpha: 0.5)
                    : AdminUi.borderSubtle(context),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    e.nombre,
                    style: TextStyle(
                      color: AdminUi.onCard(context),
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: !e.activa
                        ? Colors.red.withValues(alpha: 0.12)
                        : vigente
                            ? Colors.teal.withValues(alpha: 0.15)
                            : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    !e.activa
                        ? 'Desactivada'
                        : vigente
                            ? 'Contrato activo'
                            : 'Pendiente activar',
                    style: TextStyle(
                      color: !e.activa
                          ? Colors.red.shade700
                          : vigente
                              ? Colors.teal
                              : Colors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.indigo.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.indigo.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Encargado${encargados.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: Colors.indigo.shade800,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (encargados.isEmpty)
                    Text(
                      'Sin encargado — usá «Encargado» y Buscar '
                      '(nombre, correo, tel, cédula o empresa)',
                      style: TextStyle(
                        color: AdminUi.secondary(context),
                        fontSize: 12,
                      ),
                    )
                  else
                    ...encargados.map((p) {
                      final nombre = p.nombre.trim().isNotEmpty
                          ? p.nombre.trim()
                          : 'Sin nombre (sincronizá perfil)';
                      final line2 = [
                        if (p.telefono.trim().isNotEmpty) p.telefono.trim(),
                        if (p.email.trim().isNotEmpty) p.email.trim(),
                      ].join(' · ');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nombre,
                              style: TextStyle(
                                color: AdminUi.onCard(context),
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            if (line2.isNotEmpty)
                              Text(
                                line2,
                                style: TextStyle(
                                  color: AdminUi.secondary(context),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (e.documentoLegal.isNotEmpty)
              Text(
                '${e.etiquetaDocumento}: ${e.documentoLegal}',
                style: TextStyle(
                  color: AdminUi.onCard(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            Text(
              'Ciclo ${CorporativoCicloFacturacion.descripcion(e.facturacionCicloDias)}'
              ' · ${CorporativoCicloFacturacion.etiquetaFormaPago(e.formaPagoRai)}'
              '${e.telefonoEmpresa.isNotEmpty ? ' · Tel ${e.telefonoEmpresa}' : ''}',
              style: TextStyle(color: AdminUi.secondary(context), fontSize: 12),
            ),
            if (e.direccion.isNotEmpty)
              Text(
                e.direccion,
                style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
              ),
            if (e.contratoHasta != null)
              Text(
                'Contrato hasta: ${_fmtFecha.format(e.contratoHasta!)}',
                style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
              ),
            if (e.tarifaViajeContratadaRd > 0)
              Text(
                'Tarifa contratada: RD\$ ${e.tarifaViajeContratadaRd.toStringAsFixed(0)} / viaje',
                style: TextStyle(
                  color: Colors.teal.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (e.activa && !vigente)
                  FilledButton.icon(
                    onPressed: procesando ? null : () => _activarContrato(e),
                    icon: const Icon(Icons.verified_outlined, size: 18),
                    label: const Text('Activar contrato'),
                  ),
                if (e.activa && vigente)
                  OutlinedButton.icon(
                    onPressed: procesando ? null : () => _activarContrato(e),
                    icon: const Icon(Icons.price_change_outlined, size: 18),
                    label: const Text('Cambiar tarifa'),
                  ),
                if (e.activa)
                  OutlinedButton.icon(
                    onPressed: procesando ? null : () => _editarEmpresa(e),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Editar datos'),
                  ),
                if (e.activa)
                  OutlinedButton.icon(
                    onPressed: procesando ? null : () => _agregarEncargado(e),
                    icon: const Icon(Icons.person_add_outlined, size: 18),
                    label: const Text('Encargado'),
                  ),
                if (e.activa && e.encargadoUids.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed:
                        procesando ? null : () => _sincronizarEncargados(e),
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('Sync perfil'),
                  ),
                if (e.activa)
                  OutlinedButton.icon(
                    onPressed: procesando
                        ? null
                        : () {
                            Navigator.push<void>(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => AdminCorporativoPlantillasPage(
                                  empresaId: e.id,
                                  empresaNombre: e.nombre,
                                ),
                              ),
                            );
                          },
                    icon: const Icon(Icons.alt_route, size: 18),
                    label: const Text('Rutas / chofer'),
                  ),
                if (e.activa)
                  OutlinedButton.icon(
                    onPressed: procesando ? null : () => _desactivarEmpresa(e),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Desactivar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                    ),
                  ),
                if (!e.activa)
                  FilledButton.icon(
                    onPressed: procesando ? null : () => _reactivarEmpresa(e),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Reactivar'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
