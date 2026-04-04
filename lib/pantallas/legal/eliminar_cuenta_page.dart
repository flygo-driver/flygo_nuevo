// lib/pantallas/comun/eliminar_cuenta_page.dart
import 'package:flutter/material.dart';

class EliminarCuentaPage extends StatelessWidget {
  const EliminarCuentaPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Estilos constantes reutilizables
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
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Cómo borro mi cuenta?', style: h1),
            SizedBox(height: 10),
            Text(
              'Abre la app → Perfil → Configuración → Eliminar cuenta. '
              'La eliminación desactiva tu acceso y borra o anonimiza datos no sujetos a conservación legal. '
              'Registros de viaje, facturación y evidencias necesarias pueden conservarse por plazos legales.',
              style: body,
            ),
            SizedBox(height: 18),
            Text(
              'Si no puedes acceder a tu cuenta, solicita la eliminación desde el canal de soporte dentro de la app.',
              style: body,
            ),
          ],
        ),
      ),
    );
  }
}
