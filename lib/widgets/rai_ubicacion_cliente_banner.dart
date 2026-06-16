import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/rai_ubicacion_cliente_service.dart';

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

  Future<void> _onPermitirTap() async {
    await _svc.solicitarPermisoDesdeBanner();
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
        final bool sinUbicacionAun =
            (_svc.feedbackSinUbicacion.value ?? '').trim().isNotEmpty;
        final Color acento = sinUbicacionAun ? cs.error : cs.primary;

        return Material(
          color: sinUbicacionAun
              ? cs.errorContainer.withValues(alpha: 0.92)
              : cs.primaryContainer.withValues(alpha: 0.92),
          elevation: 2,
          child: SafeArea(
            bottom: false,
            child: InkWell(
              onTap: cargando ? null : () => unawaited(_onPermitirTap()),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      sinUbicacionAun
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
                              color: sinUbicacionAun
                                  ? cs.onErrorContainer
                                  : cs.onPrimaryContainer,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            cargando
                                ? 'Confirma en el cuadro del teléfono: elige '
                                    '«Permitir» o «Al usar la app». '
                                    'Si cierras sin aceptar, te avisaremos.'
                                : _svc.mensajeBannerVisible,
                            style: TextStyle(
                              color: (sinUbicacionAun
                                      ? cs.onErrorContainer
                                      : cs.onPrimaryContainer)
                                  .withValues(alpha: 0.9),
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: cargando ? null : () => unawaited(_onPermitirTap()),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(88, 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      child: cargando
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.onPrimary,
                              ),
                            )
                          : Text(_svc.accionPrincipal),
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
