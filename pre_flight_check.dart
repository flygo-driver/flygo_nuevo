// Verificación rápida pre-pruebas en calle (RAI / giras prepago).
//
// Ejecutar desde la raíz del repo:
//   dart run pre_flight_check.dart
//
// Requiere el mismo entorno Firebase que la app (Windows/Android/iOS según plataforma).
// Si las callables devuelven `unauthenticated`, iniciá sesión en la app con la misma
// cuenta o habilitá acceso anónimo en Firebase Auth para pruebas.
//
// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'package:flygo_nuevo/firebase_options.dart';

bool _tieneComisionGiraEstimada(Map<String, dynamic> d) {
  final v = d['comisionGiraEstimadaRd'];
  if (v is num && v.isFinite && v > 1e-9) return true;
  if (v is String) {
    final x = double.tryParse(v);
    return x != null && x.isFinite && x > 1e-9;
  }
  return false;
}

Future<void> _pingCallable(String name, Map<String, dynamic> payload) async {
  try {
    final c =
        FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(name);
    await c.call(payload);
    print('  [OK] $name respondió sin lanzar (revisar payload si era inesperado).');
  } on FirebaseFunctionsException catch (e) {
    print('  [ping] $name → ${e.code}: ${e.message}');
  } catch (e) {
    print('  [ping] $name → $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  print('[PRE_FLIGHT] Firebase inicializado (projectId=${DefaultFirebaseOptions.currentPlatform.projectId})');

  try {
    await FirebaseAuth.instance.signInAnonymously();
    print('[PRE_FLIGHT] Auth: anónimo OK uid=${FirebaseAuth.instance.currentUser?.uid}');
  } catch (e) {
    print(
      '[PRE_FLIGHT] Auth anónimo no disponible: $e\n'
      '  Continuando solo lecturas Firestore que permita el usuario actual.',
    );
  }

  final db = FirebaseFirestore.instance;

  final appCfg = await db.collection('configuracion_globals').doc('app').get();
  final comGira = appCfg.data()?['comision_gira_porcentaje'];
  print('[PRE_FLIGHT] configuracion_globals/app.comision_gira_porcentaje → $comGira');

  final pruebas = await db.collection('configuracion_globals').doc('pruebas').get();
  print('[PRE_FLIGHT] configuracion_globals/pruebas → ${pruebas.data()}');

  print(
    '[PRE_FLIGHT] Reglas Firestore: `ledger_giras` debe tener create/update/delete en false '
    'para clientes; reservas y devoluciones solo vía Cloud Functions.',
  );

  print('[PRE_FLIGHT] Buscando giras “legacy” (sin comisionGiraEstimadaRd válida) en muestra…');
  const activos = <String>{
    'abierto',
    'preconfirmado',
    'confirmado',
    'activo',
    'disponible',
    'buscando',
    'en_ruta',
  };
  final snap = await db.collection('viajes_pool').limit(500).get();
  final legacy = <String>[];
  for (final doc in snap.docs) {
    final d = doc.data();
    final est = (d['estado'] ?? '').toString().trim().toLowerCase();
    if (!activos.contains(est)) continue;
    if (!_tieneComisionGiraEstimada(d)) {
      legacy.add('${doc.id} (estado=$est)');
    }
  }
  if (legacy.isEmpty) {
    print('  Ninguna en la muestra de ${snap.docs.length} documentos.');
  } else {
    print('  Encontradas ${legacy.length} (muestra máx. 500 docs):');
    for (final id in legacy.take(40)) {
      print('    - $id');
    }
    if (legacy.length > 40) {
      print('    … y ${legacy.length - 40} más. Sugerencia: cancelarlas y recrearlas.');
    } else {
      print('  Sugerencia: cancelarlas desde la app o admin y recrearlas con comisión estimada.');
    }
  }

  print('[PRE_FLIGHT] Ping de callables (se espera not-found / invalid-argument, no unauthenticated):');
  final ts = DateTime.now().millisecondsSinceEpoch;
  await _pingCallable('startPoolTrip', {
    'poolId': '__pre_flight__',
    'idempotencyKey': 'pf_start_$ts',
  });
  await _pingCallable('cancelPoolTrip', {
    'poolId': '__pre_flight__',
    'motivo': 'pre_flight_check',
    'idempotencyKey': 'pf_cancel_$ts',
  });
  await _pingCallable('finalizePoolTrip', {
    'poolId': '__pre_flight__',
    'idempotencyKey': 'pf_fin_$ts',
  });

  print('[PRE_FLIGHT] Listo.');
}
