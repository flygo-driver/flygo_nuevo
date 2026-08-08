import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/widgets/cliente_viaje_live_conductores.dart';
import 'package:flygo_nuevo/widgets/cliente_viaje_espera_cronometro.dart';
import 'package:flygo_nuevo/widgets/metodo_pago_visual_badge.dart';
import 'package:flygo_nuevo/widgets/rai_asistente_launcher.dart';

/// UI mientras el cliente espera que un taxista acepte (solo presentación).
class ClienteEsperaTaxistaPanel extends StatelessWidget {
  const ClienteEsperaTaxistaPanel({
    super.key,
    required this.viaje,
    required this.esMotor,
    required this.conductoresCerca,
    required this.docsOrdenados,
    required this.fotoPorUid,
    required this.inicioEspera,
  });

  final Viaje viaje;
  final bool esMotor;
  final int conductoresCerca;
  final List<DocumentSnapshot<Map<String, dynamic>>> docsOrdenados;
  final Map<String, String?> fotoPorUid;
  final DateTime inicioEspera;

  static const Color _amarillo = RaiDsColors.gold;

  String get _codigoViaje {
    final String id = viaje.id.trim();
    if (id.length <= 4) return 'RAI-${id.toUpperCase()}';
    return 'RAI-${id.substring(id.length - 4).toUpperCase()}';
  }

  double get _precioMostrar {
    if (viaje.precioFinal > 0) return viaje.precioFinal;
    return viaje.precio;
  }

  @override
  Widget build(BuildContext context) {
    final bool sinConductoresVisibles = conductoresCerca == 0;
    final String rol = esMotor ? 'motorista' : 'conductor';
    final String rolPlural = esMotor ? 'motoristas' : 'conductores';
    final MetodoPagoVisualTheme pago =
        MetodoPagoVisualTheme.deMetodo(viaje.metodoPago);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EncabezadoEspera(
          codigoViaje: _codigoViaje,
          titulo: esMotor
              ? 'Buscando tu motorista'
              : 'Buscando tu conductor',
          subtitulo: sinConductoresVisibles
              ? 'Tu solicitud está activa en toda la red RAI'
              : 'Notificando $rolPlural cerca de ti',
        ),
        const SizedBox(height: 14),
        const ClienteViajeProgresoStepper(pasoActivo: 0),
        const SizedBox(height: 12),
        ClienteViajeEsperaCronometro(
          inicio: inicioEspera,
          modo: ClienteViajeEsperaCronometroModo.busquedaConductor,
          compacto: true,
        ),
        const SizedBox(height: 16),
        _TarjetaBusqueda(
          esMotor: esMotor,
          conductoresCerca: conductoresCerca,
          docsOrdenados: docsOrdenados,
          fotoPorUid: fotoPorUid,
          sinConductores: sinConductoresVisibles,
          rol: rol,
          rolPlural: rolPlural,
        ),
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _TarjetaDetallesViaje(
                  viaje: viaje,
                  precio: _precioMostrar,
                  pagoLabel: pago.label,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TarjetaAyudaRai(
                  sinConductores: sinConductoresVisibles,
                  onEscribir: () => RaiAsistenteLauncher.abrirAsistente(context),
                ),
              ),
            ],
          ),
        ),
        if (sinConductoresVisibles) ...[
          const SizedBox(height: 12),
          _GarantiaServicioBanner(esMotor: esMotor),
        ],
      ],
    );
  }
}

class _EncabezadoEspera extends StatelessWidget {
  const _EncabezadoEspera({
    required this.codigoViaje,
    required this.titulo,
    required this.subtitulo,
  });

