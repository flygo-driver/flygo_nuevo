// lib/pantallas/cliente/post_viaje_cliente_flow.dart
//
// Flujo único post-viaje: resumen (según método) → calificación → cierre.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/data/viaje_data.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/pantallas/cliente/reportar_viaje.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';

class PostViajeClienteFlow extends StatefulWidget {
  final String viajeId;

  const PostViajeClienteFlow({super.key, required this.viajeId});

  @override
  State<PostViajeClienteFlow> createState() => _PostViajeClienteFlowState();
}

class _PostViajeClienteFlowState extends State<PostViajeClienteFlow> {
  int _step = 0;
  double _calificacion = 5;
  final TextEditingController _comentario = TextEditingController();
  bool _cargandoRating = false;
  static const int _maxComentario = 280;

  @override
  void dispose() {
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
    if (esEfectivo && !yaVioRecibo) {
      try {
        await _marcarReciboEfectivoVisto(v.id, uid);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo guardar el recibo: $e')),
          );
        }
      }
    }
    if (!mounted) return;
    final String estN = EstadosViaje.normalizar(v.estado);
    final bool puedeRate = v.uidTaxista.isNotEmpty &&
        v.calificado != true &&
        !EstadosViaje.esCancelado(estN);
    setState(() {
      _step = puedeRate ? 1 : 2;
    });
  }

  Future<void> _enviarCalificacion(Viaje v, String uid) async {
    if (_cargandoRating) return;
    FocusScope.of(context).unfocus();
    setState(() => _cargandoRating = true);
    try {
      await ViajeData.calificarViajeSeguro(
        viajeId: v.id,
        uidCliente: uid,
        calificacion: _calificacion.clamp(1, 5).toDouble(),
        comentario: _comentario.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Gracias por tu calificación!')),
      );
      setState(() {
        _cargandoRating = false;
        _step = 2;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al calificar: $e')),
        );
        setState(() => _cargandoRating = false);
      }
    }
  }

  void _irInicio() {
    Navigator.of(context)
        .pushNamedAndRemoveUntil('/auth_check', (Route<dynamic> r) => false);
  }

  Widget _stepResumen({
    required Viaje v,
    required Map<String, dynamic> d,
    required String uid,
  }) {
    final String metodoRaw =
        (d['metodoPago'] ?? v.metodoPago).toString().toLowerCase();
    final bool esEfectivo = metodoRaw.contains('efectivo');
    final bool esTransfer = metodoRaw.contains('transfer');
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
                if (v.destino.isNotEmpty) _kv('Destino', v.destino),
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
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                    builder: (_) => ReportarViaje(viaje: v)),
              );
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
              onPressed: () => setState(() => _step = 2),
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
            onPressed: _irInicio,
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
            onPressed: _irInicio,
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

  @override
  Widget build(BuildContext context) {
    final User? u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child:
                Text('Inicia sesión', style: TextStyle(color: Colors.white70))),
      );
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
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
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('viajes')
              .doc(widget.viajeId)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: Colors.greenAccent));
            }
            if (snap.hasError || !snap.hasData || !snap.data!.exists) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'No encontramos el viaje.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _irInicio,
                        child: const Text('Ir al inicio'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final d = snap.data!.data() ?? {};
            final v =
                Viaje.fromMap(snap.data!.id, Map<String, dynamic>.from(d));
            final st =
                EstadosViaje.normalizar((d['estado'] ?? v.estado).toString());
            final bool esCancel =
                st == EstadosViaje.cancelado || st == EstadosViaje.rechazado;
            final bool esOk =
                (d['completado'] == true) || st == EstadosViaje.completado;

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

            switch (_step) {
              case 0:
                return _stepResumen(v: v, d: d, uid: u.uid);
              case 1:
                return _stepCalificar(v, u.uid);
              default:
                return _stepCierre();
            }
          },
        ),
      ),
    );
  }
}
