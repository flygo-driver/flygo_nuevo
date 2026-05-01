// lib/pantallas/welcome_page.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final green = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: true,
        child: LayoutBuilder(
          builder: (context, c) {
            final double h = c.maxHeight; // usar solo h evita warnings

            // Logos GRANDES por ALTURA (consistente en todos los equipos)
            final double paraH = (h * 0.34).clamp(240.0, 460.0);
            final double logoH = (h * 0.18).clamp(130.0, 280.0);

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: h),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // ------- Arriba: paracaídas + logo + textos -------
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
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
                            'Largos viajes,\nFáciles y seguros',
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

                    // ------- Abajo: botones casi pegados al borde -------
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
                      child: Column(
                        children: [
                          _WhitePrimaryButton(
                            icon: Icons.person,
                            label: 'Soy Cliente',
                            iconColor: green,
                            onTap: () =>
                                Navigator.pushNamed(context, '/login_cliente'),
                          ),
                          const SizedBox(height: 10),
                          _WhitePrimaryButton(
                            icon: Icons.local_taxi,
                            label: 'Soy Taxista',
                            iconColor: green,
                            onTap: () =>
                                Navigator.pushNamed(context, '/login_taxista'),
                          ),
                          const SizedBox(height: 10),
                          Text.rich(
                            TextSpan(
                              style: const TextStyle(
                                color: Color.fromARGB(170, 255, 255, 255),
                                fontSize: 12.5,
                                height: 1.25,
                              ),
                              children: [
                                const TextSpan(
                                    text: 'Al continuar aceptas nuestras '),
                                TextSpan(
                                  text: 'Condiciones',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    decoration: TextDecoration.underline,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () => Navigator.pushNamed(
                                        context, '/terminos'),
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
                                    ..onTap = () => Navigator.pushNamed(
                                        context, '/privacidad'),
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

class _WhitePrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColor;

  const _WhitePrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      elevation: 8,
      shadowColor: const Color(0x40000000),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
