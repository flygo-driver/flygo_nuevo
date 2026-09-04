import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/servicios/asignacion_turismo_repo.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/cliente_shell_nav_bridge.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/precio_viaje_doc.dart';
import 'package:flygo_nuevo/utils/trip_publish_windows.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';
import 'package:flygo_nuevo/widgets/rai_back_button.dart';
import 'package:flygo_nuevo/widgets/shell_tab_nav.dart';
import 'package:flygo_nuevo/widgets/turismo_mensaje_operaciones_panel.dart';

String _textoVentanaPoolCliente(int minutos) {
  if (minutos < 1) {
    return 'Poco antes de la recogida tu viaje entra al pool de conductores cercanos.';
  }
  if (minutos < 60) {
    return 'Unos $minutos minutos antes de la recogida los conductores podrán ver y aceptar tu viaje en RAI.';
  }
  final h = minutos ~/ 60;
  final r = minutos % 60;
  if (r == 0) {
    return 'Unas $h ${h == 1 ? 'hora' : 'horas'} antes de la recogida abrimos la búsqueda de conductor.';
  }
  return 'Unos $minutos minutos antes de la recogida abrimos la búsqueda de conductor.';
}

String _textoVentanaPoolTurismoCliente(int minutos) {
  if (minutos < 1) {
    return 'Poco antes de la recogida RAI abre la asignación y el pool de choferes de turismo.';
  }
  if (minutos < 60) {
    return 'Unos $minutos minutos antes de la recogida los choferes de turismo habilitados podrán ver y aceptar tu reserva.';
  }
  final h = minutos ~/ 60;
  final r = minutos % 60;
  if (r == 0) {
    return 'Unas $h ${h == 1 ? 'hora' : 'horas'} antes de la recogida abrimos asignación RAI y pool turístico.';
  }
  return 'Unos $minutos minutos antes de la recogida abrimos asignación RAI y pool turístico.';
}

/// Seguimiento en vivo del viaje programado: ventana al pool, búsqueda de conductor, etc.
class ViajeProgramadoConfirmacion extends StatefulWidget {
  const ViajeProgramadoConfirmacion({
    super.key,
    required this.viajeId,
    this.fechaHoraPickup,
    this.origen,
    this.destino,
    this.precio,
    this.desdeListaReservas = false,
  });

  final String viajeId;
  final DateTime? fechaHoraPickup;
  final String? origen;
  final String? destino;
  final double? precio;

  /// Desde «Mis reservas programadas»: mostrar detalle estable sin auto-redirigir al mapa.
  final bool desdeListaReservas;

  @override
  State<ViajeProgramadoConfirmacion> createState() =>
      _ViajeProgramadoConfirmacionState();
}

enum _FaseReserva {
  cancelado,
  completado,
  pendientePago,
  antesDelPool,
  enPool,
  conductorAsignado,
}

