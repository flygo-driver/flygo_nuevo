import 'package:flutter/material.dart';
import 'dart:async';

class LoadingProfessional extends StatefulWidget {
  final String? mensajePersonalizado;
  final bool mostrarAnimacionAuto;

  const LoadingProfessional({
    Key? key,
    this.mensajePersonalizado,
    this.mostrarAnimacionAuto = true,
  }) : super(key: key);

  @override
  State<LoadingProfessional> createState() => _LoadingProfessionalState();
}

class _LoadingProfessionalState extends State<LoadingProfessional>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  int _mensajeIndex = 0;
  Timer? _timer;

  final List<String> _mensajesProfesionales = [
    "Buscando los mejores viajes para ti",
    "Conectando con conductores cercanos",
    "Calculando tarifas más competitivas",
    "Preparando opciones disponibles",
    "Casi listo, un momento por favor",
    "Optimizando tu experiencia",
  ];

  final List<String> _subMensajes = [
    "Estamos analizando la demanda en tu zona",
    "Encontrando la mejor ruta disponible",
    "Verificando disponibilidad de conductores",
    "Procesando solicitudes cercanas",
    "Esto tomará solo unos segundos",
    "Gracias por tu paciencia",
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _fadeAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.mostrarAnimacionAuto) {
      _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
        if (mounted) {
          setState(() {
            _mensajeIndex = (_mensajeIndex + 1) % _mensajesProfesionales.length;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 0.8 + (_controller.value * 0.2),
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.green.shade400,
                            Colors.green.shade700,
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.directions_car,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: Text(
                  widget.mensajePersonalizado ??
                      _mensajesProfesionales[_mensajeIndex],
                  key: ValueKey(_mensajeIndex),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              FadeTransition(
                opacity: _fadeAnimation,
                child: Text(
                  _subMensajes[_mensajeIndex % _subMensajes.length],
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 30),
              Container(
                width: 200,
                height: 2,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return FractionallySizedBox(
                      widthFactor: _controller.value,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.green.shade400,
                              Colors.green.shade600,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
