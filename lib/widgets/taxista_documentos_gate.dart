import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/taxista/documentos_taxista.dart';
import 'package:flygo_nuevo/servicios/taxista_operacion_gate.dart';

/// Tras registro completo: obliga documentos hasta enviar a revisión (o renovación/rechazo).
class TaxistaDocumentosGate extends StatelessWidget {
  const TaxistaDocumentosGate({super.key, required this.child});

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
        if (taxistaDebeCompletarDocumentosAhora(data)) {
          return const DocumentosTaxista(onboardingObligatorio: true);
        }
        return child;
      },
    );
  }
}
