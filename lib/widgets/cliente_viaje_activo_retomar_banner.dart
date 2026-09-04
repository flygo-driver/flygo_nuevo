import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';

/// Banner persistente cuando el cliente pausó un viaje activo y está en el home.
class ClienteViajeActivoRetomarBanner extends StatefulWidget {
  const ClienteViajeActivoRetomarBanner({
    super.key,
    required this.uid,
  });

  final String uid;

  @override
  State<ClienteViajeActivoRetomarBanner> createState() =>
      _ClienteViajeActivoRetomarBannerState();

  static String _etiquetaEstado(
    Map<String, dynamic> d,
    String estadoRaw,
  ) {
    if (ViajePoolTaxistaGate.esReservaProgramadaLejana(d)) {
      final DateTime? pickup = _fechaHora(d['fechaHora']);
      if (pickup != null) {
        final String fmt =
            DateFormat('EEE d MMM · HH:mm', 'es').format(pickup);
        return 'Recogida $fmt';
      }
      return 'Aún no entra al pool de conductores';
    }

    final String st = EstadosViaje.normalizar(estadoRaw);
    if (EstadosViaje.esPendiente(st) || st == 'pendiente_admin') {
      return 'Buscando conductor';
    }
    if (EstadosViaje.esAceptado(st)) return 'Conductor asignado';
    if (EstadosViaje.esEnCaminoPickup(st)) return 'Conductor en camino';
    if (EstadosViaje.esAbordo(st)) return 'Abordo — listo para salir';
    if (EstadosViaje.esEnCurso(st)) return 'Viaje en ruta';
    return 'Viaje en curso';
  }

