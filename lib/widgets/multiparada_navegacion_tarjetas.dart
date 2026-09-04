import 'package:flutter/material.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';

/// Punto navegable (origen, parada o destino final) — diseño alineado a corp. informativo.
class MultiparadaNavegacionTarjetaModel {
  const MultiparadaNavegacionTarjetaModel({
    required this.titulo,
    required this.subtitulo,
    required this.accion,
    required this.acento,
    required this.icono,
    this.legIndex,
    this.visitado = false,
    this.navegadoEnSesion = false,
    this.confirmacionHabilitada = false,
    this.onTap,
    this.onMarcarHecha,
    this.onConfirmarBloqueado,
  });

  final String titulo;
  final String subtitulo;
  final String accion;
  final Color acento;
  final IconData icono;
  /// `null` = recogida/origen (no registra leg en servidor).
  final int? legIndex;
  final bool visitado;
  final bool navegadoEnSesion;
  /// ✓ activo (Waze/Maps ya abierto o modo prueba).
  final bool confirmacionHabilitada;
  final VoidCallback? onTap;
  final VoidCallback? onMarcarHecha;
  /// Al tocar ✓ antes de abrir Waze/Maps.
  final VoidCallback? onConfirmarBloqueado;

  bool get yaAbierta => visitado || navegadoEnSesion;
  bool get destacarConfirmacion =>
      confirmacionHabilitada && navegadoEnSesion && !visitado;
  bool get mostrarBotonConfirmar =>
      legIndex != null && !visitado && onMarcarHecha != null;
}

/// Índices de legs multiparada ya confirmados en Firestore (orden libre).
Set<int> multiparadaLegsVisitadosDesdeViaje(Viaje v, {required int totalLegs}) {
  final out = <int>{};
  final raw = v.multiparadaParadasVisitadas;
  if (raw != null && raw.isNotEmpty) {
    for (final item in raw) {
      final dynamic idxRaw = item['legIndex'];
      if (idxRaw is num && idxRaw.isFinite) {
        final int idx = idxRaw.toInt();
        if (idx >= 0 && idx < totalLegs) out.add(idx);
      }
    }
    return out;
  }
  final int n = v.multiparadaLegCompletadas.clamp(0, totalLegs);
  for (var i = 0; i < n; i++) {
    out.add(i);
  }
  return out;
}

/// Paradas donde el chofer ya abrió Waze/Maps (incluye confirmadas).
Set<int> multiparadaLegsAbiertosDesdeViaje(Viaje v, {required int totalLegs}) {
  final out = <int>{};
  for (final idx in v.multiparadaParadasAbiertas) {
    if (idx >= 0 && idx < totalLegs) out.add(idx);
  }
  out.addAll(multiparadaLegsVisitadosDesdeViaje(v, totalLegs: totalLegs));
  return out;
}

bool multiparadaRecogidaAbiertaDesdeViaje(Viaje v) {
  if (v.multiparadaRecogidaAbierta) return true;
  final extras = v.extras;
  if (extras != null) {
    if (extras['clienteAbordo'] == true) return true;
    if (extras['pickupConfirmadoEn'] != null) return true;
  }
  return false;
}

const List<Color> kMultiparadaNavegacionAcentos = <Color>[
  Color(0xFFEAB308),
  Color(0xFF22C55E),
  Color(0xFF3B82F6),
  Color(0xFFA855F7),
  Color(0xFFF97316),
  Color(0xFF14B8A6),
  Color(0xFFEC4899),
  Color(0xFF06B6D4),
];

const String kMultiparadaNavegacionHintPasos =
    '① Tocá la parada  →  ② Waze o Maps  →  ③ Confirmá con ✓';

/// Lista de tarjetas tocables (Waze/Maps) con rayita al navegar — mismo lenguaje que corp.
class MultiparadaNavegacionTarjetasPanel extends StatelessWidget {
  const MultiparadaNavegacionTarjetasPanel({
    super.key,
    required this.tituloProgreso,
    required this.tarjetas,
    this.subtituloHint,
    this.accionesInferiores = const <Widget>[],
    this.mostrarPasos = true,
  });

  final String tituloProgreso;
  final String? subtituloHint;
  final List<MultiparadaNavegacionTarjetaModel> tarjetas;
  final List<Widget> accionesInferiores;
  final bool mostrarPasos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                Colors.orange.withValues(alpha: 0.18),
                Colors.orange.withValues(alpha: 0.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.alt_route_rounded,
                      color: Colors.orangeAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tituloProgreso,
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              if (mostrarPasos) ...<Widget>[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    kMultiparadaNavegacionHintPasos,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (subtituloHint != null && subtituloHint!.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  subtituloHint!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final t in tarjetas) ...<Widget>[
          MultiparadaNavegacionTarjeta(model: t),
          const SizedBox(height: 10),
        ],
        ...accionesInferiores,
      ],
    );
  }
}

