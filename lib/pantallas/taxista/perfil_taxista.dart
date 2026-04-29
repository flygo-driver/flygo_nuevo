// lib/pantallas/taxista/perfil_taxista.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Reutilizamos tu screen de foto y el avatar redondo
import 'panel_taxista.dart' show PerfilFotoScreen; // ya lo tienes ahí
import 'package:flygo_nuevo/widgets/avatar_circle.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';

class PerfilTaxista extends StatelessWidget {
  const PerfilTaxista({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.greenAccent,
          title: const Text('Mi Perfil'),
          centerTitle: true,
        ),
        body: const Center(
          child: Text('Inicia sesión para ver tu perfil',
              style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    final uid = user.uid;
    final usersRef = FirebaseFirestore.instance.collection('usuarios').doc(uid);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.greenAccent,
        title: const Text('Mi Perfil'),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: usersRef.snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() ?? const <String, dynamic>{};
          final nombre = (data['nombre'] ?? user.displayName ?? '').toString();
          final email = (user.email ?? '').toString();
          final fotoUrl = (data['fotoUrl'] ?? '').toString();
          final disponible = (data['disponible'] ?? false) == true;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Column(
                  children: [
                    AvatarCircle(
                      imageUrl: fotoUrl.isNotEmpty ? fotoUrl : null,
                      name: nombre.isNotEmpty ? nombre : email,
                      size: 110,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const PerfilFotoScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      nombre.isNotEmpty ? nombre : 'Taxista',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email.isNotEmpty ? email : '(sin correo)',
                      style: const TextStyle(color: Colors.white54),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 180,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const PerfilFotoScreen()),
                          );
                        },
                        icon: const Icon(Icons.camera_alt,
                            color: Colors.greenAccent),
                        label: const Text('Cambiar foto',
                            style: TextStyle(color: Colors.greenAccent)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.greenAccent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Divider(color: Colors.white12),
              const SizedBox(height: 6),

              // Disponibilidad — capturamos el messenger ANTES del gap async
              SwitchListTile.adaptive(
                activeColor: Colors.greenAccent,
                value: disponible,
                title: const Text('Disponible para aceptar viajes',
                    style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  disponible
                      ? 'Apareces en el pool'
                      : 'No aparecerás en disponibles',
                  style: const TextStyle(color: Colors.white54),
                ),
                onChanged: (val) {
                  final messenger = ScaffoldMessenger.of(context);
                  () async {
                    if (val) {
                      final snap = await usersRef.get();
                      if (snap.data()?['tienePagoPendiente'] == true) {
                        if (!context.mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: const Text(PagosTaxistaRepo
                                .mensajeRecargaActivarDisponible),
                            action: SnackBarAction(
                              label: 'Mis pagos',
                              onPressed: () {
                                Navigator.of(context).pushNamed('/mis_pagos');
                              },
                            ),
                          ),
                        );
                        return;
                      }
                    }
                    try {
                      await usersRef.set({
                        'disponible': val,
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                      if (!context.mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(val
                              ? 'Disponibilidad activada'
                              : 'Disponibilidad desactivada'),
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      messenger.showSnackBar(
                        SnackBar(content: Text('Error al actualizar: $e')),
                      );
                    }
                  }();
                },
              ),

              const SizedBox(height: 6),
              const Divider(color: Colors.white12),
              const SizedBox(height: 6),

              // Documentación (placeholder)
              ListTile(
                leading:
                    const Icon(Icons.verified_user, color: Colors.greenAccent),
                title: const Text('Documentación',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text('Estado: Aprobado',
                    style: TextStyle(color: Colors.white54)),
                onTap: () {
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.showSnackBar(const SnackBar(
                      content: Text('TODO: Pantalla de documentación')));
                },
              ),

              // Ajustes (placeholder)
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.greenAccent),
                title: const Text('Ajustes',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.showSnackBar(const SnackBar(
                      content: Text('TODO: Pantalla de ajustes')));
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
