// Flujo post-viaje taxista: calificar cliente + reportar → cola / shell.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/data/viaje_data.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/pantallas/taxista/reportar_cliente_viaje.dart';
import 'package:flygo_nuevo/servicios/taxista_cola_post_completar.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';

class PostViajeTaxistaFlow extends StatefulWidget {
  const PostViajeTaxistaFlow({
    super.key,
    required this.viajeId,
    required this.uidTaxista,
    this.viajeDataSemilla,
  });

  final String viajeId;
  final String uidTaxista;
  final Map<String, dynamic>? viajeDataSemilla;

  @override
  State<PostViajeTaxistaFlow> createState() => _PostViajeTaxistaFlowState();
}

class _PostViajeTaxistaFlowState extends State<PostViajeTaxistaFlow> {
  double _calificacion = 5;
  final TextEditingController _comentario = TextEditingController();
  bool _cargandoRating = false;
  bool _salioDeCalificacion = false;
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

  Future<void> _finalizarFlujo() async {
    if (!mounted) return;
    await TaxistaColaPostCompletar.navegarTrasCompletar(
      context: context,
      uidTaxista: widget.uidTaxista,
    );
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
      setState(() => _salioDeCalificacion = true);
      await _finalizarFlujo();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al calificar: $e')),
      );
    } finally {
      if (mounted) setState(() => _cargandoRating = false);
    }
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
    final double precio = (d['precioFinal'] is num)
        ? (d['precioFinal'] as num).toDouble()
        : v.precio;

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
          title: const Text('Calificar pasajero'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${v.origen} → ${v.destino}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                'Total: ${FormatosMoneda.rd(precio)}',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '¿Cómo fue el pasajero?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (int i) {
                  final bool filled = _calificacion >= i + 1;
                  return GestureDetector(
                    onTap: yaCalificado
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
              const SizedBox(height: 12),
              Slider(
                value: _calificacion,
                min: 1,
                max: 5,
                divisions: 4,
                activeColor: Colors.greenAccent,
                onChanged:
                    yaCalificado ? null : (double x) => setState(() => _calificacion = x),
              ),
              TextField(
                controller: _comentario,
                enabled: !yaCalificado,
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
              const SizedBox(height: 16),
              if (_cargandoRating)
                const Center(
                  child: CircularProgressIndicator(color: Colors.greenAccent),
                )
              else
                FilledButton(
                  onPressed: yaCalificado ? null : () => _enviarCalificacion(v),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    yaCalificado ? 'Ya calificaste' : 'Enviar calificación',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              const SizedBox(height: 10),
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
                onPressed: _finalizarFlujo,
                child: const Text(
                  'Omitir y continuar',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
