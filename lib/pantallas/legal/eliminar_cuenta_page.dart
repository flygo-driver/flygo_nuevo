// lib/pantallas/legal/eliminar_cuenta_page.dart
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/legal/terms_data.dart';
import 'package:flygo_nuevo/legal/legal_urls.dart';

class EliminarCuentaPage extends StatelessWidget {
  const EliminarCuentaPage({super.key});

  @override
  Widget build(BuildContext context) {
    const body = TextStyle(color: Colors.white, height: 1.58, fontSize: 14);
    const h1 = TextStyle(
      color: Colors.white,
      fontSize: 20,
      fontWeight: FontWeight.w800,
      height: 1.25,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Eliminar mi cuenta'),
        backgroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('¿Cómo borro mi cuenta?', style: h1),
            const SizedBox(height: 10),
            const Text(
              'Desde la app: Cuenta → Eliminar cuenta (esta pantalla) o solicita por correo.',
              style: body,
            ),
            const SizedBox(height: 12),
            const Text(
              'La eliminación desactiva tu acceso y borra o anonimiza datos no sujetos a '
              'conservación legal. Registros de viaje, facturación y evidencias necesarias '
              'pueden conservarse por plazos legales.',
              style: body,
            ),
            const SizedBox(height: 18),
            Text(
              'Correo de solicitud: $kTermsContactEmail',
              style: body,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => abrirEliminarCuentaWeb(context),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Instrucciones en la web (Google Play)'),
            ),
          ],
        ),
      ),
    );
  }
}
