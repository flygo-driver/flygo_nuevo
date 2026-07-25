import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/cliente_verificacion_identidad_service.dart';

/// Exige selfie vigente antes de mostrar flujos de pedir viaje (deep links, programar, etc.).
class ClienteVerificacionIdentidadGate extends StatefulWidget {
  const ClienteVerificacionIdentidadGate({super.key, required this.child});

  final Widget child;

  @override
  State<ClienteVerificacionIdentidadGate> createState() =>
      _ClienteVerificacionIdentidadGateState();
}

class _ClienteVerificacionIdentidadGateState
    extends State<ClienteVerificacionIdentidadGate> {
  bool _listo = false;
  bool _falloLectura = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _verificar());
  }

  Future<void> _verificar() async {
    if (!mounted) return;
    try {
      final ok =
          await ClienteVerificacionIdentidadService.ensureVerificadoOMostrar(
        context,
      );
      if (!mounted) return;
      if (!ok) {
        Navigator.of(context).maybePop();
        return;
      }
      setState(() => _listo = true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _falloLectura = true;
        _listo = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_listo) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_falloLectura) {
      return Scaffold(
        appBar: AppBar(title: const Text('Confirmación de identidad')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No pudimos verificar tu estado. Revisa la conexión e intenta de nuevo.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _listo = false;
                      _falloLectura = false;
                    });
                    _verificar();
                  },
                  child: const Text('Reintentar'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Volver'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return widget.child;
  }
}
