// lib/pantallas/admin/aprobar_choferes_turismo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/modelo/vehiculo_turismo.dart';
import 'package:flygo_nuevo/servicios/solicitud_turismo_repo.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/admin_drawer.dart';
import 'admin_expediente_chofer_utils.dart';
import 'admin_solicitud_turismo_utils.dart';
import 'admin_ui_theme.dart';

class AprobarChoferesTurismo extends StatefulWidget {
  const AprobarChoferesTurismo({super.key});

  @override
  State<AprobarChoferesTurismo> createState() => _AprobarChoferesTurismoState();
}

class _AprobarChoferesTurismoState extends State<AprobarChoferesTurismo>
    with SingleTickerProviderStateMixin {
  final Set<String> _idsProcesando = <String>{};
  final TextEditingController _buscarCtrl = TextEditingController();
  late final TabController _tabCtrl;
  AdminTipoVehiculoTurismoFiltro _filtroTipo = AdminTipoVehiculoTurismoFiltro.todos;
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


  String _mensajeFirebase(FirebaseException e) {
    final m = e.message?.trim();
    if (m != null && m.isNotEmpty) return m;
    return e.code;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filtrarYOrdenar(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> raw,
  ) {
    return raw.where((doc) {
      final d = doc.data();
      if (!AdminSolicitudTurismoUtils.coincideFiltroTipo(d, _filtroTipo)) {
        return false;
      }
      return AdminSolicitudTurismoUtils.coincideBusqueda(d, doc.id, _buscar);
    }).toList()
      ..sort((a, b) => AdminSolicitudTurismoUtils.fechaOrden(b.data())
          .compareTo(AdminSolicitudTurismoUtils.fechaOrden(a.data())));
  }

  Widget _chipFiltro(
    AdminTipoVehiculoTurismoFiltro filtro,
    String label,
    int count,
  ) {
    final selected = _filtroTipo == filtro;
    return FilterChip(
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: (_) => setState(() => _filtroTipo = filtro),
      selectedColor: Colors.deepPurpleAccent.withValues(alpha: 0.25),
      checkmarkColor: Colors.deepPurpleAccent,
      labelStyle: TextStyle(
        color: selected ? AdminUi.onCard(context) : AdminUi.secondary(context),
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12,
      ),
    );
  }

  Future<void> _iniciarAprobar(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
  ) async {
    if (_idsProcesando.contains(docId)) return;

    final String uidChofer = (data['uidChofer'] ?? '').toString().trim();
    if (uidChofer.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solicitud inválida: falta uid del chofer.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final List<Map<String, dynamic>> vehiculos =
        AdminSolicitudTurismoUtils.vehiculosDesdeSolicitud(data);
    if (vehiculos.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La solicitud no incluye tipos de vehículo.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AdminUi.dialogSurface(ctx),
          title: Text(
            'Aprobar solicitud turismo',
            style: TextStyle(color: AdminUi.onCard(ctx)),
          ),
          content: Text(
            'Se registrará al chofer en turismo y quedará disponible para asignación. '
            '¿Confirmas la aprobación?',
            style: TextStyle(color: AdminUi.secondary(ctx)),
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
                backgroundColor: Colors.green.shade700,
              ),
              child: const Text('Aprobar'),
            ),
          ],
        );
      },
    );
    if (ok != true || !context.mounted) return;

    await _commitAprobar(context, docId, data, uidChofer, vehiculos);
  }

  Future<void> _commitAprobar(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
    String uidChofer,
    List<Map<String, dynamic>> vehiculos,
  ) async {
    if (_idsProcesando.contains(docId)) return;
    setState(() => _idsProcesando.add(docId));

    try {
      final batch = FirebaseFirestore.instance.batch();
      final user = FirebaseAuth.instance.currentUser;

      final usuarioSnap = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uidChofer)
          .get();
      final bool dispUsuario = RolesService.leerDisponibleDesdeUsuarioDoc(
        usuarioSnap.data(),
      );

      final solicitudRef = FirebaseFirestore.instance
          .collection('solicitudes_turismo')
          .doc(docId);

      batch.update(solicitudRef, {
        'estado': 'aprobado',
        'revisadoPor': user?.uid ?? '',
        'revisadoEn': FieldValue.serverTimestamp(),
      });

      final choferRef = FirebaseFirestore.instance
          .collection('choferes_turismo')
          .doc(uidChofer);

      batch.set(
        choferRef,
        {
          'uid': uidChofer,
          'nombre': data['nombre'],
          'email': data['email'],
          'telefono': data['telefono'],
          'vehiculos': SolicitudTurismoRepo.vehiculosParaFirestore(
            vehiculos.map((Map<String, dynamic> v) {
              return VehiculoTurismo.fromMap(v);
            }).toList(),
          ),
          'documentos': data['documentos'] ?? {},
          'estado': 'aprobado',
          'disponible': dispUsuario,
          'calificacion': 0.0,
          'viajesCompletados': 0,
          'zonas': [],
          'subtiposTurismo': vehiculos
              .map((v) => (v['tipo'] ?? '').toString().toLowerCase())
              .where((t) => t.isNotEmpty)
              .toSet()
              .toList(),
          'fechaRegistro': FieldValue.serverTimestamp(),
          'verificadoPor': user?.uid ?? '',
          'verificadoEn': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      batch.set(
        FirebaseFirestore.instance.collection('usuarios').doc(uidChofer),
        {
          'choferTurismoAprobado': true,
          'choferTurismoEstado': 'aprobado',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chofer turismo aprobado'),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensajeFirebase(e)),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _idsProcesando.remove(docId));
    }
  }

  Future<void> _iniciarRechazar(BuildContext context, String docId) async {
    if (_idsProcesando.contains(docId)) return;

    final motivoCtrl = TextEditingController();
    try {
      final bool ok = await showDialog<bool>(
            context: context,
            builder: (ctx) {
              final cs = Theme.of(ctx).colorScheme;
              return AlertDialog(
                backgroundColor: AdminUi.dialogSurface(ctx),
                title: Text(
                  'Rechazar solicitud turismo',
                  style: TextStyle(color: AdminUi.onCard(ctx)),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'El chofer podrá enviar una nueva solicitud más adelante.',
                        style: TextStyle(color: AdminUi.secondary(ctx)),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: motivoCtrl,
                        style: TextStyle(color: AdminUi.onCard(ctx)),
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Motivo (opcional, auditoría interna)',
                          hintStyle: TextStyle(
                            color: AdminUi.secondary(ctx).withValues(alpha: 0.75),
                          ),
                          filled: true,
                          fillColor: AdminUi.inputFill(ctx),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: AdminUi.borderSubtle(ctx)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: AdminUi.borderSubtle(ctx)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: cs.primary, width: 1.4),
                          ),
                        ),
                      ),
                    ],
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
          ) ??
          false;
      if (!ok || !context.mounted) return;

      setState(() => _idsProcesando.add(docId));
      final user = FirebaseAuth.instance.currentUser;
      final motivo = motivoCtrl.text.trim();
      final Map<String, dynamic> patch = {
        'estado': 'rechazado',
        'revisadoPor': user?.uid ?? '',
        'revisadoEn': FieldValue.serverTimestamp(),
      };
      if (motivo.isNotEmpty) {
        patch['motivoRechazo'] = motivo;
      }

      try {
        await FirebaseFirestore.instance
            .collection('solicitudes_turismo')
            .doc(docId)
            .update(patch);

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud turismo rechazada'),
            backgroundColor: Colors.orange,
          ),
        );
      } on FirebaseException catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensajeFirebase(e)),
            backgroundColor: Colors.red,
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      } finally {
        if (mounted) setState(() => _idsProcesando.remove(docId));
      }
    } finally {
      motivoCtrl.dispose();
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamSolicitudes() {
    if (_tabCtrl.index == 0) {
      return FirebaseFirestore.instance
          .collection('solicitudes_turismo')
          .where('estado', isEqualTo: 'pendiente')
          .orderBy('fechaSolicitud', descending: true)
          .snapshots();
    }
    return FirebaseFirestore.instance
        .collection('solicitudes_turismo')
        .where('estado', isEqualTo: 'rechazado')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        iconTheme: IconThemeData(color: AdminUi.appBarFg(context)),
        title: Text(
          'Solicitudes turismo',
          style: TextStyle(color: AdminUi.onCard(context)),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.deepPurpleAccent,
          unselectedLabelColor: AdminUi.tabUnselected(context),
          indicatorColor: Colors.deepPurpleAccent,
          tabs: const [
            Tab(text: 'Pendientes'),
            Tab(text: 'Rechazadas'),
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
                prefixIcon:
                    Icon(Icons.search, color: AdminUi.secondary(context)),
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
            stream: _streamSolicitudes(),
            builder: (context, countSnap) {
              final raw = countSnap.data?.docs ?? const [];
              final dataList = raw.map((e) => e.data()).toList();
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Row(
                  children: [
                    _chipFiltro(
                      AdminTipoVehiculoTurismoFiltro.todos,
                      'Todos',
                      dataList.length,
                    ),
                    const SizedBox(width: 6),
                    _chipFiltro(
                      AdminTipoVehiculoTurismoFiltro.carro,
                      'Carro',
                      AdminSolicitudTurismoUtils.contarPorTipo(
                        dataList,
                        AdminTipoVehiculoTurismoFiltro.carro,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _chipFiltro(
                      AdminTipoVehiculoTurismoFiltro.jeepeta,
                      'Jeepeta',
                      AdminSolicitudTurismoUtils.contarPorTipo(
                        dataList,
                        AdminTipoVehiculoTurismoFiltro.jeepeta,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _chipFiltro(
                      AdminTipoVehiculoTurismoFiltro.minivan,
                      'Minivan',
                      AdminSolicitudTurismoUtils.contarPorTipo(
                        dataList,
                        AdminTipoVehiculoTurismoFiltro.minivan,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _chipFiltro(
                      AdminTipoVehiculoTurismoFiltro.bus,
                      'Bus',
                      AdminSolicitudTurismoUtils.contarPorTipo(
                        dataList,
                        AdminTipoVehiculoTurismoFiltro.bus,
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
                'Choferes normales/motor van en «Expedientes choferes».',
                style: TextStyle(color: AdminUi.muted(context), fontSize: 11),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _streamSolicitudes(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: AdminUi.progressAccent(context),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  final err = snapshot.error;
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
                            'No se pudieron cargar las solicitudes.',
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
                  snapshot.data?.docs ??
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                );

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      _tabCtrl.index == 0
                          ? 'No hay solicitudes pendientes con este filtro.'
                          : 'No hay solicitudes rechazadas con este filtro.',
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
                  itemBuilder: (context, index) {
                    if (muchos && index == 0) {
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
                    final idx = muchos ? index - 1 : index;
                    final doc = docs[idx];
                    final data = doc.data();
                    return _SolicitudTurismoCard(
                      data: data,
                      docId: doc.id,
                      pendiente: _tabCtrl.index == 0,
                      procesando: _idsProcesando.contains(doc.id),
                      fechaFmt: _fechaFmt,
                      onAprobar: () => _iniciarAprobar(context, doc.id, data),
                      onRechazar: () => _iniciarRechazar(context, doc.id),
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

class _SolicitudTurismoCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final bool pendiente;
  final bool procesando;
  final DateFormat fechaFmt;
  final VoidCallback onAprobar;
  final VoidCallback onRechazar;

  const _SolicitudTurismoCard({
    required this.data,
    required this.docId,
    required this.pendiente,
    required this.procesando,
    required this.fechaFmt,
    required this.onAprobar,
    required this.onRechazar,
  });

  @override
  Widget build(BuildContext context) {
    final nombre = (data['nombre'] ?? '').toString();
    final email = (data['email'] ?? '').toString();
    final telefono = (data['telefono'] ?? '').toString();
    final notas = (data['notas'] ?? '').toString().trim();
    final uidChofer = (data['uidChofer'] ?? '').toString();
    final motivoRechazo = (data['motivoRechazo'] ?? '').toString().trim();
    final vehiculos = AdminSolicitudTurismoUtils.vehiculosDesdeSolicitud(data);
    final docsOk = AdminSolicitudTurismoUtils.documentosCompletosCount(data);
    final fecha = AdminSolicitudTurismoUtils.fechaOrden(data);

    return Card(
      color: AdminUi.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AdminUi.borderSubtle(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                        nombre.isNotEmpty ? nombre : 'Sin nombre',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AdminUi.onCard(context),
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
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
                    color: Colors.deepPurpleAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.deepPurpleAccent.withValues(alpha: 0.45),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tour, size: 14, color: Colors.deepPurpleAccent),
                      SizedBox(width: 4),
                      Text(
                        'Turismo',
                        style: TextStyle(
                          color: Colors.deepPurpleAccent,
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
            Row(
              children: [
                Text(
                  'Docs $docsOk/3',
                  style: TextStyle(
                    color: docsOk == 3
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
                if (uidChofer.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'UID ${uidChofer.length > 10 ? '${uidChofer.substring(0, 10)}…' : uidChofer}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AdminUi.muted(context), fontSize: 10),
                    ),
                  ),
                ],
              ],
            ),
            if (vehiculos.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Sin tipos de vehículo en la solicitud',
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.deepOrange.shade800
                        : Colors.orangeAccent,
                    fontSize: 12,
                  ),
                ),
              )
            else ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: vehiculos.map((v) {
                  final tipo = (v['tipo'] ?? '').toString();
                  final color = AdminSolicitudTurismoUtils.colorTipo(tipo);
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: color.withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          AdminSolicitudTurismoUtils.iconoTipo(tipo),
                          size: 13,
                          color: color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          (v['tipoLabel'] ?? tipo).toString(),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              ...vehiculos.map((v) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    AdminSolicitudTurismoUtils.vehiculoLinea(v),
                    style: TextStyle(
                      color: AdminUi.secondary(context),
                      fontSize: 12,
                    ),
                  ),
                );
              }),
            ],
            const SizedBox(height: 8),
            _EnlacesDocumentosTurismo(documentos: data['documentos']),
            if (notas.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AdminUi.inputFill(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AdminUi.borderSubtle(context)),
                ),
                child: Text(
                  'Notas: $notas',
                  style: TextStyle(
                    color: AdminUi.secondary(context),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            if (!pendiente && motivoRechazo.isNotEmpty) ...[
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
                  'Motivo rechazo: $motivoRechazo',
                  style: const TextStyle(
                    color: Color(0xFFFF8A80),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            if (pendiente) ...[
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
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
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

class _EnlacesDocumentosTurismo extends StatelessWidget {
  final dynamic documentos;

  const _EnlacesDocumentosTurismo({required this.documentos});

  static Future<void> _abrir(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (documentos is! Map) {
      return Text(
        'Documentos: sin archivos',
        style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
      );
    }
    final Map<String, dynamic> m =
        Map<String, dynamic>.from(documentos as Map);

    Widget docChip(String label, String key) {
      final url = (m[key] ?? '').toString().trim();
      final ok = AdminExpedienteChoferUtils.urlAbrible(url);
      return ActionChip(
        avatar: Icon(
          ok ? Icons.check_circle : Icons.error_outline,
          size: 16,
          color: ok ? Colors.green : Colors.orange,
        ),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onPressed: ok ? () => _abrir(url) : null,
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        docChip('Licencia', 'licencia'),
        docChip('Seguro', 'seguro'),
        docChip('Foto vehículo', 'fotoVehiculo'),
      ],
    );
  }
}
