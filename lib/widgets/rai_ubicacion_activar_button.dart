import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/rai_ubicacion_cliente_service.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_taxista_service.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_rol.dart';

/// Botón único RAI (cliente o taxista): GPS, permiso o ajustes del teléfono.
class RaiUbicacionActivarButton extends StatefulWidget {
  const RaiUbicacionActivarButton({
    super.key,
    required this.rol,
    this.alerta = false,
    this.mapStyle = false,
    this.minimumSize = const Size(88, 40),
  });

  final RaiUbicacionRol rol;
  final bool alerta;
  final bool mapStyle;
  final Size minimumSize;

  @override
  State<RaiUbicacionActivarButton> createState() =>
      _RaiUbicacionActivarButtonState();
}

class _RaiUbicacionActivarButtonState extends State<RaiUbicacionActivarButton> {
  ValueNotifier<bool> get _solicitudEnCurso =>
      widget.rol == RaiUbicacionRol.cliente
          ? RaiUbicacionClienteService.instance.solicitudEnCurso
          : RaiUbicacionTaxistaService.instance.solicitudEnCurso;

  Future<void> _activar() async {
    if (widget.rol == RaiUbicacionRol.cliente) {
      await RaiUbicacionClienteService.instance.activarUbicacionDesdeApp();
    } else {
      await RaiUbicacionTaxistaService.instance.activarUbicacionDesdeApp();
    }
  }

  @override
  void initState() {
    super.initState();
    _solicitudEnCurso.addListener(_rebuild);
  }

  @override
  void dispose() {
    _solicitudEnCurso.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cargando = _solicitudEnCurso.value;
    const accent = Color(0xFF49F18B);
    final String etiqueta = widget.rol == RaiUbicacionRol.cliente
        ? RaiUbicacionClienteService.instance.etiquetaAccionBanner
        : RaiUbicacionTaxistaService.instance.etiquetaAccionBanner;

    return FilledButton(
      onPressed: cargando ? null : () => unawaited(_activar()),
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: widget.minimumSize,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        backgroundColor: widget.alerta
            ? cs.error
            : (widget.mapStyle ? accent : null),
        foregroundColor: widget.alerta
            ? cs.onError
            : (widget.mapStyle ? Colors.black : null),
      ),
      child: cargando
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: widget.alerta
                    ? cs.onError
                    : (widget.mapStyle ? Colors.black : cs.onPrimary),
              ),
            )
          : Text(
              etiqueta,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
    );
  }
}
