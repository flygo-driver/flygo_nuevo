// lib/pantallas/admin/asignar_viaje_turismo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flygo_nuevo/servicios/asignacion_turismo_repo.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

import 'admin_ui_theme.dart';

class AsignarViajeTurismo extends StatefulWidget {
  final String viajeId;

  /// `subtipoTurismo` del viaje (carro, Carro Turismo, etc.)
  final String? subtipoTurismo;

  /// `tipoVehiculo` legado / emoji del documento
  final String? tipoVehiculoDoc;
  final double? latOrigen;
  final double? lonOrigen;

  const AsignarViajeTurismo({
    super.key,
    required this.viajeId,
    this.subtipoTurismo,
    this.tipoVehiculoDoc,
    this.latOrigen,
    this.lonOrigen,
  });

  @override
  State<AsignarViajeTurismo> createState() => _AsignarViajeTurismoState();
}

class _AsignarViajeTurismoState extends State<AsignarViajeTurismo> {
  String _filtroVehiculo = '';
  final TextEditingController _notaCtrl = TextEditingController();
  bool _asignacionEnCurso = false;

  late final String _tipoVehiculoRequerido;
  late final String _etiquetaTipo;

  @override
  void initState() {
    super.initState();
    _tipoVehiculoRequerido = AsignacionTurismoRepo.normalizarCodigoTipoTurismo(
      widget.subtipoTurismo,
      widget.tipoVehiculoDoc,
    );
    final String raw = (widget.subtipoTurismo ?? '').trim().isNotEmpty
        ? widget.subtipoTurismo!.trim()
        : (widget.tipoVehiculoDoc ?? '').trim();
    _etiquetaTipo = raw.isNotEmpty ? raw : _tipoVehiculoRequerido;
  }

  @override
  void dispose() {
    _notaCtrl.dispose();
    super.dispose();
  }

  String _mensajeFirebase(FirebaseException e) {
    final m = e.message?.trim();
    if (m != null && m.isNotEmpty) return m;
    return e.code;
  }

  /// Texto legible para códigos devueltos por [AsignacionTurismoRepo.asignarChofer].
  String _mensajeResultadoAsignacion(String res) {
    if (res == 'ok') return '';
    switch (res) {
      case 'viaje-no-existe':
        return 'El viaje ya no existe.';
      case 'no-turismo':
        return 'El viaje no es de turismo.';
      case 'canal-invalido':
        return 'El viaje ya no está en cola de administración (fue liberado al pool u otro canal).';
      case 'estado-invalido':
        return 'El estado del viaje ya no permite asignación manual.';
      case 'ya-asignado':
        return 'Este viaje ya tiene chofer asignado.';
      case 'chofer-no-existe':
        return 'El chofer no existe en turismo.';
      case 'chofer-no-aprobado':
        return 'El chofer no está aprobado para turismo.';
      case 'chofer-no-disponible':
        return 'El chofer ya no está disponible (posiblemente en otro viaje).';
      case 'chofer-bloqueo-prepago':
        return 'Chofer bloqueado por prepago/comisión RAI (misma regla que pool): '
            'regularizar billetera antes de asignar.';
      default:
        if (res.startsWith('firebase:')) {
          final code = res.substring('firebase:'.length);
          return 'Error de servidor (${code.isEmpty ? 'desconocido' : code}).';
        }
        return res;
    }
  }

  static String _fmtCalificacion(dynamic c) {
    if (c == null) return 'N/A';
    if (c is num) return c.toDouble().toStringAsFixed(1);
    final d = double.tryParse(c.toString());
    return d != null ? d.toStringAsFixed(1) : 'N/A';
  }

