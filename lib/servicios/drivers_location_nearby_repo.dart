import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:flygo_nuevo/servicios/drivers_location_nearby_config.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/utils/rai_geohash.dart';
import 'package:flygo_nuevo/utils/rai_region_operativa.dart';
import 'package:flygo_nuevo/widgets/rai_live_driver_map_animator.dart';

/// Resultado de consulta geoespacial (escalable — no lee toda la colección).
class DriversLocationNearbyUpdate {
  const DriversLocationNearbyUpdate({
    required this.conductores,
    required this.docs,
    required this.region,
  });

  final List<RaiLiveDriverPoint> conductores;
  final List<DocumentSnapshot<Map<String, dynamic>>> docs;
  final String region;
}

/// Escucha conductores por **región + geohash** (nacional sin mezclar ciudades).
class DriversLocationNearbySession {
  DriversLocationNearbySession({
    required this.onUpdate,
    this.radiusKm = 30,
    this.maxResultados = 60,
    this.maxAge = const Duration(minutes: 4),
  });

  final void Function(DriversLocationNearbyUpdate update) onUpdate;
  final double radiusKm;
  final int maxResultados;
  final Duration maxAge;

  final Map<String, DocumentSnapshot<Map<String, dynamic>>> _merged =
      <String, DocumentSnapshot<Map<String, dynamic>>>{};
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _cellSubs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _legacyCellSubs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _asignadoSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _fallbackSub;

  LatLng? _queryCenter;
  String _region = RaiRegionOperativa.otros;
  List<String> _prefixes = const <String>[];
  String? _uidAsignado;

  void update({
    required LatLng center,
    String? uidAsignado,
    bool forzarReconsulta = false,
  }) {
    final String nuevaRegion =
        RaiRegionOperativa.resolver(center.latitude, center.longitude);
    final bool cambioRegion = nuevaRegion != _region;

    final bool recalc = forzarReconsulta ||
        cambioRegion ||
        _queryCenter == null ||
        RaiGeohash.debeRecalcularConsulta(
          prevLat: _queryCenter!.latitude,
          prevLon: _queryCenter!.longitude,
          newLat: center.latitude,
          newLon: center.longitude,
          radiusKm: radiusKm,
        );

    if (recalc) {
      _queryCenter = center;
      if (cambioRegion) {
        _region = nuevaRegion;
        _merged.clear();
        _rearmarFallback();
      }
      _rearmarConsultasCeldas();
    }

    if (_uidAsignado != uidAsignado) {
      _uidAsignado = uidAsignado;
      _rearmarAsignado(uidAsignado);
    }
  }

  void dispose() {
    for (final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> s
        in _cellSubs) {
      unawaited(s.cancel());
    }
    _cellSubs.clear();
    for (final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> s
        in _legacyCellSubs) {
      unawaited(s.cancel());
    }
    _legacyCellSubs.clear();
    unawaited(_asignadoSub?.cancel());
    unawaited(_fallbackSub?.cancel());
    _asignadoSub = null;
    _fallbackSub = null;
    _merged.clear();
  }

  void _iniciar(LatLng center, String? uidAsignado) {
    _queryCenter = center;
    _region = RaiRegionOperativa.resolver(center.latitude, center.longitude);
    _uidAsignado = uidAsignado;
    _rearmarConsultasCeldas();
    _rearmarFallback();
    _rearmarAsignado(uidAsignado);
  }

  void _rearmarConsultasCeldas() {
    final LatLng? center = _queryCenter;
    if (center == null) return;

    for (final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> s
        in _cellSubs) {
      unawaited(s.cancel());
    }
    _cellSubs.clear();
    for (final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> s
        in _legacyCellSubs) {
      unawaited(s.cancel());
    }
    _legacyCellSubs.clear();

    _prefixes = RaiGeohash.prefixesForRadius(
      center.latitude,
      center.longitude,
      radiusKm,
    );

    for (final String prefix in _prefixes) {
      final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> sub =
          FirebaseFirestore.instance
              .collection('drivers_location')
              .where('region', isEqualTo: _region)
              .where('geohash', isGreaterThanOrEqualTo: prefix)
              .where('geohash',
                  isLessThanOrEqualTo: RaiGeohash.upperBound(prefix))
              .limit(40)
              .snapshots()
              .listen(
        (QuerySnapshot<Map<String, dynamic>> snap) {
          for (final DocumentSnapshot<Map<String, dynamic>> d in snap.docs) {
            _merged[d.id] = d;
          }
          _publicarMerged();
        },
        onError: (_) => _publicarMerged(),
      );
      _cellSubs.add(sub);
    }

    // Migración: docs sin campo `region` (app conductor antigua) — misma celda geohash.
    if (DriversLocationNearbyConfig.consultasLegacySinRegion) {
      for (final String prefix in _prefixes) {
        final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> sub =
            FirebaseFirestore.instance
                .collection('drivers_location')
                .where('geohash', isGreaterThanOrEqualTo: prefix)
                .where('geohash',
                    isLessThanOrEqualTo: RaiGeohash.upperBound(prefix))
                .limit(25)
                .snapshots()
                .listen(
          (QuerySnapshot<Map<String, dynamic>> snap) {
            for (final DocumentSnapshot<Map<String, dynamic>> d in snap.docs) {
              if (RaiRegionOperativa.desdeDoc(d.data()) != null) continue;
              if (!RaiRegionOperativa.docEnRegion(d.data(), _region)) continue;
              _merged[d.id] = d;
            }
            _publicarMerged();
          },
          onError: (_) => _publicarMerged(),
        );
        _legacyCellSubs.add(sub);
      }
    }
  }

