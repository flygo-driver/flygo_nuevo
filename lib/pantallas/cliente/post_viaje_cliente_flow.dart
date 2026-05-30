// lib/pantallas/cliente/post_viaje_cliente_flow.dart
//
// Flujo único post-viaje: resumen (según método) → calificación → cierre.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/data/viaje_data.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/pantallas/cliente/reportar_viaje.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/shell/cliente_shell.dart';
import 'package:flygo_nuevo/widgets/cliente_post_viaje_reopen_guard.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/firebase_auth_resolve.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/utils/post_viaje_rating_throttle.dart';
import 'package:flygo_nuevo/widgets/datos_transferencia_conductor_panel.dart';

class PostViajeClienteFlow extends StatefulWidget {
  final String viajeId;

  /// Datos del viaje ya conocidos en pantalla previa (p. ej. [ViajeEnCursoCliente]).
  /// Evita el “hueco” en que el cuerpo es solo spinner hasta el primer snapshot remoto.
  final Map<String, dynamic>? viajeDataSemilla;

  const PostViajeClienteFlow({
    super.key,
    required this.viajeId,
    this.viajeDataSemilla,
  });

  @override
  State<PostViajeClienteFlow> createState() => _PostViajeClienteFlowState();
}

class _PostViajeClienteFlowState extends State<PostViajeClienteFlow> {
  int _step = 0;
  double _calificacion = 5;
  final TextEditingController _comentario = TextEditingController();
  bool _cargandoRating = false;
  /// Tras enviar calificación u omitir: el stream puede traer aún `calificado: false`
  /// y devolvía al paso 1 (botones “muertos”). Forzamos no bajar de cierre.
  bool _salioDeCalificacion = false;
  bool _scheduledAuthRedirect = false;
  static const int _maxComentario = 280;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _viajeSub;
  DocumentSnapshot<Map<String, dynamic>>? _viajeSnap;
  /// Copia local hasta tener [DocumentSnapshot] fiable (semilla o post-[get]).
  Map<String, dynamic>? _viajeDatosUi;
  Object? _viajeListenError;
  Timer? _snapDebounce;

  @override
  void initState() {
    super.initState();
    ClientePostViajeReopenGuard.markOpened(widget.viajeId);
    // Evita que el shell siga en modo “viaje en curso” tapando tabs / bloqueando toques.
    ActiveTripService.cancelarMantenimientoOverlayViaje();
    final Map<String, dynamic>? sem = widget.viajeDataSemilla;
    if (sem != null && sem.isNotEmpty) {
      _viajeDatosUi = Map<String, dynamic>.from(sem);
    }
    unawaited(_bootstrapViajeDoc());
  }

