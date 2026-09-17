import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';

/// Tarjeta sin cobrar RAI: detecta bloqueo y localiza el viaje pendiente.
class ClienteCobroTarjetaPendienteService {
  ClienteCobroTarjetaPendienteService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static bool esBloqueoTarjetaPendiente(Object error) {
    if (error is FirebaseFunctionsException) {
      if (error.code != 'failed-precondition') return false;
      return _mensajeEsTarjetaPendiente(error.message);
    }
    if (error is FirebaseException && error.code == 'permission-denied') {
      return _mensajeEsTarjetaPendiente(error.message);
    }
    return false;
  }

  static bool _mensajeEsTarjetaPendiente(String? raw) {
    final String msg = (raw ?? '').toLowerCase();
    if (msg.isEmpty) return false;
    return msg.contains('tarjeta') &&
        (msg.contains('pendiente') ||
            msg.contains('cobro') ||
            msg.contains('pago'));
  }

  static Future<bool> usuarioTieneBloqueoTarjeta({String? uid}) async {
    final String id = (uid ?? FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (id.isEmpty) return false;
    try {
      final snap = await _db.collection('usuarios').doc(id).get();
      if (snap.data()?['tieneCobroViajePendiente'] != true) return false;
      // Solo tarjeta bloquea; efectivo/transfer legacy puede tener flag residual.
      final String? viajeTarjeta = await resolverViajeIdTarjetaPendiente(uid: id);
      return viajeTarjeta != null;
    } catch (_) {
      return false;
    }
  }

  /// Viaje asociado a la deuda del cliente (tarjeta pendiente o impago legacy).
  static Future<({String id, Map<String, dynamic> data})?> resolverViajeDeudaCliente({
    String? uid,
  }) async {
    final String id = (uid ?? FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (id.isEmpty) return null;

    ({String id, Map<String, dynamic> data})? mejor;
    DateTime mejorTs = DateTime.fromMillisecondsSinceEpoch(0);

    void considerar(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      final Map<String, dynamic> d = doc.data();
      if (CorporativoTaxistaService.debeOcultarEnAppCliente(d)) return;
      final DateTime ts = _fechaViaje(d);
      if (ts.isAfter(mejorTs)) {
        mejorTs = ts;
        mejor = (id: doc.id, data: d);
      }
    }

    for (final String campoCliente in <String>['clienteId', 'uidCliente']) {
      try {
        final QuerySnapshot<Map<String, dynamic>> pendientes = await _db
            .collection('viajes')
            .where(campoCliente, isEqualTo: id)
            .where('cobroClientePendiente', isEqualTo: true)
            .limit(10)
            .get();
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in pendientes.docs) {
          considerar(doc);
        }
      } catch (_) {}
    }

    for (final String campoCliente in <String>['clienteId', 'uidCliente']) {
      try {
        final QuerySnapshot<Map<String, dynamic>> snap = await _db
            .collection('viajes')
            .where(campoCliente, isEqualTo: id)
            .where('completado', isEqualTo: true)
            .limit(50)
            .get();

        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs) {
          final Map<String, dynamic> d = doc.data();
          if (CorporativoTaxistaService.debeOcultarEnAppCliente(d)) continue;
          final String estado =
              (d['cobroClienteEstado'] ?? '').toString().trim().toLowerCase();
          if (estado == 'impago_registrado' ||
              estado == 'pendiente' ||
              d['cobroClientePendiente'] == true ||
              _esViajeTarjetaPendienteBloqueante(d)) {
            considerar(doc);
          }
        }
      } catch (_) {}
    }

    return mejor;
  }

  /// Viaje con tarjeta sin cobrar que bloquea nuevos pedidos (si existe).
  static Future<String?> resolverViajeIdTarjetaPendiente({String? uid}) async {
    final String id = (uid ?? FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (id.isEmpty) return null;

    final resolved = await resolverViajeDeudaCliente(uid: id);
    if (resolved == null) return null;
    if (!_esViajeTarjetaPendienteBloqueante(resolved.data)) return null;
    return resolved.id;
  }

  static bool _esViajeTarjetaPendienteBloqueante(Map<String, dynamic> d) {
    if (!MetodoPagoViaje.esTarjeta(d['metodoPago']?.toString())) return false;
    if (d['cobroClientePendiente'] == true) return true;
    return MetodoPagoViaje.cobroClienteBloqueaApp(d);
  }

  static DateTime _fechaViaje(Map<String, dynamic> d) {
    for (final String k in <String>[
      'finalizadoEn',
      'completadoEn',
      'updatedAt',
      'actualizadoEn',
      'fechaHora',
      'creadoEn',
    ]) {
      final dynamic v = d[k];
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
