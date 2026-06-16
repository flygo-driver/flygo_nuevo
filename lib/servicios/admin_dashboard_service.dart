import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AdminCentroMetricas {
  final int expedientesEnRevision;
  final int solicitudesTurismoPendiente;
  final int liquidacionesPendiente;
  final int pagosPendiente;
  final int viajesActivos;
  final int viajesBuscando;
  final int bolasAbiertas;
  final int bolasEnCurso;
  final int bolasTransferenciaPendiente;
  final int alertasNoLeidas;
  final int incidenciasAbiertas;
  final int reportesViajeAbiertos;
  final int bloqueosComision;
  final int recargasPrepagoPendiente;
  final int viajesCompletados24h;
  final int viajesCancelados24h;
  final DateTime? updatedAt;

  const AdminCentroMetricas({
    this.expedientesEnRevision = 0,
    this.solicitudesTurismoPendiente = 0,
    this.liquidacionesPendiente = 0,
    this.pagosPendiente = 0,
    this.viajesActivos = 0,
    this.viajesBuscando = 0,
    this.bolasAbiertas = 0,
    this.bolasEnCurso = 0,
    this.bolasTransferenciaPendiente = 0,
    this.alertasNoLeidas = 0,
    this.incidenciasAbiertas = 0,
    this.reportesViajeAbiertos = 0,
    this.bloqueosComision = 0,
    this.recargasPrepagoPendiente = 0,
    this.viajesCompletados24h = 0,
    this.viajesCancelados24h = 0,
    this.updatedAt,
  });

  factory AdminCentroMetricas.fromMap(Map<String, dynamic> m) {
    int i(String k) => (m[k] as num?)?.toInt() ?? 0;
    DateTime? ts;
    final raw = m['updatedAt'];
    if (raw is String) ts = DateTime.tryParse(raw);
    return AdminCentroMetricas(
      expedientesEnRevision: i('expedientesEnRevision'),
      solicitudesTurismoPendiente: i('solicitudesTurismoPendiente'),
      liquidacionesPendiente: i('liquidacionesPendiente'),
      pagosPendiente: i('pagosPendiente'),
      viajesActivos: i('viajesActivos'),
      viajesBuscando: i('viajesBuscando'),
      bolasAbiertas: i('bolasAbiertas'),
      bolasEnCurso: i('bolasEnCurso'),
      bolasTransferenciaPendiente: i('bolasTransferenciaPendiente'),
      alertasNoLeidas: i('alertasNoLeidas'),
      incidenciasAbiertas: i('incidenciasAbiertas'),
      reportesViajeAbiertos: i('reportesViajeAbiertos'),
      bloqueosComision: i('bloqueosComision'),
      recargasPrepagoPendiente: i('recargasPrepagoPendiente'),
      viajesCompletados24h: i('viajesCompletados24h'),
      viajesCancelados24h: i('viajesCancelados24h'),
      updatedAt: ts,
    );
  }
}

class AdminViajeResumen {
  final String id;
  final String estado;
  final String tipoServicio;
  final String uidCliente;
  final String uidTaxista;
  final String origen;
  final String destino;
  final double tarifa;
  final DateTime? updatedAt;

  const AdminViajeResumen({
    required this.id,
    required this.estado,
    required this.tipoServicio,
    required this.uidCliente,
    required this.uidTaxista,
    required this.origen,
    required this.destino,
    required this.tarifa,
    this.updatedAt,
  });

  factory AdminViajeResumen.fromMap(Map<String, dynamic> m) {
    double tarifa = 0;
    final t = m['tarifa'];
    if (t is num) tarifa = t.toDouble();
    DateTime? u;
    final raw = m['updatedAt'];
    if (raw is String) u = DateTime.tryParse(raw);
    return AdminViajeResumen(
      id: (m['id'] ?? '').toString(),
      estado: (m['estado'] ?? '').toString(),
      tipoServicio: (m['tipoServicio'] ?? '').toString(),
      uidCliente: (m['uidCliente'] ?? '').toString(),
      uidTaxista: (m['uidTaxista'] ?? '').toString(),
      origen: (m['origen'] ?? '').toString(),
      destino: (m['destino'] ?? '').toString(),
      tarifa: tarifa,
      updatedAt: u,
    );
  }
}

