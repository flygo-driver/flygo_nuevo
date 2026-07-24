import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flygo_nuevo/servicios/flygo_storage.dart';

import '../../widgets/admin_app_bar.dart';
import 'package:flygo_nuevo/widgets/admin_guia_uso.dart';
import '../../widgets/admin_drawer.dart';
import 'admin_expediente_chofer_utils.dart';
import 'admin_ui_theme.dart';

class RevisionDocumentosAdmin extends StatefulWidget {
  const RevisionDocumentosAdmin({super.key});

  @override
  State<RevisionDocumentosAdmin> createState() =>
      _RevisionDocumentosAdminState();
}

class _RevisionDocumentosAdminState extends State<RevisionDocumentosAdmin>
    with SingleTickerProviderStateMixin {
  final _db = FirebaseFirestore.instance;
  final Set<String> _uidsProcesando = <String>{};
  final TextEditingController _buscarCtrl = TextEditingController();
  late final TabController _tabCtrl;
  AdminLineaChoferFiltro _filtroLinea = AdminLineaChoferFiltro.todos;
  String _buscar = '';

  static final DateFormat _fechaFmt = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _buscarCtrl.dispose();
    super.dispose();
  }

  String get _docsEstadoQuery =>
      _tabCtrl.index == 0 ? 'en_revision' : 'rechazado';

  String _mensajeFirebase(FirebaseException e) {
    final m = e.message?.trim();
    if (m != null && m.isNotEmpty) return m;
    return e.code;
  }

  Future<void> _abrirUrl(BuildContext context, String url) async {
    final u = Uri.tryParse(url.trim());
    if (u == null ||
        !(u.hasScheme && (u.scheme == 'http' || u.scheme == 'https'))) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enlace no válido'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    try {
      final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el enlace'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el enlace'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _aprobar(String uid) async {
    if (_uidsProcesando.contains(uid)) return;
    setState(() => _uidsProcesando.add(uid));
    try {
      await _db.collection('usuarios').doc(uid).set({
        'docsEstado': 'aprobado',
        'estadoDocumentos': 'aprobado',
        'documentosCompletos': true,
        'puedeRecibirViajes': true,
        'disponible': true,
        'docsComentarioAdmin': FieldValue.delete(),
        'docsVerificadoEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expediente aprobado'),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensajeFirebase(e)),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _uidsProcesando.remove(uid));
    }
  }

  Future<void> _rechazar(String uid) async {
    if (_uidsProcesando.contains(uid)) return;

    final controller = TextEditingController();
    try {
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return AlertDialog(
            backgroundColor: AdminUi.dialogSurface(ctx),
            title: Text(
              'Rechazar expediente',
              style: TextStyle(color: AdminUi.onCard(ctx)),
            ),
            content: SingleChildScrollView(
              child: TextField(
                controller: controller,
                maxLines: 4,
                style: TextStyle(color: AdminUi.onCard(ctx)),
                decoration: InputDecoration(
                  hintText: 'Motivo del rechazo (obligatorio)',
                  hintStyle: TextStyle(
                    color: AdminUi.secondary(ctx).withValues(alpha: 0.85),
                  ),
                  filled: true,
                  fillColor: AdminUi.inputFill(ctx),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AdminUi.borderSubtle(ctx)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AdminUi.borderSubtle(ctx)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: cs.primary, width: 1.4),
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancelar',
                  style: TextStyle(color: AdminUi.secondary(ctx)),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                ),
                child: const Text('Rechazar'),
              ),
            ],
          );
        },
      );

      if (ok != true) return;

      final motivo = controller.text.trim();
      if (motivo.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Escribe el motivo del rechazo antes de confirmar.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      setState(() => _uidsProcesando.add(uid));
      try {
        await _db.collection('usuarios').doc(uid).set({
          'docsEstado': 'rechazado',
          'estadoDocumentos': 'rechazado',
          'documentosCompletos': false,
          'puedeRecibirViajes': false,
          'disponible': false,
          'docsComentarioAdmin': motivo,
          'docsRevisadoEn': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Expediente rechazado'),
            backgroundColor: Colors.orange,
          ),
        );
      } on FirebaseException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensajeFirebase(e)),
            backgroundColor: Colors.red,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      } finally {
        if (mounted) setState(() => _uidsProcesando.remove(uid));
      }
    } finally {
      controller.dispose();
    }
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filtrarYOrdenar(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> raw,
  ) {
    final list = raw.where((doc) {
      final d = doc.data();
      if (!AdminExpedienteChoferUtils.esExpedienteTaxistaOperativo(d)) {
        return false;
      }
      if (!AdminExpedienteChoferUtils.coincideFiltroLinea(d, _filtroLinea)) {
        return false;
      }
      return AdminExpedienteChoferUtils.coincideBusqueda(d, doc.id, _buscar);
    }).toList()
      ..sort((a, b) => AdminExpedienteChoferUtils.fechaOrden(b.data())
          .compareTo(AdminExpedienteChoferUtils.fechaOrden(a.data())));
    return list;
  }

  Widget _chipFiltro(
    AdminLineaChoferFiltro filtro,
    String label,
    int count,
  ) {
    final selected = _filtroLinea == filtro;
    return FilterChip(
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: (_) => setState(() => _filtroLinea = filtro),
      selectedColor: AdminUi.accentGreen(context).withValues(alpha: 0.25),
      checkmarkColor: AdminUi.accentGreen(context),
      labelStyle: TextStyle(
        color: selected ? AdminUi.onCard(context) : AdminUi.secondary(context),
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: AdminAppBar(
        guiaId: AdminGuiaIds.expedientes,
        title: 'Expedientes choferes',
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AdminUi.accentGreen(context),
          unselectedLabelColor: AdminUi.tabUnselected(context),
          indicatorColor: AdminUi.accentGreen(context),
          tabs: const [
            Tab(text: 'En revisión'),
            Tab(text: 'Rechazados'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: TextField(
              controller: _buscarCtrl,
              style: TextStyle(color: AdminUi.onCard(context)),
              decoration: InputDecoration(
                hintText: 'Buscar nombre, email, teléfono, placa o UID…',
                hintStyle: TextStyle(
                  color: AdminUi.secondary(context).withValues(alpha: 0.85),
                ),
                prefixIcon: Icon(Icons.search, color: AdminUi.secondary(context)),
                filled: true,
                fillColor: AdminUi.inputFill(context),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AdminUi.borderSubtle(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AdminUi.borderSubtle(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.4,
                  ),
                ),
              ),
              onChanged: (v) => setState(() => _buscar = v),
            ),
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db
                .collection('usuarios')
                .where('docsEstado', isEqualTo: _docsEstadoQuery)
                .snapshots(),
            builder: (context, countSnap) {
              final raw = countSnap.data?.docs ?? const [];
              final operativos = raw
                  .map((e) => e.data())
                  .where(AdminExpedienteChoferUtils.esExpedienteTaxistaOperativo)
                  .toList();
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Row(
                  children: [
                    _chipFiltro(
                      AdminLineaChoferFiltro.todos,
                      'Todos',
                      operativos.length,
                    ),
                    const SizedBox(width: 6),
                    _chipFiltro(
                      AdminLineaChoferFiltro.normal,
                      'Normal',
                      AdminExpedienteChoferUtils.contarPorLinea(
                        operativos,
                        AdminLineaChoferFiltro.normal,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _chipFiltro(
                      AdminLineaChoferFiltro.motor,
                      'Motor',
                      AdminExpedienteChoferUtils.contarPorLinea(
                        operativos,
                        AdminLineaChoferFiltro.motor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _chipFiltro(
                      AdminLineaChoferFiltro.bolaAhorro,
                      'Bola',
                      AdminExpedienteChoferUtils.contarPorLinea(
                        operativos,
                        AdminLineaChoferFiltro.bolaAhorro,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Turismo no aparece aquí — usa «Solicitudes turismo» en el menú.',
                style: TextStyle(color: AdminUi.muted(context), fontSize: 11),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db
                  .collection('usuarios')
                  .where('docsEstado', isEqualTo: _docsEstadoQuery)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: AdminUi.progressAccent(context),
                    ),
                  );
                }

                if (snap.hasError) {
                  final err = snap.error;
                  final String msg = err is FirebaseException
                      ? _mensajeFirebase(err)
                      : err.toString();
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.cloud_off_outlined,
                            size: 48,
                            color: AdminUi.secondary(context),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No se pudieron cargar los expedientes.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AdminUi.onCard(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            msg,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AdminUi.secondary(context),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final docs = _filtrarYOrdenar(
                  snap.data?.docs ??
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                );

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      _tabCtrl.index == 0
                          ? 'No hay expedientes en revisión con este filtro.'
                          : 'No hay expedientes rechazados con este filtro.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AdminUi.secondary(context)),
                    ),
                  );
                }

                final bool muchos = docs.length > 80;
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: docs.length + (muchos ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (BuildContext context, int i) {
                    if (muchos && i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 4),
                        child: Text(
                          '${docs.length} resultados — usa el buscador para acotar.',
                          style: TextStyle(
                            color: AdminUi.muted(context),
                            fontSize: 12,
                          ),
                        ),
                      );
                    }
                    final idx = muchos ? i - 1 : i;
                    final doc = docs[idx];
                    final d = doc.data();
                    final uid = doc.id;
                    return _ExpedienteChoferCard(
                      data: d,
                      uid: uid,
                      enRevision: _tabCtrl.index == 0,
                      procesando: _uidsProcesando.contains(uid),
                      fechaFmt: _fechaFmt,
                      onAbrirUrl: (url) => _abrirUrl(context, url),
                      onAprobar: () => _aprobar(uid),
                      onRechazar: () => _rechazar(uid),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpedienteChoferCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String uid;
  final bool enRevision;
  final bool procesando;
  final DateFormat fechaFmt;
  final void Function(String url) onAbrirUrl;
  final VoidCallback onAprobar;
  final VoidCallback onRechazar;

  const _ExpedienteChoferCard({
    required this.data,
    required this.uid,
    required this.enRevision,
    required this.procesando,
    required this.fechaFmt,
    required this.onAbrirUrl,
    required this.onAprobar,
    required this.onRechazar,
  });

  @override
  Widget build(BuildContext context) {
    final nombre = (data['nombre'] ?? '').toString();
    final email = (data['email'] ?? '').toString();
    final telefono = (data['telefono'] ?? '').toString();
    final map = AdminExpedienteChoferUtils.docsMap(data);
    final licenciaUrl = (map['licenciaUrl'] ?? '').toString();
    final matriculaUrl = (map['matriculaUrl'] ?? '').toString();
    final seguroUrl = (map['seguroUrl'] ?? '').toString();
    final fotoVehiculoUrl = (map['fotoVehiculoUrl'] ?? '').toString();
    final placaUrl = (map['placaUrl'] ?? '').toString();
    final docsOk = AdminExpedienteChoferUtils.documentosCompletosCount(data);
    final motivoRechazo = (data['docsComentarioAdmin'] ?? '').toString().trim();
    final fecha = AdminExpedienteChoferUtils.fechaOrden(data);
    final lineaColor = AdminExpedienteChoferUtils.lineaColor(data);
    final lineaLabel = AdminExpedienteChoferUtils.lineaEtiqueta(data);

    Widget thumb(String label, String url, String tipoDoc) {
      final bool okUrl = AdminExpedienteChoferUtils.urlAbrible(url);
      final bool esFirestore = RaiDocUrl.isFirestoreDoc(url);

      Widget imagenCuerpo() {
        if (!okUrl) {
          return Center(
            child: Icon(Icons.broken_image, color: AdminUi.muted(context)),
          );
        }
        if (esFirestore) {
          return FutureBuilder<Uint8List?>(
            future: FlygoStorage.cargarDocImagen(uid: uid, tipo: tipoDoc),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AdminUi.progressAccent(context),
                    ),
                  ),
                );
              }
              final bytes = snap.data;
              if (bytes == null || bytes.isEmpty) {
                return Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: AdminUi.muted(context),
                  ),
                );
              }
              return Image.memory(bytes, fit: BoxFit.cover);
            },
          );
        }
        return Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: AdminUi.muted(context),
            ),
          ),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AdminUi.progressAccent(context),
                ),
              ),
            );
          },
        );
      }

      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AdminUi.inputFill(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AdminUi.borderSubtle(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AdminUi.secondary(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: 4 / 3,
                child: GestureDetector(
                  onTap: !okUrl || esFirestore ? null : () => onAbrirUrl(url),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      color: AdminUi.card(context),
                      child: imagenCuerpo(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                okUrl ? 'OK' : 'Falta',
                style: TextStyle(
                  color: okUrl
                      ? AdminUi.progressAccent(context)
                      : const Color(0xFFFF5252),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: AdminUi.card(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre.isNotEmpty ? nombre : uid,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AdminUi.onCard(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AdminUi.muted(context),
                            fontSize: 12,
                          ),
                        ),
                      if (telefono.isNotEmpty)
                        Text(
                          telefono,
                          style: TextStyle(
                            color: AdminUi.secondary(context),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: lineaColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: lineaColor.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        AdminExpedienteChoferUtils.lineaIcono(data),
                        size: 14,
                        color: lineaColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        lineaLabel,
                        style: TextStyle(
                          color: lineaColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              AdminExpedienteChoferUtils.vehiculoResumen(data),
              style: TextStyle(
                color: AdminUi.secondary(context),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Docs $docsOk/5',
                  style: TextStyle(
                    color: docsOk == 5
                        ? AdminUi.progressAccent(context)
                        : const Color(0xFFFF5252),
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  fecha.millisecondsSinceEpoch > 0
                      ? fechaFmt.format(fecha)
                      : 'Sin fecha',
                  style: TextStyle(color: AdminUi.muted(context), fontSize: 11),
                ),
              ],
            ),
            if (!enRevision && motivoRechazo.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'Motivo: $motivoRechazo',
                  style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                thumb('Licencia', licenciaUrl, 'licencia'),
                const SizedBox(width: 8),
                thumb('Matrícula', matriculaUrl, 'matricula'),
                const SizedBox(width: 8),
                thumb('Seguro', seguroUrl, 'seguro'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                thumb('Foto vehículo', fotoVehiculoUrl, 'fotoVehiculo'),
                const SizedBox(width: 8),
                thumb('Placa', placaUrl, 'placa'),
                const Spacer(),
              ],
            ),
            if (enRevision) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: procesando ? null : onRechazar,
                      icon: procesando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFFF5252),
                              ),
                            )
                          : const Icon(Icons.close),
                      label: Text(procesando ? 'Procesando…' : 'Rechazar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF5252),
                        side: const BorderSide(color: Color(0xFFFF5252)),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: procesando ? null : onAprobar,
                      icon: procesando
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AdminUi.progressAccent(context),
                              ),
                            )
                          : const Icon(Icons.check),
                      label: Text(procesando ? 'Procesando…' : 'Aprobar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.green,
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
