// lib/pantallas/cliente/cliente_home.dart
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/widgets/cliente_drawer.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';

class ClienteHome extends StatelessWidget {
  const ClienteHome({super.key});

  void _go(BuildContext context, bool ahora) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProgramarViaje(modoAhora: ahora)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color green = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const ClienteDrawer(),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        title: Image.asset(
          'assets/icon/logo_flygo.png',
          height: 28,
          filterQuality: FilterQuality.high,
        ),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            tooltip: 'Menú',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      ),

      // ⬇️ Body responsivo (sin overflow al girar)
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final bool isLandscape = c.maxWidth > c.maxHeight;
            final double imgH = isLandscape ? 120.0 : c.maxHeight * 0.36;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 🪂 Paracaídas adaptativo
                  Center(
                    child: Image.asset(
                      'assets/icon/paracaida_color.png',
                      height: imgH,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Título + subtítulo
                  const Text(
                    '¿A dónde vamos hoy?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Viajes largos, fáciles y seguros',
                    textAlign: TextAlign.center,
                    // 75% opacidad sin withOpacity
                    style: TextStyle(color: Color(0xBFFFFFFF), fontSize: 14),
                  ),

                  const SizedBox(height: 24),

                  // Botón primario (blanco)
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    elevation: 10,
                    shadowColor: Colors.black26,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => _go(context, true),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 18,
                          horizontal: 20,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.local_taxi, color: green, size: 22),
                            const SizedBox(width: 12),
                            const Text(
                              'Solicitar viaje ahora',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Botón secundario (outline verde)
                  OutlinedButton(
                    onPressed: () => _go(context, false),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: green, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 20,
                      ),
                      foregroundColor: green,
                      backgroundColor: Colors.black,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.access_time, size: 22),
                        SizedBox(width: 12),
                        Text(
                          'Programar viaje',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),
                  const Center(
                    child: Text(
                      'Tu viaje, a otro nivel.',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