  Future<void> _bootstrapViajeDoc() async {
    final DocumentReference<Map<String, dynamic>> ref = FirebaseFirestore
        .instance
        .collection('viajes')
        .doc(widget.viajeId);
    try {
      final DocumentSnapshot<Map<String, dynamic>> primero =
          await ref.get(const GetOptions(source: Source.serverAndCache)).timeout(
                const Duration(seconds: 20),
                onTimeout: () => throw TimeoutException(
                  'Tiempo de espera al leer el viaje (comprueba conexión).',
                ),
              );
      if (!mounted) return;
      setState(() {
        _viajeSnap = primero;
        _viajeListenError = null;
        if (primero.exists) {
          _viajeDatosUi = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _viajeListenError = e);
    }

    _viajeSub = ref.snapshots().listen(
      (DocumentSnapshot<Map<String, dynamic>> snap) {
        _snapDebounce?.cancel();
        _snapDebounce = Timer(const Duration(milliseconds: 120), () {
          if (!mounted) return;
          setState(() {
            _viajeSnap = snap;
            _viajeListenError = null;
            if (snap.exists) {
              _viajeDatosUi = null;
            }
          });
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _viajeListenError = e;
        });
      },
    );
  }

  @override
  void dispose() {
    _snapDebounce?.cancel();
    _viajeSub?.cancel();
    _comentario.dispose();
    super.dispose();
  }

  String _money(num? n) {
    try {
      return FormatosMoneda.rd((n ?? 0).toDouble());
    } catch (_) {
      return FormatosMoneda.rd(0);
    }
  }

  String _fecha(Timestamp? ts) {
    if (ts == null) return '—';
    try {
      final d = ts.toDate();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} · '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '—';
    }
  }

  Future<void> _marcarReciboEfectivoVisto(
      String viajeId, String uidCliente) async {
    await FirebaseFirestore.instance.collection('viajes').doc(viajeId).set(
      {
        'clienteFacturaEfectivoVistaEn': FieldValue.serverTimestamp(),
        'clienteFacturaEfectivoVistaPorUid': uidCliente,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _continuarDesdeResumen({
    required Viaje v,
    required Map<String, dynamic> d,
    required bool esEfectivo,
    required bool yaVioRecibo,
    required String uid,
  }) async {
    final String estN = EstadosViaje.normalizar(v.estado);
    final bool puedeRate = v.uidTaxista.isNotEmpty &&
        v.calificado != true &&
        !EstadosViaje.esCancelado(estN);
    bool mostrarCalificacion = puedeRate;
    if (mostrarCalificacion) {
      mostrarCalificacion =
          await PostViajeRatingThrottle.shouldShowRatingPrompt();
      if (!mostrarCalificacion) {
        await PostViajeRatingThrottle.recordViajeSinPromptCalificacion();
      }
    }
    ActiveTripService.cancelarMantenimientoOverlayViaje();
    setState(() {
      _step = (puedeRate && mostrarCalificacion) ? 1 : 2;
    });
    if (puedeRate && mostrarCalificacion) {
      await PostViajeRatingThrottle.recordPromptShown();
    }

    if (esEfectivo && !yaVioRecibo) {
      unawaited(() async {
        try {
          await _marcarReciboEfectivoVisto(v.id, uid);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No se pudo guardar el recibo: $e')),
            );
          }
        }
      }());
    }
  }

  /// Sesión nula o rechazada por el servidor al calificar: snack + stack a [AuthGatePublic].
  Future<void> _redirigirALogin(String mensaje) async {
    if (!mounted) return;
    try {
      ActiveTripService.cancelarMantenimientoOverlayViaje();
    } catch (_) {}
    try {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
    } catch (_) {}
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final NavigatorState? nav = NavigationService.navigatorKey.currentState;
      if (nav != null) {
        await NavigationService.clearToAuthGate();
        return;
      }
      if (!mounted) return;
      await Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
        '/auth_check',
        (Route<dynamic> r) => false,
      );
    });
  }

  Future<void> _enviarCalificacion(Viaje v, String uid) async {
    if (_cargandoRating) return;
    final User? fresh =
        FirebaseAuth.instance.currentUser ?? await resolveFirebaseUser();
    if (fresh == null) {
      unawaited(_redirigirALogin(
        'Tu sesión expiró, inicia sesión nuevamente.',
      ));
      return;
    }
    if (fresh.uid != uid) {
      unawaited(_redirigirALogin(
        'Tu sesión no coincide con este viaje. Inicia sesión nuevamente.',
      ));
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _cargandoRating = true);
    try {
      await ViajeData.calificarViajeSeguro(
        viajeId: v.id,
        uidCliente: uid,
        calificacion: _calificacion.clamp(1, 5).toDouble(),
        comentario: _comentario.text.trim(),
      ).timeout(
        const Duration(seconds: 28),
        onTimeout: () => throw TimeoutException(
          'El servidor no respondió a tiempo. Reintentá con mejor señal.',
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Gracias por tu calificación!')),
      );
      setState(() {
        _cargandoRating = false;
        _salioDeCalificacion = true;
        _step = 2;
      });
    } on SessionExpiredForTrip catch (_) {
      if (mounted) {
        setState(() => _cargandoRating = false);
        unawaited(_redirigirALogin(
          'Tu sesión expiró, inicia sesión nuevamente.',
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al calificar: $e'),
            action: SnackBarAction(
              label: 'Reintentar',
              onPressed: () => unawaited(_enviarCalificacion(v, uid)),
            ),
          ),
        );
        setState(() => _cargandoRating = false);
      }
    }
  }

  /// Vuelve al home del cliente: overlay primero; navegación **en el siguiente frame**
  /// para no chocar con el frame del botón / PopScope. `clearAndGo` evita fallos de
  /// rutas nombradas si el stack actual no las resolvió bien.
  Future<void> _irInicio() async {
    try {
      ActiveTripService.cancelarMantenimientoOverlayViaje();
    } catch (_) {}

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final NavigatorState? nav =
          NavigationService.navigatorKey.currentState;
      if (nav != null) {
        await NavigationService.clearAndGo(const ClienteShell());
        return;
      }
      await Navigator.of(context, rootNavigator: true).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const ClienteShell()),
        (Route<dynamic> r) => false,
      );
    });
  }

  Widget _stepResumen({
    required Viaje v,
    required Map<String, dynamic> d,
    required String uid,
  }) {
    final String metodoRaw = (d['metodoPago'] ?? v.metodoPago).toString();
    final bool esEfectivo = MetodoPagoViaje.esEfectivo(metodoRaw);
    final bool esTransfer = MetodoPagoViaje.esTransferencia(metodoRaw);
    final String uidTaxista = v.uidTaxista.isNotEmpty
        ? v.uidTaxista
        : (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString().trim();
    final bool yaVioRecibo = d['clienteFacturaEfectivoVistaEn'] != null;
    final double total = (d['precioFinal'] is num)
        ? (d['precioFinal'] as num).toDouble()
        : ((d['precio'] is num) ? (d['precio'] as num).toDouble() : v.precio);
    final String refCorta = v.id.length >= 8
        ? v.id.substring(0, 8).toUpperCase()
        : v.id.toUpperCase();
    final Timestamp? finTs = d['finalizadoEn'] as Timestamp?;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle_rounded,
              color: Colors.greenAccent, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Viaje finalizado',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            esEfectivo
                ? 'Pagaste en efectivo al conductor. Aquí tienes tu resumen.'
                : esTransfer
                    ? 'Si transferiste al conductor, conserva tu comprobante.'
                    : 'Gracias por preferir RAI.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white70, height: 1.4, fontSize: 14),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv('Referencia', refCorta),
                _kv('Cierre', _fecha(finTs)),
                _kv(
                    'Método',
                    esEfectivo
                        ? 'Efectivo'
                        : (esTransfer ? 'Transferencia' : v.metodoPago)),
                if (v.origen.isNotEmpty) _kv('Origen', v.origen),
                if (v.waypoints != null && v.waypoints!.isNotEmpty)
                  ...v.waypoints!.asMap().entries.map(
                    (MapEntry<int, Map<String, dynamic>> e) {
                      final String label =
                          (e.value['label'] ?? 'Parada ${e.key + 1}')
                              .toString();
                      return _kv('Parada ${e.key + 1}', label);
                    },
                  ),
                if (v.destino.isNotEmpty) _kv('Destino final', v.destino),
                if (v.nombreTaxista.isNotEmpty)
                  _kv('Conductor', v.nombreTaxista),
                const Divider(height: 28, color: Colors.white24),
                const Text('Total del servicio',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 6),
                Text(
                  _money(total),
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          if (esTransfer) ...[
            const SizedBox(height: 16),
            DatosTransferenciaConductorPanel(
              viajeData: d,
              uidTaxista: uidTaxista,
              montoRd: total,
              fondoOscuro: true,
              titulo: 'CUENTA DEL CONDUCTOR PARA TRANSFERIR',
            ),
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Usá estos mismos datos que ve el conductor en su comprobante. '
                'Si ya transferiste, conservá el comprobante.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
              ),
            ),
          ],
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () => _continuarDesdeResumen(
              v: v,
              d: d,
              esEfectivo: esEfectivo,
              yaVioRecibo: yaVioRecibo,
              uid: uid,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Continuar',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(k,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              v.isEmpty ? '—' : v,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepCalificar(Viaje v, String uid) {
    final ya = v.calificado == true;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Califica tu experiencia',
            style: TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '${v.origen} → ${v.destino}',
            style: const TextStyle(color: Colors.white60, fontSize: 14),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = _calificacion >= i + 1;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: ya
                    ? null
                    : () => setState(() => _calificacion = (i + 1).toDouble()),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_border_rounded,
                    color: Colors.amber,
                    size: 44,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            '${_calificacion.toInt()} ${_calificacion.toInt() == 1 ? 'estrella' : 'estrellas'}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 16),
          Slider(
            value: _calificacion,
            min: 1,
            max: 5,
            divisions: 4,
            label: '${_calificacion.toInt()}',
            activeColor: Colors.greenAccent,
            inactiveColor: Colors.white24,
            onChanged: ya ? null : (x) => setState(() => _calificacion = x),
          ),
          const SizedBox(height: 12),
          const Text('Comentario (opcional)',
              style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 8),
          TextField(
            controller: _comentario,
            enabled: !ya,
            maxLines: 3,
            maxLength: _maxComentario,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF1A1A1A),
              hintText: 'Cuéntanos cómo fue el servicio…',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),
          if (_cargandoRating)
            const Center(
                child: CircularProgressIndicator(color: Colors.greenAccent))
          else
            FilledButton(
              onPressed: ya ? null : () => _enviarCalificacion(v, uid),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                ya ? 'Ya calificaste' : 'Enviar calificación',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.of(context, rootNavigator: true).push<void>(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => ReportarViaje(viaje: v),
                ),
              );
              if (mounted) setState(() {});
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orangeAccent,
              side: const BorderSide(color: Colors.orangeAccent),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.flag_outlined, size: 20),
            label: const Text('Reportar un problema'),
          ),
          TextButton(
            onPressed: () => setState(() => _step = 0),
            child: const Text('Volver al resumen',
                style: TextStyle(color: Colors.white54)),
          ),
          if (!ya)
            TextButton(
              onPressed: () {
                try {
                  ActiveTripService.cancelarMantenimientoOverlayViaje();
                } catch (_) {}
                unawaited(_irInicio());
              },
              child: const Text('Omitir por ahora',
                  style: TextStyle(color: Colors.white38)),
            ),
        ],
      ),
    );
  }

  Widget _stepCierre() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.thumb_up_alt_rounded,
              color: Colors.greenAccent, size: 56),
          const SizedBox(height: 20),
          const Text(
            '¡Listo!',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          const Text(
            'Gracias por viajar con RAI.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 36),
          FilledButton(
            onPressed: () => _irInicio(),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Volver al inicio',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _canceladoUi(Viaje v) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cancel_outlined,
              color: Colors.orangeAccent, size: 64),
          const SizedBox(height: 20),
          const Text(
            'Viaje cancelado',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          const Text(
            'Puedes solicitar un nuevo viaje cuando quieras.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 36),
          FilledButton(
            onPressed: () => _irInicio(),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white24,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Ir al inicio',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildViajeBody(String uidCliente) {
    if (_viajeListenError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'No pudimos cargar el viaje.\n$_viajeListenError',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => _irInicio(),
                child: const Text('Ir al inicio'),
              ),
            ],
          ),
        ),
      );
    }

    Map<String, dynamic>? raw;
    if (_viajeSnap != null && _viajeSnap!.exists) {
      raw = _viajeSnap!.data();
    } else {
      raw = _viajeDatosUi;
    }

    if (raw == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.greenAccent),
      );
    }

    final Map<String, dynamic> d = Map<String, dynamic>.from(raw);
    Viaje v;
    try {
      v = Viaje.fromMap(widget.viajeId, d);
    } catch (e, st) {
      debugPrint('[PostViajeClienteFlow] Viaje.fromMap: $e\n$st');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Datos del viaje incompletos.\n$e',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => _irInicio(),
                child: const Text('Ir al inicio'),
              ),
            ],
          ),
        ),
      );
    }
    final String st =
        EstadosViaje.normalizar((d['estado'] ?? v.estado).toString());
    final bool esCancel =
        st == EstadosViaje.cancelado || st == EstadosViaje.rechazado;
    // No depender solo de `completado: true` (a veces el doc llega con estado
    // terminal antes de que el flag se replique en caché).
    final bool esOk =
        (d['completado'] == true) || EstadosViaje.esCompletado(st);

    if (esCancel) {
      return _canceladoUi(v);
    }
    if (!esOk) {
      return const Center(
        child: Text(
          'Actualizando estado del viaje…',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    // Si el viaje ya quedó calificado (u otra sesión), no dejar pantalla “muerta” en paso 1.
    // Si el usuario ya envió/omitió, no volver al paso 1 aunque el snapshot venga stale.
    final int stepUi = _salioDeCalificacion
        ? (_step < 2 ? 2 : _step).clamp(0, 2)
        : ((_step == 1 && v.calificado == true) ? 2 : _step.clamp(0, 2));

    switch (stepUi) {
      case 0:
        return _stepResumen(v: v, d: d, uid: uidCliente);
      case 1:
        return _stepCalificar(v, uidCliente);
      default:
        return _stepCierre();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        final User? u =
            snapshot.data ?? FirebaseAuth.instance.currentUser;

        // Auth aún cargando o restaurando sesión: no mandar a login.
        if (u == null &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            ),
          );
        }

        if (u == null) {
          if (!_scheduledAuthRedirect) {
            _scheduledAuthRedirect = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;
              await NavigationService.clearToAuthGate();
            });
          }
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Text(
                'Tu sesión expiró.\nRedirigiendo…',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ),
          );
        }

        _scheduledAuthRedirect = false;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop) {
              unawaited(_irInicio());
            }
          },
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              automaticallyImplyLeading: false,
              title: Text(
                _step == 0
                    ? 'Resumen'
                    : _step == 1
                        ? 'Calificación'
                        : 'Cierre',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            body: _buildViajeBody(u.uid),
          ),
        );
      },
    );
  }
}
