// lib/pantallas/admin/taxistas_turismo_admin.dart
// Panel Admin: Depuración y configuración de taxistas de TURISMO

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../widgets/admin_drawer.dart';
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

  // 🔍 Controlador para búsqueda
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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

  Color _estadoColor(String estado) {
    switch (estado) {
      case 'aprobado':
        return Colors.green;
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
      case 'rechazado':
        return 'Rechazado';
      default:
        return 'Pendiente';
    }
  }

  // ✅ ELIMINADA: _getTipoLabel no se usaba

  String _mapVehiculoInterno(String veh) {
    if (veh.contains('Carro')) {
      return 'carro';
    } else if (veh.contains('Jeepeta')) {
      return 'jeepeta';
    } else if (veh.contains('Minivan')) {
      return 'minivan';
    } else if (veh.contains('Bus') || veh.contains('bús')) {
      return 'bus';
    }
    return '';
  }

  Future<void> _abrirConfigChofer(
    BuildContext context, {
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    final String nombre = (data['nombre'] ?? '').toString();
    final String email = (data['email'] ?? '').toString();
    final String telefono = (data['telefono'] ?? '').toString();

    final List<dynamic> vehiculosRaw = data['vehiculos'] as List? ?? [];

    final Set<String> seleccionVehiculos = vehiculosRaw
        .map((v) => (v is Map ? v['tipo'] : '').toString())
        .where((e) => e.isNotEmpty)
        .toSet();

    final String estadoActual = (data['estado'] ?? 'pendiente').toString();
    final String notaActual = (data['notaAdmin'] ?? '').toString();

    String estadoSeleccionado = estadoActual;
    final TextEditingController notaCtrl = TextEditingController(text: notaActual);

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
                  _radioEstado(
                    title: 'Pendiente',
                    value: 'pendiente',
                    groupValue: estadoSeleccionado,
                    onChanged: (v) {
                      if (v != null) {
                        setStateModal(() {
                          estadoSeleccionado = v;
                        });
                      }
                    },
                  ),
                  _radioEstado(
                    title: 'Aprobado',
                    value: 'aprobado',
                    groupValue: estadoSeleccionado,
                    onChanged: (v) {
                      if (v != null) {
                        setStateModal(() {
                          estadoSeleccionado = v;
                        });
                      }
                    },
                  ),
                  _radioEstado(
                    title: 'Rechazado',
                    value: 'rechazado',
                    groupValue: estadoSeleccionado,
                    onChanged: (v) {
                      if (v != null) {
                        setStateModal(() {
                          estadoSeleccionado = v;
                        });
                      }
                    },
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
                    final bool selected = seleccionVehiculos.contains(tipoInterno);
                    return CheckboxListTile(
                      value: selected,
                      activeColor: AdminUi.progressAccent(ctx2),
                      title: Text(
                        veh,
                        style: TextStyle(color: AdminUi.secondary(ctx2)),
                      ),
                      onChanged: (v) {
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
                      hintStyle: TextStyle(color: AdminUi.secondary(ctx2).withValues(alpha: 0.75)),
                      filled: true,
                      fillColor: AdminUi.inputFill(ctx2),
                      border: OutlineInputBorder(
                        borderRadius: const BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: AdminUi.borderSubtle(ctx2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: const BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: AdminUi.borderSubtle(ctx2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: const BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: Theme.of(ctx2).colorScheme.primary, width: 1.4),
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
                            backgroundColor: Theme.of(ctx2).colorScheme.primaryContainer,
                            foregroundColor: Theme.of(ctx2).colorScheme.onPrimaryContainer,
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

    try {
      final String? adminUid = _auth.currentUser?.uid;

      final Map<String, dynamic> update = {
        'estado': estadoSeleccionado,
        'notaAdmin': notaCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'verificadoPor': adminUid,
        'verificadoEn': FieldValue.serverTimestamp(),
      };

      await _db.collection('choferes_turismo').doc(uid).set(
            update,
            SetOptions(merge: true),
          );

      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Cambios guardados'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        iconTheme: IconThemeData(color: AdminUi.appBarFg(context)),
        title: Text(
          'Choferes Turismo',
          style: TextStyle(color: AdminUi.onCard(context)),
        ),
        // 🔍 Barra de búsqueda en AppBar
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: AdminUi.onCard(context)),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, email o teléfono...',
                hintStyle: TextStyle(color: AdminUi.secondary(context).withValues(alpha: 0.85)),
                prefixIcon: Icon(Icons.search, color: AdminUi.secondary(context)),
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
                        icon: Icon(Icons.clear, color: AdminUi.secondary(context)),
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
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: AdminUi.progressAccent(context)),
            );
          }

          final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = snap.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No hay choferes registrados',
                style: TextStyle(color: AdminUi.secondary(context)),
              ),
            );
          }

          // Filtrar por búsqueda
          final List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredDocs = docs.where((doc) {
            if (_searchQuery.isEmpty) return true;
            final Map<String, dynamic> data = doc.data();
            final String nombre = (data['nombre'] ?? '').toString().toLowerCase();
            final String email = (data['email'] ?? '').toString().toLowerCase();
            final String telefono = (data['telefono'] ?? '').toString().toLowerCase();
            final String uid = doc.id.toLowerCase();
            return nombre.contains(_searchQuery) ||
                email.contains(_searchQuery) ||
                telefono.contains(_searchQuery) ||
                uid.contains(_searchQuery);
          }).toList();

          if (filteredDocs.isEmpty) {
            return Center(
              child: Text(
                'No se encontraron choferes',
                style: TextStyle(color: AdminUi.secondary(context)),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredDocs.length,
            itemBuilder: (BuildContext context, int index) {
              final QueryDocumentSnapshot<Map<String, dynamic>> doc = filteredDocs[index];
              final Map<String, dynamic> data = doc.data();
              final String uid = doc.id;

              final String nombre = (data['nombre'] ?? '').toString();
              final String email = (data['email'] ?? '').toString();
              final String telefono = (data['telefono'] ?? '').toString();
              final String estado = (data['estado'] ?? 'pendiente').toString();

              return Card(
                color: AdminUi.card(context),
                child: ListTile(
                  title: Text(
                    nombre.isNotEmpty ? nombre : uid,
                    style: TextStyle(color: AdminUi.onCard(context)),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _estadoLabel(estado),
                        style: TextStyle(
                          color: _estadoColor(estado),
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
                  trailing: IconButton(
                    icon: Icon(Icons.settings, color: AdminUi.iconStandard(context)),
                    onPressed: () {
                      _abrirConfigChofer(
                        context,
                        uid: uid,
                        data: data,
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _radioEstado({
    required String title,
    required String value,
    required String groupValue,
    required ValueChanged<String?> onChanged,
  }) {
    return RadioListTile<String>(
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
      activeColor: AdminUi.progressAccent(context),
      title: Text(
        title,
        style: TextStyle(color: AdminUi.secondary(context)),
      ),
    );
  }
}