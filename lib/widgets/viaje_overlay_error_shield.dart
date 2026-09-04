import 'package:flutter/material.dart';

/// Mientras el shell muestra viaje en curso, un fallo de hijo (mapa, parseo, etc.)
/// lo resuelve el [ErrorWidget.builder] global instalado en `main.dart`.
///
/// Este widget no reemplaza [ErrorWidget.builder]: hacerlo desde una instancia
/// del shell deja callbacks ligados a un State destruido cuando el shell se remonta.
class ViajeOverlayErrorShield extends StatelessWidget {
  const ViajeOverlayErrorShield({
    super.key,
    required this.child,
    this.esTaxista = false,
  });

  final Widget child;
  final bool esTaxista;

  @override
  Widget build(BuildContext context) {
    return ViajeSinMapaScope(
      forzarSinMapa: false,
      child: child,
    );
  }
}

/// Propaga “sin mapa” tras un crash para que [ViajeEnCursoCliente] no remonte Maps.
class ViajeSinMapaScope extends InheritedWidget {
  const ViajeSinMapaScope({
    super.key,
    required this.forzarSinMapa,
    required super.child,
  });

  final bool forzarSinMapa;

  static bool of(BuildContext context) {
    final ViajeSinMapaScope? s =
        context.getInheritedWidgetOfExactType<ViajeSinMapaScope>();
    return s?.forzarSinMapa ?? false;
  }

  @override
  bool updateShouldNotify(ViajeSinMapaScope oldWidget) =>
      forzarSinMapa != oldWidget.forzarSinMapa;
}
