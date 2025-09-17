import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flygo_nuevo/widgets/cliente_drawer.dart';

class Soporte extends StatelessWidget {
  const Soporte({super.key});

  // Datos de contacto FlyGo
  static const _soporteEmail = 'soporte@flygo.do';
  static const _soporteTelefono = '+1 829 379 2133'; // visible en UI
  static const _whatsappNumero = '+18293792133'; // E.164

  Future<void> _launch(
    BuildContext context,
    Uri uri, {
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await launchUrl(uri, mode: mode);
    if (messenger != null && !ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace.')),
      );
    }
  }

  Future<void> _enviarCorreo(BuildContext context) async {
    final subject = Uri.encodeComponent('Soporte FlyGo - Ayuda');
    final body = Uri.encodeComponent(
      'Hola FlyGo,\n\n'
      'Necesito ayuda con:\n'
      '- Describe tu problema aquí...\n\n'
      'Información adicional (opcional):\n'
      '- Versión de la app: 1.0.0\n'
      '- Dispositivo: \n'
      '- Email de registro (si aplica): \n',
    );
    final uri = Uri.parse('mailto:$_soporteEmail?subject=$subject&body=$body');
    await _launch(context, uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _llamar(BuildContext context) async {
    final uri = Uri.parse('tel:$_soporteTelefono');
    await _launch(context, uri, mode: LaunchMode.platformDefault);
  }

  Future<void> _abrirWhatsApp(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final mensaje = Uri.encodeComponent('Hola FlyGo, necesito ayuda.');

    // 1) App
    final waScheme =
        Uri.parse('whatsapp://send?phone=$_whatsappNumero&text=$mensaje');
    if (await canLaunchUrl(waScheme)) {
      final ok = await launchUrl(waScheme);
      if (messenger != null && !ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
        );
      }
      return;
    }

    // 2) Web fallback
    final waWeb = Uri.parse('https://wa.me/$_whatsappNumero?text=$mensaje');
    final ok = await launchUrl(waWeb, mode: LaunchMode.externalApplication);
    if (messenger != null && !ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace de WhatsApp.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const ClienteDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            tooltip: 'Menú',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('Soporte', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Contacto rápido
          _card(
            context,
            title: '¿Necesitas ayuda ahora?',
            child: Column(
              children: [
                _actionTile(
                  icon: Icons.email_outlined,
                  label: 'Escribir por correo',
                  subtitle: _soporteEmail,
                  onTap: () => _enviarCorreo(context),
                ),
                const Divider(height: 1, color: Colors.white12),
                _actionTile(
                  icon: Icons.call_outlined,
                  label: 'Llamar a soporte',
                  subtitle: _soporteTelefono,
                  onTap: () => _llamar(context),
                ),
                const Divider(height: 1, color: Colors.white12),
                _actionTile(
                  icon: Icons.chat_outlined,
                  label: 'WhatsApp',
                  subtitle: _whatsappNumero,
                  onTap: () => _abrirWhatsApp(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Mini FAQ
          _card(
            context,
            title: 'Preguntas frecuentes',
            child: const Column(
              children: [
                _FaqItem(
                  pregunta: '¿Cómo programo un viaje?',
                  respuesta:
                      'Desde la pantalla principal, ingresa origen/destino, calcula precio y confirma. '
                      'Si estás fuera del país, activa “Estoy fuera del país” y escribe el origen manual.',
                ),
                _FaqItem(
                  pregunta: '¿Cómo pago el viaje?',
                  respuesta:
                      'Puedes pagar en efectivo o transferencia al conductor. '
                      'La app registra el total y la comisión pendiente.',
                ),
                _FaqItem(
                  pregunta: '¿Dónde veo mi viaje en curso?',
                  respuesta:
                      'Menú → “Mi viaje en curso”. Ahí puedes ver taxi/destino y abrir ruta.',
                ),
                _FaqItem(
                  pregunta: '¿Cómo contacto soporte?',
                  respuesta:
                      'Usa correo, llamada o WhatsApp. Cuéntanos tu caso y te responderemos pronto.',
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Reporte rápido
          _card(
            context,
            title: '¿Tuviste un problema?',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Envíanos un reporte con detalles para ayudarte más rápido.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _enviarCorreo(context),
                    icon: const Icon(Icons.bug_report_outlined),
                    label: const Text('Reportar un problema'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Center(
            child: Text(
              'FlyGo • v1.0.0',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)), // ✅ sin withOpacity
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.greenAccent,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  ListTile _actionTile({
    required IconData icon,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.greenAccent),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(color: Colors.white54))
          : null,
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
      onTap: onTap,
    );
  }
}

class _FaqItem extends StatelessWidget {
  final String pregunta;
  final String respuesta;
  const _FaqItem({required this.pregunta, required this.respuesta});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        collapsedIconColor: Colors.white54,
        iconColor: Colors.greenAccent,
        title: Text(
          pregunta,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              respuesta,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
