import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminDrawer extends StatelessWidget {
  const AdminDrawer({super.key});

  Future<void> _signOut(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      // Ajusta la ruta si tu login/splash es otra.
      // Esto limpia la pila y vuelve al root.
      // ignore: use_build_context_synchronously
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    } catch (e) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cerrar sesión: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0E0E0E),
      child: SafeArea(
        child: Column(
          children: [
            const ListTile(
              leading: Icon(Icons.admin_panel_settings, color: Colors.white),
              title: Text('Panel de administración',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              subtitle: Text('FlyGo', style: TextStyle(color: Colors.white54)),
            ),
            const Divider(color: Colors.white10),

            ListTile(
              leading: const Icon(Icons.home, color: Colors.white),
              title: const Text('Inicio admin', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(context).pop(); // cierra drawer
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),

            const Spacer(),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text(
                'Cerrar sesión',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700),
              ),
              onTap: () => _signOut(context),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
