import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Registro GPS corporativo: `viajes/{viajeId}/gps_track/{puntoId}`.
/// Cola offline en SharedPreferences; sincroniza al recuperar red.
class CorporativoViajeGpsTracker {
  CorporativoViajeGpsTracker._();
  static final CorporativoViajeGpsTracker instance =
      CorporativoViajeGpsTracker._();

  static const Duration _intervaloMin = Duration(seconds: 8);

  String? _viajeId;
  DateTime? _ultimoEnvio;
  bool _sincronizando = false;

  String _prefsKey(String viajeId) => 'corp_gps_pending_$viajeId';

  CollectionReference<Map<String, dynamic>> _col(String viajeId) =>
      FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .collection('gps_track');

  Future<void> start(String viajeId) async {
    if (_viajeId == viajeId) return;
    await stop();
    _viajeId = viajeId;
    await flushPending(viajeId);
  }

  Future<void> stop() async {
    _viajeId = null;
    _ultimoEnvio = null;
  }

  /// Punto continuo en ruta (throttle 8 s). Ignora lecturas muy imprecisas.
  static const double _accuracyMaxMetros = 75;

  Future<void> onPosition({
    required String viajeId,
    required double lat,
    required double lon,
    double? accuracy,
  }) async {
    if (accuracy != null &&
        accuracy.isFinite &&
        accuracy > _accuracyMaxMetros) {
      return;
    }
    if (_viajeId != viajeId) await start(viajeId);
    final now = DateTime.now();
    if (_ultimoEnvio != null && now.difference(_ultimoEnvio!) < _intervaloMin) {
      return;
    }
    _ultimoEnvio = now;
    await _guardarPunto(
      viajeId: viajeId,
      lat: lat,
      lon: lon,
      accuracy: accuracy,
      tipo: 'en_ruta',
    );
  }

  Future<void> recordCheckpoint({
    required String viajeId,
    required String tipo,
    required double lat,
    required double lon,
    double? accuracy,
  }) async {
    await _guardarPunto(
      viajeId: viajeId,
      lat: lat,
      lon: lon,
      accuracy: accuracy,
      tipo: tipo,
    );
  }

  /// Puntos ya guardados en Firestore (para dibujar el recorrido al reabrir).
  Future<List<({double lat, double lon})>> cargarPuntosMapa(
    String viajeId, {
    int limit = 400,
  }) async {
    try {
      final snap = await _col(viajeId)
          .orderBy('timestamp', descending: false)
          .limit(limit)
          .get();
      final out = <({double lat, double lon})>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final lat = (d['lat'] as num?)?.toDouble();
        final lon = (d['lon'] as num?)?.toDouble();
        if (lat == null || lon == null || lat == 0 || lon == 0) continue;
        out.add((lat: lat, lon: lon));
      }
      return out;
    } catch (e) {
      debugPrint('[CorpGPS] cargarPuntosMapa: $e');
      return const [];
    }
  }

  Future<void> flushPending(String viajeId) async {
    if (_sincronizando) return;
    _sincronizando = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey(viajeId));
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) return;

      final col = _col(viajeId);
      final restantes = <Map<String, dynamic>>[];

      for (final item in list) {
        try {
          final tipo = (item['tipo'] ?? 'en_ruta').toString();
          await col.add({
            'lat': (item['lat'] as num).toDouble(),
            'lon': (item['lon'] as num).toDouble(),
            'timestamp': Timestamp.fromMillisecondsSinceEpoch(
              (item['ts'] as num).toInt(),
            ),
            if (item['accuracy'] != null)
              'accuracy': (item['accuracy'] as num).toDouble(),
            'tipo': tipo,
            'offline': true,
            'syncedEn': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          debugPrint('[CorpGPS] flush pending error: $e');
          restantes.add(item);
        }
      }

      if (restantes.isEmpty) {
        await prefs.remove(_prefsKey(viajeId));
      } else {
        await prefs.setString(_prefsKey(viajeId), jsonEncode(restantes));
      }
    } finally {
      _sincronizando = false;
    }
  }

  Future<void> _guardarPunto({
    required String viajeId,
    required double lat,
    required double lon,
    double? accuracy,
    required String tipo,
  }) async {
    final payload = <String, dynamic>{
      'lat': lat,
      'lon': lon,
      'timestamp': FieldValue.serverTimestamp(),
      'tipo': tipo,
      if (accuracy != null && accuracy.isFinite) 'accuracy': accuracy,
    };

    try {
      await _col(viajeId).add(payload);
    } catch (e) {
      debugPrint('[CorpGPS] online write failed → cola local: $e');
      await _encolarLocal(
        viajeId: viajeId,
        lat: lat,
        lon: lon,
        accuracy: accuracy,
        tipo: tipo,
      );
    }
  }

  Future<void> _encolarLocal({
    required String viajeId,
    required double lat,
    required double lon,
    double? accuracy,
    required String tipo,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _prefsKey(viajeId);
    final raw = prefs.getString(key);
    final list = raw == null || raw.isEmpty
        ? <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    list.add({
      'lat': lat,
      'lon': lon,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'tipo': tipo,
      if (accuracy != null) 'accuracy': accuracy,
    });
    // Evitar crecimiento infinito offline.
    while (list.length > 500) {
      list.removeAt(0);
    }
    await prefs.setString(key, jsonEncode(list));
  }
}
