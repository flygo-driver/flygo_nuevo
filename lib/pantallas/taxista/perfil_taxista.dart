import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PerfilTaxista extends StatelessWidget {
  const PerfilTaxista({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Mi Perfil', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Icon(Icons.person, size: 80, color: Colors.greenAccent),
            const SizedBox(height: 12),
            Text(
              user?.email ?? 'taxista',
              style: const TextStyle(color: Colors.white70),
            ),
            const Divider(color: Colors.white12, height: 32),
            ListTile(
              leading: const Icon(
                Icons.verified_user,
                color: Colors.greenAccent,
              ),
              title: const Text(
                'Documentación',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Aprobado',
                style: TextStyle(color: Colors.white54),
              ),
              onTap: () {}, // TODO: tu pantalla de docs
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.greenAccent),
              title: const Text(
                'Ajustes',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {}, // TODO
            ),
          ],
        ),
      ),
    );
  }
}
