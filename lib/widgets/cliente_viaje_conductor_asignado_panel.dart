import 'package:flutter/material.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/widgets/cliente_espera_taxista_panel.dart';
import 'package:flygo_nuevo/widgets/cliente_viaje_espera_cronometro.dart';
import 'package:flygo_nuevo/widgets/metodo_pago_visual_badge.dart';

/// Panel compacto cuando el taxista ya aceptó (menos scroll, más mapa visible).
class ClienteViajeConductorAsignadoPanel extends StatelessWidget {
  const ClienteViajeConductorAsignadoPanel({
    super.key,
    required this.viaje,
    required this.estadoBase,
    required this.etaLinea,
    this.etaTituloHttp,
    required this.conductorCard,
    required this.onLlamar,
    required this.onWhatsApp,
    required this.onChat,
    required this.onVerEnMapa,
    this.onCentrarMapa,
    this.inicioCamino,
  });

  final Viaje viaje;
  final String estadoBase;
  final String etaLinea;
  final String? etaTituloHttp;
  final Widget conductorCard;
  final VoidCallback onLlamar;
  final VoidCallback onWhatsApp;
  final VoidCallback onChat;
  final VoidCallback onVerEnMapa;
  final VoidCallback? onCentrarMapa;
  final DateTime? inicioCamino;

  static const Color _amarillo = RaiDsColors.gold;

  static int pasoDesdeEstado(String estado) {
    switch (EstadosViaje.normalizar(estado)) {
      case EstadosViaje.aceptado:
        return 1;
      case EstadosViaje.enCaminoPickup:
        return 2;
      case EstadosViaje.aBordo:
        return 3;
      case EstadosViaje.enCurso:
        return 2;
      default:
        return 1;
    }
  }

  String get _codigoViaje {
    final String id = viaje.id.trim();
    if (id.length <= 4) return 'RAI-${id.toUpperCase()}';
    return 'RAI-${id.substring(id.length - 4).toUpperCase()}';
  }

  String get _titulo {
    if (estadoBase == EstadosViaje.enCurso) {
      return 'Viaje en marcha';
    }
    if (estadoBase == EstadosViaje.aBordo) {
      return 'Ya estás a bordo';
    }
    return 'Tu viaje está en camino';
  }

  String get _subtitulo {
    if (estadoBase == EstadosViaje.enCurso) {
      return 'Rumbo a tu destino';
    }
    if (estadoBase == EstadosViaje.aBordo) {
      return 'Confirma el código con tu conductor si aplica';
    }
    return 'El taxista ya aceptó tu solicitud';
  }

  double get _precio =>
      viaje.precioFinal > 0 ? viaje.precioFinal : viaje.precio;

  String get _barraTitulo {
    if (estadoBase == EstadosViaje.enCurso) {
      return 'Rumbo a tu destino';
    }
    if (estadoBase == EstadosViaje.aBordo) {
      return 'Estás en el vehículo';
    }
    return 'Tu taxista está en camino';
  }

  @override
  Widget build(BuildContext context) {
    final MetodoPagoVisualTheme pago =
        MetodoPagoVisualTheme.deMetodo(viaje.metodoPago);
    final String etaPrincipal = etaTituloHttp?.trim().isNotEmpty == true
        ? etaTituloHttp!.trim()
        : etaLinea;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titulo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _subtitulo,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _CodigoChip(codigo: _codigoViaje),
          ],
        ),
        const SizedBox(height: 12),
        ClienteViajeProgresoStepper(pasoActivo: pasoDesdeEstado(estadoBase)),
        if (inicioCamino != null &&
            (estadoBase == EstadosViaje.aceptado ||
                estadoBase == EstadosViaje.enCaminoPickup)) ...[
          const SizedBox(height: 12),
          ClienteViajeEsperaCronometro(
            inicio: inicioCamino!,
            modo: ClienteViajeEsperaCronometroModo.conductorEnCamino,
            compacto: true,
          ),
        ],
        const SizedBox(height: 12),
        _BarraEtaCompacta(
          titulo: _barraTitulo,
          etaPrincipal: etaPrincipal,
          etaSecundaria: etaTituloHttp != null ? etaLinea : null,
          onVerEnMapa: onVerEnMapa,
        ),
        const SizedBox(height: 12),
        conductorCard,
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _AccionCompacta(
                icon: Icons.phone_rounded,
                label: 'Llamar',
                onTap: onLlamar,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AccionCompacta(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'WhatsApp',
                onTap: onWhatsApp,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AccionCompacta(
                icon: Icons.chat_rounded,
                label: 'Chat',
                onTap: onChat,
                destacado: true,
              ),
            ),
          ],
        ),
        if (onCentrarMapa != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onCentrarMapa,
            icon: const Icon(Icons.center_focus_strong, size: 18),
            label: const Text('Centrar mapa'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ],
        const SizedBox(height: 10),
        _ResumenViajeCompacto(
          origen: viaje.origen,
          destino: viaje.destino,
          pago: pago.label,
          precio: FormatosMoneda.rd(_precio),
        ),
      ],
    );
  }
}

class _CodigoChip extends StatelessWidget {
  const _CodigoChip({required this.codigo});
  final String codigo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'Código',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            codigo,
            style: const TextStyle(
              color: ClienteViajeConductorAsignadoPanel._amarillo,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarraEtaCompacta extends StatelessWidget {
  const _BarraEtaCompacta({
    required this.titulo,
    required this.etaPrincipal,
    this.etaSecundaria,
    required this.onVerEnMapa,
  });

  final String titulo;
  final String etaPrincipal;
  final String? etaSecundaria;
  final VoidCallback onVerEnMapa;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ClienteViajeConductorAsignadoPanel._amarillo
              .withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ClienteViajeConductorAsignadoPanel._amarillo
                  .withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_taxi_rounded,
              color: ClienteViajeConductorAsignadoPanel._amarillo,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  etaPrincipal,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 11.5,
                    height: 1.25,
                  ),
                ),
                if (etaSecundaria != null &&
                    etaSecundaria!.trim().isNotEmpty &&
                    etaSecundaria != etaPrincipal) ...[
                  const SizedBox(height: 2),
                  Text(
                    etaSecundaria!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onVerEnMapa,
            icon: const Icon(Icons.my_location_rounded),
            color: ClienteViajeConductorAsignadoPanel._amarillo,
            tooltip: 'Ver en mapa',
          ),
        ],
      ),
    );
  }
}

class _AccionCompacta extends StatelessWidget {
  const _AccionCompacta({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destacado = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: destacado
          ? ClienteViajeConductorAsignadoPanel._amarillo.withValues(alpha: 0.14)
          : const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: destacado
                  ? ClienteViajeConductorAsignadoPanel._amarillo
                      .withValues(alpha: 0.45)
                  : Colors.white12,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: destacado
                    ? ClienteViajeConductorAsignadoPanel._amarillo
                    : Colors.white,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: destacado ? Colors.white : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResumenViajeCompacto extends StatelessWidget {
  const _ResumenViajeCompacto({
    required this.origen,
    required this.destino,
    required this.pago,
    required this.precio,
  });

  final String origen;
  final String destino;
  final String pago;
  final String precio;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          _fila(Icons.trip_origin, origen, const Color(0xFF42A5F5)),
          const SizedBox(height: 6),
          _fila(Icons.flag_rounded, destino, RaiDsColors.neon),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Colors.white12),
          ),
          Row(
            children: [
              Text(
                pago,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Text(
                precio,
                style: const TextStyle(
                  color: RaiDsColors.neon,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fila(IconData icon, String texto, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
