import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/navegacion/post_viaje_taxista_nav.dart';
import 'package:flygo_nuevo/pantallas/chat/chat_screen.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/corporativo_hora_encargado.dart';
import 'package:flygo_nuevo/utils/hora_am_pm.dart';
import 'package:flygo_nuevo/widgets/corporativo_pasajeros_chofer_card.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

/// Ruta corporativa estilo «Elige tu destino»: tarjetas → Maps (sin PIN).
class CorporativoRutaDetalleInformativoPage extends StatefulWidget {
  const CorporativoRutaDetalleInformativoPage({
    super.key,
    required this.viajeId,
    required this.uidTaxista,
  });

  final String viajeId;
  final String uidTaxista;

  @override
  State<CorporativoRutaDetalleInformativoPage> createState() =>
      _CorporativoRutaDetalleInformativoPageState();
}

class _CorporativoRutaDetalleInformativoPageState
    extends State<CorporativoRutaDetalleInformativoPage> {
  bool _busy = false;
  bool _finalizando = false;
  String? _errorFinalizar;
  int _totalPasajerosActual = 0;
  Map<String, dynamic>? _viajeCache;
  /// Paradas donde el chofer ya eligió Waze/Maps en esta sesión (antes del ack del servidor).
  final Set<int> _paradasNavegadasEnSesion = <int>{};
  bool _recogidaNavegadaEnSesion = false;

  String get _uidOperativo =>
      (FirebaseAuth.instance.currentUser?.uid ?? widget.uidTaxista).trim();

  static const _fondo = Color(0xFF000000);
  static const _destinoAcentos = <Color>[
    Color(0xFFEAB308),
    Color(0xFF22C55E),
    Color(0xFF3B82F6),
    Color(0xFFA855F7),
    Color(0xFFF97316),
    Color(0xFF14B8A6),
    Color(0xFFEC4899),
    Color(0xFF06B6D4),
    Color(0xFF84CC16),
    Color(0xFFF43F5E),
  ];

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _alSalirDeRuta({Map<String, dynamic>? viajeData}) async {
    // Siempre: evita que auto-abrir reencierre la pantalla al volver atrás.
    CorporativoTaxistaService.marcarRutaCorpInformativaDismissed(
      widget.viajeId,
    );
    ActiveTripService.cancelarMantenimientoOverlayViaje();
    ActiveTripService.cancelarBloqueoShellTaxista();
    ActiveTripService.notificarRebuildShell();
    await ViajesRepo.limpiarViajeActivoSiNoOperativo(widget.uidTaxista);
    unawaited(
      CorporativoTaxistaService.refrescarOperacionChofer(widget.uidTaxista),
    );
  }

  Future<void> _confirmarTodasEntregasPendientes({
    required int totalPasajeros,
  }) async {
    if (_busy || _finalizando) return;
    final pendientes = CorporativoTaxistaService.paradasPendientesConfirmarCount(
      _viajeCache ?? <String, dynamic>{},
      totalPasajeros,
    );
    if (pendientes <= 0) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        title: const Text(
          '¿Confirmar todas las entregas?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Vas a marcar $pendientes destino(s) como entregados (✓). '
          'Después podés finalizar la ruta y ver tu factura.',
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.black87,
            ),
            child: const Text('Confirmar entregas'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await _run(() async {
      await CorporativoTaxistaService.marcarTodasParadasHechasInformativa(
        viajeId: widget.viajeId,
        totalPasajeros: totalPasajeros,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Entregas confirmadas ✓. Tocá «Finalizar ruta y ver factura».',
          ),
          backgroundColor: Color(0xFF22C55E),
          duration: Duration(seconds: 4),
        ),
      );
    });
  }

  Future<void> _salirViajeCerrado({bool verFactura = false}) async {
    await _alSalirDeRuta();
    if (!mounted) return;
    if (verFactura) {
      await PostViajeTaxistaNav.abrirFacturaYFlujo(
        context: context,
        viajeId: widget.viajeId,
        uidTaxista: _uidOperativo,
        viajeDataSemilla: _viajeCache != null
            ? Map<String, dynamic>.from(_viajeCache!)
            : null,
        evitarOverlayViajeEnCurso: true,
      );
    }
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  Future<void> _run(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _marcarHecha(int idx) async {
    try {
      await CorporativoTaxistaService.marcarParadaAbierta(
        viajeId: widget.viajeId,
        paradaIdx: idx,
        totalPasajeros: _totalPasajerosActual,
      );
      final completa = await CorporativoTaxistaService.marcarParadaHecha(
        viajeId: widget.viajeId,
        paradaIdx: idx,
        totalPasajeros: _totalPasajerosActual,
      );
      if (!mounted) return;
      _paradasNavegadasEnSesion.remove(idx);
      setState(() {});
      if (completa) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Todas las entregas ✓. Tocá «Finalizar ruta y ver factura».',
            ),
            backgroundColor: Color(0xFF22C55E),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mensajeErrorCorp(e, 'marcar entrega'))),
      );
    }
  }

  String _mensajeErrorCorp(Object e, String accion) {
    final raw = e.toString();
    if (raw.contains('permission-denied')) {
      return 'No se pudo $accion: permisos del servidor. '
          'Avisá al encargado o reintentá en unos segundos.';
    }
    if (raw.contains('failed-precondition')) {
      return 'No se pudo $accion: $raw';
    }
    return 'No se pudo $accion: $e';
  }

  Future<void> _finalizarRutaYFactura() async {
    if (_finalizando || !mounted) return;
    _finalizando = true;
    _errorFinalizar = null;
    setState(() => _busy = true);
    try {
      ActiveTripService.cancelarMantenimientoOverlayViaje();
      ActiveTripService.cancelarBloqueoShellTaxista();
      ActiveTripService.notificarRebuildShell();
      await CorporativoTaxistaService.finalizarRutaInformativaChofer(
        viajeId: widget.viajeId,
        uidTaxista: _uidOperativo,
        totalPasajeros: _totalPasajerosActual,
      );
      CorporativoTaxistaService.marcarRutaCorpInformativaDismissed(
        widget.viajeId,
      );
      if (!mounted) return;
      final ctx = context;
      await PostViajeTaxistaNav.abrirFacturaYFlujo(
        context: ctx,
        viajeId: widget.viajeId,
        uidTaxista: _uidOperativo,
        viajeDataSemilla: _viajeCache != null
            ? Map<String, dynamic>.from(_viajeCache!)
            : null,
        evitarOverlayViajeEnCurso: true,
      );
      if (!mounted) return;
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop();
      }
    } catch (e) {
      _errorFinalizar = _mensajeErrorCorp(e, 'finalizar la ruta');
      ActiveTripService.cancelarMantenimientoOverlayViaje();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorFinalizar!)),
      );
    } finally {
      _finalizando = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _marcarDestinoAbierto(int? paradaIdx) async {
    if (paradaIdx != null) {
      await CorporativoTaxistaService.marcarParadaAbierta(
        viajeId: widget.viajeId,
        paradaIdx: paradaIdx,
        totalPasajeros: _totalPasajerosActual,
      );
    } else {
      await CorporativoTaxistaService.marcarRecogidaEmpresaAbierta(
        widget.viajeId,
      );
    }
  }

  Future<void> _mostrarSelectorNavegacion({
    required String titulo,
    required String subtitulo,
    required Future<void> Function() abrirMaps,
    required Future<void> Function() abrirWaze,
    required int? paradaIdx,
  }) async {
    if (_busy) return;
    final elegido = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                if (subtitulo.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitulo,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'maps'),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Google Maps'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1E88E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'waze'),
                  icon: const Icon(Icons.navigation_rounded),
                  label: const Text('Waze'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF33CCFF),
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (elegido == null || !mounted) return;

    await _run(() async {
      if (paradaIdx != null) {
        _paradasNavegadasEnSesion.add(paradaIdx);
      } else {
        _recogidaNavegadaEnSesion = true;
      }
      await _marcarDestinoAbierto(paradaIdx);
      if (elegido == 'waze') {
        await abrirWaze();
      } else {
        await abrirMaps();
      }
    });
  }

  Future<void> _confirmarYFinalizarRuta({required bool rutaCompleta}) async {
    if (!rutaCompleta) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Marcá ✓ en cada destino después de abrir Waze o Maps '
            'antes de finalizar la ruta.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        title: const Text(
          '¿Finalizar la ruta?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Se cerrará la ruta y verás tu comprobante con el neto '
          'y el acumulado del período.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Seguir ruta'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.black87,
            ),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _finalizarRutaYFactura();
  }

  Future<void> _dejarRutaYContactarRai(Map<String, dynamic> d) async {
    if (_busy || _finalizando) return;
    final empresa =
        (d['corporativoEmpresaNombre'] ?? 'Empresa').toString().trim();
    final motivoCtrl = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        title: const Text(
          '¿Dejar esta ruta?',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vas a salir de la ruta de $empresa. '
              'RAI y el encargado serán notificados.\n\n'
              'Podés escribir el motivo (opcional):',
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              maxLines: 3,
              maxLength: 500,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Ej. avería, emergencia, conflicto de horario…',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                filled: true,
                fillColor: const Color(0xFF0D1117),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Seguir en la ruta'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Dejar ruta'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) {
      motivoCtrl.dispose();
      return;
    }
    final motivo = motivoCtrl.text.trim();
    motivoCtrl.dispose();

    setState(() => _busy = true);
    try {
      await CorporativoTaxistaService.abandonarRutaInformativaChofer(
        viajeId: widget.viajeId,
        motivo: motivo,
      );
      CorporativoTaxistaService.marcarRutaCorpInformativaDismissed(
        widget.viajeId,
      );
      await _alSalirDeRuta(viajeData: d);
      if (!mounted) return;
      final nav = Navigator.of(context);
      if (nav.canPop()) nav.pop();

      final mensajeWa = StringBuffer('Hola RAI Soporte, dejé mi ruta corporativa.')
        ..write('\nEmpresa: $empresa')
        ..write('\nViaje: ${widget.viajeId}');
      if (motivo.isNotEmpty) {
        mensajeWa.write('\nMotivo: $motivo');
      }

      if (!mounted) return;
      await _mostrarContactoRaiTrasDejar(
        mensajeWhatsApp: mensajeWa.toString(),
        viajeData: d,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mensajeErrorCorp(e, 'dejar la ruta'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mostrarContactoRaiTrasDejar({
    required String mensajeWhatsApp,
    required Map<String, dynamic> viajeData,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Ruta dejada',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Contactá a RAI o al encargado para coordinar la situación.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final ok =
                        await CorporativoTaxistaService.abrirWhatsAppSoporteRai(
                      mensaje: mensajeWhatsApp,
                    );
                    if (!mounted) return;
                    if (!ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No se pudo abrir WhatsApp.'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.support_agent_rounded),
                  label: const Text('WhatsApp Soporte RAI'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (!mounted) return;
                    _abrirChatEncargado(viajeData);
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('Chat con encargado'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _abrirChatEncargado(Map<String, dynamic> d) {
    final encargadoUid = CorporativoTaxistaService.uidEncargadoDesdeViaje(d);
    if (encargadoUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Encargado no disponible')),
      );
      return;
    }
    final nombre = CorporativoTaxistaService.nombreEncargadoDesdeViaje(d);
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: _fondo,
          appBar: RaiAppBar(title: nombre),
          body: FutureBuilder<void>(
            future: ViajesRepo.ensureChatDocForViaje(widget.viajeId),
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              return ChatScreen(
                otroUid: encargadoUid,
                otroNombre: nombre,
                viajeId: widget.viajeId,
              );
            },
          ),
        ),
      ),
    );
  }

  String _nombrePasajero(CorporativoPasajero p) {
    final n = p.nombre.trim();
    return n.isEmpty ? 'Pasajero' : n;
  }

  String _destinoPasajero(CorporativoPasajero p) {
    final dest = p.destinoLabel.trim();
    final sec = p.sector.trim();
    if (dest.isNotEmpty && sec.isNotEmpty && dest != sec) {
      return '$dest · $sec';
    }
    if (dest.isNotEmpty) return dest;
    if (sec.isNotEmpty) return sec;
    return 'Ver dirección en el mapa';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_alSalirDeRuta());
      },
      child: Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        backgroundColor: _fondo,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEAB308),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'R',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'RAI DRIVER',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                fontSize: 16,
              ),
            ),
          ],
        ),
        actions: [
          if (_viajeCache?['completado'] != true)
            TextButton(
              onPressed: _busy || _finalizando
                  ? null
                  : () {
                      final d = _viajeCache;
                      if (d != null) {
                        unawaited(_dejarRutaYContactarRai(d));
                      }
                    },
              child: Text(
                'Dejar ruta',
                style: TextStyle(
                  color: Colors.red.shade300,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Builder(
            builder: (ctx) {
              return IconButton(
                tooltip: 'Chat encargado',
                onPressed: () {
                  if (_viajeCache != null) {
                    _abrirChatEncargado(_viajeCache!);
                    return;
                  }
                  FirebaseFirestore.instance
                      .collection('viajes')
                      .doc(widget.viajeId)
                      .get()
                      .then((s) {
                    if (!ctx.mounted) return;
                    _abrirChatEncargado(s.data() ?? <String, dynamic>{});
                  });
                },
                icon: const Icon(Icons.chat_bubble_outline_rounded),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: CorporativoTaxistaService.streamOperacionChofer(
          _uidOperativo,
        ),
        builder: (context, opSnap) {
          final operacion = opSnap.data;
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('viajes')
                .doc(widget.viajeId)
                .snapshots(),
            builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(
              child: Text(
                'Ruta no encontrada',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }
          final d = Map<String, dynamic>.from(snap.data!.data() ?? {});
          d['id'] = widget.viajeId;
          _viajeCache = d;

          final empresaIdPl =
              (d['corporativoEmpresaId'] ?? '').toString().trim();
          final plantillaId =
              (d['corporativoPlantillaId'] ?? '').toString().trim();

          Widget buildConViaje(Map<String, dynamic> viaje) {
            return _buildCuerpoRutaInformativa(
              context: context,
              operacion: operacion,
              viaje: viaje,
            );
          }

          if (empresaIdPl.isEmpty || plantillaId.isEmpty) {
            return buildConViaje(viajeConHoraEncargado(d));
          }

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('empresas_corporativas')
                .doc(empresaIdPl)
                .collection('plantillas_ruta')
                .doc(plantillaId)
                .snapshots(),
            builder: (context, plSnap) {
              var viaje = viajeConHoraEncargado(d);
              if (plSnap.hasData && plSnap.data!.exists) {
                final pl = plSnap.data!.data() ?? {};
                viaje = viajeConHoraEncargado(
                  d,
                  horaEncargado: horaEncargadoCorporativo({
                    'horaRecogidaGrupo': pl['horaRecogidaGrupo'],
                    'horaRecogida': pl['horaRecogida'],
                  }),
                );
              }
              return buildConViaje(viaje);
            },
          );
            },
          );
        },
      ),
      ),
    );
  }

  Widget _buildCuerpoRutaInformativa({
    required BuildContext context,
    required Map<String, dynamic>? operacion,
    required Map<String, dynamic> viaje,
  }) {
          final d = viaje;

          if (!CorporativoTaxistaService.esViajeCorporativoAsignado(
            d,
            _uidOperativo,
          )) {
            final cacheOk = _viajeCache != null &&
                CorporativoTaxistaService.esViajeCorporativoAsignado(
                  _viajeCache!,
                  _uidOperativo,
                );
            if (!cacheOk) {
              return const Center(
                child: Text(
                  'Esta ruta no está asignada a tu cuenta',
                  style: TextStyle(color: Colors.white70),
                ),
              );
            }
          }

          final estadoViaje =
              (d['estado'] ?? '').toString().trim().toLowerCase();
          if (estadoViaje == 'cancelado_por_tiempo' ||
              estadoViaje == 'cancelado' ||
              estadoViaje == 'rechazado') {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.event_busy_rounded,
                      size: 48,
                      color: Colors.orange.shade300,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Este viaje ya no está activo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      estadoViaje == 'cancelado_por_tiempo'
                          ? 'La ventana de este viaje expiró o fue reemplazado. '
                              'Volvé a Mis rutas corporativas y esperá el envío '
                              'del día o pedile al encargado que publique de nuevo.'
                          : 'La ruta fue cancelada. Revisá Mis rutas corporativas '
                              'por si hay un viaje nuevo del día.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.maybePop(context),
                      child: const Text('Volver a Mis rutas'),
                    ),
                  ],
                ),
              ),
            );
          }

          final empresa =
              (d['corporativoEmpresaNombre'] ?? 'Empresa').toString();
          final origen = (d['origen'] ?? '').toString();
          final pasajeros =
              CorporativoPasajerosChoferCard.pasajerosDesdeMapViaje(d);
          if (_totalPasajerosActual != pasajeros.length) {
            _totalPasajerosActual = pasajeros.length;
          }
          final hechas = CorporativoTaxistaService.paradasHechasIndices(
            d,
            pasajeros.length,
          );
          final abiertas = CorporativoTaxistaService.paradasAbiertasIndices(
            d,
            pasajeros.length,
          );
          for (final i in _paradasNavegadasEnSesion) {
            if (i >= 0 && i < pasajeros.length) abiertas.add(i);
          }
          final recogidaAbierta =
              CorporativoTaxistaService.recogidaEmpresaAbierta(d) ||
                  _recogidaNavegadaEnSesion;
          final rutaCompleta =
              CorporativoTaxistaService.rutaInformativaCompleta(
            d,
            pasajeros.length,
          );
          final recogida =
              CorporativoTaxistaService.recogidaOperativaCorporativo(d);
          final horaTxt = recogida.millisecondsSinceEpoch > 0
              ? fmtHoraDeDateTimeAmPm(recogida)
              : (d['corporativoHoraRecogidaGrupo'] ?? '').toString();

          final viajeYaCerrado = d['completado'] == true;
          final completadoEnOperacion =
              CorporativoTaxistaService.viajeCompletadoEnOperacion(
            operacion,
            widget.viajeId,
          );
          if (viajeYaCerrado || completadoEnOperacion) {
            return _PantallaViajeYaCerrado(
              viajeYaFacturado: viajeYaCerrado,
              empresa: empresa,
              busy: _busy || _finalizando,
              onVerFactura: () => _salirViajeCerrado(verFactura: true),
              onVolver: () => _salirViajeCerrado(),
            );
          }

          final pagoResumen = CorporativoTaxistaService.resumenPagoChofer(
            viaje: d,
            uidTaxista: _uidOperativo,
            operacionChofer: operacion,
          );
          final mostrarFinalizar = rutaCompleta && !viajeYaCerrado;
          final pendientesConfirmar =
              CorporativoTaxistaService.paradasPendientesConfirmarCount(
            d,
            pasajeros.length,
          );
          final todasAbiertasSinConfirmar =
              CorporativoTaxistaService.todasParadasAbiertasPendientesConfirmar(
            d,
            pasajeros.length,
          );
          final mostrarConfirmarTodas =
              todasAbiertasSinConfirmar && !rutaCompleta;

          final pendientes = <MapEntry<int, CorporativoPasajero>>[];
          for (final e in pasajeros.asMap().entries) {
            if (!hechas.contains(e.key)) pendientes.add(e);
          }

          final bottomPad = MediaQuery.viewPaddingOf(context).bottom +
              ((mostrarFinalizar || mostrarConfirmarTodas) ? 96 : 32);

          return Stack(
            children: [
              ListView.builder(
                padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPad),
                itemCount: _itemCount(
                  pendientes: pendientes.length,
                  tieneEmpresa: origen.isNotEmpty && !rutaCompleta,
                  rutaCompleta: rutaCompleta,
                  sinPasajeros: pasajeros.isEmpty && !rutaCompleta,
                  tienePago: pagoResumen != null,
                  viajeYaCerrado: viajeYaCerrado,
                  mostrarBannerConfirmar: mostrarConfirmarTodas,
                ),
                itemBuilder: (context, index) {
                  return _buildListItem(
                    index: index,
                    empresa: empresa,
                    origen: origen,
                    horaTxt: horaTxt,
                    pasajeros: pasajeros,
                    pendientes: pendientes,
                    hechas: hechas,
                    abiertas: abiertas,
                    recogidaAbierta: recogidaAbierta,
                    rutaCompleta: rutaCompleta,
                    pagoResumen: pagoResumen,
                    d: d,
                    viajeData: d,
                    viajeYaCerrado: viajeYaCerrado,
                    pendientesConfirmar: pendientesConfirmar,
                    mostrarBannerConfirmar: mostrarConfirmarTodas,
                    onConfirmarTodas: mostrarConfirmarTodas
                        ? () => _confirmarTodasEntregasPendientes(
                              totalPasajeros: pasajeros.length,
                            )
                        : null,
                  );
                },
              ),
              if (mostrarConfirmarTodas)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.viewPaddingOf(context).bottom + 12,
                  child: _BarraConfirmarEntregas(
                    pendientes: pendientesConfirmar,
                    busy: _busy || _finalizando,
                    onConfirmar: () => _confirmarTodasEntregasPendientes(
                      totalPasajeros: pasajeros.length,
                    ),
                  ),
                ),
              if (mostrarFinalizar)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.viewPaddingOf(context).bottom + 12,
                  child: _BarraFinalizarRuta(
                    rutaCompleta: rutaCompleta,
                    busy: _busy || _finalizando,
                    onFinalizar: () => _confirmarYFinalizarRuta(
                      rutaCompleta: rutaCompleta,
                    ),
                  ),
                ),
              if (_busy)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x66000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          );
  }

  int _itemCount({
    required int pendientes,
    required bool tieneEmpresa,
    required bool rutaCompleta,
    required bool sinPasajeros,
    required bool tienePago,
    required bool viajeYaCerrado,
    bool mostrarBannerConfirmar = false,
  }) {
    var n = 0;
    n += 1; // encabezado
    if (mostrarBannerConfirmar) n += 1;
    if (tienePago) n += 1;
    if (tieneEmpresa) n += 1;
    if (rutaCompleta) n += 1;
    else if (sinPasajeros) n += 1;
    else n += pendientes;
    if (!viajeYaCerrado) n += 1; // dejar ruta
    n += 2; // chat + volver
    return n;
  }

  Widget _buildListItem({
    required int index,
    required String empresa,
    required String origen,
    required String horaTxt,
    required List<CorporativoPasajero> pasajeros,
    required List<MapEntry<int, CorporativoPasajero>> pendientes,
    required Set<int> hechas,
    required Set<int> abiertas,
    required bool recogidaAbierta,
    required bool rutaCompleta,
    required CorporativoChoferPagoResumen? pagoResumen,
    required Map<String, dynamic> d,
    required Map<String, dynamic> viajeData,
    required bool viajeYaCerrado,
    int pendientesConfirmar = 0,
    bool mostrarBannerConfirmar = false,
    VoidCallback? onConfirmarTodas,
  }) {
    var i = index;

    if (i == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (horaTxt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '$empresa · Recogida $horaTxt',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const Text(
            'Elige tu destino',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            rutaCompleta
                ? 'Ruta del día completada'
                : mostrarBannerConfirmar
                    ? 'Falta confirmar las entregas (✓)'
                    : 'Seleccioná tu destino rápido',
            style: TextStyle(
              color: mostrarBannerConfirmar
                  ? const Color(0xFFEAB308)
                  : Colors.white54,
              fontSize: 14,
              fontWeight:
                  mostrarBannerConfirmar ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
          if (pasajeros.isNotEmpty && !rutaCompleta) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: hechas.length / pasajeros.length,
                minHeight: 6,
                backgroundColor: Colors.white12,
                color: const Color(0xFFEAB308),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${hechas.length} de ${pasajeros.length} entregas confirmadas (✓)',
              style: const TextStyle(
                color: Color(0xFFEAB308),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (hechas.length < pasajeros.length)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Tocá un pasajero → Waze o Maps. Marcá ✓ al entregar. '
                  'Al completar todas, aparece «Finalizar ruta».',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
          ],
          const SizedBox(height: 18),
        ],
      );
    }
    i -= 1;

    if (mostrarBannerConfirmar) {
      if (i == 0) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF422006),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFEAB308).withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFFEAB308), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ya abriste todos los destinos',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Tocá ✓ en cada tarjeta o usá el botón de abajo para '
                  'confirmar $pendientesConfirmar entrega(s) y poder finalizar.',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                if (onConfirmarTodas != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy || _finalizando ? null : onConfirmarTodas,
                      icon: const Icon(Icons.done_all_rounded),
                      label: const Text('Confirmar todas las entregas'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEAB308),
                        foregroundColor: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }
      i -= 1;
    }

    if (pagoResumen != null) {
      if (i == 0) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _TarjetaPagoCorporativo(
            resumen: pagoResumen,
            destacado: rutaCompleta,
          ),
        );
      }
      i -= 1;
    }

    if (origen.isNotEmpty && !rutaCompleta) {
      if (i == 0) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _TarjetaDestino(
            nombre: empresa,
            destino: origen,
            accion: recogidaAbierta
                ? 'Recogida en curso'
                : 'Waze o Maps · Recogida',
            acento: const Color(0xFF0F766E),
            icono: Icons.store_mall_directory_rounded,
            yaAbierta: recogidaAbierta,
            onTap: _busy
                ? null
                : () => _mostrarSelectorNavegacion(
                      titulo: 'Recogida en empresa',
                      subtitulo: origen,
                      paradaIdx: null,
                      abrirMaps: () =>
                          CorporativoTaxistaService.abrirMapsEmpresa(viajeData),
                      abrirWaze: () =>
                          CorporativoTaxistaService.abrirWazeDesdeViaje(
                        viajeData,
                      ),
                    ),
          ),
        );
      }
      i -= 1;
    }

    if (rutaCompleta) {
      if (i == 0) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              const Icon(
                Icons.verified_rounded,
                color: Color(0xFF22C55E),
                size: 56,
              ),
              const SizedBox(height: 12),
              const Text(
                '¡Ruta completada!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (pagoResumen != null) ...[
                const SizedBox(height: 16),
                Text(
                  FormatosMoneda.rd(pagoResumen.totalTrasEsteViajeRd),
                  style: const TextStyle(
                    color: Color(0xFF22C55E),
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Acumulado en ${pagoResumen.etiquetaCiclo.toLowerCase()}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                if (pagoResumen.etiquetaFechaPago != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    pagoResumen.etiquetaFechaPago!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFEAB308),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 10),
              Text(
                _errorFinalizar != null
                    ? _errorFinalizar!
                    : (_finalizando || _busy
                        ? 'Generando comprobante y factura…'
                        : 'Abrimos tu comprobante de viaje.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _errorFinalizar != null
                      ? Colors.orange.shade200
                      : Colors.white54,
                ),
              ),
              if (_errorFinalizar != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _finalizarRutaYFactura,
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Reintentar factura'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.black87,
                  ),
                ),
              ] else if (!_finalizando && !_busy) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _confirmarYFinalizarRuta(
                    rutaCompleta: true,
                  ),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Finalizar ruta y ver factura'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }
      i -= 1;
    } else if (pasajeros.isEmpty) {
      if (i == 0) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'El encargado aún no cargó pasajeros en esta ruta.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
        );
      }
      i -= 1;
    } else {
      if (i < pendientes.length) {
        final e = pendientes[i];
        final pas = e.value;
        final idx = e.key;
        final acento = _destinoAcentos[idx % _destinoAcentos.length];
        final yaAbierta = abiertas.contains(idx);
        final pendienteConfirmar = yaAbierta && !hechas.contains(idx);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _TarjetaDestino(
            nombre: _nombrePasajero(pas),
            destino: _destinoPasajero(pas),
            accion: pendienteConfirmar
                ? 'Tocá ✓ para confirmar entrega'
                : yaAbierta
                    ? 'Entrega confirmada'
                    : 'Waze o Maps',
            acento: acento,
            icono: _iconoDestino(idx),
            yaAbierta: yaAbierta,
            destacarConfirmacion: pendienteConfirmar,
            onTap: _busy
                ? null
                : () => _mostrarSelectorNavegacion(
                      titulo: _nombrePasajero(pas),
                      subtitulo: _destinoPasajero(pas),
                      paradaIdx: idx,
                      abrirMaps: () =>
                          CorporativoTaxistaService.abrirNavegacionParada(pas),
                      abrirWaze: () =>
                          CorporativoTaxistaService.abrirWazeParada(pas),
                    ),
            onMarcarHecha: yaAbierta
                ? () => _run(() => _marcarHecha(idx))
                : null,
          ),
        );
      }
      i -= pendientes.length;
    }

    if (!viajeYaCerrado) {
      if (i == 0) {
        return SafeArea(
          minimum: const EdgeInsets.only(top: 8, bottom: 4),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy || _finalizando
                  ? null
                  : () => _dejarRutaYContactarRai(d),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade300,
                side: BorderSide(color: Colors.red.shade400.withValues(alpha: 0.55)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text(
                'Dejar ruta y contactar RAI',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        );
      }
      i -= 1;
    }

    if (i == 0) {
      return SafeArea(
        minimum: const EdgeInsets.only(top: 8, bottom: 4),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy || _finalizando
                ? null
                : () => _abrirChatEncargado(d),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text(
              'Chat con encargado',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _finalizando
              ? null
              : () async {
                  await _alSalirDeRuta();
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                },
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white38),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text(
            'Volver a Mis rutas',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  IconData _iconoDestino(int i) {
    const icons = [
      Icons.terrain_rounded,
      Icons.beach_access_rounded,
      Icons.apartment_rounded,
      Icons.account_balance_rounded,
      Icons.home_work_rounded,
      Icons.location_city_rounded,
      Icons.house_rounded,
      Icons.map_rounded,
    ];
    return icons[i % icons.length];
  }
}

class _PantallaViajeYaCerrado extends StatelessWidget {
  const _PantallaViajeYaCerrado({
    required this.viajeYaFacturado,
    required this.empresa,
    required this.busy,
    required this.onVerFactura,
    required this.onVolver,
  });

  final bool viajeYaFacturado;
  final String empresa;
  final bool busy;
  final VoidCallback onVerFactura;
  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 56,
              color: Colors.green.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'Este viaje ya finalizó',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              viajeYaFacturado
                  ? 'La ruta de $empresa está cerrada. '
                      'Podés ver tu comprobante o volver a Mis rutas.'
                  : 'La ruta de $empresa ya está cerrada en el sistema. '
                      'Volvé a Mis rutas o al pool Recibir.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            if (viajeYaFacturado)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : onVerFactura,
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Ver comprobante'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            if (viajeYaFacturado) const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onVolver,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Volver a Mis rutas'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarraConfirmarEntregas extends StatelessWidget {
  const _BarraConfirmarEntregas({
    required this.pendientes,
    required this.busy,
    required this.onConfirmar,
  });

  final int pendientes;
  final bool busy;
  final VoidCallback onConfirmar;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: const Color(0xFF422006),
      child: InkWell(
        onTap: busy ? null : onConfirmar,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFEAB308).withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.done_all_rounded,
                color: Color(0xFFEAB308),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$pendientes entrega(s) sin confirmar',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const Text(
                      'Tocá para marcar todas ✓ y finalizar',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFEAB308),
                  ),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFEAB308),
                  size: 28,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarraFinalizarRuta extends StatelessWidget {
  const _BarraFinalizarRuta({
    required this.rutaCompleta,
    required this.busy,
    required this.onFinalizar,
  });

  final bool rutaCompleta;
  final bool busy;
  final VoidCallback onFinalizar;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: const Color(0xFF14532D),
      child: InkWell(
        onTap: busy ? null : onFinalizar,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF22C55E).withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.receipt_long_rounded,
                color: const Color(0xFF86EFAC),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Todas las entregas ✓',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      'Tocá para factura y comprobante',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF86EFAC),
                  ),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF86EFAC),
                  size: 28,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TarjetaDestino extends StatelessWidget {
  const _TarjetaDestino({
    required this.nombre,
    required this.destino,
    required this.accion,
    required this.acento,
    required this.icono,
    this.yaAbierta = false,
    this.destacarConfirmacion = false,
    this.onTap,
    this.onMarcarHecha,
  });

  final String nombre;
  final String destino;
  final String accion;
  final Color acento;
  final IconData icono;
  final bool yaAbierta;
  final bool destacarConfirmacion;
  final VoidCallback? onTap;
  final VoidCallback? onMarcarHecha;

  @override
  Widget build(BuildContext context) {
    final esperandoConfirmacion = destacarConfirmacion;
    final colorBorde = esperandoConfirmacion
        ? const Color(0xFFEAB308).withValues(alpha: 0.65)
        : yaAbierta
            ? Colors.white24
            : acento.withValues(alpha: 0.45);
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
        ? const Color(0xFFEAB308).withValues(alpha: 0.2)
        : yaAbierta
            ? Colors.white.withValues(alpha: 0.06)
            : acento.withValues(alpha: 0.2);

    return Opacity(
      opacity: yaAbierta && !esperandoConfirmacion ? 0.72 : 1,
      child: Material(
        color: esperandoConfirmacion
            ? const Color(0xFF1A1508)
            : yaAbierta
                ? const Color(0xFF0D1117)
                : const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              if (yaAbierta && !esperandoConfirmacion)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _RayitaPainter(),
                    ),
                  ),
                ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorBorde, width: 1.2),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: colorFondoIcono,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        esperandoConfirmacion
                            ? Icons.radio_button_unchecked_rounded
                            : yaAbierta
                                ? Icons.check_rounded
                                : icono,
                        color: colorIcono,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nombre,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorNombre,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              letterSpacing: -0.2,
                              decoration: yaAbierta && !esperandoConfirmacion
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: Colors.white54,
                              decorationThickness: 2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            destino,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorDestino,
                              fontSize: 13,
                              height: 1.3,
                              decoration: yaAbierta && !esperandoConfirmacion
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: Colors.white38,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            accion,
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
                    if (onMarcarHecha != null)
                      IconButton(
                        tooltip: 'Marcar entregado',
                        onPressed: onMarcarHecha,
                        icon: Icon(
                          Icons.check_circle_outline,
                          color: esperandoConfirmacion
                              ? const Color(0xFFEAB308)
                              : yaAbierta
                                  ? Colors.white38
                                  : acento,
                          size: esperandoConfirmacion ? 30 : 24,
                        ),
                      ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: yaAbierta ? Colors.white24 : acento,
                      size: 32,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TarjetaPagoCorporativo extends StatelessWidget {
  const _TarjetaPagoCorporativo({
    required this.resumen,
    this.destacado = false,
  });

  final CorporativoChoferPagoResumen resumen;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final acumuladoLabel = resumen.viajeYaContabilizado
        ? 'Acumulado del período'
        : 'Acumulado del período (incl. este viaje)';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: destacado
            ? const Color(0xFF14532D)
            : const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: destacado
              ? const Color(0xFF22C55E).withValues(alpha: 0.55)
              : const Color(0xFFEAB308).withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: destacado
                    ? const Color(0xFF86EFAC)
                    : const Color(0xFFEAB308),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tu liquidación · ${resumen.empresaNombre}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Neto de este viaje',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      FormatosMoneda.rd(resumen.netoEsteViajeRd),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      acumuladoLabel,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      FormatosMoneda.rd(
                        resumen.viajeYaContabilizado
                            ? resumen.acumuladoPeriodoRd
                            : resumen.totalTrasEsteViajeRd,
                      ),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Color(0xFF22C55E),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${resumen.etiquetaCiclo} · '
            '${resumen.viajesCompletadosPeriodo} viaje(s) cerrado(s) en el período',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (resumen.etiquetaFechaPago != null) ...[
            const SizedBox(height: 6),
            Text(
              resumen.etiquetaFechaPago!,
              style: const TextStyle(
                color: Color(0xFFEAB308),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'RAI cobra a la empresa y te transfiere al cerrar el período. '
            'No cobrás al pasajero en la calle.',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rayita diagonal sobre la tarjeta (ruta ya abierta en Maps).
class _RayitaPainter extends CustomPainter {
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