class AdminStatsResumen {
  final int dias;
  final int total;
  final int completados;
  final int cancelados;
  final double tasaCancel;
  final int activosAhora;

  const AdminStatsResumen({
    required this.dias,
    required this.total,
    required this.completados,
    required this.cancelados,
    required this.tasaCancel,
    required this.activosAhora,
  });

  factory AdminStatsResumen.fromMap(Map<String, dynamic> m) {
    return AdminStatsResumen(
      dias: (m['dias'] as num?)?.toInt() ?? 7,
      total: (m['total'] as num?)?.toInt() ?? 0,
      completados: (m['completados'] as num?)?.toInt() ?? 0,
      cancelados: (m['cancelados'] as num?)?.toInt() ?? 0,
      tasaCancel: (m['tasaCancel'] as num?)?.toDouble() ?? 0,
      activosAhora: (m['activosAhora'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdminRaiUsageItem {
  final String uid;
  final String nombre;
  final int count;
  final int limit;

  const AdminRaiUsageItem({
    required this.uid,
    required this.nombre,
    required this.count,
    this.limit = 50,
  });

  factory AdminRaiUsageItem.fromMap(Map<String, dynamic> m) {
    return AdminRaiUsageItem(
      uid: (m['uid'] ?? '').toString(),
      nombre: (m['nombre'] ?? '').toString(),
      count: (m['count'] as num?)?.toInt() ?? 0,
      limit: (m['limit'] as num?)?.toInt() ?? 50,
    );
  }
}

class AdminAuditItem {
  final String id;
  final String action;
  final String actorUid;
  final String resourceType;
  final String resourceId;
  final String outcome;
  final DateTime? ts;

  const AdminAuditItem({
    required this.id,
    required this.action,
    required this.actorUid,
    required this.resourceType,
    required this.resourceId,
    required this.outcome,
    this.ts,
  });

  factory AdminAuditItem.fromMap(Map<String, dynamic> m) {
    DateTime? ts;
    final raw = m['ts'];
    if (raw is String) ts = DateTime.tryParse(raw);
    return AdminAuditItem(
      id: (m['id'] ?? '').toString(),
      action: (m['action'] ?? '').toString(),
      actorUid: (m['actorUid'] ?? '').toString(),
      resourceType: (m['resourceType'] ?? '').toString(),
      resourceId: (m['resourceId'] ?? '').toString(),
      outcome: (m['outcome'] ?? '').toString(),
      ts: ts,
    );
  }
}

class AdminDashboardService {
  static final FirebaseFunctions _fx = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  static Future<AdminCentroMetricas> fetchCentroMetricas() async {
    final c = _fx.httpsCallable('getAdminCentroMetricas');
    final r = await c.call();
    final m = (r.data as Map).cast<String, dynamic>();
    final metrics = (m['metrics'] as Map?)?.cast<String, dynamic>() ?? m;
    return AdminCentroMetricas.fromMap(metrics);
  }

  static const List<String> _estadosActivosViaje = <String>[
    'aceptado',
    'asignado',
    'en_camino_pickup',
    'en_camino',
    'a_bordo',
    'en_curso',
  ];

  /// Resumen desde Firestore (fallback si la CF falla o no está desplegada).
  static Future<AdminStatsResumen> computeStatsResumenLocal({int dias = 7}) async {
    final int diasClamped = dias.clamp(1, 90);
    final db = FirebaseFirestore.instance;
    final Timestamp desde =
        Timestamp.fromDate(DateTime.now().subtract(Duration(days: diasClamped)));

    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
    try {
      final snap = await db
          .collection('viajes')
          .where('updatedAt', isGreaterThanOrEqualTo: desde)
          .orderBy('updatedAt', descending: true)
          .limit(1500)
          .get();
      docs = snap.docs;
    } catch (_) {
      try {
        final snap = await db
            .collection('viajes')
            .where('updatedAt', isGreaterThanOrEqualTo: desde)
            .limit(2000)
            .get();
        docs = snap.docs.toList()
          ..sort((a, b) {
            final ta = a.data()['updatedAt'];
            final tb = b.data()['updatedAt'];
            if (ta is Timestamp && tb is Timestamp) {
              return tb.compareTo(ta);
            }
            return 0;
          });
      } catch (_) {
        final snap = await db
            .collection('viajes')
            .orderBy('updatedAt', descending: true)
            .limit(1200)
            .get();
        docs = snap.docs.where((d) {
          final raw = d.data()['updatedAt'];
          if (raw is! Timestamp) return false;
          return !raw.toDate().isBefore(desde.toDate());
        }).toList();
      }
    }

    var completados = 0;
    var cancelados = 0;
    for (final d in docs) {
      final e = (d.data()['estado'] ?? '').toString().trim().toLowerCase();
      if (e == 'completado' || e == 'completed') completados++;
      if (e == 'cancelado' || e == 'canceled') cancelados++;
    }

    var activosAhora = 0;
    try {
      final activosSnap = await db
          .collection('viajes')
          .where('estado', whereIn: _estadosActivosViaje)
          .limit(500)
          .get();
      activosAhora = activosSnap.size;
    } catch (_) {
      for (final d in docs) {
        final e = (d.data()['estado'] ?? '').toString().trim().toLowerCase();
        if (_estadosActivosViaje.contains(e)) activosAhora++;
      }
    }

    final total = docs.length;
    final tasaCancel = total > 0 ? cancelados / total : 0.0;
    return AdminStatsResumen(
      dias: diasClamped,
      total: total,
      completados: completados,
      cancelados: cancelados,
      tasaCancel: double.parse(tasaCancel.toStringAsFixed(4)),
      activosAhora: activosAhora,
    );
  }

  static Future<AdminStatsResumen> fetchStatsResumen({int dias = 7}) async {
    try {
      final c = _fx.httpsCallable('getAdminStatsResumen');
      final r = await c.call(<String, dynamic>{'dias': dias});
      final data = r.data;
      if (data is! Map) {
        return computeStatsResumenLocal(dias: dias);
      }
      return AdminStatsResumen.fromMap(data.cast<String, dynamic>());
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'permission-denied') {
        throw Exception(
          e.message?.trim().isNotEmpty == true
              ? e.message!.trim()
              : 'Tu usuario no tiene rol admin en Firestore.',
        );
      }
      return computeStatsResumenLocal(dias: dias);
    } catch (_) {
      return computeStatsResumenLocal(dias: dias);
    }
  }

  static Future<List<AdminViajeResumen>> listViajesActivos({
    String modo = 'activos',
    int limit = 50,
    String? cursor,
  }) async {
    final c = _fx.httpsCallable('listViajesActivosAdmin');
    final r = await c.call(<String, dynamic>{
      'modo': modo,
      'limit': limit,
      if (cursor != null) 'cursor': cursor,
    });
    final m = (r.data as Map).cast<String, dynamic>();
    final items = (m['items'] as List?) ?? const [];
    return items
        .map((e) => AdminViajeResumen.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
  }

  static Future<({List<AdminRaiUsageItem> items, int totalCalls, String day})>
      listRaiUsage({int limit = 50}) async {
    final c = _fx.httpsCallable('listRaiAsistenteUsageAdmin');
    final r = await c.call(<String, dynamic>{'limit': limit});
    final m = (r.data as Map).cast<String, dynamic>();
    final items = (m['items'] as List?) ?? const [];
    return (
      items: items
          .map((e) =>
              AdminRaiUsageItem.fromMap((e as Map).cast<String, dynamic>()))
          .toList(),
      totalCalls: (m['totalCalls'] as num?)?.toInt() ?? 0,
      day: (m['day'] ?? '').toString(),
    );
  }

  static Future<List<AdminAuditItem>> listAudit({
    int limit = 40,
    String? cursor,
  }) async {
    final c = _fx.httpsCallable('listAdminAudit');
    final r = await c.call(<String, dynamic>{
      'limit': limit,
      if (cursor != null) 'cursor': cursor,
    });
    final m = (r.data as Map).cast<String, dynamic>();
    final items = (m['items'] as List?) ?? const [];
    return items
        .map((e) => AdminAuditItem.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
  }

  static Future<void> marcarAlertaLeida(String alertaId) async {
    final c = _fx.httpsCallable('marcarAdminAlertaLeida');
    await c.call(<String, dynamic>{'alertaId': alertaId});
  }

  static Future<int> marcarTodasAlertasLeidas() async {
    final c = _fx.httpsCallable('marcarTodasAdminAlertasLeidas');
    final r = await c.call();
    return ((r.data as Map)['updated'] as num?)?.toInt() ?? 0;
  }
}
