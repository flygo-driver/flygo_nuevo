import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:flygo_nuevo/design_system/rai_ds_theme.dart';
import 'package:flygo_nuevo/pantallas/taxista/taxista_notificaciones_page.dart';

/// Saludo personalizado + acceso rápido a cuenta (campana).
class TaxistaInicioHeader extends StatelessWidget {
  const TaxistaInicioHeader({super.key, required this.uid});

  final String uid;

  String _primerNombre(Map<String, dynamic>? data) {
    final user = FirebaseAuth.instance.currentUser;
    final raw = (data?['nombre'] ?? user?.displayName ?? 'Conductor')
        .toString()
        .trim();
    if (raw.isEmpty) return 'Conductor';
    return raw.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('usuarios').doc(uid).snapshots(),
      builder: (context, snap) {
        final nombre = _primerNombre(snap.data?.data());

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 12, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'Hola, $nombre 👋',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.raiTextPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.15,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Notificaciones',
                onPressed: () {
                  Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TaxistaNotificacionesPage(),
                    ),
                  );
                },
                icon: Icon(
                  PhosphorIconsRegular.bell,
                  color: context.raiTextPrimary.withValues(alpha: 0.92),
                  size: 22,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: context.raiCard,
                  minimumSize: const Size(44, 44),
                  maximumSize: const Size(44, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: context.raiBorder),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