class _ViajeProgramadoConfirmacionState
    extends State<ViajeProgramadoConfirmacion> {
  Timer? _tick;
  Timer? _turismoProgramadoPoolTimer;
  bool _turismoProgramadoPoolEnCurso = false;
  bool _navegoAlMapa = false;
  bool _cancelando = false;
  bool _saliendoAlInicio = false;
  Map<String, dynamic>? _viajeDocCache;
  bool _viajeDocSyncEnCurso = false;

  static bool _puedeCancelarReserva(_FaseReserva f) {
    return f == _FaseReserva.antesDelPool ||
        f == _FaseReserva.enPool ||
        f == _FaseReserva.pendientePago;
  }

  String _motivoCancelacionFirestore(_FaseReserva f) {
    switch (f) {
      case _FaseReserva.antesDelPool:
        return 'Cancelado por cliente antes de publicación al pool';
      case _FaseReserva.enPool:
        return 'Cancelado por cliente durante búsqueda de conductor';
      case _FaseReserva.pendientePago:
        return 'Cancelado por cliente (reserva pendiente de pago)';
      default:
        return 'Cancelado por cliente';
    }
  }

  Future<void> _volverAlInicioDesdeReserva({
    bool forzarLimpiarViajeActivo = false,
  }) async {
    if (_saliendoAlInicio) return;
    _saliendoAlInicio = true;
    if (mounted) setState(() {});

    final String vid = widget.viajeId.trim();
    print(
      '[VIAJE_ACTIVO] reserva volverAlInicio tap vid=$vid '
      'desdeLista=${widget.desdeListaReservas}',
    );

    try {
      if (vid.isNotEmpty) {
        ActiveTripService.sembrarBootstrapViajeCliente(vid, _datosLocales());
      }

      await NavigationService.salirReservaProgramadaAlInicioCliente(
        viajeId: vid,
        forzarLimpiarViajeActivo: forzarLimpiarViajeActivo,
        context: mounted ? context : null,
      );
    } catch (e) {
      print('[VIAJE_ACTIVO] reserva volverAlInicio error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo volver al inicio: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      _saliendoAlInicio = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _confirmarYCancelar(_FaseReserva fase) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesión para cancelar.')),
      );
      return;
    }

    final String titulo;
    final String cuerpo;
    switch (fase) {
      case _FaseReserva.antesDelPool:
        titulo = '¿Cancelar esta reserva?';
        cuerpo =
            'Tu viaje todavía no está visible para los conductores. Si cancelás ahora, no se publicará al pool.';
        break;
      case _FaseReserva.enPool:
        titulo = '¿Cancelar la búsqueda?';
        cuerpo =
            'Los conductores ya pueden ver tu viaje. Si cancelás, dejarán de poder aceptarlo.';
        break;
      case _FaseReserva.pendientePago:
        titulo = '¿Cancelar esta solicitud?';
        cuerpo =
            'La reserva está pendiente de pago. Si cancelás, tendrás que programar de nuevo.';
        break;
      default:
        return;
    }

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(cuerpo),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _cancelando = true);
    try {
      final Map<String, dynamic> docHint =
          _viajeDocCache ?? _datosLocales();
      final bool prePool = fase == _FaseReserva.antesDelPool ||
          fase == _FaseReserva.pendientePago ||
          ViajesRepo.esReservaProgramadaAntesDelPool(docHint);

      if (prePool) {
        await ViajesRepo.cancelarReservaProgramadaPrePoolRadical(
          viajeId: widget.viajeId,
          uidCliente: user.uid,
          motivo: _motivoCancelacionFirestore(fase),
          docHint: docHint,
        );
      } else {
        await ViajesRepo.cancelarPorCliente(
          viajeId: widget.viajeId,
          uidCliente: user.uid,
          motivo: _motivoCancelacionFirestore(fase),
        ).timeout(const Duration(seconds: 20));
      }

      if (!mounted) return;
      setState(() {
        _actualizarViajeDocCache(<String, dynamic>{
          'estado': EstadosViaje.cancelado,
          'activo': false,
          'aceptado': false,
        });
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reserva cancelada'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
      if (mounted) setState(() => _cancelando = false);
      if (!mounted) return;
      if (widget.desdeListaReservas) {
        Navigator.of(context).pop();
        return;
      }
      await _volverAlInicioDesdeReserva(forzarLimpiarViajeActivo: true);
    } catch (e) {
      if (!mounted) return;
      final String msg = ViajesRepo.mensajeErrorCancelarCliente(e);
      try {
        final fresh = await ViajesRepo.leerViajeServidor(widget.viajeId)
            .timeout(const Duration(seconds: 6));
        if (fresh != null &&
            EstadosViaje.esCancelado(
              EstadosViaje.normalizar((fresh['estado'] ?? '').toString()),
            )) {
          if (mounted) setState(() => _cancelando = false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Reserva cancelada'),
              backgroundColor: Color(0xFF2E7D32),
            ),
          );
          if (widget.desdeListaReservas) {
            Navigator.of(context).pop();
          } else {
            await _volverAlInicioDesdeReserva(forzarLimpiarViajeActivo: true);
          }
          return;
        }
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (mounted) setState(() => _cancelando = false);
    }
  }

  bool _tieneDatosLocales() =>
      _viajeDocCache != null || widget.fechaHoraPickup != null;

  Map<String, dynamic> _datosLocales() => _viajeDocCache ?? _semillaReservaDoc();

  void _actualizarViajeDocCache(Map<String, dynamic> data) {
    _viajeDocCache = <String, dynamic>{
      ...?_viajeDocCache,
      ...data,
    };
  }

  @override
  void initState() {
    super.initState();
    if (widget.fechaHoraPickup != null) {
      _viajeDocCache = _semillaReservaDoc();
    }
    final String vid = widget.viajeId.trim();
    if (vid.isNotEmpty) {
      ActiveTripService.sembrarBootstrapViajeCliente(vid, _datosLocales());
    }
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_precargarViajeDocServidor());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _stopTurismoProgramadoPoolTimer();
    super.dispose();
  }

  bool _esViajeTurismoProgramado(Map<String, dynamic> d) {
    if ((d['tipoServicio'] ?? '').toString().trim() != 'turismo') return false;
    if (d['programado'] == true) return true;
    return d['esAhora'] != true;
  }

  bool _ventanaPublicacionAbierta(Map<String, dynamic> d, DateTime now) {
    final DateTime? acceptAfter = _ts(d['acceptAfter']);
    final DateTime? publishAt = _ts(d['publishAt']);
    final bool acceptOk =
        acceptAfter == null || !now.isBefore(acceptAfter);
    final bool publishOk = publishAt == null || !now.isBefore(publishAt);
    return acceptOk && publishOk;
  }

  void _stopTurismoProgramadoPoolTimer() {
    _turismoProgramadoPoolTimer?.cancel();
    _turismoProgramadoPoolTimer = null;
  }

  Map<String, dynamic> _semillaReservaDoc() {
    final Map<String, dynamic> out = <String, dynamic>{
      'programado': true,
      'esAhora': false,
      'activo': false,
      'estado': EstadosViaje.pendiente,
      if (widget.fechaHoraPickup != null)
        'fechaHora': Timestamp.fromDate(widget.fechaHoraPickup!),
      if (widget.origen != null && widget.origen!.trim().isNotEmpty)
        'origen': widget.origen!.trim(),
      if (widget.destino != null && widget.destino!.trim().isNotEmpty)
        'destino': widget.destino!.trim(),
      if (widget.precio != null && widget.precio! > 0) 'precio': widget.precio,
    };
    final DateTime? pickup = widget.fechaHoraPickup;
    if (pickup != null) {
      final DateTime now = DateTime.now();
      final DateTime publishAt =
          TripPublishWindows.poolOpensAtForScheduledPickup(pickup, now);
      final DateTime acceptAfter =
          TripPublishWindows.acceptAfterForScheduledPickup(pickup, now);
      out['publishAt'] = Timestamp.fromDate(publishAt);
      out['acceptAfter'] = Timestamp.fromDate(acceptAfter);
      out['startWindowAt'] = Timestamp.fromDate(
        TripPublishWindows.startWindowAtForScheduledPickup(pickup, now),
      );
    }
    return out;
  }

  Future<void> _precargarViajeDocServidor() async {
    final String vid = widget.viajeId.trim();
    if (vid.isEmpty || _viajeDocSyncEnCurso) return;
    _viajeDocSyncEnCurso = true;
    try {
      for (int i = 0; i < 6; i++) {
        if (!mounted) return;
        try {
          if (i == 0) {
            await FirebaseAuth.instance.currentUser?.getIdToken(true);
          }
          final DocumentSnapshot<Map<String, dynamic>> snap =
              await FirebaseFirestore.instance.collection('viajes').doc(vid).get(
                    i == 0
                        ? const GetOptions(source: Source.server)
                        : const GetOptions(),
                  );
          if (!mounted) return;
          if (snap.exists) {
            setState(() => _actualizarViajeDocCache(snap.data()!));
            return;
          }
        } on FirebaseException catch (e) {
          if (e.code != 'permission-denied' &&
              e.code != 'permission_denied' &&
              e.code != 'unavailable') {
            break;
          }
        } catch (_) {}
        await Future<void>.delayed(Duration(milliseconds: 300 * (i + 1)));
      }
    } finally {
      _viajeDocSyncEnCurso = false;
    }
  }

  Widget _pantallaCargandoReserva({String? mensaje}) {
    return PopScope(
      canPop: widget.desdeListaReservas,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        unawaited(_volverAlInicioDesdeReserva());
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Reserva'),
        leading: IconButton(
          icon: Icon(
            widget.desdeListaReservas
                ? Icons.arrow_back_rounded
                : Icons.close_rounded,
            color: RaiBackButton.resolveColor(context),
          ),
          onPressed: () => unawaited(_volverAlInicioDesdeReserva()),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              mensaje ?? 'Cargando tu reserva…',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildReservaDesdeSnapshot({
    required BuildContext context,
    required ThemeData theme,
    required bool isDark,
    required Color accent,
    required DateFormat fmtLargo,
    required DateFormat fmtCorto,
    required AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snap,
  }) {
    if (snap.hasError) {
      unawaited(_precargarViajeDocServidor());
      if (_tieneDatosLocales()) {
        return _buildReservaDesdeData(
          context: context,
          theme: theme,
          isDark: isDark,
          accent: accent,
          fmtLargo: fmtLargo,
          fmtCorto: fmtCorto,
          data: _datosLocales(),
        );
      }
      return _pantallaCargandoReserva(
        mensaje: 'Sincronizando tu reserva con el servidor…',
      );
    }

    final doc = snap.data;
    if (doc == null || !doc.exists) {
      unawaited(_precargarViajeDocServidor());
      if (_tieneDatosLocales()) {
        return _buildReservaDesdeData(
          context: context,
          theme: theme,
          isDark: isDark,
          accent: accent,
          fmtLargo: fmtLargo,
          fmtCorto: fmtCorto,
          data: _datosLocales(),
        );
      }
      return _pantallaCargandoReserva();
    }

    final data = doc.data()!;
    if (!doc.metadata.isFromCache) {
      _actualizarViajeDocCache(data);
    } else if (_viajeDocCache == null) {
      _viajeDocCache = data;
    }
    final Map<String, dynamic> effectiveData =
        doc.metadata.isFromCache && _viajeDocCache != null
            ? _viajeDocCache!
            : data;
    return _buildReservaDesdeData(
      context: context,
      theme: theme,
      isDark: isDark,
      accent: accent,
      fmtLargo: fmtLargo,
      fmtCorto: fmtCorto,
      data: effectiveData,
    );
  }

  /// Turismo programado: al abrir ventana (`publishAt`), auto-asignar o liberar al pool (callable).
  void _syncTurismoProgramadoAlPool(Map<String, dynamic> data) {
    final String estado =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());
    if (data['completado'] == true ||
        EstadosViaje.esCancelado(estado) ||
        EstadosViaje.esCompletado(estado)) {
      _stopTurismoProgramadoPoolTimer();
      return;
    }

    if (!_esViajeTurismoProgramado(data)) {
      _stopTurismoProgramadoPoolTimer();
      return;
    }

    final String taxistaId =
        (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString().trim();
    if (taxistaId.isNotEmpty) {
      _stopTurismoProgramadoPoolTimer();
      return;
    }

    if (AsignacionTurismoRepo.viajeEnPoolTurismoPublico(data)) {
      _stopTurismoProgramadoPoolTimer();
      return;
    }

    if (!_ventanaPublicacionAbierta(data, DateTime.now())) {
      _stopTurismoProgramadoPoolTimer();
      return;
    }

    if (_turismoProgramadoPoolTimer != null) return;

    unawaited(_intentarTurismoProgramadoPoolSilencioso());
    _turismoProgramadoPoolTimer = Timer.periodic(
      const Duration(seconds: 35),
      (_) => unawaited(_intentarTurismoProgramadoPoolSilencioso()),
    );
  }

  Future<void> _intentarTurismoProgramadoPoolSilencioso() async {
    if (_turismoProgramadoPoolEnCurso || !mounted) return;
    _turismoProgramadoPoolEnCurso = true;
    try {
      await AsignacionTurismoRepo.intentarAsignacionAutomatica(
        viajeId: widget.viajeId,
        radioKm: 55,
      );
    } catch (_) {
      // El stream del viaje reflejará asignación o turismo_pool.
    } finally {
      _turismoProgramadoPoolEnCurso = false;
    }
  }

  static DateTime? _ts(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  static double _precioDe(Map<String, dynamic> d) =>
      totalRdDesdeDocViaje(d);

  static _FaseReserva _fase(Map<String, dynamic> d, DateTime now) {
    final estado = EstadosViaje.normalizar((d['estado'] ?? '').toString());
    if (EstadosViaje.esCancelado(estado)) return _FaseReserva.cancelado;
    if (EstadosViaje.esCompletado(estado) || d['completado'] == true) {
      return _FaseReserva.completado;
    }

    if (EstadosViaje.esActivo(estado)) return _FaseReserva.conductorAsignado;

    final tid = (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString().trim();
    if (tid.isNotEmpty) return _FaseReserva.conductorAsignado;

    if (EstadosViaje.esPendientePago(estado)) return _FaseReserva.pendientePago;

    if (d['programado'] == true &&
        !ViajePoolTaxistaGate.ventanaPublicacionYAceptacionOk(d)) {
      return _FaseReserva.antesDelPool;
    }

    final acceptAfter = _ts(d['acceptAfter']);
    final publishAt = _ts(d['publishAt']);

    final bool acceptAbierto =
        acceptAfter == null || !now.isBefore(acceptAfter);
    final bool publishAbierto = publishAt == null || !now.isBefore(publishAt);

    if (!acceptAbierto || !publishAbierto) return _FaseReserva.antesDelPool;
    return _FaseReserva.enPool;
  }

  void _irAViajeEnCursoOnce() {
    if (_navegoAlMapa) return;
    _navegoAlMapa = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ActiveTripService.cancelarForzarInicioClienteShell();
      unawaited(
        NavigationService.clearAndGoViajeEnCursoCliente(
          preNav: Navigator.of(context, rootNavigator: true),
          forzarReabrir: true,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFF49F18B) : const Color(0xFF0F9D58);
    final fmtLargo = DateFormat("EEEE d MMM yyyy · HH:mm", 'es');
    final fmtCorto = DateFormat("d MMM yyyy · HH:mm", 'es');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('viajes')
          .doc(widget.viajeId)
          .snapshots(includeMetadataChanges: true),
      builder: (context, snap) => _buildReservaDesdeSnapshot(
        context: context,
        theme: theme,
        isDark: isDark,
        accent: accent,
        fmtLargo: fmtLargo,
        fmtCorto: fmtCorto,
        snap: snap,
      ),
    );
  }

  Widget _buildReservaDesdeData({
    required BuildContext context,
    required ThemeData theme,
    required bool isDark,
    required Color accent,
    required DateFormat fmtLargo,
    required DateFormat fmtCorto,
    required Map<String, dynamic> data,
  }) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        final cliente = ViajesRepo.uidClienteDesdeDocViaje(data);
        if (uid != null &&
            uid.isNotEmpty &&
            cliente.isNotEmpty &&
            cliente != uid) {
          return Scaffold(
            appBar: AppBar(title: const Text('Reserva')),
            body: const Center(
                child: Text('Esta reserva no pertenece a tu cuenta.')),
          );
        }

        final now = DateTime.now();
        final fase = _fase(data, now);
        final bool esTurismo =
            (data['tipoServicio'] ?? '').toString().trim() == 'turismo';
        final bool turismoEnPoolPublico =
            esTurismo && AsignacionTurismoRepo.viajeEnPoolTurismoPublico(data);

        if (fase != _FaseReserva.cancelado &&
            fase != _FaseReserva.completado) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _syncTurismoProgramadoAlPool(data);
          });
        } else {
          _stopTurismoProgramadoPoolTimer();
        }

        if (fase == _FaseReserva.conductorAsignado && !widget.desdeListaReservas) {
          _irAViajeEnCursoOnce();
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (bool didPop, Object? result) {
              if (didPop) return;
              unawaited(_volverAlInicioDesdeReserva());
            },
            child: Scaffold(
              backgroundColor: theme.scaffoldBackgroundColor,
              appBar: AppBar(
                title: const Text('Conductor asignado'),
                leading: IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: RaiBackButton.resolveColor(context),
                  ),
                  onPressed: _saliendoAlInicio
                      ? null
                      : () => unawaited(_volverAlInicioDesdeReserva()),
                ),
              ),
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Abriendo tu viaje en el mapa…',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _saliendoAlInicio
                          ? null
                          : () => unawaited(_volverAlInicioDesdeReserva()),
                      icon: const Icon(Icons.home_outlined),
                      label: Text(
                        _saliendoAlInicio
                            ? 'Volviendo al inicio…'
                            : 'Volver al inicio',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final fechaPickup =
            widget.fechaHoraPickup ?? _ts(data['fechaHora']) ?? DateTime.now();
        final origen = (widget.origen ?? data['origen'] ?? '').toString();
        final destino = (widget.destino ?? data['destino'] ?? '').toString();
        final precio = widget.precio ?? _precioDe(data);

        final publishAt = _ts(data['publishAt']);
        final acceptAfter = _ts(data['acceptAfter']);
        final ref = widget.viajeId.length >= 6
            ? widget.viajeId.substring(0, 6)
            : widget.viajeId;

        return PopScope(
          canPop: widget.desdeListaReservas,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (didPop) return;
            unawaited(_volverAlInicioDesdeReserva());
          },
          child: Scaffold(
          appBar: AppBar(
            title: Text(esTurismo ? 'Reserva turística' : 'Tu reserva'),
            leading: IconButton(
              icon: Icon(
                widget.desdeListaReservas
                    ? Icons.arrow_back_rounded
                    : Icons.close_rounded,
                color: RaiBackButton.resolveColor(context),
              ),
              onPressed: _cancelando
                  ? null
                  : () => unawaited(_volverAlInicioDesdeReserva()),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (fase == _FaseReserva.cancelado)
                  _BannerEstado(
                    icon: Icons.cancel_outlined,
                    color: theme.colorScheme.error,
                    title: 'Viaje cancelado',
                    subtitle: 'Esta reserva ya no está activa.',
                  )
                else if (fase == _FaseReserva.completado)
                  _BannerEstado(
                    icon: Icons.check_circle_outline,
                    color: accent,
                    title: 'Viaje finalizado',
                    subtitle: 'Gracias por usar RAI.',
                  )
                else if (fase == _FaseReserva.pendientePago)
                  const _BannerEstado(
                    icon: Icons.credit_card_off_outlined,
                    color: Color(0xFFFFB74D),
                    title: 'Pendiente de pago',
                    subtitle:
                        'Cuando el pago quede confirmado, tu viaje seguirá el flujo habitual hacia el pool de conductores.',
                  )
                else if (fase == _FaseReserva.conductorAsignado)
                  _BannerEstado(
                    icon: Icons.directions_car_filled_outlined,
                    color: accent,
                    title: 'Conductor asignado',
                    subtitle: esTurismo
                        ? 'Tu chofer de turismo ya está asignado. Puedes abrir el viaje en el mapa cuando quieras.'
                        : 'Tu conductor ya está asignado. Puedes abrir el viaje en el mapa cuando quieras.',
                  )
                else ...[
                  Icon(Icons.event_available_rounded, size: 48, color: accent),
                  const SizedBox(height: 12),
                  Text(
                    'Reserva confirmada',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    esTurismo
                        ? 'Aquí ves cuándo abre la asignación RAI y cuándo los choferes de turismo pueden tomar tu reserva.'
                        : 'Aquí ves en tiempo real cuándo tu viaje entra al pool y cuándo los conductores pueden aceptarlo.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.72),
                      height: 1.35,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 20),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recogida',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          fmtLargo.format(fechaPickup),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 14),
                        _RowInfo(
                            icon: Icons.trip_origin,
                            label: 'Origen',
                            value: origen),
                        const SizedBox(height: 10),
                        _RowInfo(
                            icon: Icons.flag, label: 'Destino', value: destino),
                        if (precio > 0) ...[
                          const SizedBox(height: 10),
                          _RowInfo(
                            icon: Icons.payments_outlined,
                            label: 'Tarifa estimada',
                            value: FormatosMoneda.rd(precio),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          'Referencia: #$ref',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (fase != _FaseReserva.cancelado &&
                    fase != _FaseReserva.completado &&
                    fase != _FaseReserva.pendientePago) ...[
                  const SizedBox(height: 22),
                  Text(
                    'Estado del servicio',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  _TimelineReserva(
                    fase: fase,
                    accent: accent,
                    publishAt: publishAt,
                    acceptAfter: acceptAfter,
                    now: now,
                    fmtCorto: fmtCorto,
                    poolLeadMinutes: ViajesRepo.poolLeadMinutesProgramado,
                    esTurismo: esTurismo,
                    turismoEnPoolPublico: turismoEnPoolPublico,
                  ),
                ],
                const SizedBox(height: 20),
                if (esTurismo &&
                    fase != _FaseReserva.cancelado &&
                    fase != _FaseReserva.completado)
                  TurismoMensajeOperacionesPanel(
                    viajeId: widget.viajeId,
                    origenPantalla: 'reserva_programada',
                    titulo: '¿Dudas o urgencia con tu reserva?',
                    subtitulo:
                        'Operaciones turismo ve tu mensaje al instante en el panel admin.',
                  ),
                if (esTurismo &&
                    fase != _FaseReserva.cancelado &&
                    fase != _FaseReserva.completado)
                  const SizedBox(height: 20),
                _OtrasReservasSection(
                    excluirId: widget.viajeId, accent: accent),
                if (_puedeCancelarReserva(fase)) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color:
                            theme.colorScheme.outline.withValues(alpha: 0.35),
                      ),
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.35),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          fase == _FaseReserva.antesDelPool
                              ? (esTurismo
                                  ? 'Podés cancelar sin problema: tu viaje aún no está en asignación ni en pool turístico.'
                                  : 'Podés cancelar sin problema: el viaje aún no salió al pool de conductores.')
                              : fase == _FaseReserva.enPool
                                  ? (esTurismo
                                      ? 'Podés cancelar mientras ningún chofer de turismo haya aceptado el viaje.'
                                      : 'Podés cancelar mientras ningún conductor haya aceptado el viaje.')
                                  : 'Podés cancelar esta solicitud mientras siga pendiente de pago.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.35,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _cancelando
                              ? null
                              : () => _confirmarYCancelar(fase),
                          icon: _cancelando
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.colorScheme.error,
                                  ),
                                )
                              : Icon(Icons.cancel_outlined,
                                  color: theme.colorScheme.error),
                          label: Text(
                            _cancelando ? 'Cancelando…' : 'Cancelar reserva',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: theme.colorScheme.error
                                    .withValues(alpha: 0.65)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (fase == _FaseReserva.conductorAsignado) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saliendoAlInicio
                        ? null
                        : () => unawaited(
                              NavigationService.clearAndGoViajeEnCursoCliente(
                                preNav:
                                    Navigator.of(context, rootNavigator: true),
                                forzarReabrir: true,
                              ),
                            ),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Abrir viaje en el mapa'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: accent,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _cancelando
                      ? null
                      : () => unawaited(_volverAlInicioDesdeReserva()),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: accent,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                  ),
                  child: Text(
                    _saliendoAlInicio
                        ? (widget.desdeListaReservas
                            ? 'Volviendo…'
                            : 'Volviendo al inicio…')
                        : (widget.desdeListaReservas
                            ? 'Volver a la lista'
                            : 'Volver al inicio'),
                  ),
                ),
                if (!widget.desdeListaReservas) ...[
                const SizedBox(height: 8),
                Text(
                  'Podés volver al inicio y seguir usando la app. '
                  'Tu reserva está en «Mis viajes» → «Reservas programadas».',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    height: 1.35,
                  ),
                  textAlign: TextAlign.center,
                ),
                ],
              ],
            ),
          ),
        ),
        );
  }
}