  static int _toIntViajes(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  Map<String, dynamic>? _vehiculoCoincidente(Map<String, dynamic> choferData) {
    for (final dynamic v in choferData['vehiculos'] as List? ?? const []) {
      if (v is! Map) continue;
      final String t = (v['tipo'] ?? '').toString().toLowerCase();
      if (t == _tipoVehiculoRequerido) {
        return Map<String, dynamic>.from(v);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        iconTheme: IconThemeData(color: AdminUi.appBarFg(context)),
        title: Text('Asignar chofer de turismo',
            style: TextStyle(color: AdminUi.onCard(context))),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Vehículo requerido: $_tipoVehiculoRequerido ($_etiquetaTipo)',
              style: TextStyle(color: AdminUi.secondary(context), fontSize: 12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              style: TextStyle(color: AdminUi.onCard(context)),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, teléfono o tipo de vehículo...',
                hintStyle: TextStyle(
                    color: AdminUi.secondary(context).withValues(alpha: 0.75)),
                prefixIcon:
                    Icon(Icons.search, color: AdminUi.secondary(context)),
                filled: true,
                fillColor: AdminUi.inputFill(context),
                border: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: AdminUi.borderSubtle(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: AdminUi.borderSubtle(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: cs.primary, width: 1.4),
                ),
              ),
              onChanged: (String v) =>
                  setState(() => _filtroVehiculo = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('choferes_turismo')
                  .where('estado', isEqualTo: 'aprobado')
                  .where('disponible', isEqualTo: true)
                  .snapshots(),
              builder: (BuildContext context,
                  AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                      child: CircularProgressIndicator(
                          color: AdminUi.progressAccent(context)));
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
                                color: AdminUi.secondary(context),
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
                    snapshot.data?.docs ?? [];

                final List<QueryDocumentSnapshot<Map<String, dynamic>>>
                    choferesCompatibles = docs.where((doc) {
                  return _vehiculoCoincidente(doc.data()) != null;
                }).toList();

                if (choferesCompatibles.isEmpty) {
                  final warn = Theme.of(context).brightness == Brightness.light
                      ? Colors.deepOrange.shade700
                      : Colors.orangeAccent;
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, color: warn, size: 64),
                          const SizedBox(height: 16),
                          Text(
                            'No hay choferes disponibles para',
                            style: TextStyle(color: AdminUi.secondary(context)),
                          ),
                          Text(
                            _tipoVehiculoRequerido.toUpperCase(),
                            style: TextStyle(
                              color: warn,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Verifica que:\n'
                            '• Haya choferes con ese vehículo\n'
                            '• Estén aprobados\n'
                            '• Estén disponibles',
                            style: TextStyle(color: AdminUi.muted(context)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final List<QueryDocumentSnapshot<Map<String, dynamic>>>
                    choferesFiltrados = choferesCompatibles.where((doc) {
                  if (_filtroVehiculo.isEmpty) return true;
                  final Map<String, dynamic> data = doc.data();
                  final String nombre =
                      (data['nombre'] ?? '').toString().toLowerCase();
                  final String tel =
                      (data['telefono'] ?? '').toString().toLowerCase();
                  final String email =
                      (data['email'] ?? '').toString().toLowerCase();
                  if (nombre.contains(_filtroVehiculo) ||
                      tel.contains(_filtroVehiculo) ||
                      email.contains(_filtroVehiculo)) {
                    return true;
                  }
                  final List<dynamic> vehiculos =
                      (data['vehiculos'] as List?) ?? [];
                  final List<String> tipos = vehiculos
                      .map((v) =>
                          (v is Map ? v['tipo'] : '').toString().toLowerCase())
                      .toList();
                  return tipos.any((String t) => t.contains(_filtroVehiculo));
                }).toList();

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: choferesFiltrados.length,
                  itemBuilder: (BuildContext context, int index) {
                    final QueryDocumentSnapshot<Map<String, dynamic>> doc =
                        choferesFiltrados[index];
                    final Map<String, dynamic> data = doc.data();

                    return FutureBuilder<double>(
                      future: _calcularDistancia(data),
                      builder: (BuildContext context,
                          AsyncSnapshot<double> distanciaSnap) {
                        final double distancia =
                            distanciaSnap.data ?? double.infinity;

                        final green = AdminUi.accentGreen(context);
                        final String nombre = (data['nombre'] ?? '').toString();
                        final String inicial =
                            nombre.isNotEmpty ? nombre[0].toUpperCase() : '?';

                        return Card(
                          color: AdminUi.card(context),
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: AdminUi.borderSubtle(context)),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(12),
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).brightness ==
                                      Brightness.light
                                  ? Colors.deepPurple.shade100
                                  : Colors.purple,
                              child: Text(
                                inicial,
                                style: TextStyle(
                                  color: Theme.of(context).brightness ==
                                          Brightness.light
                                      ? Colors.deepPurple.shade900
                                      : Colors.white,
                                ),
                              ),
                            ),
                            title: Text(
                              nombre.isNotEmpty ? nombre : 'Sin nombre',
                              style: TextStyle(color: AdminUi.onCard(context)),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '📞 ${data['telefono'] ?? ''}',
                                  style: TextStyle(
                                      color: AdminUi.secondary(context)),
                                ),
                                Wrap(
                                  spacing: 4,
                                  children: (data['vehiculos'] as List?)
                                          ?.where((dynamic v) {
                                        if (v is! Map) return false;
                                        return (v['tipo'] ?? '')
                                                .toString()
                                                .toLowerCase() ==
                                            _tipoVehiculoRequerido;
                                      }).map((dynamic v) {
                                        return Chip(
                                          label: Text('✅ ${v['tipo'] ?? ''}'),
                                          backgroundColor:
                                              green.withValues(alpha: 0.18),
                                          labelStyle: TextStyle(
                                            color: green,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        );
                                      }).toList() ??
                                      const [],
                                ),
                                if (distancia != double.infinity)
                                  Text(
                                    '📍 A ${distancia.toStringAsFixed(1)} km',
                                    style: TextStyle(
                                        color: AdminUi.muted(context)),
                                  ),
                                Text(
                                  '⭐ ${_fmtCalificacion(data['calificacion'])} '
                                  '(${_toIntViajes(data['viajesCompletados'])} viajes)',
                                  style: TextStyle(
                                    color: Theme.of(context).brightness ==
                                            Brightness.light
                                        ? Colors.amber.shade900
                                        : Colors.amber,
                                  ),
                                ),
                              ],
                            ),
                            trailing: ElevatedButton(
                              onPressed: _asignacionEnCurso
                                  ? null
                                  : () => _asignar(doc.id, data),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                foregroundColor: Colors.white,
                              ),
                              child: Text(_asignacionEnCurso ? '…' : 'Asignar'),
                            ),
                          ),
                        );
                      },
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

  Future<double> _calcularDistancia(Map<String, dynamic> chofer) async {
    if (widget.latOrigen == null || widget.lonOrigen == null) {
      return double.infinity;
    }

    double? lat;
    double? lon;

    final dynamic u = chofer['ultimaUbicacion'];
    if (u is GeoPoint) {
      lat = u.latitude;
      lon = u.longitude;
    } else {
      final Map? ubicacion = chofer['ubicacion'] as Map?;
      if (ubicacion != null) {
        lat = (ubicacion['lat'] as num?)?.toDouble();
        lon = (ubicacion['lon'] as num?)?.toDouble();
      }
    }

    if (lat == null || lon == null) return double.infinity;

    return Geolocator.distanceBetween(
          widget.latOrigen!,
          widget.lonOrigen!,
          lat,
          lon,
        ) /
        1000;
  }

  Future<void> _asignar(String uidChofer, Map<String, dynamic> data) async {
    if (_asignacionEnCurso) return;

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AdminUi.dialogSurface(ctx),
        title: Text('Confirmar asignación',
            style: TextStyle(color: AdminUi.onCard(ctx))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('¿Asignar este chofer?',
                style: TextStyle(color: AdminUi.secondary(ctx))),
            const SizedBox(height: 12),
            TextField(
              controller: _notaCtrl,
              style: TextStyle(color: AdminUi.onCard(ctx)),
              decoration: InputDecoration(
                labelText: 'Nota (opcional)',
                labelStyle: TextStyle(color: AdminUi.secondary(ctx)),
                border: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: AdminUi.borderSubtle(ctx)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: AdminUi.borderSubtle(ctx)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(
                      color: Theme.of(ctx).colorScheme.primary, width: 1.4),
                ),
                filled: true,
                fillColor: AdminUi.inputFill(ctx),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: TextStyle(color: AdminUi.secondary(ctx))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.primary,
              foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
            ),
            child: const Text('Asignar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final Map<String, dynamic>? veh = _vehiculoCoincidente(data);
    if (veh == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El chofer ya no tiene un vehículo compatible.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final String placa = (veh['placa'] ?? '').toString();
    final String marca = (veh['marca'] ?? '').toString();
    final String modelo = (veh['modelo'] ?? '').toString();
    final String color = (veh['color'] ?? '').toString();
    final String nota = _notaCtrl.text.trim();

    setState(() => _asignacionEnCurso = true);
    try {
      final String res = await AsignacionTurismoRepo.asignarChofer(
        viajeId: widget.viajeId,
        uidChofer: uidChofer,
        nombreChofer: (data['nombre'] ?? '').toString(),
        telefonoChofer: (data['telefono'] ?? '').toString(),
        placa: placa,
        subtipoTurismoCodigo: _tipoVehiculoRequerido,
        notaAdmin: nota.isNotEmpty ? nota : null,
        marca: marca,
        modelo: modelo,
        color: color,
      );

      if (!mounted) return;

      if (res == 'ok') {
        try {
          await ViajesRepo.ensureChatDocForViaje(widget.viajeId);
        } catch (_) {
          // La asignación ya quedó; el chat se puede crear después.
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chofer asignado'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        final msg = _mensajeResultadoAsignacion(res);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg.isEmpty ? res : msg),
            backgroundColor: Colors.red,
          ),
        );
      }
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
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _asignacionEnCurso = false);
    }
  }
}
