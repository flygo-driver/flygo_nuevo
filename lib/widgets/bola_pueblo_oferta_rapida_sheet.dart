// Hoja rápida de oferta / contraoferta Bola Ahorro (estilo RAI).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pantallas/comun/bola_pueblo_visual.dart';
import '../servicios/bola_pueblo_repo.dart';

/// Montos sugeridos para chips de contraoferta (3 distintos dentro del rango).
List<double> bolaMontosChipSugeridos({
  required double base,
  required double minRd,
  required double maxRd,
  bool soloMayoresQueBase = true,
}) {
  double redondear(double v) {
    if (v < 200) return (v / 10).round() * 10.0;
    if (v < 1000) return (v / 25).round() * 25.0;
    return (v / 50).round() * 50.0;
  }

  final List<double> candidatos = soloMayoresQueBase
      ? [
          redondear(base * 1.08),
          redondear(base * 1.14),
          redondear(base * 1.20),
          redondear(base * 1.28),
          redondear((minRd + maxRd) / 2),
          maxRd,
        ]
      : [
          redondear(base * 0.92),
          redondear(base * 0.96),
          base,
          redondear(base * 1.06),
          redondear(base * 1.12),
        ];

  final List<double> out = <double>[];
  for (final raw in candidatos) {
    final double v = raw.clamp(minRd, maxRd);
    if (v <= 0) continue;
    if (soloMayoresQueBase && v <= base + 0.5) continue;
    if (out.any((e) => (e - v).abs() < 5)) continue;
    out.add(v);
    if (out.length >= 3) break;
  }
  while (out.length < 3 && maxRd > base) {
    final double extra = redondear(
      base + (out.length + 1) * ((maxRd - base) / 4),
    ).clamp(minRd, maxRd);
    if (!out.any((e) => (e - extra).abs() < 5)) out.add(extra);
    if (out.length >= 3) break;
    if (extra >= maxRd - 1) break;
  }
  return out.take(3).toList();
}

/// Acciones de la lista de ofertas (lógica vive en [BolaPuebloDialogs.verOfertasSheet]).
class BolaPuebloListaOfertasCallbacks {
  const BolaPuebloListaOfertasCallbacks({
    required this.aceptar,
    required this.descartar,
    this.contraofertar,
    required this.retirarContra,
  });

  final Future<void> Function(BuildContext sheetCtx, String ofertaId) aceptar;
  final Future<void> Function(BuildContext sheetCtx, String ofertaId) descartar;
  final Future<void> Function(
    BuildContext sheetCtx,
    String ofertaId,
    Map<String, dynamic> oferta,
    double monto,
  )? contraofertar;
  final Future<void> Function(BuildContext sheetCtx, String ofertaId)
      retirarContra;
}

abstract final class BolaPuebloOfertaRapidaSheet {
  /// Conductor/pasajero envía oferta sobre una publicación ajena.
  static Future<void> mostrarEnviarOferta({
    required BuildContext context,
    required String bolaId,
    required String uid,
    required String nombre,
    required String rol,
    required double precioReferencia,
    required double minRd,
    required double maxRd,
    required String origen,
    required String destino,
    String tituloPublicador = '',
  }) {
    final double base =
        precioReferencia > 0 ? precioReferencia : minRd.clamp(1, maxRd);
    return _mostrar(
      context: context,
      titulo: 'Tu propuesta',
      subtitulo: tituloPublicador.trim().isEmpty
          ? 'Elegí el monto y enviá'
          : tituloPublicador.trim(),
      origen: origen,
      destino: destino,
      precioHero: base,
      minRd: minRd,
      maxRd: maxRd,
      textoBotonPrincipal: 'Enviar por RD\$${base.toStringAsFixed(0)}',
      etiquetaChips: 'Ofrecé tu tarifa',
      soloChipsMayores: true,
      onPrincipal: () => _enviarOferta(
        context: context,
        bolaId: bolaId,
        uid: uid,
        nombre: nombre,
        rol: rol,
        monto: base,
        minRd: minRd,
        maxRd: maxRd,
      ),
      onChip: (monto) => _enviarOferta(
        context: context,
        bolaId: bolaId,
        uid: uid,
        nombre: nombre,
        rol: rol,
        monto: monto,
        minRd: minRd,
        maxRd: maxRd,
      ),
    );
  }

