import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/data/viaje_data.dart';
import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_ui.dart';
import 'package:flygo_nuevo/servicios/corporativo_pago_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_ruta_service.dart';
import 'package:flygo_nuevo/utils/corporativo_historial_labels.dart';
import 'package:flygo_nuevo/widgets/corporativo_chofer_perfil_card.dart';

/// Tipos de incidencia que el encargado puede reportar (RAI valida).
abstract final class CorporativoIncidenciaTipo {
  CorporativoIncidenciaTipo._();

  static const feriado = 'feriado_no_laborable';
  static const imprevisto = 'imprevisto_operativo';
  static const fraudeChofer = 'fraude_chofer_sin_ruta';

  static const List<(String id, String label, String hint)> opciones = [
    (
      feriado,
      'Feriado / no laborable',
      'Ese día la empresa no operó (feriado, cierre, etc.).',
    ),
    (
      imprevisto,
      'Imprevisto operativo',
      'Algo impidió la ruta (clima, emergencia, cancelación de última hora).',
    ),
    (
      fraudeChofer,
      'Chofer marcó sin hacer la ruta',
      'Se usó el código pero el servicio no se realizó.',
    ),
  ];

  static String etiqueta(String id) {
    for (final o in opciones) {
      if (o.$1 == id) return o.$2;
    }
    return id;
  }
}

class CorporativoHistorialPage extends StatefulWidget {
  const CorporativoHistorialPage({super.key, required this.empresaId});

  final String empresaId;

  @override
  State<CorporativoHistorialPage> createState() =>
      _CorporativoHistorialPageState();
}

class _CorporativoHistorialPageState extends State<CorporativoHistorialPage> {
  bool _mostrarArchivados = false;
  final Set<String> _quitandoViajeIds = {};

