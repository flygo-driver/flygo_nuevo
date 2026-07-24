// Flujo post-viaje taxista: resumen (monto grande) → calificación (throttle) → cola.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/data/viaje_data.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/pantallas/taxista/reportar_cliente_viaje.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/taxista_cola_post_completar.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/utils/post_viaje_rating_throttle.dart';

class PostViajeTaxistaFlow extends StatefulWidget {
  const PostViajeTaxistaFlow({
    super.key,
    required this.viajeId,
    required this.uidTaxista,
    this.viajeDataSemilla,
    this.regresarAlPoolNormal = false,
  });

  final String viajeId;
  final String uidTaxista;
  final Map<String, dynamic>? viajeDataSemilla;
  final bool regresarAlPoolNormal;

  @override
  State<PostViajeTaxistaFlow> createState() => _PostViajeTaxistaFlowState();
}

class _PostViajeTaxistaFlowState extends State<PostViajeTaxistaFlow> {
  int _step = 0;
  double _calificacion = 5;
  final TextEditingController _comentario = TextEditingController();
  bool _cargandoRating = false;
  bool _salioDeCalificacion = false;
  bool _omitioCalificacionPorThrottle = false;
  bool _regresoColaProgramado = false;
  static const int _maxComentario = 280;
  static const Duration _delayRegresoCola = Duration(milliseconds: 900);

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _viajeSub;
  DocumentSnapshot<Map<String, dynamic>>? _viajeSnap;
  Map<String, dynamic>? _viajeDatosUi;

  @override
  void initState() {
    super.initState();
    final Map<String, dynamic>? sem = widget.viajeDataSemilla;
    if (sem != null && sem.isNotEmpty) {
      _viajeDatosUi = Map<String, dynamic>.from(sem);
    }
    _viajeSub = FirebaseFirestore.instance
        .collection('viajes')
        .doc(widget.viajeId)
        .snapshots()
        .listen((DocumentSnapshot<Map<String, dynamic>> snap) {
      if (!mounted) return;
      setState(() {
        _viajeSnap = snap;
        if (snap.exists) _viajeDatosUi = null;
      });
    });
  }

