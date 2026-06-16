import 'package:flutter/material.dart';

import 'package:flygo_nuevo/auth/seleccion_usuario.dart';
import 'package:flygo_nuevo/pantallas/taxista/entry_taxista.dart';

/// Error recuperable en [TaxistaEntry] (nunca redirige a shell cliente).
class TaxistaEntryErrorPage extends StatelessWidget {
  const TaxistaEntryErrorPage({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Conductor'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            const Text(
              'No pudimos cargar tu perfil de conductor.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => const TaxistaEntry(),
                  ),
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/auth_check',
                  (r) => false,
                );
              },
              child: const Text('Volver a inicio de sesión'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute<void>(
                    builder: (_) => const SeleccionUsuario(),
                  ),
                  (r) => false,
                );
              },
              child: const Text('Elegir otra cuenta'),
            ),
          ],
        ),
      ),
    );
  }
}
