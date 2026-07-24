// lib/pantallas/admin/taxistas_turismo_admin.dart
// Panel Admin: Depuración y configuración de taxistas de TURISMO

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../widgets/admin_app_bar.dart';
import 'package:flygo_nuevo/widgets/admin_guia_uso.dart';
import '../../widgets/admin_drawer.dart';
import 'admin_chofer_turismo_operativo_utils.dart';
import 'admin_ui_theme.dart';

/// Tipos de vehículos turismo usados en la app
const List<String> kVehiculosTurismo = [
  'Carro Turismo',
  'Jeepeta Turismo',
  'Minivan Turismo',
  'Minibús Turismo',
  'Autobús Turismo',
];

class TaxistasTurismoAdmin extends StatefulWidget {
  const TaxistasTurismoAdmin({super.key});

  @override
  State<TaxistasTurismoAdmin> createState() => _TaxistasTurismoAdminState();
}

class _TaxistasTurismoAdminState extends State<TaxistasTurismoAdmin> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  AdminFiltroOperativoTurismo _filtroOperativo =
      AdminFiltroOperativoTurismo.todos;

  /// uid → null=cargando, true=bloqueado, false=ok
  final Map<String, bool?> _bloqueoPagosPorUid = <String, bool?>{};
  final Set<String> _bloqueoPagosEnCarga = <String>{};

  /// Evita doble apertura / doble guardado por UID.
  final Set<String> _uidsEnProceso = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamTaxistasTurismo() {
    return _db
        .collection('choferes_turismo')
        .orderBy('fechaRegistro', descending: true)
        .snapshots();
  }

  String _mensajeFirebase(FirebaseException e) {
    final m = e.message?.trim();
    if (m != null && m.isNotEmpty) return m;
    return e.code;
  }

  Color _estadoColor(String estado) {
    switch (estado) {
      case 'aprobado':
        return Colors.green;
      case 'activo':
        return Colors.lightGreen;
      case 'rechazado':
        return Colors.red;
      default:
        return Colors.amber;
    }
  }

  String _estadoLabel(String estado) {
    switch (estado) {
      case 'aprobado':
        return 'Aprobado';
      case 'activo':
        return 'Activo';
      case 'rechazado':
        return 'Rechazado';
      default:
        return 'Pendiente';
    }
  }

  void _precargarBloqueosPagos(Iterable<String> uids) {
    for (final String uid in uids) {
      if (_bloqueoPagosPorUid.containsKey(uid) ||
          _bloqueoPagosEnCarga.contains(uid)) {
        continue;
      }
      _bloqueoPagosEnCarga.add(uid);
      AdminChoferTurismoOperativo.consultarBloqueoPagos(uid).then((bool bloq) {
        if (!mounted) return;
        setState(() {
          _bloqueoPagosPorUid[uid] = bloq;
          _bloqueoPagosEnCarga.remove(uid);
        });
      }).catchError((_) {
        if (!mounted) return;
        setState(() {
          _bloqueoPagosPorUid[uid] = true;
          _bloqueoPagosEnCarga.remove(uid);
        });
      });
    }
  }

  AdminChoferTurismoOperativo _operativoDesde(
    Map<String, dynamic> data,
    String uid,
  ) {
    final base = AdminChoferTurismoOperativo.desdeChoferDoc(data);
    final bool? bloq = _bloqueoPagosPorUid[uid];
    if (bloq == null) return base;
    return base.conBloqueoPagos(bloq);
  }

  Widget _chipOperativo(
    AdminFiltroOperativoTurismo filtro,
    String label,
    int count,
  ) {
    final selected = _filtroOperativo == filtro;
    return FilterChip(
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: (_) => setState(() => _filtroOperativo = filtro),
      selectedColor: Colors.deepPurpleAccent.withValues(alpha: 0.25),
      checkmarkColor: Colors.deepPurpleAccent,
      labelStyle: TextStyle(
        color: selected ? AdminUi.onCard(context) : AdminUi.secondary(context),
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12,
      ),
    );
  }

  Widget _badgeWidget(AdminOperativoBadge b) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: b.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: b.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(b.icon, size: 13, color: b.color),
          const SizedBox(width: 4),
          Text(
            b.label,
            style: TextStyle(
              color: b.color,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  /// Código interno alineado con `choferes_turismo.vehiculos[].tipo` y asignación turismo.
  String _mapVehiculoInterno(String veh) {
    final lower = veh.toLowerCase();
    // Minibús antes que cualquier comprobación que coincida con "bus".
    if (lower.contains('minib')) {
      return 'minivan';
    }
    if (lower.contains('jeepeta')) {
      return 'jeepeta';
    }
    if (lower.contains('minivan')) {
      return 'minivan';
    }
    if (lower.contains('autobús') || lower.contains('autobus')) {
      return 'bus';
    }
    if (lower.contains('bus') || lower.contains('guagua')) {
      return 'bus';
    }
    if (lower.contains('carro')) {
      return 'carro';
    }
    return '';
  }

  static String _tipoLabelDesdeCodigo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'carro':
        return 'Carro Turismo';
      case 'jeepeta':
        return 'Jeepeta Turismo';
      case 'minivan':
        return 'Minivan Turismo';
      case 'bus':
        return 'Bus Turismo';
      default:
        return tipo;
    }
  }

  /// Reconstruye `vehiculos` según selección del admin, conservando datos de cada tipo ya existente.
  List<Map<String, dynamic>> _vehiculosDesdeSeleccion({
    required Set<String> seleccionTipos,
    required List<dynamic> vehiculosRaw,
  }) {
    final List<Map<String, dynamic>> out = [];
    for (final tipo in seleccionTipos) {
      final tNorm = tipo.toLowerCase();
      Map<String, dynamic>? existente;
      for (final v in vehiculosRaw) {
        if (v is! Map) continue;
        final vt = (v['tipo'] ?? '').toString().toLowerCase();
        if (vt == tNorm) {
          existente = v.map((k, val) => MapEntry(k.toString(), val));
          break;
        }
      }
      if (existente != null) {
        out.add(Map<String, dynamic>.from(existente));
      } else {
        out.add({
          'tipo': tNorm,
          'tipoLabel': _tipoLabelDesdeCodigo(tNorm),
          'marca': '',
          'modelo': '',
          'color': '',
          'placa': '',
          'anio': 0,
        });
      }
    }
    return out;
  }

  Future<void> _abrirConfigChofer(
    BuildContext context, {
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    if (_uidsEnProceso.contains(uid)) return;

    final messenger = ScaffoldMessenger.of(context);

    final String nombre = (data['nombre'] ?? '').toString();
    final String email = (data['email'] ?? '').toString();
    final String telefono = (data['telefono'] ?? '').toString();

    final List<dynamic> vehiculosRaw = data['vehiculos'] as List? ?? [];

    final Set<String> seleccionVehiculos = vehiculosRaw
        .map((v) =>
            (v is Map ? (v['tipo'] ?? '').toString().toLowerCase() : '').trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    final String estadoActual = (data['estado'] ?? 'pendiente').toString();
    final String notaActual = (data['notaAdmin'] ?? '').toString();

    String estadoSeleccionado = estadoActual;
    final TextEditingController notaCtrl =
        TextEditingController(text: notaActual);

    try {
      final bool? result = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: AdminUi.sheetSurface(context),
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx2, setStateModal) {
              return Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(ctx2).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configurar chofer de turismo',
                      style: TextStyle(
                        color: AdminUi.onCard(ctx2),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      nombre.isNotEmpty ? nombre : uid,
                      style: TextStyle(color: AdminUi.secondary(ctx2)),
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: TextStyle(color: AdminUi.muted(ctx2)),
                      ),
                    if (telefono.isNotEmpty)
                      Text(
                        'Tel: $telefono',
                        style: TextStyle(color: AdminUi.muted(ctx2)),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'Estado',
                      style: TextStyle(
                        color: AdminUi.secondary(ctx2),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    RadioGroup<String>(
                      groupValue: estadoSeleccionado,
                      onChanged: (v) {
                        if (v != null) {
                          setStateModal(() {
                            estadoSeleccionado = v;
                          });
                        }
                      },
                      child: Column(
                        children: [
                          _radioEstado(
                            title: 'Pendiente',
                            value: 'pendiente',
                          ),
                          _radioEstado(
                            title: 'Aprobado',
                            value: 'aprobado',
                          ),
                          _radioEstado(
                            title: 'Rechazado',
                            value: 'rechazado',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Vehículos permitidos',
                      style: TextStyle(
                        color: AdminUi.secondary(ctx2),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    ...kVehiculosTurismo.map((veh) {
                      final String tipoInterno = _mapVehiculoInterno(veh);
                      final bool valido = tipoInterno.isNotEmpty;
                      final bool selected =
                          valido && seleccionVehiculos.contains(tipoInterno);
                      return CheckboxListTile(
                        value: selected,
                        activeColor: AdminUi.progressAccent(ctx2),
                        title: Text(
                          veh,
                          style: TextStyle(color: AdminUi.secondary(ctx2)),
                        ),
                        subtitle: !valido
                            ? Text(
                                'Tipo no mapeado; no se usará hasta corregir etiqueta.',
                                style: TextStyle(
                                  color: Theme.of(ctx2).brightness ==
                                          Brightness.light
                                      ? Colors.deepOrange.shade800
                                      : Colors.orangeAccent,
                                  fontSize: 11,
                                ),
                              )
                            : null,
                        onChanged: !valido
                            ? null
                            : (v) {
                                setStateModal(() {
                                  if (v == true) {
                                    seleccionVehiculos.add(tipoInterno);
                                  } else {
                                    seleccionVehiculos.remove(tipoInterno);
                                  }
                                });
                              },
                      );
                    }),
                    const SizedBox(height: 10),
                    Text(
                      'Nota interna',
                      style: TextStyle(
                        color: AdminUi.secondary(ctx2),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: notaCtrl,
                      style: TextStyle(color: AdminUi.onCard(ctx2)),
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Nota para administración',
                        hintStyle: TextStyle(
                            color: AdminUi.secondary(ctx2)
                                .withValues(alpha: 0.75)),
                        filled: true,
                        fillColor: AdminUi.inputFill(ctx2),
                        border: OutlineInputBorder(
                          borderRadius:
                              const BorderRadius.all(Radius.circular(10)),
                          borderSide:
                              BorderSide(color: AdminUi.borderSubtle(ctx2)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              const BorderRadius.all(Radius.circular(10)),
                          borderSide:
                              BorderSide(color: AdminUi.borderSubtle(ctx2)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              const BorderRadius.all(Radius.circular(10)),
                          borderSide: BorderSide(
                            color: Theme.of(ctx2).colorScheme.primary,
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(
                              'Cancelar',
                              style: TextStyle(color: AdminUi.secondary(ctx2)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Theme.of(ctx2).colorScheme.primaryContainer,
                              foregroundColor:
                                  Theme.of(ctx2).colorScheme.onPrimaryContainer,
                            ),
                            child: const Text('Guardar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      );

      if (result != true) {
        return;
      }

      if (estadoSeleccionado == 'aprobado' && seleccionVehiculos.isEmpty) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Un chofer aprobado debe tener al menos un tipo de vehículo seleccionado.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      setState(() => _uidsEnProceso.add(uid));
      try {
        final String? adminUid = _auth.currentUser?.uid;

        final List<Map<String, dynamic>> nuevosVehiculos =
            _vehiculosDesdeSeleccion(
          seleccionTipos: seleccionVehiculos,
          vehiculosRaw: vehiculosRaw,
        );

        final Map<String, dynamic> update = {
          'estado': estadoSeleccionado,
          'notaAdmin': notaCtrl.text.trim(),
          'vehiculos': nuevosVehiculos,
          'updatedAt': FieldValue.serverTimestamp(),
          'verificadoPor': adminUid,
          'verificadoEn': FieldValue.serverTimestamp(),
        };

        await _db.collection('choferes_turismo').doc(uid).set(
              update,
              SetOptions(merge: true),
            );

        if (!mounted) return;

        messenger.showSnackBar(
          const SnackBar(
            content: Text('Cambios guardados'),
            backgroundColor: Colors.green,
          ),
        );
      } on FirebaseException catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(_mensajeFirebase(e)),
            backgroundColor: Colors.red,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) setState(() => _uidsEnProceso.remove(uid));
      }
    } finally {
      notaCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: AdminAppBar(
        guiaId: AdminGuiaIds.choferesTurismo,
        title: 'Choferes turismo — flota',
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: AdminUi.onCard(context)),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, email o teléfono...',
                hintStyle: TextStyle(
                    color: AdminUi.secondary(context).withValues(alpha: 0.85)),
                prefixIcon:
                    Icon(Icons.search, color: AdminUi.secondary(context)),
                filled: true,
                fillColor: AdminUi.inputFill(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AdminUi.borderSubtle(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AdminUi.borderSubtle(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cs.primary, width: 1.4),
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear,
                            color: AdminUi.secondary(context)),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (String value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _streamTaxistasTurismo(),
        builder: (BuildContext context,
            AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                  color: AdminUi.progressAccent(context)),
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
                    Icon(Icons.cloud_off_outlined,
                        size: 48, color: AdminUi.secondary(context)),
                    const SizedBox(height: 12),
                    Text(
                      'No se pudieron cargar los choferes.',
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
                          color: AdminUi.secondary(context), fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }

          final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
              snap.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No hay choferes registrados',
                style: TextStyle(color: AdminUi.secondary(context)),
              ),
            );
          }

          final List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredDocs =
              docs.where((doc) {
            if (_searchQuery.isEmpty) return true;
            final Map<String, dynamic> data = doc.data();
            final String nombre =
                (data['nombre'] ?? '').toString().toLowerCase();
            final String email = (data['email'] ?? '').toString().toLowerCase();
            final String telefono =
                (data['telefono'] ?? '').toString().toLowerCase();
            final String uid = doc.id.toLowerCase();
            return nombre.contains(_searchQuery) ||
                email.contains(_searchQuery) ||
                telefono.contains(_searchQuery) ||
                uid.contains(_searchQuery);
          }).toList();

          _precargarBloqueosPagos(filteredDocs.map((d) => d.id));

          final List<QueryDocumentSnapshot<Map<String, dynamic>>> visibleDocs =
              filteredDocs.where((doc) {
            final oper = _operativoDesde(doc.data(), doc.id);
            return oper.coincideFiltro(_filtroOperativo);
          }).toList();

          int countListos = 0;
          int countNoDisp = 0;
          int countSinGps = 0;
          int countEnViaje = 0;
          for (final doc in filteredDocs) {
            final op = _operativoDesde(doc.data(), doc.id);
            if (op.listoAutoAsignacion) countListos++;
            if (!op.disponible) countNoDisp++;
            if (!op.tieneGps) countSinGps++;
            if (op.enViaje) countEnViaje++;
          }

          if (filteredDocs.isEmpty) {
            return Center(
              child: Text(
                'No se encontraron choferes',
                style: TextStyle(color: AdminUi.secondary(context)),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    _chipOperativo(
                      AdminFiltroOperativoTurismo.todos,
                      'Todos',
                      filteredDocs.length,
                    ),
                    const SizedBox(width: 6),
                    _chipOperativo(
                      AdminFiltroOperativoTurismo.candidatosAuto,
                      'Listos auto',
                      countListos,
                    ),
                    const SizedBox(width: 6),
                    _chipOperativo(
                      AdminFiltroOperativoTurismo.noDisponibles,
                      'No disp.',
                      countNoDisp,
                    ),
                    const SizedBox(width: 6),
                    _chipOperativo(
                      AdminFiltroOperativoTurismo.sinGps,
                      'Sin GPS',
                      countSinGps,
                    ),
                    const SizedBox(width: 6),
                    _chipOperativo(
                      AdminFiltroOperativoTurismo.enViaje,
                      'En viaje',
                      countEnViaje,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Indicadores de auto-asignación: disponible, GPS, pagos y viaje activo.',
                  style: TextStyle(color: AdminUi.muted(context), fontSize: 11),
                ),
              ),
              Expanded(
                child: visibleDocs.isEmpty
                    ? Center(
                        child: Text(
                          'Ningún chofer coincide con este filtro.',
                          style: TextStyle(color: AdminUi.secondary(context)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: visibleDocs.length,
                        itemBuilder: (BuildContext context, int index) {
                          final QueryDocumentSnapshot<Map<String, dynamic>> doc =
                              visibleDocs[index];
                          final Map<String, dynamic> data = doc.data();
                          final String uid = doc.id;
                          final oper = _operativoDesde(data, uid);

                          final String nombre = (data['nombre'] ?? '').toString();
                          final String email = (data['email'] ?? '').toString();
                          final String telefono =
                              (data['telefono'] ?? '').toString();
                          final String estado =
                              (data['estado'] ?? 'pendiente').toString();
                          final bool procesando =
                              _uidsEnProceso.contains(uid);
                          final List<dynamic> vehiculosRaw =
                              data['vehiculos'] as List? ?? const [];

                          final Color? bordeListo = oper.listoAutoAsignacion
                              ? Colors.green.withValues(alpha: 0.55)
                              : null;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            color: AdminUi.card(context),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: bordeListo ??
                                    AdminUi.borderSubtle(context),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              nombre.isNotEmpty ? nombre : uid,
                                              style: TextStyle(
                                                color: AdminUi.onCard(context),
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16,
                                              ),
                                            ),
                                            Text(
                                              _estadoLabel(estado),
                                              style: TextStyle(
                                                color: _estadoColor(estado),
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ),
                                            if (email.isNotEmpty)
                                              Text(
                                                email,
                                                style: TextStyle(
                                                  color: AdminUi.muted(context),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            if (telefono.isNotEmpty)
                                              Text(
                                                telefono,
                                                style: TextStyle(
                                                  color: AdminUi.muted(context),
                                                  fontSize: 12,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      procesando
                                          ? SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: AdminUi.progressAccent(
                                                    context),
                                              ),
                                            )
                                          : IconButton(
                                              icon: Icon(
                                                Icons.settings,
                                                color: AdminUi.iconStandard(
                                                    context),
                                              ),
                                              onPressed: () {
                                                _abrirConfigChofer(
                                                  context,
                                                  uid: uid,
                                                  data: data,
                                                );
                                              },
                                            ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    oper.resumenAutoAsignacion,
                                    style: TextStyle(
                                      color: oper.listoAutoAsignacion
                                          ? Colors.green.shade400
                                          : AdminUi.secondary(context),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      ...oper.badgesSync().map(_badgeWidget),
                                      if (oper.badgePagos() != null)
                                        _badgeWidget(oper.badgePagos()!),
                                    ],
                                  ),
                                  if (vehiculosRaw.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Vehículos: ${vehiculosRaw.map((v) {
                                        if (v is Map) {
                                          final lbl =
                                              (v['tipoLabel'] ?? v['tipo'] ?? '')
                                                  .toString();
                                          final placa =
                                              (v['placa'] ?? '').toString();
                                          return placa.isNotEmpty
                                              ? '$lbl ($placa)'
                                              : lbl;
                                        }
                                        return v.toString();
                                      }).join(' · ')}',
                                      style: TextStyle(
                                        color: AdminUi.muted(context),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _radioEstado({
    required String title,
    required String value,
  }) {
    return RadioListTile<String>(
      value: value,
      activeColor: AdminUi.progressAccent(context),
      title: Text(
        title,
        style: TextStyle(color: AdminUi.secondary(context)),
      ),
    );
  }
}