class MultiparadaNavegacionTarjeta extends StatelessWidget {
  const MultiparadaNavegacionTarjeta({super.key, required this.model});

  final MultiparadaNavegacionTarjetaModel model;

  @override
  Widget build(BuildContext context) {
    final esperandoConfirmacion = model.destacarConfirmacion;
    final yaAbierta = model.visitado || model.navegadoEnSesion;
    final acento = model.acento;
    final colorBorde = esperandoConfirmacion
        ? const Color(0xFFEAB308).withValues(alpha: 0.75)
        : yaAbierta
            ? Colors.white24
            : acento.withValues(alpha: 0.5);
    final colorNombre = esperandoConfirmacion
        ? Colors.white
        : yaAbierta
            ? Colors.white38
            : Colors.white;
    final colorDestino = esperandoConfirmacion
        ? Colors.white70
        : yaAbierta
            ? Colors.white30
            : Colors.white60;
    final colorIcono = esperandoConfirmacion
        ? const Color(0xFFEAB308)
        : yaAbierta
            ? Colors.white38
            : acento;
    final colorFondoIcono = esperandoConfirmacion
        ? const Color(0xFFEAB308).withValues(alpha: 0.22)
        : yaAbierta
            ? Colors.white.withValues(alpha: 0.06)
            : acento.withValues(alpha: 0.2);

    return Opacity(
      opacity: model.visitado ? 0.72 : 1,
      child: Material(
        color: esperandoConfirmacion
            ? const Color(0xFF1A1508)
            : yaAbierta
                ? const Color(0xFF0D1117)
                : RaiDsColors.bg,
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: <Widget>[
            if (yaAbierta && !esperandoConfirmacion)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _MultiparadaNavegacionRayitaPainter(),
                  ),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorBorde,
                  width: esperandoConfirmacion ? 1.6 : 1.2,
                ),
                boxShadow: esperandoConfirmacion
                    ? <BoxShadow>[
                        BoxShadow(
                          color: const Color(0xFFEAB308).withValues(alpha: 0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: InkWell(
                      onTap: model.onTap,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: colorFondoIcono,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                model.visitado
                                    ? Icons.check_rounded
                                    : esperandoConfirmacion
                                        ? Icons.navigation_rounded
                                        : model.icono,
                                color: colorIcono,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    model.titulo,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colorNombre,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 17,
                                      letterSpacing: -0.2,
                                      decoration: model.visitado
                                          ? TextDecoration.lineThrough
                                          : null,
                                      decorationColor: Colors.white54,
                                      decorationThickness: 2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    model.subtitulo,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colorDestino,
                                      fontSize: 13,
                                      height: 1.3,
                                      decoration: model.visitado
                                          ? TextDecoration.lineThrough
                                          : null,
                                      decorationColor: Colors.white38,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    model.accion,
                                    style: TextStyle(
                                      color: esperandoConfirmacion
                                          ? const Color(0xFFEAB308)
                                          : yaAbierta
                                              ? Colors.white38
                                              : acento,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: model.onTap == null
                                  ? Colors.white24
                                  : yaAbierta
                                      ? Colors.white24
                                      : acento,
                              size: 30,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (model.mostrarBotonConfirmar)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _BotonConfirmarParada(
                        habilitado: model.confirmacionHabilitada,
                        destacado: esperandoConfirmacion,
                        acento: acento,
                        onConfirmar: model.onMarcarHecha,
                        onBloqueado: model.onConfirmarBloqueado,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotonConfirmarParada extends StatelessWidget {
  const _BotonConfirmarParada({
    required this.habilitado,
    required this.destacado,
    required this.acento,
    required this.onConfirmar,
    this.onBloqueado,
  });

  final bool habilitado;
  final bool destacado;
  final Color acento;
  final VoidCallback? onConfirmar;
  final VoidCallback? onBloqueado;

  @override
  Widget build(BuildContext context) {
    final Color color = destacado
        ? const Color(0xFFEAB308)
        : habilitado
            ? acento
            : Colors.white38;
    final double size = destacado ? 52 : 46;

    return Material(
      color: habilitado
          ? color.withValues(alpha: destacado ? 0.22 : 0.14)
          : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          if (habilitado) {
            onConfirmar?.call();
          } else {
            onBloqueado?.call();
          }
        },
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            habilitado ? Icons.check_rounded : Icons.check_circle_outline,
            color: color,
            size: destacado ? 30 : 26,
          ),
        ),
      ),
    );
  }
}

class _MultiparadaNavegacionRayitaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      const Offset(8, 12),
      Offset(size.width - 8, size.height - 12),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
