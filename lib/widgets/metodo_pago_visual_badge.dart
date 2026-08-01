import 'package:flutter/material.dart';

import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';

/// Paleta unificada: verde efectivo, azul transferencia, morado tarjeta/AZUL.
class MetodoPagoVisualTheme {
  const MetodoPagoVisualTheme({
    required this.label,
    required this.icon,
    required this.accent,
    required this.accentDeep,
    this.badge,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final Color accentDeep;
  final String? badge;

  static const MetodoPagoVisualTheme efectivo = MetodoPagoVisualTheme(
    label: 'Efectivo',
    icon: Icons.payments_rounded,
    accent: Color(0xFF69F0AE),
    accentDeep: Color(0xFF1B5E20),
  );

  static const MetodoPagoVisualTheme transferencia = MetodoPagoVisualTheme(
    label: 'Transferencia',
    icon: Icons.account_balance_rounded,
    accent: Color(0xFF64B5F6),
    accentDeep: Color(0xFF0D47A1),
  );

  static const MetodoPagoVisualTheme tarjeta = MetodoPagoVisualTheme(
    label: 'Tarjeta',
    icon: Icons.credit_card_rounded,
    accent: Color(0xFFB388FF),
    accentDeep: Color(0xFF4A148C),
    badge: 'AZUL',
  );

  static const MetodoPagoVisualTheme corporativo = MetodoPagoVisualTheme(
    label: 'Corporativo',
    icon: Icons.business_center_rounded,
    accent: Color(0xFF80DEEA),
    accentDeep: Color(0xFF006064),
  );

  static const MetodoPagoVisualTheme desconocido = MetodoPagoVisualTheme(
    label: 'Pago',
    icon: Icons.payments_outlined,
    accent: Color(0xFFB0BEC5),
    accentDeep: Color(0xFF455A64),
  );

  static MetodoPagoVisualTheme deMetodo(String? metodo, {bool corporativo = false}) {
    if (corporativo) return MetodoPagoVisualTheme.corporativo;
    if (MetodoPagoViaje.esEfectivo(metodo)) return MetodoPagoVisualTheme.efectivo;
    if (MetodoPagoViaje.esTransferencia(metodo)) {
      return MetodoPagoVisualTheme.transferencia;
    }
    if (MetodoPagoViaje.esTarjeta(metodo)) return MetodoPagoVisualTheme.tarjeta;
    final String raw = (metodo ?? '').trim();
    if (raw.isEmpty) return MetodoPagoVisualTheme.desconocido;
    return MetodoPagoVisualTheme(
      label: MetodoPagoViaje.etiquetaDocumento(raw),
      icon: Icons.payments_outlined,
      accent: const Color(0xFFB0BEC5),
      accentDeep: const Color(0xFF455A64),
    );
  }

  static String subtituloResumen({
    required String metodo,
    Map<String, dynamic>? viajeData,
    bool corporativo = false,
    bool usaRecaudoRai = false,
  }) {
    if (corporativo) {
      return 'Facturación corporativa — la empresa liquida con RAI.';
    }
    if (MetodoPagoViaje.esTarjeta(metodo)) {
      final Map<String, dynamic> d = viajeData ?? <String, dynamic>{};
      if (MetodoPagoViaje.tarjetaPagadoVerificado(d)) {
        return 'Pago con tarjeta confirmado por AZUL.';
      }
      if (MetodoPagoViaje.tarjetaPagoFallido(d)) {
        return 'La tarjeta fue rechazada. Elegí otro método en el viaje.';
      }
      return 'Pago seguro procesado por AZUL.';
    }
    if (MetodoPagoViaje.esEfectivo(metodo)) {
      return 'Entregá el monto al conductor al finalizar el viaje.';
    }
    if (MetodoPagoViaje.esTransferencia(metodo)) {
      if (usaRecaudoRai) {
        return 'Transferencia a la cuenta corporativa de RAI.';
      }
      return 'Transferencia bancaria al conductor.';
    }
    return MetodoPagoViaje.etiquetaDocumento(metodo);
  }
}

/// Tarjeta destacada del método de pago (factura, post-viaje, recibos).
class MetodoPagoVisualCard extends StatelessWidget {
  const MetodoPagoVisualCard({
    super.key,
    required this.metodoPago,
    this.viajeData,
    this.corporativo = false,
    this.usaRecaudoRai = false,
    this.estadoSello,
    this.estadoColor,
    this.subtitulo,
    this.fondoOscuro = false,
  });

  final String metodoPago;
  final Map<String, dynamic>? viajeData;
  final bool corporativo;
  final bool usaRecaudoRai;
  final String? estadoSello;
  final Color? estadoColor;
  final String? subtitulo;
  final bool fondoOscuro;

  @override
  Widget build(BuildContext context) {
    final MetodoPagoVisualTheme theme = MetodoPagoVisualTheme.deMetodo(
      metodoPago,
      corporativo: corporativo,
    );
    final bool oscuro =
        fondoOscuro || Theme.of(context).brightness == Brightness.dark;
    final String detalle = subtitulo ??
        MetodoPagoVisualTheme.subtituloResumen(
          metodo: metodoPago,
          viajeData: viajeData,
          corporativo: corporativo,
          usaRecaudoRai: usaRecaudoRai,
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            theme.accentDeep.withValues(alpha: oscuro ? 0.5 : 0.16),
            theme.accentDeep.withValues(alpha: oscuro ? 0.22 : 0.06),
          ],
        ),
        border: Border.all(color: theme.accent.withValues(alpha: 0.45)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: theme.accent.withValues(alpha: 0.14),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.accent.withValues(alpha: 0.18),
              border: Border.all(color: theme.accent.withValues(alpha: 0.45)),
            ),
            child: Icon(theme.icon, color: theme.accent, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      theme.label,
                      style: TextStyle(
                        color: oscuro ? Colors.white : theme.accentDeep,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    if (theme.badge != null) ...<Widget>[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.accentDeep,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          theme.badge!,
                          style: TextStyle(
                            color: theme.accent,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  detalle,
                  style: TextStyle(
                    color: oscuro
                        ? Colors.white.withValues(alpha: 0.78)
                        : Colors.black.withValues(alpha: 0.62),
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
                if (estadoSello != null && estadoSello!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (estadoColor ?? theme.accent)
                          .withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: (estadoColor ?? theme.accent)
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      estadoSello!,
                      style: TextStyle(
                        color: estadoColor ?? theme.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner operativo (taxista/cliente en viaje) con la misma paleta visual.
class MetodoPagoEstadoBanner extends StatelessWidget {
  const MetodoPagoEstadoBanner({
    super.key,
    required this.metodoPago,
    required this.titulo,
    required this.detalle,
    this.estado = MetodoPagoBannerEstado.info,
    this.padding = const EdgeInsets.only(bottom: 12),
  });

  final String metodoPago;
  final String titulo;
  final String detalle;
  final MetodoPagoBannerEstado estado;
  final EdgeInsetsGeometry padding;

  Color _tituloColor(MetodoPagoVisualTheme theme) {
    switch (estado) {
      case MetodoPagoBannerEstado.exito:
        return const Color(0xFF69F0AE);
      case MetodoPagoBannerEstado.error:
        return const Color(0xFFFF8A80);
      case MetodoPagoBannerEstado.advertencia:
        return const Color(0xFFFFD54F);
      case MetodoPagoBannerEstado.info:
        return theme.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final MetodoPagoVisualTheme theme =
        MetodoPagoVisualTheme.deMetodo(metodoPago);
    final Color tituloColor = _tituloColor(theme);

    return Padding(
      padding: padding,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: <Color>[
              theme.accentDeep.withValues(alpha: 0.42),
              theme.accentDeep.withValues(alpha: 0.18),
            ],
          ),
          border: Border.all(color: tituloColor.withValues(alpha: 0.45)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: theme.accent.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.accent.withValues(alpha: 0.16),
              ),
              child: Icon(theme.icon, color: tituloColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    titulo,
                    style: TextStyle(
                      color: tituloColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detalle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum MetodoPagoBannerEstado { exito, error, advertencia, info }