  static DateTime? _fechaHora(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  static bool _esReservaFutura(Map<String, dynamic> d) =>
      ViajePoolTaxistaGate.esReservaProgramadaLejana(d);

  static Widget _bannerConDatos({
    required Map<String, dynamic> d,
    required String estadoRaw,
    required bool cargando,
  }) {
    final bool reservaFutura = _esReservaFutura(d);
    final String estadoLabel = _etiquetaEstado(d, estadoRaw);
    final String destino =
        (d['destino'] ?? d['destinoLabel'] ?? '').toString().trim();
    final bool esTurismo =
        (d['tipoServicio'] ?? '').toString().trim() == 'turismo';

    return Material(
      elevation: 0,
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: reservaFutura
                ? const <Color>[Color(0xFF1A3D5C), Color(0xFF2563EB)]
                : const <Color>[Color(0xFF1B5E20), Color(0xFF2E7D32)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: (reservaFutura
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF1B5E20))
                  .withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          onTap: NavigationService.retomarViajeActivoCliente,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: cargando
                      ? const Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white70,
                          ),
                        )
                      : Icon(
                          reservaFutura
                              ? Icons.event_note_rounded
                              : Icons.local_taxi_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        reservaFutura
                            ? (esTurismo
                                ? 'Reserva turística'
                                : 'Reserva programada')
                            : 'Viaje en curso',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        destino.isNotEmpty
                            ? '$estadoLabel · $destino'
                            : estadoLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: NavigationService.retomarViajeActivoCliente,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: reservaFutura
                        ? const Color(0xFF1D4ED8)
                        : const Color(0xFF1B5E20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    reservaFutura ? 'Ver reserva' : 'Retomar',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _bannerConectando() {
    return Material(
      elevation: 0,
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFF1B5E20), Color(0xFF2E7D32)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: NavigationService.retomarViajeActivoCliente,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white70,
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Viaje en curso',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Toca Retomar para volver al viaje',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: NavigationService.retomarViajeActivoCliente,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Color(0xFF1B5E20),
                    padding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  child: Text(
                    'Retomar',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClienteViajeActivoRetomarBannerState
    extends State<ClienteViajeActivoRetomarBanner> {
  VoidCallback? _shellTick;

  @override
  void initState() {
    super.initState();
    _shellTick = () {
      if (mounted) setState(() {});
    };
    ActiveTripService.shellRebuildTick.addListener(_shellTick!);
  }

  @override
  void dispose() {
    if (_shellTick != null) {
      ActiveTripService.shellRebuildTick.removeListener(_shellTick!);
    }
    super.dispose();
  }

  String? _resolverViajeIdBanner() {
    final String pausa =
        ActiveTripService.resolverViajeIdClienteParaPausa();
    if (pausa.isNotEmpty) return pausa;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (ActiveTripService.flujoPostViajeClienteActivo) {
      return const SizedBox.shrink();
    }
    if (!ActiveTripService.debeMostrarBannerRecuperacionViaje) {
      return const SizedBox.shrink();
    }

    final String? viajeIdInicial = _resolverViajeIdBanner();
    if (viajeIdInicial == null || viajeIdInicial.isEmpty) {
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('usuarios')
            .doc(widget.uid)
            .snapshots(),
        builder: (
          BuildContext context,
          AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> userSnap,
        ) {
          final String vid =
              (userSnap.data?.data()?['viajeActivoId'] ?? '')
                  .toString()
                  .trim();
          if (vid.isEmpty) return const SizedBox.shrink();
          return _BannerViajeDoc(viajeId: vid, uid: widget.uid);
        },
      );
    }

    return _BannerViajeDoc(viajeId: viajeIdInicial, uid: widget.uid);
  }
}

/// Datos locales + stream; permission-denied no oculta el banner en pausa.
class _BannerViajeDoc extends StatefulWidget {
  const _BannerViajeDoc({
    required this.viajeId,
    required this.uid,
  });

  final String viajeId;
  final String uid;

  @override
  State<_BannerViajeDoc> createState() => _BannerViajeDocState();
}

class _BannerViajeDocState extends State<_BannerViajeDoc> {
  Map<String, dynamic>? _datosLocales;
  bool _bootstrapEnCurso = false;

  @override
  void initState() {
    super.initState();
    _cargarResumenLocal();
    unawaited(_bootstrapSiFalta());
  }

  @override
  void didUpdateWidget(covariant _BannerViajeDoc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viajeId != widget.viajeId) {
      _cargarResumenLocal();
      unawaited(_bootstrapSiFalta());
    }
  }

  void _cargarResumenLocal() {
    final Map<String, dynamic>? local =
        ActiveTripService.peekResumenViajeCliente(widget.viajeId);
    if (local != null && local.isNotEmpty) {
      _datosLocales = Map<String, dynamic>.from(local);
    }
  }

  Future<void> _bootstrapSiFalta() async {
    final String id = widget.viajeId.trim();
    if (id.isEmpty || _bootstrapEnCurso) return;
    if (_datosLocales != null && _datosLocales!.isNotEmpty) return;
    _bootstrapEnCurso = true;
    try {
      final Map<String, dynamic>? d =
          await ViajesRepo.fetchViajeDocClienteAutoritativo(id);
      if (!mounted) return;
      if (d != null && d.isNotEmpty) {
        ActiveTripService.sembrarBootstrapViajeCliente(id, d);
        setState(() => _datosLocales = Map<String, dynamic>.from(d));
      }
    } finally {
      _bootstrapEnCurso = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ActiveTripService.viajeClienteDescartadoEnSesion(widget.viajeId)) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('viajes')
          .doc(widget.viajeId)
          .snapshots(),
      builder: (
        BuildContext context,
        AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> viajeSnap,
      ) {
        Map<String, dynamic>? d = _datosLocales;
        bool cargando = false;

        if (viajeSnap.hasData && viajeSnap.data!.exists) {
          d = Map<String, dynamic>.from(viajeSnap.data!.data() ?? {});
          if (_datosLocales?.toString() != d.toString()) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _datosLocales = d);
            });
          }
        } else if (!viajeSnap.hasData ||
            viajeSnap.connectionState == ConnectionState.waiting) {
          cargando = d == null || d.isEmpty;
          if (cargando && !_bootstrapEnCurso) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(_bootstrapSiFalta());
            });
          }
        } else if (viajeSnap.hasData && !viajeSnap.data!.exists) {
          if (d == null || d.isEmpty) {
            return const SizedBox.shrink();
          }
        }

        if (d == null || d.isEmpty) {
          return ClienteViajeActivoRetomarBanner._bannerConectando();
        }
        if (ViajePoolTaxistaGate.esReservaProgramadaLejana(d)) {
          return const SizedBox.shrink();
        }
        final String st =
            EstadosViaje.normalizar((d['estado'] ?? '').toString());
        if (EstadosViaje.esTerminal(st) || d['completado'] == true) {
          return const SizedBox.shrink();
        }
        return ClienteViajeActivoRetomarBanner._bannerConDatos(
          d: d,
          estadoRaw: st,
          cargando: cargando,
        );
      },
    );
  }
}
