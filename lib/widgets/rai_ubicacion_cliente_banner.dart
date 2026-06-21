import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/rai_ubicacion_cliente_service.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_ui_constants.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_activar_button.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_rol.dart';

/// Aviso en el shell del cliente cuando falta GPS o permiso de ubicación.
class RaiUbicacionClienteBanner extends StatefulWidget {
  const RaiUbicacionClienteBanner({super.key});

  @override
  State<RaiUbicacionClienteBanner> createState() =>
      _RaiUbicacionClienteBannerState();
}

class _RaiUbicacionClienteBannerState extends State<RaiUbicacionClienteBanner> {
  final _svc = RaiUbicacionClienteService.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_svc.ensureStarted());
    _svc.modo.addListener(_rebuild);
    _svc.solicitudEnCurso.addListener(_rebuild);
    _svc.feedbackSinUbicacion.addListener(_rebuild);
  }

  @override
  void dispose() {
    _svc.modo.removeListener(_rebuild);
    _svc.solicitudEnCurso.removeListener(_rebuild);
    _svc.feedbackSinUbicacion.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RaiUbicacionClienteModo>(
      valueListenable: _svc.modo,
      builder: (context, modo, _) {
        if (modo == RaiUbicacionClienteModo.listo) {
          return const SizedBox.shrink();
        }

        final cs = Theme.of(context).colorScheme;
        final cargando = _svc.solicitudEnCurso.value;
        final bool alertaRoja = _svc.bannerEnAlertaRoja;
        final Color acento = alertaRoja ? cs.error : cs.primary;
        final Color fondo = alertaRoja
            ? Color.alphaBlend(
                cs.error.withValues(alpha: 0.22),
                cs.surfaceContainerHighest,
              )
            : cs.primaryContainer.withValues(alpha: 0.92);
        final Color texto = alertaRoja ? cs.onErrorContainer : cs.onPrimaryContainer;

        return Material(
          color: fondo,
          elevation: alertaRoja ? 3 : 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: acento.withValues(alpha: alertaRoja ? 0.95 : 0.35),
                  width: alertaRoja ? 2.5 : 1,
                ),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      alertaRoja
                          ? Icons.location_off_rounded
                          : Icons.location_disabled_rounded,
                      color: acento,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _svc.tituloBanner,
                            style: TextStyle(
                              color: texto,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            cargando
                                ? RaiUbicacionUiConstants
                                    .msgEsperandoCuadroTelefono
                                : _svc.mensajeBannerVisible,
                            style: TextStyle(
                              color: texto.withValues(alpha: 0.92),
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    RaiUbicacionActivarButton(
                      rol: RaiUbicacionRol.cliente,
                      alerta: alertaRoja,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
