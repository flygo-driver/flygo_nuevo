import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flygo_nuevo/data/viaje_data.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/pantallas/cliente/reportar_viaje.dart';

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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = cs.onSurface;
    final muted = onSurface.withValues(alpha: 0.72);
    final hint = onSurface.withValues(alpha: 0.45);
    final fieldFill = isDark
        ? (Colors.grey[900] ?? const Color(0xFF212121))
        : const Color(0xFFF1F5F9);

    return PopScope(
      // Bloquea el "atrás" mientras está guardando
      canPop: !_cargando,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.appBarTheme.backgroundColor,
          foregroundColor: theme.appBarTheme.foregroundColor,
          iconTheme: IconThemeData(color: theme.appBarTheme.foregroundColor),
          elevation: theme.appBarTheme.elevation ?? 0,
          title: Text(
            'Calificar Servicio',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: cs.primary,
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
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (v.precio > 0) ...[
                  Text(
                    '💰 Total: RD\$${v.precio.toStringAsFixed(2)}',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 16),
                ],

                Text(
                  '¿Qué te pareció el servicio?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: onSurface,
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
                          color: cs.primary,
                          size: 32,
                        ),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 8),
                Text(
                  '${_calificacion.toInt()} ${_calificacion.toInt() == 1 ? 'estrella' : 'estrellas'}',
                  style: TextStyle(color: muted),
                ),

                const SizedBox(height: 16),

                // Slider sincronizado
                Slider(
                  value: _calificacion,
                  min: 1,
                  max: 5,
                  divisions: 4,
                  activeColor: cs.primary,
                  inactiveColor:
                      cs.outline.withValues(alpha: isDark ? 0.45 : 0.35),
                  label: '${_calificacion.toInt()}',
                  onChanged: yaCalificado
                      ? null
                      : (value) {
                          setState(() => _calificacion = value);
                        },
                ),

                const SizedBox(height: 8),
                Text(
                  'Comentario (opcional)',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 8),

                TextField(
                  controller: _comentarioController,
                  enabled: !yaCalificado,
                  style: TextStyle(color: onSurface, fontSize: 16),
                  maxLines: 3,
                  maxLength: _maxComentario,
                  decoration: InputDecoration(
                    counterStyle: TextStyle(color: hint),
                    hintText: 'Escribe algo…',
                    hintStyle: TextStyle(color: hint),
                    filled: true,
                    fillColor: fieldFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: cs.primary.withValues(alpha: 0.65)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: cs.primary,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                _cargando
                    ? Center(
                        child: CircularProgressIndicator(
                          color: cs.primary,
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
                            backgroundColor: cs.primary,
                            foregroundColor:
                                isDark ? Colors.black87 : Colors.white,
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
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReportarViaje(viaje: widget.viaje),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.primary,
                      side:
                          BorderSide(color: cs.primary.withValues(alpha: 0.55)),
                    ),
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Reportar problema de este viaje'),
                  ),
                ),
                if (yaCalificado) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Este viaje ya fue calificado. ¡Gracias!',
                    style: TextStyle(color: hint),
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
