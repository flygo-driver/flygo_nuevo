import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/cliente/apariencia.dart';
import 'package:flygo_nuevo/servicios/custom_theme_service.dart';
import 'package:flygo_nuevo/servicios/logout.dart';

/// Entrada destacada a la pantalla de color / tamaño de texto.
class CuentaAparienciaTile extends StatelessWidget {
  const CuentaAparienciaTile({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color bg = Theme.of(context).scaffoldBackgroundColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: cs.primary.withValues(alpha: CustomThemeService.bgDark(bg) ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AparienciaScreen()),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.45),
              ),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primary.withValues(alpha: 0.22),
                child: Icon(Icons.color_lens_outlined, color: cs.primary),
              ),
              title: Text(
                'Apariencia',
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                'Color de fondo y tamaño del texto',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              trailing: Icon(Icons.chevron_right, color: cs.primary),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cerrar sesión con rojo de alto contraste sobre el fondo elegido.
class CuentaCerrarSesionTile extends StatelessWidget {
  const CuentaCerrarSesionTile({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color bg = Theme.of(context).scaffoldBackgroundColor;
    final Color destructive = cs.error;
    final Color surface = CustomThemeService.destructiveSurfaceOn(bg);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap ?? () => cerrarSesion(context),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: destructive.withValues(alpha: 0.45),
              ),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: destructive.withValues(alpha: 0.18),
                child: Icon(Icons.logout_rounded, color: destructive),
              ),
              title: Text(
                'Cerrar sesión',
                style: TextStyle(
                  color: destructive,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                'Salir de tu cuenta en este dispositivo',
                style: TextStyle(
                  color: destructive.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
