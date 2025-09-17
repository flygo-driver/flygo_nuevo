// lib/auth/seleccion_usuario.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/auth/login_cliente.dart';
import 'package:flygo_nuevo/auth/login_taxista.dart';
import 'package:flygo_nuevo/pantallas/comun/legales.dart';

class SeleccionUsuario extends StatelessWidget {
  const SeleccionUsuario({super.key});

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    const Color bg = Colors.black;
    const Color btnBg = Colors.white;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        bottom: true,
        child: LayoutBuilder(
          builder: (context, c) {
            final double h = c.maxHeight;

            // Logos GRANDES por ALTURA
            final double paraH = (h * 0.30).clamp(210.0, 420.0);
            final double logoH = (h * 0.18).clamp(120.0, 280.0);

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: h),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // ---------- Arriba: paracaídas + FLYGO + textos ----------
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                      child: Column(
                        children: [
                          Center(
                            child: Image.asset(
                              'assets/icon/paracaida_color.png',
                              height: paraH,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                          SizedBox(height: h * 0.012),
                          Center(
                            child: Image.asset(
                              'assets/icon/logo_flygo.png',
                              height: logoH,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                          SizedBox(height: h * 0.022),
                          const Text(
                            'Largos viajes,\nfáciles y seguros',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Comparte ruta, ahorra y viaja mejor.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color.fromARGB(191, 255, 255, 255),
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ---------- Abajo: botones casi pegados al borde ----------
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: Column(
                        children: [
                          _BigButton(
                            background: btnBg,
                            foreground: accent,
                            icon: Icons.person,
                            label: 'Soy Cliente',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const LoginCliente()),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          _BigButton(
                            background: btnBg,
                            foreground: accent,
                            icon: Icons.local_taxi,
                            label: 'Soy Taxista',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const LoginTaxista()),
                              );
                            },
                          ),
                          const SizedBox(height: 10),

                          // Legales compactos
                          Text.rich(
                            TextSpan(
                              style: const TextStyle(
                                color: Color.fromARGB(180, 255, 255, 255),
                                fontSize: 12.5,
                                height: 1.25,
                              ),
                              children: [
                                const TextSpan(text: 'Al continuar aceptas nuestras '),
                                TextSpan(
                                  text: 'Condiciones',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    decoration: TextDecoration.underline,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const TerminosCondicionesPage()),
                                      );
                                    },
                                ),
                                const TextSpan(text: ' y '),
                                TextSpan(
                                  text: 'Política de privacidad',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    decoration: TextDecoration.underline,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const PoliticaPrivacidadPage()),
                                      );
                                    },
                                ),
                                const TextSpan(text: '.'),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Botón grande redondeado con sombra, fondo blanco.
/// Ícono verde (accent) y **TEXTO NEGRO** como pediste.
class _BigButton extends StatelessWidget {
  final Color background;
  final Color foreground; // usado para el ícono
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _BigButton({
    required this.background,
    required this.foreground,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 22),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: foreground),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black, // ← texto negro
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
