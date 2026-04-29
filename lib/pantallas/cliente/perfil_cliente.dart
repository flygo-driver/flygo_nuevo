import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

class PerfilCliente extends StatelessWidget {
  const PerfilCliente({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: const RaiAppBar(
        title: 'Mi Perfil',
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.person, size: 80, color: Colors.greenAccent),
            const SizedBox(height: 12),
            Text(
              'Email: ${user?.email ?? '—'}',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'UID: ${user?.uid ?? '—'}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Editar perfil (placeholder)'),
                    ),
                  );
                },
                icon: const Icon(Icons.edit, color: Colors.greenAccent),
                label: const Text(
                  'Editar perfil',
                  style: TextStyle(color: Colors.greenAccent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