  /// Migración: conductores sin `geohash` en la misma región (límite fijo).
  void _rearmarFallback() {
    unawaited(_fallbackSub?.cancel());
    _fallbackSub = FirebaseFirestore.instance
        .collection('drivers_location')
        .where('region', isEqualTo: _region)
        .where('tracking', isEqualTo: true)
        .orderBy('updatedAt', descending: true)
        .limit(35)
        .snapshots()
        .listen(
      (QuerySnapshot<Map<String, dynamic>> snap) {
        for (final DocumentSnapshot<Map<String, dynamic>> d in snap.docs) {
          final String? gh = d.data()?['geohash']?.toString();
          if (gh != null && gh.isNotEmpty) continue;
          if (!RaiRegionOperativa.docEnRegion(d.data(), _region)) continue;
          _merged[d.id] = d;
        }
        _publicarMerged();
      },
      onError: (_) => _publicarMerged(),
    );
  }

  void _rearmarAsignado(String? uid) {
    unawaited(_asignadoSub?.cancel());
    _asignadoSub = null;
    if (uid == null || uid.isEmpty) {
      _publicarMerged();
      return;
    }
    _asignadoSub = FirebaseFirestore.instance
        .collection('drivers_location')
        .doc(uid)
        .snapshots()
        .listen((DocumentSnapshot<Map<String, dynamic>> snap) {
      if (snap.exists) {
        _merged[uid] = snap;
      } else {
        _merged.remove(uid);
      }
      _publicarMerged();
    }, onError: (_) => _publicarMerged());
  }

  void _publicarMerged() {
    final LatLng? center = _queryCenter;
    if (center == null) return;

    final Iterable<DocumentSnapshot<Map<String, dynamic>>> enRegion =
        _merged.values.where(
      (DocumentSnapshot<Map<String, dynamic>> d) =>
          RaiRegionOperativa.docEnRegion(d.data(), _region),
    );

    final List<RaiLiveDriverPoint> parsed = raiLiveDriversDesdeDocs(
      enRegion,
      centroKm: center,
      radioKm: radiusKm,
      maxAge: maxAge,
    );

    parsed.sort((a, b) {
      final double ka = DistanciaService.calcularDistancia(
        center.latitude,
        center.longitude,
        a.position.latitude,
        a.position.longitude,
      );
      final double kb = DistanciaService.calcularDistancia(
        center.latitude,
        center.longitude,
        b.position.latitude,
        b.position.longitude,
      );
      return ka.compareTo(kb);
    });

    final List<RaiLiveDriverPoint> limited = parsed.length > maxResultados
        ? parsed.sublist(0, maxResultados)
        : parsed;

    final List<DocumentSnapshot<Map<String, dynamic>>> docs = limited
        .map((RaiLiveDriverPoint p) => _merged[p.uid])
        .whereType<DocumentSnapshot<Map<String, dynamic>>>()
        .toList(growable: false);

    onUpdate(
      DriversLocationNearbyUpdate(
        conductores: limited,
        docs: docs,
        region: _region,
      ),
    );
  }
}

abstract final class DriversLocationNearbyRepo {
  DriversLocationNearbyRepo._();

  static DriversLocationNearbySession createSession({
    required LatLng initialCenter,
    required void Function(DriversLocationNearbyUpdate update) onUpdate,
    String? uidAsignado,
    double radiusKm = 30,
    int maxResultados = 60,
  }) {
    final DriversLocationNearbySession session = DriversLocationNearbySession(
      onUpdate: onUpdate,
      radiusKm: radiusKm,
      maxResultados: maxResultados,
    );
    session._iniciar(initialCenter, uidAsignado);
    return session;
  }
}
