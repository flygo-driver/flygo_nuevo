import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/location_permission_service.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_cliente_service.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_taxista_service.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_ui_constants.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_activar_button.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_rol.dart';

/// Ubicación en Cuenta / Configuración de perfil (cliente o conductor).
class RaiUbicacionConfigPanel extends StatefulWidget {
  const RaiUbicacionConfigPanel({
    super.key,
    required this.rol,
    this.compact = false,
  });

  final RaiUbicacionRol rol;
  final bool compact;

  @override
  State<RaiUbicacionConfigPanel> createState() =>
      _RaiUbicacionConfigPanelState();
}

class _RaiUbicacionConfigPanelState extends State<RaiUbicacionConfigPanel>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_ensureYRefrescar());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refrescar());
    }
  }

  Future<void> _ensureYRefrescar() async {
    if (widget.rol == RaiUbicacionRol.cliente) {
      await RaiUbicacionClienteService.instance.ensureStarted();
    } else {
      await RaiUbicacionTaxistaService.instance.ensureStarted();
    }
    await _refrescar();
  }

  Future<void> _refrescar() async {
    if (widget.rol == RaiUbicacionRol.cliente) {
      await RaiUbicacionClienteService.instance.refrescar();
    } else {
      await RaiUbicacionTaxistaService.instance.refrescar();
    }
    if (mounted) setState(() {});
  }

  bool get _listo => widget.rol == RaiUbicacionRol.cliente
      ? RaiUbicacionClienteService.instance.ubicacionLista
      : RaiUbicacionTaxistaService.instance.ubicacionLista;

  bool get _alertaRoja => widget.rol == RaiUbicacionRol.cliente
      ? RaiUbicacionClienteService.instance.bannerEnAlertaRoja
      : RaiUbicacionTaxistaService.instance.bannerEnAlertaRoja;

  String get _mensaje => widget.rol == RaiUbicacionRol.cliente
      ? RaiUbicacionClienteService.instance.mensajeBannerVisible
      : RaiUbicacionTaxistaService.instance.mensajeBannerVisible;

  String get _titulo => widget.rol == RaiUbicacionRol.cliente
      ? RaiUbicacionClienteService.instance.tituloBanner
      : RaiUbicacionTaxistaService.instance.tituloBanner;

  Future<void> _abrirAjustesManual() async {
    await LocationPermissionService.abrirAjustesUbicacionManualmente();
    await _refrescar();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color acento = _listo
        ? const Color(0xFF49F18B)
        : (_alertaRoja ? cs.error : cs.primary);

    return Card(
      margin: widget.compact
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _listo ? Icons.location_on_rounded : Icons.location_off_rounded,
                  color: acento,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        RaiUbicacionUiConstants.tituloConfigUbicacion,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _listo
                            ? RaiUbicacionUiConstants
                                .subtituloConfigUbicacionActiva
                            : (_titulo.isNotEmpty
                                ? '$_titulo. $_mensaje'
                                : _mensaje),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              height: 1.35,
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!_listo) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: RaiUbicacionActivarButton(
                  rol: widget.rol,
                  alerta: _alertaRoja,
                  minimumSize: const Size(120, 42),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => unawaited(_abrirAjustesManual()),
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: Text(RaiUbicacionUiConstants.accionAjustesManual),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pantalla completa desde la pestaña Cuenta.
class RaiUbicacionAjustesPage extends StatelessWidget {
  const RaiUbicacionAjustesPage({super.key, required this.rol});

  final RaiUbicacionRol rol;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ubicación'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RaiUbicacionConfigPanel(rol: rol),
        ],
      ),
    );
  }
}
