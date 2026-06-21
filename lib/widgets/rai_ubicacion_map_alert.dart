import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/custom_theme_service.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_cliente_service.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_taxista_service.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_ui_constants.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_activar_button.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_rol.dart';

/// Aviso compacto (mapa o formulario) + botón «Activar ubicación» unificado.
class RaiUbicacionMapAlert extends StatefulWidget {
  const RaiUbicacionMapAlert({
    super.key,
    required this.rol,
    this.mapFloating = false,
    this.obteniendoGps = false,
    this.permisoBloqueadoEnPantalla = false,
  });

  final RaiUbicacionRol rol;
  final bool mapFloating;
  final bool obteniendoGps;
  final bool permisoBloqueadoEnPantalla;

  @override
  State<RaiUbicacionMapAlert> createState() => _RaiUbicacionMapAlertState();
}

class _RaiUbicacionMapAlertState extends State<RaiUbicacionMapAlert> {
  dynamic get _svc => widget.rol == RaiUbicacionRol.cliente
      ? RaiUbicacionClienteService.instance
      : RaiUbicacionTaxistaService.instance;

  ValueNotifier<bool> get _solicitudEnCurso => _svc.solicitudEnCurso;

  ValueNotifier get _modo => _svc.modo;

  @override
  void initState() {
    super.initState();
    unawaited(_svc.ensureStarted());
    _modo.addListener(_rebuild);
    _solicitudEnCurso.addListener(_rebuild);
    _svc.feedbackSinUbicacion.addListener(_rebuild);
  }

  @override
  void dispose() {
    _modo.removeListener(_rebuild);
    _solicitudEnCurso.removeListener(_rebuild);
    _svc.feedbackSinUbicacion.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  bool get _listo {
    if (widget.rol == RaiUbicacionRol.cliente) {
      return _modo.value == RaiUbicacionClienteModo.listo;
    }
    return _modo.value == RaiUbicacionTaxistaModo.listo;
  }

  bool get _gpsApagado {
    if (widget.rol == RaiUbicacionRol.cliente) {
      return _modo.value == RaiUbicacionClienteModo.gpsApagado;
    }
    return _modo.value == RaiUbicacionTaxistaModo.gpsApagado;
  }

  bool get _bloqueado {
    if (widget.rol == RaiUbicacionRol.cliente) {
      return _modo.value == RaiUbicacionClienteModo.permisoBloqueado;
    }
    return _modo.value == RaiUbicacionTaxistaModo.permisoBloqueado;
  }

  @override
  Widget build(BuildContext context) {
    final cargando = _solicitudEnCurso.value;
    final alerta = _svc.bannerEnAlertaRoja || widget.permisoBloqueadoEnPantalla;

    final bool esperandoFix = _listo && widget.obteniendoGps;
    final bool necesitaPermiso = !_listo || widget.permisoBloqueadoEnPantalla;

    String titulo;
    String mensaje;
    IconData icono;
    bool mostrarBoton = true;

    if (widget.permisoBloqueadoEnPantalla || _bloqueado) {
      titulo = 'Ubicación bloqueada';
      mensaje = _svc.mensajeBannerVisible;
      icono = Icons.location_off_rounded;
    } else if (_gpsApagado) {
      titulo = 'GPS desactivado';
      mensaje = _svc.mensajeBannerVisible;
      icono = Icons.gps_off_rounded;
    } else if (esperandoFix) {
      titulo = 'Obteniendo tu ubicación';
      mensaje = widget.rol == RaiUbicacionRol.cliente
          ? 'Un momento… RAI está leyendo tu posición para cotizar el viaje.'
          : 'Un momento… RAI está leyendo tu posición para operar.';
      icono = Icons.location_searching_rounded;
      mostrarBoton = false;
    } else if (necesitaPermiso) {
      titulo = alerta ? 'Ubicación requerida' : 'Ubicación necesaria';
      mensaje = cargando
          ? RaiUbicacionUiConstants.msgEsperandoCuadroTelefono
          : _svc.mensajeBannerVisible;
      icono = alerta
          ? Icons.location_off_rounded
          : Icons.location_on_outlined;
    } else {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    const accent = Color(0xFF49F18B);
    final Color cardBg = widget.mapFloating
        ? const Color(0xFF0F172A).withValues(alpha: 0.94)
        : CustomThemeService.cardOn(Theme.of(context).scaffoldBackgroundColor);
    final Color textColor = widget.mapFloating
        ? Colors.white
        : CustomThemeService.textOn(cardBg);
    final Color borderColor = alerta
        ? cs.error.withValues(alpha: 0.85)
        : accent.withValues(alpha: widget.mapFloating ? 0.85 : 0.55);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: alerta
            ? Color.alphaBlend(cs.error.withValues(alpha: 0.18), cardBg)
            : cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: alerta ? 2 : 1.4),
        boxShadow: widget.mapFloating
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.32),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: alerta ? cs.error : accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  mensaje,
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.92),
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (mostrarBoton) ...[
            const SizedBox(width: 8),
            RaiUbicacionActivarButton(
              rol: widget.rol,
              alerta: alerta,
              mapStyle: true,
              minimumSize: const Size(72, 40),
            ),
          ],
        ],
      ),
    );
  }
}
