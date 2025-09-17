import 'package:flutter/material.dart';

class TerminosCondicionesPage extends StatelessWidget {
  const TerminosCondicionesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Condiciones de uso')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _P('Última actualización: 2025-09-14'),
          _H('1. Aceptación'),
          _P('Al usar FlyGo aceptas estas condiciones. Ajusta este texto con tus reglas reales.'),
          _H('2. Uso permitido'),
          _P('Describe qué está permitido y qué no, pagos, cancelaciones, seguridad, etc.'),
          _H('3. Responsabilidades'),
          _P('Responsabilidades de clientes y taxistas, soporte y resolución de disputas.'),
        ],
      ),
    );
  }
}

class PoliticaPrivacidadPage extends StatelessWidget {
  const PoliticaPrivacidadPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Política de privacidad')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _P('Última actualización: 2025-09-14'),
          _H('1. Datos que recopilamos'),
          _P('Ej.: nombre, teléfono, ubicación para el viaje, notificaciones push, etc.'),
          _H('2. Uso de datos'),
          _P('Ej.: coordinar viajes, seguridad, soporte, mejoras del servicio.'),
          _H('3. Tus derechos'),
          _P('Cómo solicitar acceso, corrección o eliminación de tus datos.'),
        ],
      ),
    );
  }
}

/// ======= Helpers (sin withOpacity/withValues) =======

class _H extends StatelessWidget {
  final String t;
  const _H(this.t);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        t,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _P extends StatelessWidget {
  final String t;
  const _P(this.t);

  @override
  Widget build(BuildContext context) {
    return Text(
      t,
      style: const TextStyle(
        // 0.85 de opacidad => 217
        color: Color.fromARGB(217, 255, 255, 255),
        fontSize: 14.5,
        height: 1.4,
      ),
    );
  }
}
