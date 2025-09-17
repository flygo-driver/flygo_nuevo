import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flygo_nuevo/data/viaje_data.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';

class CalificarServicio extends StatefulWidget {
  final Viaje viaje;
  const CalificarServicio({super.key, required this.viaje});

  @override
  State<CalificarServicio> createState() => _CalificarServicioState();
}

class _CalificarServicioState extends State<CalificarServicio> {
  double _calificacion = 5.0;
  final TextEditingController _comentarioController = TextEditingController();
  bool _cargando = false;
  static const int _maxComentario = 280;

  @override
  void dispose() {
    _comentarioController.dispose();
    super.dispose();
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _onTapStar(int index) {
    if (widget.viaje.calificado == true) return; // bloqueo si ya calificado
    setState(() => _calificacion = (index + 1).toDouble()); // 1..5
  }

  Future<void> _guardarCalificacion() async {
    if (_cargando) return;
    FocusScope.of(context).unfocus();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _msg('Debes iniciar sesión.');
      return;
    }
    if (widget.viaje.calificado == true) {
      _msg('Este viaje ya fue calificado.');
      return;
    }

    setState(() => _cargando = true);
    final nav = Navigator.of(context);

    try {
      await ViajeData.calificarViajeSeguro(
        viajeId: widget.viaje.id,
        uidCliente: user.uid,
        calificacion: _calificacion.clamp(1, 5).toDouble(),
        comentario: _comentarioController.text.trim(),
      );

      _msg('¡Gracias por tu calificación!');
      if (mounted) nav.pop(true);
    } catch (e) {
      _msg('Error al guardar calificación: $e');
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.viaje;
    final yaCalificado = v.calificado == true;

    return PopScope(
      // Bloquea el "atrás" mientras está guardando
      canPop: !_cargando,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'Calificar Servicio',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.greenAccent,
            ),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (v.origen.isNotEmpty || v.destino.isNotEmpty) ...[
                  Text(
                    '🧭 ${v.origen} → ${v.destino}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (v.precio > 0) ...[
                  Text(
                    '💰 Total: RD\$${v.precio.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                ],

                const Text(
                  '¿Qué te pareció el servicio?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),

                // Estrellas táctiles
                Row(
                  children: List.generate(5, (i) {
                    final filled = _calificacion >= i + 1;
                    return GestureDetector(
                      onTap: yaCalificado ? null : () => _onTapStar(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          filled ? Icons.star : Icons.star_border,
                          color: Colors.greenAccent,
                          size: 32,
                        ),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 8),
                Text(
                  '${_calificacion.toInt()} ${_calificacion.toInt() == 1 ? 'estrella' : 'estrellas'}',
                  style: const TextStyle(color: Colors.white70),
                ),

                const SizedBox(height: 16),

                // Slider sincronizado
                Slider(
                  value: _calificacion,
                  min: 1,
                  max: 5,
                  divisions: 4,
                  activeColor: Colors.greenAccent,
                  inactiveColor: Colors.white24,
                  label: '${_calificacion.toInt()}',
                  onChanged: yaCalificado
                      ? null
                      : (value) {
                          setState(() => _calificacion = value);
                        },
                ),

                const SizedBox(height: 8),
                const Text(
                  'Comentario (opcional)',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),

                TextField(
                  controller: _comentarioController,
                  enabled: !yaCalificado,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  maxLines: 3,
                  maxLength: _maxComentario,
                  decoration: InputDecoration(
                    counterStyle: const TextStyle(color: Colors.white54),
                    hintText: 'Escribe algo…',
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: Colors.grey[900],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.greenAccent),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(
                        color: Colors.greenAccent,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                _cargando
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Colors.greenAccent,
                        ),
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.send),
                          label: Text(
                            yaCalificado
                                ? 'Ya calificado'
                                : 'Enviar calificación',
                          ),
                          onPressed: yaCalificado ? null : _guardarCalificacion,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.green,
                            minimumSize: const Size(double.infinity, 55),
                            textStyle: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                if (yaCalificado) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Este viaje ya fue calificado. ¡Gracias!',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