  /// Dueño de la publicación revisa ofertas (una por página).
  static void mostrarListaOfertas({
    required BuildContext context,
    required String bolaId,
    required String tipoPublicacion,
    double? ofertaMinRd,
    double? ofertaMaxRd,
    required String origen,
    required String destino,
    required BolaPuebloListaOfertasCallbacks callbacks,
  }) {
    final c = BolaPuebloColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(sheetCtx).size.height * 0.72,
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: BolaPuebloRepo.streamOfertas(bolaId),
                  builder: (_, snap) {
                    final docs = _filtrarOfertasVisibles(
                      snap.data?.docs ?? const [],
                      tipoPublicacion: tipoPublicacion,
                    );
                    if (docs.isEmpty) {
                      return _vacio(sheetCtx, 'Aún no hay ofertas');
                    }
                    return PageView.builder(
                      itemCount: docs.length,
                      controller: PageController(viewportFraction: 0.94),
                      itemBuilder: (_, i) {
                        final d = docs[i];
                        final m = d.data();
                        final estado = (m['estado'] ?? '').toString();
                        final fromUid = (m['fromUid'] ?? '').toString();
                        final fromRol =
                            (m['fromRol'] ?? '').toString().toLowerCase();
                        final esContraCliente =
                            m['esContraofertaCliente'] == true;
                        final esContraConductor =
                            m['esContraofertaConductor'] == true;
                        final miUid =
                            FirebaseAuth.instance.currentUser?.uid ?? '';
                        final esMiContraPendiente = estado == 'pendiente' &&
                            ((esContraCliente && fromUid == miUid) ||
                                (tipoPublicacion == 'oferta' &&
                                    esContraConductor &&
                                    fromUid == miUid));
                        final filaConductorPedido = estado == 'pendiente' &&
                            tipoPublicacion == 'pedido' &&
                            (fromRol == 'taxista' || fromRol == 'driver') &&
                            !esContraCliente &&
                            !esContraConductor;
                        final filaClienteOferta = estado == 'pendiente' &&
                            tipoPublicacion == 'oferta' &&
                            fromRol == 'cliente' &&
                            !esContraCliente &&
                            !esContraConductor;
                        final puedeContraofertar =
                            filaConductorPedido || filaClienteOferta;

                        if (esMiContraPendiente) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(6, 8, 6, 12),
                            child: _PanelEsperandoContra(
                              oferta: m,
                              origen: origen,
                              destino: destino,
                              onRetirar: () =>
                                  callbacks.retirarContra(sheetCtx, d.id),
                            ),
                          );
                        }

                        if (estado != 'pendiente') {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(6, 8, 6, 12),
                            child: _PanelOfertaEstado(
                              oferta: m,
                              estado: estado,
                              origen: origen,
                              destino: destino,
                            ),
                          );
                        }

                        return Padding(
                          padding: const EdgeInsets.fromLTRB(6, 8, 6, 12),
                          child: _PanelOfertaDueno(
                            ofertaId: d.id,
                            oferta: m,
                            minRd: ofertaMinRd ?? 0,
                            maxRd: ofertaMaxRd ?? 0,
                            origen: origen,
                            destino: destino,
                            tipoPublicacion: tipoPublicacion,
                            puedeContraofertar: puedeContraofertar,
                            onAceptar: () =>
                                callbacks.aceptar(sheetCtx, d.id),
                            onDescartar: () =>
                                callbacks.descartar(sheetCtx, d.id),
                            onContraofertar: callbacks.contraofertar == null
                                ? null
                                : (monto) => callbacks.contraofertar!(
                                      sheetCtx,
                                      d.id,
                                      m,
                                      monto,
                                    ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _filtrarOfertasVisibles(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> raw, {
    required String tipoPublicacion,
  }) {
    final seenTaxistaPending = <String>{};
    final seenContraDestino = <String>{};
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in raw) {
      final m = d.data();
      final estado = (m['estado'] ?? '').toString();
      final from = (m['fromUid'] ?? '').toString();
      final esContraCliente = m['esContraofertaCliente'] == true;
      final esContraConductor = m['esContraofertaConductor'] == true;
      if (estado == 'pendiente' && !esContraCliente && !esContraConductor) {
        if (from.isEmpty || seenTaxistaPending.contains(from)) continue;
        seenTaxistaPending.add(from);
      }
      if (estado == 'pendiente' &&
          (esContraCliente || esContraConductor)) {
        final dest = (m['contraOfertaParaUid'] ?? '').toString().trim();
        final clave = '${esContraCliente ? 'c' : 't'}:$dest';
        if (dest.isEmpty || seenContraDestino.contains(clave)) continue;
        seenContraDestino.add(clave);
      }
      docs.add(d);
    }
    return docs;
  }

  static Widget _vacio(BuildContext context, String msg) {
    final c = BolaPuebloColors.of(context);
    return Center(
      child: Text(msg, style: TextStyle(color: c.onMuted, fontSize: 15)),
    );
  }

  static Future<void> _mostrar({
    required BuildContext context,
    required String titulo,
    required String subtitulo,
    required String origen,
    required String destino,
    required double precioHero,
    required double minRd,
    required double maxRd,
    required String textoBotonPrincipal,
    required String etiquetaChips,
    required bool soloChipsMayores,
    required Future<void> Function() onPrincipal,
    required Future<void> Function(double monto) onChip,
  }) {
    final c = BolaPuebloColors.of(context);
    bool busy = false;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final chips = bolaMontosChipSugeridos(
              base: precioHero,
              minRd: minRd > 0 ? minRd : precioHero * 0.5,
              maxRd: maxRd > 0 ? maxRd : precioHero * 2,
              soloMayoresQueBase: soloChipsMayores,
            );
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewPaddingOf(sheetCtx).bottom,
              ),
              child: _CuerpoHoja(
                titulo: titulo,
                subtitulo: subtitulo,
                origen: origen,
                destino: destino,
                precioHero: precioHero,
                textoBotonPrincipal: textoBotonPrincipal,
                etiquetaChips: etiquetaChips,
                chips: chips,
                busy: busy,
                onPrincipal: () async {
                  if (busy) return;
                  setSheet(() => busy = true);
                  try {
                    await onPrincipal();
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  } finally {
                    if (ctx.mounted) setSheet(() => busy = false);
                  }
                },
                onChip: (m) async {
                  if (busy) return;
                  setSheet(() => busy = true);
                  try {
                    await onChip(m);
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  } finally {
                    if (ctx.mounted) setSheet(() => busy = false);
                  }
                },
                onPersonalizado: () async {
                  final monto = await _dialogoMontoPersonalizado(
                    sheetCtx,
                    semilla: precioHero,
                    minRd: minRd,
                    maxRd: maxRd,
                  );
                  if (monto == null || busy) return;
                  setSheet(() => busy = true);
                  try {
                    await onChip(monto);
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  } finally {
                    if (ctx.mounted) setSheet(() => busy = false);
                  }
                },
                onCerrar: () => Navigator.pop(sheetCtx),
              ),
            );
          },
        );
      },
    );
  }

  static Future<double?> _dialogoMontoPersonalizado(
    BuildContext context, {
    required double semilla,
    required double minRd,
    required double maxRd,
  }) async {
    final ctrl = TextEditingController(text: semilla.toStringAsFixed(0));
    final c = BolaPuebloColors.of(context);
    return showDialog<double>(
      context: context,
      builder: (ctx) => Theme(
        data: BolaPuebloTheme.dialogTheme(context),
        child: AlertDialog(
          backgroundColor: c.surface,
          title: Text('Tu monto', style: TextStyle(color: c.onSurface)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.onSurface,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
            decoration: InputDecoration(
              prefixText: 'RD\$ ',
              hintText: minRd > 0 && maxRd >= minRd
                  ? '${minRd.toStringAsFixed(0)} – ${maxRd.toStringAsFixed(0)}'
                  : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(
                  ctrl.text.trim().replaceAll(',', '.'),
                );
                if (v == null || v <= 0) return;
                Navigator.pop(ctx, v);
              },
              child: const Text('Listo'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _enviarOferta({
    required BuildContext context,
    required String bolaId,
    required String uid,
    required String nombre,
    required String rol,
    required double monto,
    required double minRd,
    required double maxRd,
  }) async {
    final msg = BolaPuebloRepo.validarMontoEnRangoBola(
      monto,
      minRd: minRd,
      maxRd: maxRd,
    );
    if (msg != null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        BolaPuebloTheme.snack(context, msg, error: true),
      );
      return;
    }
    await BolaPuebloRepo.enviarOferta(
      bolaId: bolaId,
      fromUid: uid,
      fromNombre: nombre,
      fromRol: rol,
      montoRd: monto,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      BolaPuebloTheme.snack(
        context,
        'Oferta enviada · RD\$${monto.toStringAsFixed(0)}',
      ),
    );
  }

  static Future<void> enviarOfertaDirecta({
    required BuildContext context,
    required String bolaId,
    required String uid,
    required String nombre,
    required String rol,
    required double monto,
    required double minRd,
    required double maxRd,
  }) =>
      _enviarOferta(
        context: context,
        bolaId: bolaId,
        uid: uid,
        nombre: nombre,
        rol: rol,
        monto: monto,
        minRd: minRd,
        maxRd: maxRd,
      );

  static Future<double?> dialogoMontoPersonalizado(
    BuildContext context, {
    required double semilla,
    required double minRd,
    required double maxRd,
  }) =>
      _dialogoMontoPersonalizado(
        context,
        semilla: semilla,
        minRd: minRd,
        maxRd: maxRd,
      );
}

/// Tarifas en la tarjeta del tablero (debajo del precio, sin abrir hoja ni «Más»).
class BolaPuebloOfertaTableroInline extends StatefulWidget {
  const BolaPuebloOfertaTableroInline({
    super.key,
    required this.bolaId,
    required this.uid,
    required this.nombre,
    required this.rol,
    required this.base,
    required this.minRd,
    required this.maxRd,
    this.disabled = false,
  });

  final String bolaId;
  final String uid;
  final String nombre;
  final String rol;
  final double base;
  final double minRd;
  final double maxRd;
  final bool disabled;

  @override
  State<BolaPuebloOfertaTableroInline> createState() =>
      _BolaPuebloOfertaTableroInlineState();
}

class _BolaPuebloOfertaTableroInlineState
    extends State<BolaPuebloOfertaTableroInline> {
  bool _busy = false;

  double get _min =>
      widget.minRd > 0 ? widget.minRd : widget.base * 0.7;
  double get _max =>
      widget.maxRd > 0 ? widget.maxRd : widget.base * 1.4;

  Future<void> _enviar(double monto) async {
    if (_busy || widget.disabled) return;
    setState(() => _busy = true);
    try {
      await BolaPuebloOfertaRapidaSheet.enviarOfertaDirecta(
        context: context,
        bolaId: widget.bolaId,
        uid: widget.uid,
        nombre: widget.nombre,
        rol: widget.rol,
        monto: monto,
        minRd: _min,
        maxRd: _max,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BolaPuebloColors.of(context);
    final chips = bolaMontosChipSugeridos(
      base: widget.base,
      minRd: _min,
      maxRd: _max,
      soloMayoresQueBase: true,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Text(
          'Elegí tu tarifa',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.onMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final m in chips)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: m == chips.last ? 0 : 6),
                  child: _ChipMontoRai(
                    monto: m,
                    compact: true,
                    onTap: _busy || widget.disabled ? null : () => _enviar(m),
                  ),
                ),
              ),
            SizedBox(
              width: 48,
              height: 48,
              child: _ChipMontoRai(
                icono: Icons.edit_rounded,
                compact: true,
                onTap: _busy || widget.disabled
                    ? null
                    : () async {
                        final monto =
                            await BolaPuebloOfertaRapidaSheet
                                .dialogoMontoPersonalizado(
                          context,
                          semilla: widget.base,
                          minRd: _min,
                          maxRd: _max,
                        );
                        if (monto != null) await _enviar(monto);
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: FilledButton(
            style: BolaPuebloUi.filledPrimary.copyWith(
              minimumSize: const WidgetStatePropertyAll(
                Size(double.infinity, 52),
              ),
            ),
            onPressed: _busy || widget.disabled
                ? null
                : () => _enviar(widget.base),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    widget.base > 0
                        ? 'Ofertar · RD\$${widget.base.toStringAsFixed(0)}'
                        : 'Ofertar',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _CuerpoHoja extends StatelessWidget {
  const _CuerpoHoja({
    required this.titulo,
    required this.subtitulo,
    required this.origen,
    required this.destino,
    required this.precioHero,
    required this.textoBotonPrincipal,
    required this.etiquetaChips,
    required this.chips,
    required this.busy,
    required this.onPrincipal,
    required this.onChip,
    required this.onPersonalizado,
    required this.onCerrar,
    this.textoCerrar = 'Cerrar',
    this.ocultarChips = false,
  });

  final String titulo;
  final String subtitulo;
  final String origen;
  final String destino;
  final double precioHero;
  final String textoBotonPrincipal;
  final String etiquetaChips;
  final List<double> chips;
  final bool busy;
  final VoidCallback onPrincipal;
  final ValueChanged<double> onChip;
  final VoidCallback onPersonalizado;
  final VoidCallback onCerrar;
  final String textoCerrar;
  final bool ocultarChips;

  @override
  Widget build(BuildContext context) {
    final c = BolaPuebloColors.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.dragHandle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: BolaPuebloTheme.accent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: BolaPuebloTheme.accent.withValues(alpha: 0.45),
                  ),
                ),
                child: const Icon(
                  Icons.local_taxi_rounded,
                  color: BolaPuebloTheme.accent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        color: c.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    if (subtitulo.isNotEmpty)
                      Text(
                        subtitulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.onMuted, fontSize: 13),
                      ),
                  ],
                ),
              ),
              _RaiBadge(),
            ],
          ),
          const SizedBox(height: 16),
          _RutaRai(origen: origen, destino: destino),
          const SizedBox(height: 20),
          Text(
            'RD\$${precioHero.toStringAsFixed(0)}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: BolaPuebloTheme.accentWarm,
              fontSize: 40,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              height: 1,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 56,
            child: FilledButton(
              style: BolaPuebloUi.filledPrimary.copyWith(
                minimumSize: const WidgetStatePropertyAll(
                  Size(double.infinity, 56),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              onPressed: busy ? null : onPrincipal,
              child: busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      textoBotonPrincipal,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 18),
          if (!ocultarChips) ...[
            Text(
              etiquetaChips,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.onMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final m in chips)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: m == chips.last ? 0 : 8,
                      ),
                      child: _ChipMontoRai(
                        monto: m,
                        onTap: busy ? null : () => onChip(m),
                      ),
                    ),
                  ),
                SizedBox(
                  width: 56,
                  height: 56,
                  child: _ChipMontoRai(
                    icono: Icons.edit_rounded,
                    onTap: busy ? null : onPersonalizado,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          OutlinedButton(
            onPressed: busy ? null : onCerrar,
            style: OutlinedButton.styleFrom(
              foregroundColor: c.onMuted,
              side: BorderSide(color: c.outlineSoft),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(textoCerrar),
          ),
        ],
      ),
    );
  }
}

class _PanelOfertaDueno extends StatefulWidget {
  const _PanelOfertaDueno({
    required this.ofertaId,
    required this.oferta,
    required this.minRd,
    required this.maxRd,
    required this.origen,
    required this.destino,
    required this.tipoPublicacion,
    required this.puedeContraofertar,
    required this.onAceptar,
    required this.onDescartar,
    this.onContraofertar,
  });

  final String ofertaId;
  final Map<String, dynamic> oferta;
  final double minRd;
  final double maxRd;
  final String origen;
  final String destino;
  final String tipoPublicacion;
  final bool puedeContraofertar;
  final Future<void> Function() onAceptar;
  final Future<void> Function() onDescartar;
  final Future<void> Function(double monto)? onContraofertar;

  @override
  State<_PanelOfertaDueno> createState() => _PanelOfertaDuenoState();
}

class _PanelOfertaDuenoState extends State<_PanelOfertaDueno> {
  bool _busy = false;

  double get _monto => ((widget.oferta['montoRd'] ?? 0) as num).toDouble();

  String get _nombre =>
      (widget.oferta['fromNombre'] ?? 'Usuario').toString();

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        BolaPuebloTheme.snack(context, '$e', error: true),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chips = widget.puedeContraofertar && widget.onContraofertar != null
        ? bolaMontosChipSugeridos(
            base: _monto,
            minRd: widget.minRd > 0 ? widget.minRd : _monto * 0.7,
            maxRd: widget.maxRd > 0 ? widget.maxRd : _monto * 1.5,
            soloMayoresQueBase: false,
          )
        : <double>[];
    return Material(
      color: BolaPuebloColors.of(context).surfaceRaised,
      borderRadius: BorderRadius.circular(20),
      child: _CuerpoHoja(
        titulo: _nombre,
        subtitulo: widget.tipoPublicacion == 'pedido'
            ? 'Conductor'
            : 'Pasajero',
        origen: widget.origen,
        destino: widget.destino,
        precioHero: _monto,
        textoBotonPrincipal: 'Aceptar por RD\$${_monto.toStringAsFixed(0)}',
        etiquetaChips: widget.puedeContraofertar
            ? 'Proponé otro monto'
            : 'Otras opciones',
        chips: chips,
        busy: _busy,
        onPrincipal: () => _run(widget.onAceptar),
        onChip: (m) => _run(() => widget.onContraofertar!(m)),
        onPersonalizado: widget.onContraofertar == null
            ? () {}
            : () async {
                final monto =
                    await BolaPuebloOfertaRapidaSheet._dialogoMontoPersonalizado(
                  context,
                  semilla: _monto,
                  minRd: widget.minRd,
                  maxRd: widget.maxRd,
                );
                if (monto != null) {
                  await _run(() => widget.onContraofertar!(monto));
                }
              },
        onCerrar: () => _run(widget.onDescartar),
        textoCerrar: 'Descartar',
        ocultarChips: chips.isEmpty,
      ),
    );
  }
}

class _PanelEsperandoContra extends StatefulWidget {
  const _PanelEsperandoContra({
    required this.oferta,
    required this.origen,
    required this.destino,
    required this.onRetirar,
  });

  final Map<String, dynamic> oferta;
  final String origen;
  final String destino;
  final Future<void> Function() onRetirar;

  @override
  State<_PanelEsperandoContra> createState() => _PanelEsperandoContraState();
}

class _PanelEsperandoContraState extends State<_PanelEsperandoContra> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final monto = ((widget.oferta['montoRd'] ?? 0) as num).toDouble();
    final c = BolaPuebloColors.of(context);
    return Material(
      color: c.surfaceRaised,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tu contraoferta',
              style: TextStyle(
                color: c.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Esperando respuesta · RD\$${monto.toStringAsFixed(0)}',
              style: TextStyle(color: c.onMuted, fontSize: 14),
            ),
            const SizedBox(height: 16),
            _RutaRai(origen: widget.origen, destino: widget.destino),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await widget.onRetirar();
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Retirar contraoferta'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelOfertaEstado extends StatelessWidget {
  const _PanelOfertaEstado({
    required this.oferta,
    required this.estado,
    required this.origen,
    required this.destino,
  });

  final Map<String, dynamic> oferta;
  final String estado;
  final String origen;
  final String destino;

  @override
  Widget build(BuildContext context) {
    final c = BolaPuebloColors.of(context);
    final monto = ((oferta['montoRd'] ?? 0) as num).toDouble();
    final nombre = (oferta['fromNombre'] ?? 'Usuario').toString();
    final motivo = (oferta['motivoRechazo'] ?? '').toString().trim();
    return Material(
      color: c.surfaceRaised,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              nombre,
              style: TextStyle(
                color: c.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'RD\$${monto.toStringAsFixed(0)}',
              style: TextStyle(
                color: BolaPuebloTheme.accentWarm,
                fontSize: 32,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            _RutaRai(origen: origen, destino: destino),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: c.onSurface.withValues(alpha: c.isDark ? 0.08 : 0.06),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                estado,
                style: TextStyle(
                  color: c.onMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (estado == 'rechazada' && motivo.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Motivo: $motivo',
                style: TextStyle(
                  color: c.onMuted,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RaiBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [BolaPuebloTheme.accent, BolaPuebloTheme.accentDark],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'RAI',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _RutaRai extends StatelessWidget {
  const _RutaRai({required this.origen, required this.destino});

  final String origen;
  final String destino;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _lineaRuta(
          context,
          color: const Color(0xFF64B5FF),
          texto: origen.isEmpty ? 'Origen' : origen,
        ),
        const SizedBox(height: 10),
        _lineaRuta(
          context,
          color: BolaPuebloTheme.accent,
          texto: destino.isEmpty ? 'Destino' : destino,
        ),
      ],
    );
  }

  Widget _lineaRuta(
    BuildContext context, {
    required Color color,
    required String texto,
  }) {
    final c = BolaPuebloColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            texto,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChipMontoRai extends StatelessWidget {
  const _ChipMontoRai({
    this.monto,
    this.icono,
    this.onTap,
    this.compact = false,
  });

  final double? monto;
  final IconData? icono;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bool esIcono = icono != null;
    final double h = compact ? 48 : 56;
    return Material(
      color: BolaPuebloTheme.accent.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(compact ? 12 : 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        child: Container(
          height: h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 12 : 14),
            border: Border.all(
              color: BolaPuebloTheme.accent.withValues(alpha: 0.45),
            ),
          ),
          child: esIcono
              ? Icon(icono, color: BolaPuebloTheme.accent, size: compact ? 20 : 22)
              : Text(
                  'RD\$${monto!.toStringAsFixed(0)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: BolaPuebloTheme.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 12 : 13,
                  ),
                ),
        ),
      ),
    );
  }
}
