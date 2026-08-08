// Flujo post-viaje taxista: resumen (monto grande) → calificación (throttle) → cola.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/data/viaje_data.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/pantallas/taxista/reportar_cliente_viaje.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/taxista_cola_post_completar.dart';
import 'package:flygo_nuevo/servicios/calificacion_pendiente_service.dart';
import 'package:flygo_nuevo/servicios/rai_connectivity_service.dart';
import 'package:flygo_nuevo/utils/post_viaje_rating_throttle.dart';
import 'package:flygo_nuevo/widgets/post_viaje_recibo_resumen.dart';

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
  static const int _maxComentario = 280;

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
    RaiConnectivityService.instance.ensureStarted();
    unawaited(CalificacionPendienteService.flushPendientes());
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

  double _scrollBottomPad(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final double sys = mq.viewPadding.bottom > mq.padding.bottom
        ? mq.viewPadding.bottom
        : mq.padding.bottom;
    return sys + 48;
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
    } catch (e) {
      if (!mounted) return;
      if (CalificacionPendienteService.esErrorDeRed(e)) {
        await CalificacionPendienteService.encolar(
          rol: 'taxista',
          viajeId: widget.viajeId,
          uid: widget.uidTaxista,
          calificacion: _calificacion,
          comentario: _comentario.text.trim(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sin conexión estable. Guardamos tu calificación y la enviaremos al reconectar.',
            ),
          ),
        );
        setState(() {
          _salioDeCalificacion = true;
          _step = 2;
        });
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al calificar: $e')),
      );
    } finally {
      if (mounted) setState(() => _cargandoRating = false);
    }
  }

  Widget _stepResumen(Viaje v, Map<String, dynamic> d) {
    final double bottomPad = _scrollBottomPad(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 8, 24, bottomPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PostViajeReciboResumen(
            role: 'taxista',
            viaje: v,
            data: d,
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
              },
              child: const Text('Ahora no',
                  style: TextStyle(color: Colors.white38)),
            ),
        ],
      ),
    );
  }

  Widget _stepCierre() {
    final bool corp = widget.regresarAlPoolNormal;
    final String subtitulo = corp
        ? 'Ruta cerrada. Cuando quieras, volvé a Mis rutas corporativas.'
        : _salioDeCalificacion
            ? 'Tu calificación fue registrada. Podés volver a recibir viajes.'
            : _omitioCalificacionPorThrottle
                ? 'Listo para seguir recibiendo viajes.'
                : 'Viaje cerrado correctamente.';
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
          FilledButton.icon(
            onPressed: () => unawaited(_finalizarFlujo()),
            icon: Icon(corp ? Icons.route_rounded : Icons.local_taxi_rounded),
            label: Text(
              corp ? 'Volver a Mis rutas' : 'Volver a recibir viajes',
              style: const TextStyle(fontWeight: FontWeight.w800),
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
