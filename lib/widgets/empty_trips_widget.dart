import 'package:flutter/material.dart';

class EmptyTripsWidget extends StatelessWidget {
  final bool esTabAhora;
  
  const EmptyTripsWidget({
    Key? key,
    required this.esTabAhora,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF111827);
    final textSecondary =
        isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF4B5563);
    final iconColor =
        isDark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF6B7280);
    final bubbleColor =
        isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFE5E7EB);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Ilustración animada
          TweenAnimationBuilder(
            tween: Tween<double>(begin: 0.9, end: 1.0),
            duration: const Duration(milliseconds: 1000),
            builder: (context, double scale, child) {
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    esTabAhora ? Icons.timer_off_outlined : Icons.event_busy,
                    size: 55,
                    color: iconColor,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 30),
          
          // Título
          Text(
            esTabAhora ? "No hay viajes ahora" : "No hay viajes programados",
            style: TextStyle(
              color: textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          
          // Descripción
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              esTabAhora 
                  ? "Los viajes disponibles aparecerán aquí automáticamente"
                  : "Los viajes que reserves con anticipación se mostrarán aquí",
              style: TextStyle(
                color: textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          
          // Mensaje motivacional
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              esTabAhora ? "Mantente atento 🚖" : "Revisa más tarde 📅",
              style: TextStyle(
                color: Colors.green.shade300,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}