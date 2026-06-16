import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/taxista/completar_registro_taxista.dart';
import 'package:flygo_nuevo/servicios/taxista_registro_perfil_data.dart';

/// Bloquea la app taxista si el perfil operativo no está completo (sin huecos).
class TaxistaRegistroGate extends StatelessWidget {
  const TaxistaRegistroGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return child;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snap.data?.data() ?? <String, dynamic>{};
        if (!TaxistaRegistroPerfilData.taxistaRegistroPerfilCompleto(data)) {
          return const CompletarRegistroTaxista();
        }
        return child;
      },
    );
  }
}
