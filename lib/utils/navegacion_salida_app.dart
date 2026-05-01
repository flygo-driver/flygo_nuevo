import 'package:flutter/material.dart';
import 'package:flygo_nuevo/utils/app_routes.dart';

/// Ruta al gate de auth cuando no hay pantalla anterior en la pila (deep link / shell).
const String kRutaGateAuth = AppRoutes.authCheck;

/// Vuelve atrás si existe ruta debajo; si no, abre el gate (misma lógica en toda la app).
void intentarSalirAlGate(BuildContext context) {
  final NavigatorState nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop();
    return;
  }
  final NavigatorState root = Navigator.of(context, rootNavigator: true);
  if (!identical(nav, root) && root.canPop()) {
    root.pop();
    return;
  }
  Navigator.of(context).pushNamedAndRemoveUntil(
    kRutaGateAuth,
    (Route<dynamic> route) => false,
  );
}

/// Atrás del sistema (Android / gesto iOS): evita quedarse “trabado” en la raíz.
class FlygoSalidaSegura extends StatelessWidget {
  const FlygoSalidaSegura({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool puede = Navigator.of(context).canPop();
    return PopScope(
      canPop: puede,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        intentarSalirAlGate(context);
      },
      child: child,
    );
  }
}