  final String codigoViaje;
  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitulo,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Código de viaje',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                codigoViaje,
                style: const TextStyle(
                  color: ClienteEsperaTaxistaPanel._amarillo,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ClienteViajeProgresoStepper extends StatelessWidget {
  const ClienteViajeProgresoStepper({super.key, required this.pasoActivo});

  /// 0=Solicitado, 1=Aceptado, 2=En camino, 3=Llegada
  final int pasoActivo;

  static const List<(_PasoViaje, IconData)> _pasos = [
    (_PasoViaje('Solicitado', 'Solicitud enviada'), Icons.local_taxi_rounded),
    (_PasoViaje('Aceptado', 'Conductor asignado'), Icons.person_rounded),
    (_PasoViaje('En camino', 'Hacia tu punto'), Icons.directions_car_rounded),
    (_PasoViaje('Llegada', 'Abordaje'), Icons.flag_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List<Widget>.generate(_pasos.length * 2 - 1, (int i) {
        if (i.isOdd) {
          final int left = i ~/ 2;
          final bool lineaActiva = left < pasoActivo;
          return Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.only(bottom: 22),
              color: lineaActiva
                  ? ClienteEsperaTaxistaPanel._amarillo
                  : Colors.white24,
            ),
          );
        }
        final int idx = i ~/ 2;
        final bool activo = idx <= pasoActivo;
        final (_PasoViaje paso, IconData icon) = _pasos[idx];
        return Expanded(
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: activo
                      ? ClienteEsperaTaxistaPanel._amarillo
                          .withValues(alpha: 0.18)
                      : const Color(0xFF1A1A1A),
                  border: Border.all(
                    color: activo
                        ? ClienteEsperaTaxistaPanel._amarillo
                        : Colors.white24,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: activo
                      ? ClienteEsperaTaxistaPanel._amarillo
                      : Colors.white38,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                paso.titulo,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: activo ? Colors.white : Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _PasoViaje {
  const _PasoViaje(this.titulo, this.subtitulo);
  final String titulo;
  final String subtitulo;
}

class _TarjetaBusqueda extends StatelessWidget {
  const _TarjetaBusqueda({
    required this.esMotor,
    required this.conductoresCerca,
    required this.docsOrdenados,
    required this.fotoPorUid,
    required this.sinConductores,
    required this.rol,
    required this.rolPlural,
  });

  final bool esMotor;
  final int conductoresCerca;
  final List<DocumentSnapshot<Map<String, dynamic>>> docsOrdenados;
  final Map<String, String?> fotoPorUid;
  final bool sinConductores;
  final String rol;
  final String rolPlural;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF1A1608), Color(0xFF12100A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ClienteEsperaTaxistaPanel._amarillo.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.radar_rounded,
                color: ClienteEsperaTaxistaPanel._amarillo,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  esMotor
                      ? 'Buscando motorista cercano'
                      : 'Buscando conductor cercano',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            sinConductores
                ? 'No hay $rolPlural visibles en el mapa ahora, pero tu viaje sigue en cola y la red RAI lo está notificando.'
                : 'Hay $conductoresCerca $rol${conductoresCerca == 1 ? '' : 'es'} cerca de ti.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (!sinConductores) ...[
            const SizedBox(height: 14),
            ClienteConductoresCercaStrip(
              docsOrdenados: docsOrdenados,
              fotoPorUid: fotoPorUid,
            ),
          ],
        ],
      ),
    );
  }
}

class _TarjetaDetallesViaje extends StatelessWidget {
  const _TarjetaDetallesViaje({
    required this.viaje,
    required this.precio,
    required this.pagoLabel,
  });

  final Viaje viaje;
  final double precio;
  final String pagoLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Detalles del viaje',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          _filaDireccion(
            color: const Color(0xFF42A5F5),
            texto: viaje.origen,
          ),
          const SizedBox(height: 8),
          _filaDireccion(
            color: RaiDsColors.neon,
            texto: viaje.destino,
          ),
          const SizedBox(height: 10),
          _filaInfo('Pago', pagoLabel),
          const SizedBox(height: 6),
          _filaInfo(
            'Precio total',
            FormatosMoneda.rd(precio),
            valorColor: RaiDsColors.neon,
          ),
        ],
      ),
    );
  }

  Widget _filaDireccion({required Color color, required String texto}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _filaInfo(String label, String valor, {Color? valorColor}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        ),
        Flexible(
          child: Text(
            valor,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: valorColor ?? Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _TarjetaAyudaRai extends StatelessWidget {
  const _TarjetaAyudaRai({
    required this.sinConductores,
    required this.onEscribir,
  });

  final bool sinConductores;
  final VoidCallback onEscribir;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: sinConductores
              ? ClienteEsperaTaxistaPanel._amarillo.withValues(alpha: 0.4)
              : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '¿Necesitas ayuda?',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            sinConductores
                ? 'Si no ves un taxista cerca, escríbenos y te ayudamos a enviarte uno.'
                : '¿Dudas con tu solicitud? Escríbenos y te acompañamos.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onEscribir,
              icon: const Icon(Icons.chat_bubble_rounded, size: 18),
              label: const Text('Escribir a RAI'),
              style: ElevatedButton.styleFrom(
                backgroundColor: ClienteEsperaTaxistaPanel._amarillo,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Te respondemos en menos de 2 min',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _GarantiaServicioBanner extends StatelessWidget {
  const _GarantiaServicioBanner({required this.esMotor});

  final bool esMotor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: RaiDsColors.neon.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RaiDsColors.neon.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: RaiDsColors.neon, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              esMotor
                  ? 'Tu solicitud no se pierde: RAI sigue buscando hasta asignarte un motorista.'
                  : 'Tu solicitud no se pierde: RAI sigue buscando hasta asignarte un conductor.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
