import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flygo_nuevo/data/viaje_data.dart';

/// Cola local de calificaciones para reintentar cuando vuelve la red.
class CalificacionPendienteService {
  CalificacionPendienteService._();

  static const String _key = 'calificacion_pendiente_v1';

  static bool esErrorDeRed(Object e) {
    if (e is TimeoutException) return true;
    if (e is FirebaseFunctionsException) {
      return e.code == 'unavailable' ||
          e.code == 'deadline-exceeded' ||
          e.code == 'internal' ||
          e.code == 'unknown';
    }
    final String s = e.toString().toLowerCase();
    return s.contains('network') ||
        s.contains('socket') ||
        s.contains('connection') ||
        s.contains('internet') ||
        s.contains('host lookup') ||
        s.contains('failed host lookup') ||
        s.contains('timed out');
  }

  static Future<void> encolar({
    required String rol,
    required String viajeId,
    required String uid,
    required double calificacion,
    String? comentario,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> list = _leerLista(prefs);
    list.removeWhere(
      (Map<String, dynamic> e) =>
          e['viajeId'] == viajeId && e['rol'] == rol,
    );
    list.add(<String, dynamic>{
      'rol': rol,
      'viajeId': viajeId,
      'uid': uid,
      'calificacion': calificacion,
      if (comentario != null && comentario.trim().isNotEmpty)
        'comentario': comentario.trim(),
      'encoladoEn': DateTime.now().toIso8601String(),
    });
    await prefs.setString(_key, jsonEncode(list));
  }

  static Future<void> quitar({
    required String rol,
    required String viajeId,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> list = _leerLista(prefs);
    final int antes = list.length;
    list.removeWhere(
      (Map<String, dynamic> e) =>
          e['viajeId'] == viajeId && e['rol'] == rol,
    );
    if (list.length != antes) {
      await prefs.setString(_key, jsonEncode(list));
    }
  }

  static Future<int> flushPendientes() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> list = _leerLista(prefs);
    if (list.isEmpty) return 0;

    int enviados = 0;
    final List<Map<String, dynamic>> restantes = <Map<String, dynamic>>[];

    for (final Map<String, dynamic> item in list) {
      final String rol = (item['rol'] ?? '').toString();
      final String viajeId = (item['viajeId'] ?? '').toString();
      final String uid = (item['uid'] ?? '').toString();
      final double cal = (item['calificacion'] as num?)?.toDouble() ?? 0;
      final String? comentario = (item['comentario'] as String?)?.trim();

      if (viajeId.isEmpty || uid.isEmpty || cal < 1 || cal > 5) continue;

      try {
        if (rol == 'cliente') {
          await ViajeData.calificarViajeSeguro(
            viajeId: viajeId,
            uidCliente: uid,
            calificacion: cal,
            comentario: comentario,
            reintentosRed: 2,
          );
        } else if (rol == 'taxista') {
          await ViajeData.calificarClienteSeguro(
            viajeId: viajeId,
            uidTaxista: uid,
            calificacion: cal,
            comentario: comentario,
            reintentosRed: 2,
          );
        } else {
          continue;
        }
        enviados++;
      } catch (e) {
        if (esErrorDeRed(e)) {
          restantes.add(item);
        } else {
          debugPrint('CalificacionPendiente: descartada $viajeId ($rol): $e');
        }
      }
    }

    await prefs.setString(_key, jsonEncode(restantes));
    return enviados;
  }

  static List<Map<String, dynamic>> _leerLista(SharedPreferences prefs) {
    final String raw = prefs.getString(_key) ?? '[]';
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((Map e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }
}
