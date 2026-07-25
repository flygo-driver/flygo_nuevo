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
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/widgets/cliente_post_viaje_reopen_guard.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/firebase_auth_resolve.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/utils/post_viaje_rating_throttle.dart';
import 'package:flygo_nuevo/pantallas/comun/factura_viaje.dart';
import 'package:flygo_nuevo/utils/transferencia_recaudo_ui.dart';
import 'package:flygo_nuevo/widgets/subir_comprobante_viaje_button.dart';
import 'package:flygo_nuevo/widgets/taxista_perfil_post_viaje_card.dart';

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
  bool _calificacionEnviada = false;
  bool _omitioCalificacionPorThrottle = false;
  bool? _solicitaCalificacionMutua;
  String? _uidCliente;
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
    _uidCliente = FirebaseAuth.instance.currentUser?.uid;
    if (_uidCliente == null) {
      unawaited(_resolverUidCliente());
    }
    ClientePostViajeReopenGuard.markOpened(widget.viajeId);
    // Evita que el shell siga en modo “viaje en curso” tapando tabs / bloqueando toques.
    ActiveTripService.cancelarMantenimientoOverlayViaje();
    final Map<String, dynamic>? sem = widget.viajeDataSemilla;
    if (sem != null && sem.isNotEmpty) {
      _viajeDatosUi = Map<String, dynamic>.from(sem);
    }
    unawaited(_iniciarPostViaje());
  }

  Future<void> _iniciarPostViaje() async {
    final User? user = await resolveFirebaseUser(
      timeout: const Duration(seconds: 8),
    );
    if (!mounted) return;
    if (user == null) {
      setState(() => _viajeListenError = 'Sin sesión activa.');
      return;
    }
    setState(() => _uidCliente = user.uid);
    if (await CorporativoTaxistaService.debeOcultarEnAppClientePorId(
      widget.viajeId,
      semilla: widget.viajeDataSemilla ?? _viajeDatosUi,
    )) {
      await ClientePostViajeReopenGuard.markCompleted(
        viajeId: widget.viajeId,
        uidCliente: user.uid,
      );
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
      return;
    }
    unawaited(_bootstrapViajeDoc());
    unawaited(_publicarBanderaCalificacionMutua());
  }

  bool _esErrorPermisoLectura(Object e) {
    final String s = e.toString().toLowerCase();
    return s.contains('permission-denied') ||
        s.contains('permission_denied');
  }

  String? _uidClienteEfectivo() =>
      _uidCliente ?? FirebaseAuth.instance.currentUser?.uid;

  bool _semillaPerteneceACliente(Map<String, dynamic> sem, String uid) {
    final String c1 = (sem['uidCliente'] ?? '').toString().trim();
    final String c2 = (sem['clienteId'] ?? '').toString().trim();
    return c1 == uid || c2 == uid;
  }

  /// Si Firestore falla al arranque pero el listener trajo datos del viaje propio.
  bool _puedeMostrarConSemilla(Object? error) {
    if (error == null || !_esErrorPermisoLectura(error)) return false;
    final String? uid = _uidClienteEfectivo();
    if (uid == null || uid.isEmpty) return false;
    final Map<String, dynamic>? sem =
        _viajeDatosUi ?? widget.viajeDataSemilla;
    if (sem == null || sem.isEmpty) return false;
    return _semillaPerteneceACliente(sem, uid);
  }

  Future<void> _publicarBanderaCalificacionMutua() async {
    final String? uid = _uidClienteEfectivo();
    if (uid == null || uid.isEmpty) return;
    final bool mostrar =
        await PostViajeRatingThrottle.publicarBanderaCalificacionMutuaEnViaje(
      viajeId: widget.viajeId,
      uidCliente: uid,
    );
    if (!mounted) return;
    setState(() => _solicitaCalificacionMutua = mostrar);
  }

  Future<void> _resolverUidCliente() async {
    final User? u = await resolveFirebaseUser(
      timeout: const Duration(seconds: 8),
    );
    if (!mounted || u == null) return;
    setState(() => _uidCliente = u.uid);
  }

  Future<void> _bootstrapViajeDoc() async {
    final DocumentReference<Map<String, dynamic>> ref = FirebaseFirestore
        .instance
        .collection('viajes')
        .doc(widget.viajeId);

    Future<DocumentSnapshot<Map<String, dynamic>>> leerViaje() {
      return ref.get(const GetOptions(source: Source.serverAndCache)).timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw TimeoutException(
              'Tiempo de espera al leer el viaje (comprueba conexión).',
            ),
          );
    }

    Object? ultimoError;
    for (int intento = 0; intento < 3; intento++) {
      try {
        final DocumentSnapshot<Map<String, dynamic>> primero = await leerViaje();
        if (!mounted) return;
        setState(() {
          _viajeSnap = primero;
          _viajeListenError = null;
          if (primero.exists) {
            _viajeDatosUi = null;
          }
        });
        ultimoError = null;
        break;
      } catch (e) {
        ultimoError = e;
        if (_esErrorPermisoLectura(e) && intento < 2) {
          await resolveFirebaseUser(timeout: const Duration(seconds: 3));
          await Future<void>.delayed(
            Duration(milliseconds: 350 * (intento + 1)),
          );
          continue;
        }
        if (!mounted) return;
        if (_puedeMostrarConSemilla(e)) {
          setState(() => _viajeListenError = null);
        } else {
          setState(() => _viajeListenError = e);
        }
        break;
      }
    }

    _viajeSub?.cancel();
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
        if (_puedeMostrarConSemilla(e)) return;
        setState(() => _viajeListenError = e);
      },
    );

    if (!mounted || ultimoError == null || _puedeMostrarConSemilla(ultimoError)) {
      return;
    }
    // Reintento en background por si Auth/Firestore sincronizan un poco tarde.
    unawaited(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted || _viajeSnap != null) return;
      try {
        final DocumentSnapshot<Map<String, dynamic>> snap = await leerViaje();
        if (!mounted) return;
        setState(() {
          _viajeSnap = snap;
          _viajeListenError = null;
          if (snap.exists) _viajeDatosUi = null;
        });
      } catch (_) {}
    }());
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

  bool _viajeCompletadoParaUi(Map<String, dynamic> d) {
    if (d['completado'] == true) return true;
    final String st =
        EstadosViaje.normalizar((d['estado'] ?? '').toString());
    return EstadosViaje.esCompletado(st);
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
    bool mostrarCalificacion = puedeRate &&
        (_solicitaCalificacionMutua ??
            PostViajeRatingThrottle.viajeSolicitaCalificacionMutua(d));
    if (puedeRate && !mostrarCalificacion) {
      _omitioCalificacionPorThrottle = true;
    }
    ActiveTripService.cancelarMantenimientoOverlayViaje();
    if (!mostrarCalificacion || !puedeRate) {
      await _irInicio();
      return;
    }
    setState(() => _step = 1);
    await PostViajeRatingThrottle.recordPromptShown();

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

  Future<bool> _viajeYaCalificadoEnServidor() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await FirebaseFirestore.instance
              .collection('viajes')
              .doc(widget.viajeId)
              .get(const GetOptions(source: Source.server));
      return snap.data()?['calificado'] == true;
    } catch (_) {
      return _viajeSnap?.data()?['calificado'] == true;
    }
  }

  void _mostrarSnackCalificacionOk({bool yaEstaba = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          yaEstaba
              ? 'Este viaje ya estaba calificado.'
              : '¡Conductor calificado! Gracias — tu opinión llegó al equipo RAI.',
        ),
        backgroundColor: Colors.green.shade800,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void     _pasarACierreTrasCalificacion() {
    setState(() {
      _cargandoRating = false;
      _calificacionEnviada = true;
      _salioDeCalificacion = true;
      _step = 2;
    });
  }

  Future<void> _enviarCalificacion(Viaje v, String uid) async {
    if (_cargandoRating) return;
    final User? fresh =
        FirebaseAuth.instance.currentUser ?? await resolveFirebaseUser();
    if (fresh == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Espera un momento mientras confirmamos tu sesión e inténtalo otra vez.',
          ),
        ),
      );
      unawaited(_resolverUidCliente());
      return;
    }
    if (fresh.uid != uid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tu cuenta no coincide con este viaje. Verifica que iniciaste con el mismo perfil.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _cargandoRating = true);
    try {
      final CalificarViajeResult res = await ViajeData.calificarViajeSeguro(
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
      _mostrarSnackCalificacionOk(yaEstaba: res.alreadyRated);
      _pasarACierreTrasCalificacion();
    } on SessionExpiredForTrip catch (_) {
      final bool guardado = await _viajeYaCalificadoEnServidor();
      if (!mounted) return;
      if (guardado) {
        _mostrarSnackCalificacionOk();
        _pasarACierreTrasCalificacion();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos enviar la calificación. Comprueba tu conexión e inténtalo de nuevo.',
          ),
        ),
      );
      setState(() => _cargandoRating = false);
      unawaited(_resolverUidCliente());
    } catch (e) {
      final bool guardado = await _viajeYaCalificadoEnServidor();
      if (!mounted) return;
      if (guardado) {
        _mostrarSnackCalificacionOk();
        _pasarACierreTrasCalificacion();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo calificar: $e'),
          action: SnackBarAction(
            label: 'Reintentar',
            onPressed: () => unawaited(_enviarCalificacion(v, uid)),
          ),
        ),
      );
      setState(() => _cargandoRating = false);
    }
  }

  /// Vuelve al home del cliente: overlay primero; navegación **en el siguiente frame**
  /// para no chocar con el frame del botón / PopScope. `clearAndGo` evita fallos de
  /// rutas nombradas si el stack actual no las resolvió bien.
  double _scrollBottomPad(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final double sys = mq.viewPadding.bottom > mq.padding.bottom
        ? mq.viewPadding.bottom
        : mq.padding.bottom;
    return sys + 48;
  }

  Future<void> _irInicio() async {
    if (!mounted) return;
    final String? uid = _uidClienteEfectivo();
    if (uid != null && uid.isNotEmpty) {
      unawaited(
        ClientePostViajeReopenGuard.markCompleted(
          viajeId: widget.viajeId,
          uidCliente: uid,
        ),
      );
    }

    await NavigationService.irAlInicioCliente(
      context: context,
      viajeId: widget.viajeId,
      forzarLimpiarViajeActivo: true,
    );
  }

  Widget _stepResumen({
    required Viaje v,
    required Map<String, dynamic> d,
    required String uid,
  }) {
    final String metodoRaw = (d['metodoPago'] ?? v.metodoPago).toString();
    final bool esEfectivo = MetodoPagoViaje.esEfectivo(metodoRaw);
    final bool esTransfer = MetodoPagoViaje.esTransferencia(metodoRaw);
    final bool usaRecaudoRai =
        esTransfer && TransferenciaRecaudoUi.viajeUsaRecaudoEnCuentaRai(d);
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

    final double bottomPad = _scrollBottomPad(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 8, 24, bottomPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle_rounded,
              color: Colors.greenAccent, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Recibo del viaje',
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
                ? 'Total a pagar al conductor en efectivo. Conserva este resumen.'
                : usaRecaudoRai
                    ? 'Total del viaje. Transferí a la cuenta corporativa de RAI con la referencia indicada.'
                    : esTransfer
                        ? 'Total acordado con el conductor. Si transferiste, conserva tu comprobante.'
                        : 'Gracias por preferir RAI.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white70, height: 1.4, fontSize: 14),
          ),
          const SizedBox(height: 24),
          if (uidTaxista.isNotEmpty) ...[
            TaxistaPerfilPostViajeCard(
              uidTaxista: uidTaxista,
              nombreFallback: v.nombreTaxista,
              viajeData: d,
            ),
            const SizedBox(height: 16),
          ],
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
                Text(
                  usaRecaudoRai
                      ? 'Monto a transferir a RAI'
                      : 'Monto a pagar al conductor',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _money(total),
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      height: 1.05,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (esTransfer) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => FacturaViaje.mostrar(
                context,
                viajeId: v.id,
                role: 'cliente',
              ),
              icon: const Icon(Icons.receipt_long_outlined, size: 20),
              label: const Text('Ver comprobante oficial del viaje'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 16),
            TransferenciaRecaudoUi.panel(
              viajeData: d,
              uidTaxista: uidTaxista,
              montoRd: total,
              fondoOscuro: true,
              tituloConductor: 'CUENTA DEL CONDUCTOR PARA TRANSFERIR',
              tituloRai: 'PAGAR A RAI (TRANSFERENCIA)',
            ),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                TransferenciaRecaudoUi.viajeUsaRecaudoEnCuentaRai(d)
                    ? 'Transferí a la cuenta de RAI con la referencia indicada. '
                        'Conservá el comprobante.'
                    : 'Usá estos mismos datos que ve el conductor en su comprobante. '
                        'Si ya transferiste, conservá el comprobante.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
              ),
            ),
            if (clienteDebePoderSubirComprobanteTransferencia(d)) ...[
              const SizedBox(height: 16),
              SubirComprobanteViajeButton(viajeId: v.id),
            ],
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

  Widget _stepCalificar(Viaje v, String uid, Map<String, dynamic> d) {
    final ya = v.calificado == true;
    final String uidTx = v.uidTaxista.isNotEmpty
        ? v.uidTaxista
        : (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString().trim();
    final double bottomPad = _scrollBottomPad(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 8, 24, bottomPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Califica a tu conductor',
            style: TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '${v.origen} → ${v.destino}',
            style: const TextStyle(color: Colors.white60, fontSize: 14),
          ),
          if (uidTx.isNotEmpty) ...[
            const SizedBox(height: 16),
            TaxistaPerfilPostViajeCard(
              uidTaxista: uidTx,
              nombreFallback: v.nombreTaxista,
              viajeData: d,
            ),
          ],
          const SizedBox(height: 20),
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
                setState(() {
                  _salioDeCalificacion = true;
                });
                unawaited(_irInicio());
              },
              child: const Text('Ahora no',
                  style: TextStyle(color: Colors.white38)),
            ),
        ],
      ),
    );
  }

  Widget _stepCierre() {
    final String subtitulo = _calificacionEnviada
        ? 'Tu calificación fue registrada.'
        : _omitioCalificacionPorThrottle
            ? 'Gracias por viajar con RAI.'
            : 'Gracias por viajar con RAI.';
    final double bottomPad = _scrollBottomPad(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 40, 24, bottomPad),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _calificacionEnviada
                ? Icons.star_rounded
                : Icons.thumb_up_alt_rounded,
            color: Colors.greenAccent,
            size: 56,
          ),
          const SizedBox(height: 20),
          Text(
            _calificacionEnviada ? '¡Conductor calificado!' : '¡Listo!',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            subtitulo,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
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
    if (_viajeListenError != null && !_puedeMostrarConSemilla(_viajeListenError)) {
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

    Map<String, dynamic> d = Map<String, dynamic>.from(raw);
    final Map<String, dynamic>? sem = widget.viajeDataSemilla;
    if (sem != null && sem.isNotEmpty) {
      d = <String, dynamic>{...Map<String, dynamic>.from(sem), ...d};
    }
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
    // Semilla del viaje en curso: el snapshot remoto puede llegar un instante
    // sin `completado` y dejaba la pantalla en "Actualizando…" sin recibo.
    final bool esOk = _viajeCompletadoParaUi(d);

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

    // Siempre mostrar recibo (paso 0) hasta que el usuario pulse Continuar.
    int stepUi = _step.clamp(0, 2);
    if (_step == 1 && (v.calificado == true || _salioDeCalificacion)) {
      stepUi = 2;
    }

    switch (stepUi) {
      case 0:
        return _stepResumen(v: v, d: d, uid: uidCliente);
      case 1:
        return _stepCalificar(v, uidCliente, d);
      default:
        return _stepCierre();
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? uid = _uidCliente ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.greenAccent),
        ),
      );
    }

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
                ? 'Recibo'
                : _step == 1
                    ? 'Calificación'
                    : 'Cierre',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: SafeArea(
          child: _buildViajeBody(uid),
        ),
      ),
    );
  }
}
