import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart' as cf;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../modelo/viaje.dart';

class TripsService {
  TripsService._();

  static void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }

  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static const String _region = 'us-central1';
  static const int _umbralAhoraMin = 10;

  static String _callableUrl(String name) {
    final proj = Firebase.app().options.projectId;
    return 'https://$_region-$proj.cloudfunctions.net/$name';
  }

  static Future<Map<String, dynamic>> _callCallableHttp(
    String name,
    Map<String, dynamic> payload,
  ) async {
    final u = _auth.currentUser;
    final idToken = await u?.getIdToken();
    final url = Uri.parse(_callableUrl(name));

    final body = jsonEncode({'data': payload});
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (idToken != null) 'Authorization': 'Bearer $idToken',
    };

    _log('[CF HTTP] POST $url payload=$payload');
    final res = await http.post(url, headers: headers, body: body);

    if (res.statusCode != 200) {
      _log('[CF HTTP] $name -> ${res.statusCode} ${res.body}');
      throw FirebaseException(
        plugin: 'cloud_functions_http',
        code: 'http-${res.statusCode}',
        message: res.body.isNotEmpty ? res.body : 'Error HTTP',
      );
    }

    final Map<String, dynamic> decoded =
        (jsonDecode(res.body) as Map).cast<String, dynamic>();
    final dynamic inner = decoded['result'] ?? decoded['data'] ?? decoded;
    return (inner as Map).cast<String, dynamic>();
  }

  static Future<String> crearViaje(Viaje v) async {
    final u = _auth.currentUser;
    if (u == null) {
      throw FirebaseAuthException(
        code: 'no-auth',
        message: 'Debes iniciar sesión.',
      );
    }

    final esAhora = !v.fechaHora.isAfter(
      DateTime.now().add(const Duration(minutes: _umbralAhoraMin)),
    );

    final data = v.toCreateMap();
    data['uidCliente'] = u.uid;
    data['clienteId'] = u.uid;
    data['esAhora'] = esAhora;

    data['uidTaxista'] = '';
    data['taxistaId'] = '';
    data['nombreTaxista'] = '';

    final ref = await _db.collection('viajes').add(data);
    _log('[Viajes] creado ${ref.id}');
    return ref.id;
  }

  static Future<({String pin, DateTime? expiresAt})> emitirPin(
    String tripId, {
    int ttlMinutes = 240,
  }) async {
    try {
      final functions = cf.FirebaseFunctions.instanceFor(region: _region);
      final callable = functions.httpsCallable('issueBoardingPin');
      _log('[CF plugin] issueBoardingPin call tripId=$tripId');
      final res = await callable.call(<String, dynamic>{
        'tripId': tripId,
        'ttlMinutes': ttlMinutes,
      });

      final data = (res.data as Map).cast<String, dynamic>();
      final pin = (data['pin'] ?? '').toString();
      final expIso = (data['expiresAt'] ?? '').toString();

      final DateTime? expires = DateTime.tryParse(expIso);
      return (pin: pin, expiresAt: expires);
    } catch (e) {
      _log('[CF plugin] issueBoardingPin FALLÓ -> $e');
      final data = await _callCallableHttp('issueBoardingPin', {
        'tripId': tripId,
        'ttlMinutes': ttlMinutes,
      });
      final pin = (data['pin'] ?? '').toString();
      final expIso = (data['expiresAt'] ?? '').toString();
      return (pin: pin, expiresAt: DateTime.tryParse(expIso));
    }
  }

  static Future<void> confirmarAbordaje(String tripId, String pin) async {
    try {
      final functions = cf.FirebaseFunctions.instanceFor(region: _region);
      final callable = functions.httpsCallable('confirmBoarding');
      _log('[CF plugin] confirmBoarding call tripId=$tripId pin=$pin');
      await callable.call(<String, dynamic>{'tripId': tripId, 'pin': pin});
    } catch (e) {
      _log('[CF plugin] confirmBoarding FALLÓ -> $e');
      await _callCallableHttp(
          'confirmBoarding', {'tripId': tripId, 'pin': pin});
    }
  }

  static Stream<List<Viaje>> streamProgramadosAsignados(String uidTaxista) {
    final desde = DateTime.now().subtract(const Duration(days: 1));

    return _db
        .collection('viajes')
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('fechaHora', isGreaterThanOrEqualTo: Timestamp.fromDate(desde))
        .where('estado',
            whereIn: ['aceptado', 'en_camino_pickup', 'encaminopickup'])
        .orderBy('fechaHora', descending: false)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Viaje.fromMap(d.id, d.data())).toList());
  }
}
