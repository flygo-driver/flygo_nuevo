import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Conductor publicado en `drivers_location` (app abierta + GPS activo).
class RaiDriverLocationLive {
  const RaiDriverLocationLive({
    required this.uid,
    required this.position,
    required this.disponible,
    required this.updatedAt,
    this.heading,
    this.viajeId,
    this.clienteId,
  });

  final String uid;
  final LatLng position;
  final bool disponible;
  final DateTime? updatedAt;
  final double? heading;
  final String? viajeId;
  final String? clienteId;

  bool fresca({Duration maxAge = const Duration(minutes: 3)}) {
    if (updatedAt == null) return true;
    return DateTime.now().difference(updatedAt!) <= maxAge;
  }
}

abstract final class RaiDriversLocationParser {
  RaiDriversLocationParser._();

  static RaiDriverLocationLive? fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    Duration maxAge = const Duration(minutes: 3),
  }) {
    final Map<String, dynamic>? data = doc.data();
    if (data == null) return null;

    final bool tracking = data['tracking'] == true;
    final bool online = data['online'] == true;
    if (!tracking && !online) return null;

    final GeoPoint? gp = _geo(data['location']);
    if (gp == null || !_coordsOk(gp.latitude, gp.longitude)) return null;

    DateTime? updatedAt;
    final dynamic rawTs = data['updatedAt'];
    if (rawTs is Timestamp) updatedAt = rawTs.toDate();
    if (rawTs is DateTime) updatedAt = rawTs;
    if (updatedAt != null && DateTime.now().difference(updatedAt) > maxAge) {
      return null;
    }

    double? heading;
    final dynamic h = data['heading'];
    if (h is num && h.isFinite && h >= 0 && h <= 360) {
      heading = h.toDouble();
    }

    final String viajeId = (data['viajeId'] ?? '').toString().trim();
    final String clienteId = (data['clienteId'] ?? '').toString().trim();

    return RaiDriverLocationLive(
      uid: doc.id,
      position: LatLng(gp.latitude, gp.longitude),
      disponible: online && viajeId.isEmpty,
      updatedAt: updatedAt,
      heading: heading,
      viajeId: viajeId.isEmpty ? null : viajeId,
      clienteId: clienteId.isEmpty ? null : clienteId,
    );
  }

  static List<RaiDriverLocationLive> fromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap, {
    Duration maxAge = const Duration(minutes: 3),
  }) {
    final List<RaiDriverLocationLive> out = <RaiDriverLocationLive>[];
    for (final DocumentSnapshot<Map<String, dynamic>> doc in snap.docs) {
      final RaiDriverLocationLive? d =
          fromDoc(doc, maxAge: maxAge);
      if (d != null) out.add(d);
    }
    return out;
  }

  static GeoPoint? _geo(dynamic raw) {
    if (raw is GeoPoint) return raw;
    return null;
  }

  static bool _coordsOk(double lat, double lon) =>
      lat.isFinite && lon.isFinite && lat.abs() <= 90 && lon.abs() <= 180;
}
