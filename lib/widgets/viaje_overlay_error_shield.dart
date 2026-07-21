import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';

/// Mientras el shell muestra viaje en curso, un fallo de hijo (mapa, parseo, etc.)
/// no debe dejar la pantalla roja de [ErrorWidget] global.
///
/// Cuenta anidada: cliente y taxista pueden montar shield a la vez.
class ViajeOverlayErrorShield extends StatefulWidget {
  const ViajeOverlayErrorShield({
    super.key,
    required this.child,
    this.esTaxista = false,
  });

  final Widget child;
  final bool esTaxista;

  static int _depth = 0;
  static ErrorWidgetBuilder? _saved;

  @override
  State<ViajeOverlayErrorShield> createState() =>
      _ViajeOverlayErrorShieldState();
}

class _ViajeOverlayErrorShieldState extends State<ViajeOverlayErrorShield> {
  bool _forzarSinMapa = false;

  @override
  void initState() {
    super.initState();
    if (ViajeOverlayErrorShield._depth == 0) {
      ViajeOverlayErrorShield._saved = ErrorWidget.builder;
      ErrorWidget.builder = _builderShield;
    }
    ViajeOverlayErrorShield._depth++;
  }

  Widget _builderShield(FlutterErrorDetails details) {
    debugPrint(
      '[VIAJE_ACTIVO] shield ErrorWidget: ${details.exceptionAsString()}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ActiveTripService.mantenerOverlayViajeEnShell(
        const Duration(seconds: 120),
      );
      setState(() {
        _forzarSinMapa = true;
      });
    });
    return Material(
      color: const Color(0xFF0A0A0A),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.greenAccent,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Entrando a tu viaje…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Si tarda, toca Abrir viaje.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    ActiveTripService.mantenerOverlayViajeEnShell(
                      const Duration(seconds: 120),
                    );
                    if (widget.esTaxista) {
                      unawaited(
                        NavigationService.clearAndGoViajeEnCursoTaxista(),
                      );
                    } else {
                      unawaited(
                        NavigationService.clearAndGoViajeEnCursoCliente(),
                      );
                    }
                    if (mounted) {
                      setState(() => _forzarSinMapa = true);
                    }
                  },
                  child: const Text('Abrir viaje'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    ViajeOverlayErrorShield._depth =
        (ViajeOverlayErrorShield._depth - 1).clamp(0, 999);
    if (ViajeOverlayErrorShield._depth == 0 &&
        ViajeOverlayErrorShield._saved != null) {
      ErrorWidget.builder = ViajeOverlayErrorShield._saved!;
      ViajeOverlayErrorShield._saved = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ViajeSinMapaScope(
      forzarSinMapa: _forzarSinMapa,
      child: widget.child,
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
