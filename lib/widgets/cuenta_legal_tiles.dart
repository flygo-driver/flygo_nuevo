import 'package:flutter/material.dart';
import 'package:flygo_nuevo/legal/legal_urls.dart';
import 'package:flygo_nuevo/legal/terms_policy_screen.dart';
import 'package:flygo_nuevo/pantallas/legal/eliminar_cuenta_page.dart';

/// Enlaces legales para Google Play (web pública + in-app).
class CuentaLegalTiles extends StatelessWidget {
  const CuentaLegalTiles({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        ListTile(
          leading: Icon(Icons.privacy_tip_outlined, color: cs.primary),
          title: const Text('Política de privacidad'),
          subtitle: const Text('Documento público (misma URL que Play Store)'),
          trailing: Icon(Icons.open_in_new, color: cs.outline, size: 20),
          onTap: () => abrirPoliticaPrivacidadWeb(context),
        ),
        ListTile(
          leading: Icon(Icons.gavel_outlined, color: cs.primary),
          title: const Text('Términos y condiciones'),
          subtitle: const Text('Leer y aceptar en la app'),
          trailing: Icon(Icons.chevron_right, color: cs.outline),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TermsPolicyScreen()),
            );
          },
        ),
        ListTile(
          leading: Icon(Icons.person_remove_outlined, color: cs.error),
          title: Text('Eliminar cuenta', style: TextStyle(color: cs.error)),
          subtitle: const Text('Solicitar borrado de tu cuenta y datos'),
          trailing: Icon(Icons.chevron_right, color: cs.outline),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EliminarCuentaPage()),
            );
          },
        ),
      ],
    );
  }
}
