import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Aviso poco frecuente al cliente en hitos de uso (3, 10, 30, 50 viajes). Una vez por hito y usuario en este dispositivo.
class ClienteFidelidadMilestoneListener extends StatefulWidget {
  const ClienteFidelidadMilestoneListener({super.key, required this.child});

  final Widget child;

  @override
  State<ClienteFidelidadMilestoneListener> createState() =>
      _ClienteFidelidadMilestoneListenerState();
}

class _ClienteFidelidadMilestoneListenerState
    extends State<ClienteFidelidadMilestoneListener> {
  static const List<int> _hitos = [3, 10, 30, 50];

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  int _ultimoN = -1;

  @override
  void initState() {
    super.initState();
    final User? u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    _sub = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(u.uid)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final int n = _leerCompletados(snap.data());
      if (n == _ultimoN) return;
      _ultimoN = n;
      unawaited(_evaluarHitoSiCorresponde(u.uid, n));
    });
  }

  int _leerCompletados(Map<String, dynamic>? m) {
    if (m == null) return 0;
    final dynamic v = m['clienteViajesCompletados'];
    if (v is int) return v < 0 ? 0 : v;
    if (v is num) return v.toInt().clamp(0, 999999);
    return 0;
  }

  String _mensajeHito(int h, int n) {
    switch (h) {
      case 3:
        return '¡Ya sumás $n viajes con RAI! Gracias por confiar en el servicio.';
      case 10:
        return '¡$n viajes completados! Sos un usuario muy activo — gracias.';
      case 30:
        return '¡$n viajes! Tu confianza nos impulsa a seguir mejorando.';
      case 50:
        return '¡$n viajes completados! Gracias por ser parte de la comunidad RAI.';
      default:
        return '¡Gracias por seguir eligiendo RAI!';
    }
  }

  Future<void> _evaluarHitoSiCorresponde(String uid, int n) async {
    if (n <= 0) return;
    final SharedPreferences p = await SharedPreferences.getInstance();
    if (!mounted) return;
    for (final int h in _hitos.reversed) {
      if (n < h) continue;
      final String key = 'fidelidad_hito_${uid}_$h';
      if (p.getBool(key) == true) continue;
      await p.setBool(key, true);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          content: Text(
            _mensajeHito(h, n),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
      return;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
