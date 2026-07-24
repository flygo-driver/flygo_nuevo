import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/pantallas/admin/admin_corporativo_calendario.dart';
import 'package:flygo_nuevo/servicios/corporativo_admin_service.dart';
import 'package:flygo_nuevo/widgets/admin_app_bar.dart';
import 'package:flygo_nuevo/widgets/admin_guia_uso.dart';
import 'package:flygo_nuevo/widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';

/// Admin: pool de choferes corporativos (como turismo, asignación manual a rutas).
class AdminChoferesCorporativoPage extends StatefulWidget {
  const AdminChoferesCorporativoPage({super.key});

  @override
  State<AdminChoferesCorporativoPage> createState() =>
      _AdminChoferesCorporativoPageState();
}

class _AdminChoferesCorporativoPageState extends State<AdminChoferesCorporativoPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _buscarCtrl = TextEditingController();
  String _buscar = '';
  final Set<String> _procesando = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _buscarCtrl.dispose();
    super.dispose();
  }

  bool _coincideBusqueda(Map<String, dynamic> d, String id) {
    final q = _buscar.trim().toLowerCase();
    if (q.isEmpty) return true;
    final campos = [
      id,
      (d['nombre'] ?? '').toString(),
      (d['telefono'] ?? '').toString(),
      (d['email'] ?? '').toString(),
      (d['cedula'] ?? '').toString(),
      (d['placa'] ?? '').toString(),
    ];
    return campos.any((c) => c.toLowerCase().contains(q));
  }

  bool _coincideBusquedaChoferOAsignaciones(
    Map<String, dynamic> d,
    String id,
    List<CorporativoAsignacionRutaAdmin> asignaciones,
  ) {
    if (_coincideBusqueda(d, id)) return true;
    final q = _buscar.trim();
    if (q.isEmpty) return true;
    return asignaciones.any(
      (a) => CorporativoAdminService.asignacionCoincideBusqueda(a, q),
    );
  }

  Future<void> _aprobarSolicitud(String docId, Map<String, dynamic> data) async {
    if (_procesando.contains(docId)) return;
    final uid = (data['uidChofer'] ?? '').toString().trim();
    if (uid.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprobar chofer corporativo'),
        content: Text(
          '¿Habilitar a ${data['nombre']} en el pool corporativo?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aprobar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _procesando.add(docId));
    try {
      final batch = FirebaseFirestore.instance.batch();
      final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';

      batch.update(
        FirebaseFirestore.instance.collection('solicitudes_corporativo').doc(docId),
        {
          'estado': 'aprobado',
          'revisadoPor': adminUid,
          'revisadoEn': FieldValue.serverTimestamp(),
        },
      );

      batch.set(
        FirebaseFirestore.instance.collection('choferes_corporativos').doc(uid),
        {
          'uid': uid,
          'nombre': data['nombre'],
          'email': data['email'],
          'telefono': data['telefono'],
          'cedula': data['cedula'],
          'placa': data['placa'],
          'marca': data['marca'],
          'modelo': data['modelo'],
          'color': data['color'],
          'estado': 'aprobado',
          'activo': true,
          'disponible': true,
          'viajesCorporativos': 0,
          'verificadoPor': adminUid,
          'verificadoEn': FieldValue.serverTimestamp(),
          'fuente': 'solicitud',
          'actualizadoEn': FieldValue.serverTimestamp(),
          'creadoEn': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chofer corporativo aprobado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade800),
      );
    } finally {
      if (mounted) setState(() => _procesando.remove(docId));
    }
  }

  Future<void> _rechazarSolicitud(String docId) async {
    final motivoCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar solicitud'),
        content: TextField(
          controller: motivoCtrl,
          decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Rechazar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await FirebaseFirestore.instance
        .collection('solicitudes_corporativo')
        .doc(docId)
        .update({
      'estado': 'rechazado',
      'motivoRechazo': motivoCtrl.text.trim(),
      'revisadoPor': FirebaseAuth.instance.currentUser?.uid ?? '',
      'revisadoEn': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _habilitarDirecto() async {
    final telCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Habilitar taxista en corporativo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Busca un taxista ya registrado en RAI y lo agrega al pool corporativo.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: telCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono del taxista',
                hintText: '8095551234',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Habilitar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await CorporativoAdminService.habilitarChoferCorporativo(
        telefono: telCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chofer habilitado en corporativo')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade800),
      );
    }
  }

  Future<void> _deshabilitarChofer(String uid, String nombre) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar del pool corporativo'),
        content: Text('¿Quitar a $nombre del pool corporativo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await CorporativoAdminService.deshabilitarChoferCorporativo(choferUid: uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chofer quitado del pool')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade800),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy · HH:mm', 'es');
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      appBar: AdminAppBar(
        guiaId: AdminGuiaIds.choferesCorp,
        title: 'Choferes corporativos',
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Solicitudes'),
            Tab(text: 'Pool activo'),
            Tab(text: 'Asignaciones'),
          ],
        ),
      ),
      drawer: const AdminDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _habilitarDirecto,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Habilitar taxista'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _buscarCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Buscar nombre, correo, teléfono, cédula…',
                suffixIcon: _buscar.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _buscarCtrl.clear();
                          setState(() => _buscar = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _buscar = v),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('solicitudes_corporativo')
                      .where('estado', isEqualTo: 'pendiente')
                      .limit(40)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = (snap.data?.docs ?? [])
                        .where((d) => _coincideBusqueda(d.data(), d.id))
                        .toList();
                    if (docs.isEmpty) {
                      return Center(
                        child: Text(
                          'Sin solicitudes pendientes',
                          style: TextStyle(color: AdminUi.secondary(context)),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final d = doc.data();
                        final proc = _procesando.contains(doc.id);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (d['nombre'] ?? 'Taxista').toString(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AdminUi.onCard(context),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Tel: ${d['telefono']} · Cédula: ${d['cedula']}\n'
                                  'Placa: ${d['placa']} · ${d['marca']} ${d['modelo']}',
                                  style: TextStyle(
                                    color: AdminUi.secondary(context),
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                                if ((d['notaChofer'] ?? '').toString().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      'Nota: ${d['notaChofer']}',
                                      style: TextStyle(
                                        color: AdminUi.muted(context),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    FilledButton(
                                      onPressed: proc
                                          ? null
                                          : () => _aprobarSolicitud(doc.id, d),
                                      child: const Text('Aprobar'),
                                    ),
                                    OutlinedButton(
                                      onPressed: proc
                                          ? null
                                          : () => _rechazarSolicitud(doc.id),
                                      child: const Text('Rechazar'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                StreamBuilder<List<CorporativoAsignacionRutaAdmin>>(
                  stream: CorporativoAdminService.streamAsignacionesRutas(),
                  builder: (context, asigSnap) {
                    final asignaciones = asigSnap.data ?? const [];
                    final porChofer =
                        CorporativoAdminService.agruparAsignacionesPorChofer(
                      asignaciones,
                    );
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('choferes_corporativos')
                          .where('estado', whereIn: ['aprobado', 'activo'])
                          .limit(80)
                          .snapshots(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting &&
                            asigSnap.connectionState ==
                                ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final docs = (snap.data?.docs ?? [])
                            .where(
                              (d) => _coincideBusquedaChoferOAsignaciones(
                                d.data(),
                                d.id,
                                porChofer[d.id] ?? const [],
                              ),
                            )
                            .toList();
                        final activos = docs
                            .where((d) => d.data()['activo'] != false)
                            .toList();
                        final pausados = docs
                            .where((d) => d.data()['activo'] == false)
                            .toList();
                        if (activos.isEmpty && pausados.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Sin choferes en el pool. Habilita taxistas o aprueba solicitudes.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AdminUi.secondary(context),
                                ),
                              ),
                            ),
                          );
                        }
                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Text(
                              '${activos.length} chofer(es) en la plataforma corporativa',
                              style: TextStyle(
                                color: AdminUi.onCard(context),
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Debajo de cada nombre ves para qué empresa y ruta está asignado.',
                              style: TextStyle(
                                color: AdminUi.secondary(context),
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...activos.map((doc) {
                              final d = doc.data();
                              final rutas = porChofer[doc.id] ?? const [];
                              final verificado =
                                  d['verificadoEn'] as Timestamp?;
                              return _TarjetaChoferPoolAdmin(
                                uid: doc.id,
                                nombre: (d['nombre'] ?? 'Conductor').toString(),
                                telefono: (d['telefono'] ?? '').toString(),
                                cedula: (d['cedula'] ?? '').toString(),
                                placa: (d['placa'] ?? '').toString(),
                                vehiculo:
                                    '${d['marca'] ?? ''} ${d['modelo'] ?? ''}'
                                        .trim(),
                                verificado: verificado != null
                                    ? fmt.format(verificado.toDate())
                                    : null,
                                asignaciones: rutas,
                                onCalendario: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          AdminCorporativoCalendarioPage(
                                        choferUid: doc.id,
                                        choferNombre:
                                            (d['nombre'] ?? '').toString(),
                                      ),
                                    ),
                                  );
                                },
                                onPausar: () => _deshabilitarChofer(
                                  doc.id,
                                  (d['nombre'] ?? 'Conductor').toString(),
                                ),
                              );
                            }),
                            if (pausados.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Pausados / inactivos',
                                style: TextStyle(
                                  color: AdminUi.muted(context),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...pausados.map((doc) {
                                final d = doc.data();
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  color: Colors.orange.withValues(alpha: 0.06),
                                  child: ListTile(
                                    title: Text(
                                      (d['nombre'] ?? 'Conductor').toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Tel: ${d['telefono']} · Pausado en pool',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    trailing: FilledButton.tonal(
                                      onPressed: () async {
                                        try {
                                          await CorporativoAdminService
                                              .habilitarChoferCorporativo(
                                            choferUid: doc.id,
                                          );
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Chofer reactivado en pool',
                                              ),
                                            ),
                                          );
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(content: Text('Error: $e')),
                                          );
                                        }
                                      },
                                      child: const Text('Reactivar'),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ],
                        );
                      },
                    );
                  },
                ),
                _AsignacionesCorporativoTab(buscar: _buscar),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaChoferPoolAdmin extends StatelessWidget {
  const _TarjetaChoferPoolAdmin({
    required this.uid,
    required this.nombre,
    required this.telefono,
    required this.cedula,
    required this.placa,
    required this.vehiculo,
    required this.asignaciones,
    required this.onCalendario,
    required this.onPausar,
    this.verificado,
  });

  final String uid;
  final String nombre;
  final String telefono;
  final String cedula;
  final String placa;
  final String vehiculo;
  final String? verificado;
  final List<CorporativoAsignacionRutaAdmin> asignaciones;
  final VoidCallback onCalendario;
  final VoidCallback onPausar;

  @override
  Widget build(BuildContext context) {
    final tieneRutas = asignaciones.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: tieneRutas
              ? Colors.teal.withValues(alpha: 0.45)
              : Colors.orange.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.teal.shade700,
                  child: Text(
                    nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AdminUi.onCard(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tel: $telefono · Cédula: $cedula',
                        style: TextStyle(
                          color: AdminUi.secondary(context),
                          fontSize: 11,
                        ),
                      ),
                      if (placa.isNotEmpty || vehiculo.isNotEmpty)
                        Text(
                          'Placa: $placa${vehiculo.isNotEmpty ? ' · $vehiculo' : ''}',
                          style: TextStyle(
                            color: AdminUi.secondary(context),
                            fontSize: 11,
                          ),
                        ),
                      if (verificado != null)
                        Text(
                          'En pool desde: $verificado',
                          style: TextStyle(
                            color: AdminUi.muted(context),
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Calendario semanal',
                  onPressed: onCalendario,
                  icon: const Icon(Icons.calendar_month),
                ),
                IconButton(
                  tooltip: 'Pausar / quitar del pool',
                  onPressed: onPausar,
                  icon: const Icon(Icons.pause_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (tieneRutas) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.teal.shade700,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$nombre está asignado a ${asignaciones.length} ruta(s)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...asignaciones.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.teal.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Empresa: ${a.empresaNombre}',
                          style: TextStyle(
                            color: Colors.teal.shade900,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ruta: ${a.plantillaNombre}',
                          style: TextStyle(
                            color: AdminUi.onCard(context),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '⏰ ${a.horaRecogida} · ${a.diasLabel} · '
                          '${a.pasajerosActivos} pasajero(s)',
                          style: TextStyle(
                            color: AdminUi.secondary(context),
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                        Text(
                          '📍 ${a.origenLabel}',
                          style: TextStyle(
                            color: AdminUi.muted(context),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ] else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'Sin rutas asignadas. Asignalo desde Cuentas corporativas → Rutas de la empresa.',
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AsignacionesCorporativoTab extends StatelessWidget {
  const _AsignacionesCorporativoTab({required this.buscar});

  final String buscar;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CorporativoAsignacionRutaAdmin>>(
      stream: CorporativoAdminService.streamAsignacionesRutas(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No se pudieron cargar las asignaciones.\n${snap.error}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade800),
              ),
            ),
          );
        }
        var items = snap.data ?? const <CorporativoAsignacionRutaAdmin>[];
        final q = buscar.trim().toLowerCase();
        if (q.isNotEmpty) {
          items = items
              .where(
                (a) => CorporativoAdminService.asignacionCoincideBusqueda(a, q),
              )
              .toList();
        }
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                q.isEmpty
                    ? 'Ningún chofer tiene rutas asignadas todavía.\n'
                        'Asigná desde Cuentas corporativas → Rutas de cada empresa.'
                    : 'Sin asignaciones que coincidan con la búsqueda.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AdminUi.secondary(context)),
              ),
            ),
          );
        }
        final porChofer =
            CorporativoAdminService.agruparAsignacionesPorChofer(items);
        final choferes = porChofer.entries.toList()
          ..sort(
            (a, b) => (a.value.first.choferNombre)
                .toLowerCase()
                .compareTo(b.value.first.choferNombre.toLowerCase()),
          );
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${choferes.length} chofer(es) con rutas asignadas',
              style: TextStyle(
                color: AdminUi.onCard(context),
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Cada tarjeta resume empresa, hora, días y pasajeros de todas sus rutas.',
              style: TextStyle(
                color: AdminUi.secondary(context),
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            ...choferes.map((entry) {
              final rutas = entry.value;
              final cab = rutas.first;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.verified_user,
                            color: Colors.teal.shade700,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              rutas.length == 1
                                  ? cab.tituloChoferEmpresa
                                  : '${cab.choferNombre} · ${rutas.length} rutas asignadas',
                              style: TextStyle(
                                color: AdminUi.onCard(context),
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tel: ${cab.choferTelefono.isNotEmpty ? cab.choferTelefono : '—'}',
                        style: TextStyle(
                          color: AdminUi.secondary(context),
                          fontSize: 11,
                        ),
                      ),
                      if (rutas.length > 1) ...[
                        const SizedBox(height: 6),
                        Text(
                          '+ ${rutas.length - 1} empresa(s) / ruta(s) más:',
                          style: TextStyle(
                            color: Colors.teal.shade800,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      ...rutas.map(
                        (a) => Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AdminUi.scaffold(context),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AdminUi.borderSubtle(context),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a.empresaNombre,
                                style: TextStyle(
                                  color: Colors.teal.shade900,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                a.plantillaNombre,
                                style: TextStyle(
                                  color: AdminUi.onCard(context),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '⏰ Recogida ${a.horaRecogida} · ${a.diasLabel}',
                                style: TextStyle(
                                  color: AdminUi.secondary(context),
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                '👥 ${a.pasajerosActivos} pasajero(s) activos · 📍 ${a.origenLabel}'
                                '${a.precioAcordado > 0 ? ' · RD\$ ${a.precioAcordado.toStringAsFixed(0)}' : ''}',
                                style: TextStyle(
                                  color: AdminUi.muted(context),
                                  fontSize: 11,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