  @override
  void dispose() {
    _viajeSub?.cancel();
    _comentario.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _datos {
    if (_viajeSnap?.exists == true) {
      return _viajeSnap!.data();
    }
    return _viajeDatosUi;
  }

  String _money(num? n) => FormatosMoneda.rd((n ?? 0).toDouble());

  double _scrollBottomPad(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final double sys = mq.viewPadding.bottom > mq.padding.bottom
        ? mq.viewPadding.bottom
        : mq.padding.bottom;
    return sys + 48;
  }

  double _totalRd(Map<String, dynamic> d, Viaje v) {
    if (d['precioFinal'] is num) {
      return (d['precioFinal'] as num).toDouble();
    }
    return v.precio;
  }

  Future<void> _finalizarFlujo() async {
    if (!mounted) {
      await TaxistaColaPostCompletar.navegarTrasCompletar(
        uidTaxista: widget.uidTaxista,
        regresarAlPoolNormal: widget.regresarAlPoolNormal,
      );
      return;
    }
    await TaxistaColaPostCompletar.navegarTrasCompletar(
      context: context,
      uidTaxista: widget.uidTaxista,
      regresarAlPoolNormal: widget.regresarAlPoolNormal,
    );
  }

  void _programarRegresoCola() {
    if (_regresoColaProgramado) return;
    _regresoColaProgramado = true;
    Future<void>.delayed(_delayRegresoCola, () {
      if (!mounted) return;
      unawaited(_finalizarFlujo());
    });
  }

  Future<void> _continuarDesdeResumen(Viaje v, Map<String, dynamic> d) async {
    final bool yaCalificado =
        d['clienteCalificado'] == true || _salioDeCalificacion;
    final bool puedeRate =
        !yaCalificado && v.uidCliente.trim().isNotEmpty;
    final bool esCorp = CorporativoTaxistaService.esViajeCorporativoDoc(d);
    final bool mostrarCalificacion = puedeRate &&
        (esCorp || PostViajeRatingThrottle.viajeSolicitaCalificacionMutua(d));
    if (puedeRate && !mostrarCalificacion) {
      _omitioCalificacionPorThrottle = true;
    }
    if (!mounted) return;
    if (!mostrarCalificacion || !puedeRate) {
      setState(() {
        _salioDeCalificacion = true;
        _step = 2;
      });
      _programarRegresoCola();
      return;
    }
    setState(() => _step = 1);
  }

  Future<void> _enviarCalificacion(Viaje v) async {
    if (_cargandoRating) return;
    setState(() => _cargandoRating = true);
    try {
      await ViajeData.calificarClienteSeguro(
        viajeId: widget.viajeId,
        uidTaxista: widget.uidTaxista,
        calificacion: _calificacion,
        comentario: _comentario.text.trim().isEmpty
            ? null
            : _comentario.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Calificación enviada.')),
      );
      setState(() {
        _salioDeCalificacion = true;
        _step = 2;
      });
      _programarRegresoCola();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al calificar: $e')),
      );
    } finally {
      if (mounted) setState(() => _cargandoRating = false);
    }
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
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _gananciaNetaRd(Map<String, dynamic> d, Viaje v) {
    final gc = d['ganancia_cents'];
    if (gc is num && gc > 0) return gc.toDouble() / 100.0;
    final g = d['gananciaTaxista'];
    if (g is num && g > 0) return g.toDouble();
    return PlataformaEconomia.gananciaTaxistaRdDesdeTotal(_totalRd(d, v));
  }

  Widget _stepResumen(Viaje v, Map<String, dynamic> d) {
    final double total = _totalRd(d, v);
    final double neto = _gananciaNetaRd(d, v);
    final bool esCorp = CorporativoTaxistaService.esViajeCorporativoDoc(d);
    final bool esEfectivo = MetodoPagoViaje.esEfectivo(v.metodoPago);
    final bool esTransfer = MetodoPagoViaje.esTransferencia(v.metodoPago);

    final double bottomPad = _scrollBottomPad(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 8, 24, bottomPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            '${v.origen} → ${v.destino}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, height: 1.35),
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
                _kv('Método', MetodoPagoViaje.etiquetaDocumento(v.metodoPago)),
                if ((d['nombreCliente'] ?? d['clienteNombre'] ?? '')
                    .toString()
                    .trim()
                    .isNotEmpty)
                  _kv(
                    'Pasajero',
                    (d['nombreCliente'] ?? d['clienteNombre'] ?? '')
                        .toString()
                        .trim(),
                  ),
                const Divider(height: 28, color: Colors.white24),
                const Text(
                  'Monto del servicio',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _money(esCorp ? neto : total),
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      height: 1.05,
                    ),
                  ),
                ),
                if (esCorp) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Tarifa ruta ${_money(total)} · tu neto acumulado',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Ruta corporativa: este neto se suma en Ganancias → Corporativo. '
                    'RAI te transfiere al liquidar el período con la empresa. '
                    'No cobrás al pasajero en la calle.',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ] else if (esEfectivo) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Cobraste ${_money(total)} en efectivo al pasajero.',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ] else if (esTransfer) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'En transferencia, el pasajero paga el total acordado a tu cuenta.',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () => _continuarDesdeResumen(v, d),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Continuar',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepCalificar(Viaje v, Map<String, dynamic> d) {
    final bool ya =
        d['clienteCalificado'] == true || _salioDeCalificacion;
    final bool esCorp = CorporativoTaxistaService.esViajeCorporativoDoc(d);

    final double bottomPad = _scrollBottomPad(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 8, 24, bottomPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            esCorp ? 'Califica al encargado' : 'Califica al pasajero',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (esCorp) ...[
            const SizedBox(height: 6),
            const Text(
              'Ruta corporativa: calificás al contacto de la empresa, no a cada pasajero.',
              style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.35),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${v.origen} → ${v.destino}',
            style: const TextStyle(color: Colors.white60, fontSize: 14),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (int i) {
              final bool filled = _calificacion >= i + 1;
              return GestureDetector(
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
          const SizedBox(height: 16),
          Slider(
            value: _calificacion,
            min: 1,
            max: 5,
            divisions: 4,
            activeColor: Colors.greenAccent,
            onChanged:
                ya ? null : (double x) => setState(() => _calificacion = x),
          ),
          TextField(
            controller: _comentario,
            enabled: !ya,
            maxLines: 3,
            maxLength: _maxComentario,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF1A1A1A),
              labelText: 'Comentario (opcional)',
              labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_cargandoRating)
            const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            )
          else
            FilledButton(
              onPressed: ya ? null : () => _enviarCalificacion(v),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 16),
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
                  builder: (_) => ReportarClienteViaje(viaje: v),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orangeAccent,
              side: const BorderSide(color: Colors.orangeAccent),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.flag_outlined, size: 20),
            label: const Text('Reportar problema con el pasajero'),
          ),
          TextButton(
            onPressed: () => setState(() => _step = 0),
            child: const Text('Volver al resumen',
                style: TextStyle(color: Colors.white54)),
          ),
          if (!ya)
            TextButton(
              onPressed: () {
                setState(() {
                  _salioDeCalificacion = true;
                  _step = 2;
                });
                _programarRegresoCola();
              },
              child: const Text('Ahora no',
                  style: TextStyle(color: Colors.white38)),
            ),
        ],
      ),
    );
  }

  Widget _stepCierre() {
    final String subtitulo = _salioDeCalificacion
        ? 'Tu calificación fue registrada. Volviendo al inicio…'
        : _omitioCalificacionPorThrottle
            ? 'Listo para seguir recibiendo viajes. Volviendo al inicio…'
            : 'Volviendo al inicio…';
    if (!_regresoColaProgramado) {
      _programarRegresoCola();
    }
    final double bottomPad = _scrollBottomPad(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 40, 24, bottomPad),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_rounded,
              color: Colors.greenAccent, size: 56),
          const SizedBox(height: 20),
          const Text(
            '¡Listo!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 28),
          const CircularProgressIndicator(color: Colors.greenAccent),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => unawaited(_finalizarFlujo()),
            icon: const Icon(Icons.local_taxi_rounded),
            label: const Text(
              'Volver a recibir viajes',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? d = _datos;
    if (d == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(
          child: CircularProgressIndicator(color: Colors.greenAccent),
        ),
      );
    }

    final Viaje v = Viaje.fromMap(widget.viajeId, d);
    final bool yaCalificado =
        d['clienteCalificado'] == true || _salioDeCalificacion;

    final int stepUi = _salioDeCalificacion
        ? (_step < 2 ? 2 : _step).clamp(0, 2)
        : ((_step == 1 && yaCalificado) ? 2 : _step.clamp(0, 2));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) return;
        unawaited(_finalizarFlujo());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF141414),
          foregroundColor: Colors.white,
          title: Text(
            stepUi == 0
                ? 'Recibo'
                : stepUi == 1
                    ? 'Calificar pasajero'
                    : 'Listo',
          ),
        ),
        body: switch (stepUi) {
          0 => _stepResumen(v, d),
          1 => _stepCalificar(v, d),
          _ => _stepCierre(),
        },
      ),
    );
  }
}
