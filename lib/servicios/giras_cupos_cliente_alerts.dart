import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flygo_nuevo/app_flavor.dart';
import 'package:flygo_nuevo/servicios/notification_service.dart';

/// Alertas in-app (timbre + bandeja) para el catálogo **Giras por cupos** del cliente.
/// No afecta el timbre del conductor ni otros productos.
class GirasCuposClienteAlerts {
  GirasCuposClienteAlerts._();

  static final GirasCuposClienteAlerts I = GirasCuposClienteAlerts._();

  static const String _kSeenIds = 'giras_cupos_cliente_seen_v1';

  final Set<String> _sessionSeen = <String>{};

  Future<void> handleCatalogUpdate({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required bool esPrimeraEmisionSuscripcion,
    required bool welcomeYaEnEstaVisita,
    required void Function() onWelcomePlayed,
  }) async {
    if (!isClienteFlavor) return;

    if (esPrimeraEmisionSuscripcion) {
      if (!welcomeYaEnEstaVisita) {
        await _alertarEntradaCatalogo(docs);
        onWelcomePlayed();
      } else {
        await _alertarSalidasNoVistas(docs);
      }
      await _marcarVistas(docs.map((d) => d.id));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final persisted = (prefs.getStringList(_kSeenIds) ?? <String>[]).toSet();

    for (final doc in docs) {
      final id = doc.id;
      if (_sessionSeen.contains(id)) continue;
      if (persisted.contains(id)) {
        _sessionSeen.add(id);
        continue;
      }
      await _alertarNuevaSalida(doc);
      _sessionSeen.add(id);
      await _persistSeenId(prefs, id);
    }
  }

  Future<void> _alertarEntradaCatalogo(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (docs.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final persisted = (prefs.getStringList(_kSeenIds) ?? <String>[]).toSet();
    final nuevas =
        docs.where((d) => !persisted.contains(d.id)).length;

    await NotificationService.I.notifyEntradaCatalogoGirasCliente(
      salidasVisibles: docs.length,
      salidasNuevas: nuevas,
    );
  }

  Future<void> _alertarSalidasNoVistas(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (docs.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final persisted = (prefs.getStringList(_kSeenIds) ?? <String>[]).toSet();
    var alertadas = 0;

    for (final doc in docs) {
      final id = doc.id;
      if (_sessionSeen.contains(id) || persisted.contains(id)) continue;
      await _alertarNuevaSalida(doc);
      _sessionSeen.add(id);
      await _persistSeenId(prefs, id);
      alertadas++;
    }

    if (alertadas == 0) return;
  }

  Future<void> _alertarNuevaSalida(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final d = doc.data();
    final titulo = _tituloGira(d);
    final cuerpo = _cuerpoGira(d);
    await NotificationService.I.notifyGiraCuposCliente(
      poolId: doc.id,
      titulo: titulo,
      cuerpo: cuerpo,
    );
  }

  Future<void> _marcarVistas(Iterable<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    for (final id in ids) {
      _sessionSeen.add(id);
      await _persistSeenId(prefs, id);
    }
  }

  Future<void> _persistSeenId(SharedPreferences prefs, String id) async {
    final ids = prefs.getStringList(_kSeenIds) ?? <String>[];
    if (ids.contains(id)) return;
    ids.add(id);
    if (ids.length > 300) {
      ids.removeRange(0, ids.length - 300);
    }
    await prefs.setStringList(_kSeenIds, ids);
  }

  static String _tituloGira(Map<String, dynamic> d) {
    final agencia = (d['agenciaNombre'] ?? '').toString().trim();
    final origen =
        (d['origenTown'] ?? d['origen'] ?? 'Origen').toString().trim();
    final destino = (d['destino'] ?? 'Destino').toString().trim();
    if (agencia.isNotEmpty) {
      return '$agencia · $origen → $destino';
    }
    return '$origen → $destino';
  }

  static String _cuerpoGira(Map<String, dynamic> d) {
    final cap = (d['capacidad'] as num?)?.toInt() ?? 0;
    final occ = (d['asientosReservados'] as num?)?.toInt() ?? 0;
    final left = (cap - occ).clamp(0, cap);
    final precio = (d['precioPorAsiento'] as num?)?.toDouble() ?? 0;
    final mult = (d['sentido'] == 'ida_y_vuelta') ? 2 : 1;
    final precioTxt = precio > 0
        ? 'Desde RD\$ ${(precio * mult).toStringAsFixed(0)}'
        : 'Consultá precio en la app';
    return left > 0
        ? '$left cupo${left == 1 ? '' : 's'} · $precioTxt'
        : 'Cupos completos · $precioTxt';
  }
}