  bool _puedeQuitarDelHistorial({
    required String viajeId,
    required String estadoLc,
    required bool incidenciaPendiente,
  }) {
    if (viajeId.isEmpty || incidenciaPendiente) return false;
    return estadoLc != 'en_curso' &&
        estadoLc != 'a_bordo' &&
        estadoLc != 'abordo' &&
        estadoLc != 'encurso';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    final fmt = DateFormat('EEE d MMM · HH:mm', 'es');

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _mostrarArchivados
          ? CorporativoRutaService.streamHistorialArchivado(widget.empresaId)
          : CorporativoRutaService.streamHistorial(widget.empresaId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: p.primary));
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_rounded, size: 44, color: p.muted),
                  const SizedBox(height: 12),
                  Text(
                    _mostrarArchivados
                        ? 'Sin rutas en períodos cerrados'
                        : 'Sin viajes corporativos aún',
                    style: TextStyle(
                      color: p.onCard,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _mostrarArchivados
                        ? 'Cuando RAI valide un pago, las rutas cobradas se archivan aquí.'
                        : 'Cuando se complete una ruta, aparece aquí con su cobro. '
                            'Al pagar el período, las rutas cerradas se archivan solas.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, height: 1.35),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: items.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            if (i == 0) {
              return corporativoCard(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _mostrarArchivados
                          ? 'Períodos ya pagados a RAI. Conservado para auditoría; '
                              'no llena la vista del día a día.'
                          : 'Rutas activas y pendientes de cobro. '
                              'Al pagar el período con RAI, las rutas completadas '
                              'se archivan automáticamente.',
                      style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
                    ),
                    const SizedBox(height: 10),
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: CorporativoRutaService.streamHistorialArchivado(
                        widget.empresaId,
                      ),
                      builder: (context, archSnap) {
                        final nArch = archSnap.data?.length ?? 0;
                        if (nArch <= 0 && !_mostrarArchivados) {
                          return const SizedBox.shrink();
                        }
                        return TextButton.icon(
                          onPressed: () => setState(
                            () => _mostrarArchivados = !_mostrarArchivados,
                          ),
                          icon: Icon(
                            _mostrarArchivados
                                ? Icons.visibility_off_outlined
                                : Icons.inventory_2_outlined,
                            size: 18,
                          ),
                          label: Text(
                            _mostrarArchivados
                                ? 'Ver solo rutas activas'
                                : 'Ver archivadas ($nArch)',
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            }
            final m = items[i - 1];
            final nombre = (m['plantillaNombre'] ?? 'Ruta').toString();
            final ref = (m['referencia'] ?? '').toString();
            final origen = (m['origenLabel'] ?? '').toString();
            final precio = (m['precio'] as num?)?.toDouble() ??
                (m['monto'] as num?)?.toDouble() ??
                0;
            final rawPas = m['pasajeros'];
            final nPas = rawPas is List ? rawPas.length : 0;
            DateTime? fecha;
            final fr = m['fechaRecogida'];
            if (fr is Timestamp) fecha = fr.toDate();
            final viajeId = (m['viajeId'] ?? m['_id'] ?? '').toString();

            final estado = (m['estado'] ?? '').toString();
            final estadoLc = estado.toLowerCase();
            final chofer = (m['choferNombre'] ?? m['choferAsignadoNombre'] ?? '')
                .toString()
                .trim();
            final perfilChofer = CorporativoChoferPerfil.fromMap(
              m['choferAsignadoPerfil'],
            );
            final puedeReportar =
                estadoLc == 'completado' && viajeId.isNotEmpty;
            final incidenciaPendiente = estadoLc == 'anulacion_pendiente';
            final puedeQuitar = _puedeQuitarDelHistorial(
              viajeId: viajeId,
              estadoLc: estadoLc,
              incidenciaPendiente: incidenciaPendiente,
            );
            final quitando = _quitandoViajeIds.contains(viajeId);
            final tipoIncidencia =
                (m['motivoAnulacion'] ?? m['tipoIncidencia'] ?? '')
                    .toString()
                    .trim();

            return corporativoCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: corporativoEllipsis(
                          nombre,
                          maxLines: 2,
                          style: TextStyle(
                            color: p.onCard,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (estado.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: CorporativoHistorialLabels.colorEstado(
                                estado,
                                success: p.success,
                                accent: p.accent,
                                warning: Colors.orange,
                                error: Colors.red.shade700,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: corporativoEllipsis(
                              CorporativoHistorialLabels.etiqueta(estado),
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: CorporativoHistorialLabels.colorEstado(
                                  estado,
                                  success: p.success,
                                  accent: p.accent,
                                  warning: Colors.orange,
                                  error: Colors.red.shade700,
                                ),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (ref.isNotEmpty)
                    Text('Ref: $ref', style: TextStyle(color: p.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  Text(
                    origen,
                    style: TextStyle(color: p.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    estadoLc == 'no_ejecutado'
                        ? 'No cobrado · RD\$ 0'
                        : '$nPas pasajero(s) · RD\$ ${precio.toStringAsFixed(0)}',
                    style: TextStyle(color: p.onCard, fontSize: 13),
                  ),
                  if (perfilChofer != null) ...[
                    const SizedBox(height: 10),
                    CorporativoChoferPerfilCard(
                      perfil: perfilChofer,
                      compacto: true,
                      mostrarTitulo: false,
                    ),
                  ] else if (chofer.isNotEmpty)
                    Text(
                      'Chofer: $chofer',
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                  if (fecha != null)
                    Text(
                      fmt.format(fecha),
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                  if (incidenciaPendiente) ...[
                    const SizedBox(height: 8),
                    Text(
                      tipoIncidencia.isNotEmpty
                          ? 'Incidencia: ${CorporativoHistorialLabels.etiquetaIncidencia(tipoIncidencia)} · espera validación RAI'
                          : 'Incidencia enviada · espera validación RAI. El cobro sigue hasta que aprueben.',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (puedeReportar) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _calificarChofer(
                          context,
                          viajeId: viajeId,
                          nombreRuta: nombre,
                          choferNombre: chofer,
                        ),
                        icon: const Icon(Icons.star_outline_rounded, size: 18),
                        label: const Text('Calificar chofer'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _reportarIncidencia(
                          context,
                          empresaId: widget.empresaId,
                          viajeId: viajeId,
                          nombreRuta: nombre,
                        ),
                        icon: const Icon(Icons.report_problem_outlined, size: 18),
                        label: const Text('Reportar incidencia'),
                      ),
                    ),
                  ],
                  if (puedeQuitar) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: quitando
                            ? null
                            : () => _quitarDelHistorial(
                                  context,
                                  viajeId: viajeId,
                                  nombreRuta: nombre,
                                  estado: estado,
                                ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade800,
                          side: BorderSide(color: Colors.red.shade200),
                        ),
                        icon: quitando
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.red.shade800,
                                ),
                              )
                            : const Icon(Icons.delete_outline_rounded, size: 18),
                        label: Text(
                          quitando ? 'Quitando…' : 'Quitar del historial',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _calificarChofer(
    BuildContext context, {
    required String viajeId,
    required String nombreRuta,
    required String choferNombre,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Iniciá sesión para calificar.')),
      );
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .get();
      if (!snap.exists) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No encontramos el viaje.')),
        );
        return;
      }
      final d = snap.data() ?? <String, dynamic>{};
      if (d['calificado'] == true) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Esta ruta ya fue calificada.')),
        );
        return;
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo verificar el viaje: $e')),
      );
      return;
    }

    if (!context.mounted) return;
    final p = context.corporativoPalette;
    var estrellas = 5.0;
    final comentarioCtrl = TextEditingController();
    var enviando = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: p.card,
          title: Text(
            'Calificar chofer',
            style: TextStyle(color: p.onCard, fontWeight: FontWeight.w800),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '«$nombreRuta»'
                  '${choferNombre.isNotEmpty ? '\n$choferNombre' : ''}',
                  style: TextStyle(color: p.muted, height: 1.35),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final filled = estrellas >= i + 1;
                    return IconButton(
                      onPressed: enviando
                          ? null
                          : () => setLocal(() => estrellas = (i + 1).toDouble()),
                      icon: Icon(
                        filled ? Icons.star_rounded : Icons.star_border_rounded,
                        color: Colors.amber,
                        size: 32,
                      ),
                    );
                  }),
                ),
                TextField(
                  controller: comentarioCtrl,
                  enabled: !enviando,
                  maxLines: 2,
                  maxLength: 280,
                  decoration: const InputDecoration(
                    labelText: 'Comentario (opcional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: enviando ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: enviando
                  ? null
                  : () async {
                      setLocal(() => enviando = true);
                      try {
                        final res = await ViajeData.calificarViajeSeguro(
                          viajeId: viajeId,
                          uidCliente: uid,
                          calificacion: estrellas.clamp(1, 5),
                          comentario: comentarioCtrl.text.trim().isEmpty
                              ? null
                              : comentarioCtrl.text.trim(),
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx, true);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              res.alreadyRated
                                  ? 'Esta ruta ya estaba calificada.'
                                  : '¡Calificación enviada! Gracias.',
                            ),
                            backgroundColor: Colors.green.shade800,
                          ),
                        );
                      } catch (e) {
                        setLocal(() => enviando = false);
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('No se pudo enviar: $e'),
                            backgroundColor: Colors.red.shade800,
                          ),
                        );
                      }
                    },
              child: Text(enviando ? 'Enviando…' : 'Enviar'),
            ),
          ],
        ),
      ),
    );
    comentarioCtrl.dispose();
    if (ok != true) return;
  }

  Future<void> _reportarIncidencia(
    BuildContext context, {
    required String empresaId,
    required String viajeId,
    required String nombreRuta,
  }) async {
    final p = context.corporativoPalette;
    var tipo = CorporativoIncidenciaTipo.feriado;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: p.card,
          title: Text(
            'Reportar incidencia',
            style: TextStyle(color: p.onCard, fontWeight: FontWeight.w800),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '«$nombreRuta»\n\n'
                  'Elegí el tipo. RAI valida si es cierto antes de quitar el cobro.',
                  style: TextStyle(color: p.muted, height: 1.4),
                ),
                const SizedBox(height: 12),
                ...CorporativoIncidenciaTipo.opciones.map((o) {
                  final selected = tipo == o.$1;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => setLocal(() => tipo = o.$1),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected ? p.primary : p.cardBorder,
                            width: selected ? 1.5 : 1,
                          ),
                          color: selected
                              ? p.primary.withValues(alpha: 0.08)
                              : Colors.transparent,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              size: 20,
                              color: selected ? p.primary : p.muted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    o.$2,
                                    style: TextStyle(
                                      color: p.onCard,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    o.$3,
                                    style: TextStyle(
                                      color: p.muted,
                                      fontSize: 11,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enviar a RAI'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      final res = await CorporativoPagoService.anularViaje(
        empresaId: empresaId,
        viajeId: viajeId,
        motivo: tipo,
      );
      if (!context.mounted) return;
      final pendiente = res['pendiente'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pendiente
                ? 'Incidencia enviada. RAI validará antes de quitar el cobro.'
                : 'Incidencia resuelta · cobro quitado.',
          ),
          backgroundColor: Colors.green.shade800,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo reportar: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  Future<void> _quitarDelHistorial(
    BuildContext context, {
    required String viajeId,
    required String nombreRuta,
    required String estado,
  }) async {
    final ok = await confirmarQuitarViajeHistorialCorporativo(
      context,
      nombreRuta: nombreRuta,
      estado: estado,
    );
    if (!ok || !context.mounted) return;

    setState(() => _quitandoViajeIds.add(viajeId));
    try {
      final res = await CorporativoPagoService.ocultarViajeHistorial(
        empresaId: widget.empresaId,
        viajeId: viajeId,
      );
      if (!context.mounted) return;
      final cancelado = res['viajeCancelado'] == true;
      final advertenciaCobro = res['advertenciaCobro'] == true;
      var msg = 'Viaje quitado de tu historial.';
      if (cancelado) {
        msg = 'Envío cancelado y quitado del historial.';
      } else if (advertenciaCobro) {
        msg =
            'Quitado de tu lista. El cobro sigue en tu liquidación '
            '(usá incidencia si no corresponde).';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.green.shade800,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _quitandoViajeIds.remove(viajeId));
      }
    }
  }
}