class _BannerEstado extends StatelessWidget {
  const _BannerEstado({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineReserva extends StatelessWidget {
  const _TimelineReserva({
    required this.fase,
    required this.accent,
    required this.publishAt,
    required this.acceptAfter,
    required this.now,
    required this.fmtCorto,
    required this.poolLeadMinutes,
    this.esTurismo = false,
    this.turismoEnPoolPublico = false,
  });

  final _FaseReserva fase;
  final Color accent;
  final DateTime? publishAt;
  final DateTime? acceptAfter;
  final DateTime now;
  final DateFormat fmtCorto;
  final int poolLeadMinutes;
  final bool esTurismo;
  final bool turismoEnPoolPublico;

  @override
  Widget build(BuildContext context) {
    const bool t1Done = true;
    final bool t2Done = fase == _FaseReserva.enPool;
    final bool t2Current = fase == _FaseReserva.antesDelPool;
    const bool t3Done = false;
    final bool t3Current = fase == _FaseReserva.enPool;

    final DateTime? pub = publishAt;
    final DateTime? acc = acceptAfter;
    final DateTime? aperturaPool;
    if (pub != null && acc != null) {
      aperturaPool = pub.isAfter(acc) ? pub : acc;
    } else {
      aperturaPool = pub ?? acc;
    }

    String subt2;
    if (fase == _FaseReserva.antesDelPool && aperturaPool != null) {
      if (now.isBefore(aperturaPool)) {
        subt2 = esTurismo
            ? 'RAI y los choferes de turismo verán tu reserva a partir del ${fmtCorto.format(aperturaPool)}. Antes de esa hora queda guardada solo para vos.'
            : 'Los conductores verán tu viaje a partir del ${fmtCorto.format(aperturaPool)}. Antes de esa hora la reserva queda guardada solo para vos.';
      } else {
        subt2 = esTurismo
            ? 'Tu reserva entrará en asignación en cuanto se cumplan las condiciones de publicación.'
            : 'Tu viaje entrará en la red en cuanto se cumplan las condiciones de publicación.';
      }
    } else if (fase == _FaseReserva.enPool) {
      if (esTurismo && turismoEnPoolPublico) {
        subt2 =
            'Tu reserva está visible en Pool turístico para choferes habilitados. Te avisamos cuando uno la acepte.';
      } else if (esTurismo) {
        subt2 =
            'RAI asigna chofer aprobado o publica en pool turístico. Esto puede tardar unos segundos…';
      } else {
        subt2 =
            'Tu viaje está visible para conductores cercanos. Te avisamos por notificación cuando uno lo acepte (si tenés alertas activas).';
      }
    } else {
      subt2 = '';
    }

    return Column(
      children: [
        _TimelineTile(
          accent: accent,
          done: t1Done,
          current: false,
          icon: Icons.check_circle,
          title: 'Reserva guardada',
          subtitle: 'Datos registrados en el sistema.',
        ),
        _TimelineTile(
          accent: accent,
          done: t2Done,
          current: t2Current,
          icon: Icons.groups_2_outlined,
          title: esTurismo
              ? 'Asignación / pool turístico'
              : 'En red de conductores (pool)',
          subtitle: subt2.isEmpty
              ? (esTurismo
                  ? _textoVentanaPoolTurismoCliente(poolLeadMinutes)
                  : _textoVentanaPoolCliente(poolLeadMinutes))
              : subt2,
        ),
        _TimelineTile(
          accent: accent,
          done: t3Done,
          current: t3Current,
          icon: Icons.directions_car_outlined,
          title: esTurismo ? 'Chofer asignado' : 'Conductor asignado',
          subtitle: fase == _FaseReserva.enPool
              ? (esTurismo
                  ? 'Buscando chofer de turismo disponible…'
                  : 'Buscando conductor disponible…')
              : (esTurismo
                  ? 'Cuando un chofer acepte, pasarás automáticamente al mapa del viaje.'
                  : 'Cuando un conductor acepte, pasarás automáticamente al mapa del viaje.'),
          isLast: true,
        ),
      ],
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.accent,
    required this.done,
    required this.current,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isLast = false,
  });

  final Color accent;
  final bool done;
  final bool current;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineColor = done || current ? accent : theme.dividerColor;
    final iconBg = done
        ? accent.withValues(alpha: 0.2)
        : current
            ? accent.withValues(alpha: 0.35)
            : theme.colorScheme.surfaceContainerHighest;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconBg,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: done || current ? accent : theme.dividerColor,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    done ? Icons.check : icon,
                    size: 18,
                    color: done || current
                        ? accent
                        : theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: lineColor.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: current ? accent : null,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.4,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RowInfo extends StatelessWidget {
  const _RowInfo({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              Text(
                value.isEmpty ? '—' : value,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OtrasReservasSection extends StatelessWidget {
  const _OtrasReservasSection({
    required this.excluirId,
    required this.accent,
  });

  final String excluirId;
  final Color accent;

  static DateTime _asDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static bool _terminal(Map<String, dynamic> d) {
    final e = EstadosViaje.normalizar((d['estado'] ?? '').toString());
    if (EstadosViaje.esCancelado(e) || EstadosViaje.esCompletado(e)) {
      return true;
    }
    if (d['completado'] == true) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('viajes')
          .where(
            Filter.or(
              Filter('clienteId', isEqualTo: uid),
              Filter('uidCliente', isEqualTo: uid),
            ),
          )
          .where('programado', isEqualTo: true)
          .limit(30)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.hasError) return const SizedBox.shrink();

        final fmt = DateFormat("d MMM · HH:mm", 'es');
        final otros = snap.data!.docs.where((x) {
          if (x.id == excluirId) return false;
          final m = x.data();
          if (m['programado'] != true) return false;
          if (_terminal(m)) return false;
          return true;
        }).toList()
          ..sort((a, b) => _asDate(a.data()['fechaHora'])
              .compareTo(_asDate(b.data()['fechaHora'])));

        if (otros.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tus otras reservas',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ...otros.take(4).map((doc) {
              final m = doc.data();
              final fecha = _asDate(m['fechaHora']);
              final o = (m['origen'] ?? '').toString();
              final de = (m['destino'] ?? '').toString();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      unawaited(NavigationService.pushEnTabShell(
                        context,
                        ViajeProgramadoConfirmacion(
                          viajeId: doc.id,
                          fechaHoraPickup: fecha,
                          origen: o,
                          destino: de,
                          precio: totalRdDesdeDocViaje(m) > 0
                              ? totalRdDesdeDocViaje(m)
                              : null,
                          desdeListaReservas: true,
                        ),
                      ));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.event, size: 18, color: accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fmt.format(fecha),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13),
                                ),
                                Text(
                                  '$o → $de',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.35)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
