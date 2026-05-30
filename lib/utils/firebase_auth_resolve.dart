import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

/// `FirebaseAuth.instance.currentUser` puede ser `null` unos milisegundos al
/// arrancar Auth o al volver del background aunque la sesión siga viva.
/// Espera a un usuario desde [authStateChanges] antes de tratar como logout.
Future<User?> resolveFirebaseUser({
  Duration timeout = const Duration(seconds: 4),
}) async {
  final User? now = FirebaseAuth.instance.currentUser;
  if (now != null) return now;
  try {
    return await FirebaseAuth.instance
        .authStateChanges()
        .where((u) => u != null)
        .cast<User>()
        .timeout(timeout)
        .first;
  } on TimeoutException {
    return FirebaseAuth.instance.currentUser;
  }
}
