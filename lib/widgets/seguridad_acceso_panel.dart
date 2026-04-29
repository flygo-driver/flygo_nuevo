import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SeguridadAccesoPanel extends StatefulWidget {
  const SeguridadAccesoPanel({super.key});

  @override
  State<SeguridadAccesoPanel> createState() => _SeguridadAccesoPanelState();
}

class _SeguridadAccesoPanelState extends State<SeguridadAccesoPanel> {
  Future<void> _vincularGoogle() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // 🔗 Vínculo con Google sin usar google_sign_in (compatible con firebase_auth 4.x)
      final provider = GoogleAuthProvider();
      provider.setCustomParameters({'prompt': 'select_account'});
      await user.linkWithProvider(provider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cuenta vinculada con Google.')),
      );
    } on FirebaseAuthException catch (e) {
      var msg = 'No se pudo vincular.';
      if (e.code == 'provider-already-linked') {
        msg = 'Ya estaba vinculada con Google.';
      } else if (e.code == 'credential-already-in-use') {
        msg = 'Ese Google ya está ligado a otra cuenta.';
      } else if (e.code == 'requires-recent-login') {
        msg = 'Vuelve a iniciar sesión y reintenta.';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _agregarOCambiarContrasena() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '';
    if (user == null || email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta cuenta no tiene email.')),
      );
      return;
    }

    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Definir contraseña'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration:
              const InputDecoration(hintText: 'Nueva contraseña (min. 6)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar')),
        ],
      ),
    );

    if (ok != true) return;
    final pwd = ctrl.text.trim();
    if (pwd.length < 6) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mínimo 6 caracteres.')),
      );
      return;
    }

    try {
      final tienePassword =
          user.providerData.any((p) => p.providerId == 'password');
      if (!tienePassword) {
        final cred = EmailAuthProvider.credential(email: email, password: pwd);
        await user.linkWithCredential(cred); // añade proveedor password
      } else {
        await user.updatePassword(pwd); // ya tenía password → solo cambia
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contraseña configurada.')),
      );
    } on FirebaseAuthException catch (e) {
      var msg = 'No se pudo configurar la contraseña.';
      if (e.code == 'requires-recent-login') {
        msg = 'Vuelve a iniciar sesión y reintenta.';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final tieneGoogle =
        user?.providerData.any((p) => p.providerId == 'google.com') ?? false;
    final tienePassword =
        user?.providerData.any((p) => p.providerId == 'password') ?? false;

    return Card(
      color: const Color(0xFF121212),
      margin: const EdgeInsets.only(top: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Seguridad y acceso',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: tieneGoogle ? null : _vincularGoogle,
                    icon: const Icon(Icons.link),
                    label: Text(tieneGoogle
                        ? 'Google vinculado'
                        : 'Vincular con Google'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _agregarOCambiarContrasena,
                    icon: const Icon(Icons.password, color: Colors.green),
                    label: Text(tienePassword
                        ? 'Cambiar contraseña'
                        : 'Agregar contraseña'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
