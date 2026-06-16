import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/lugares_service.dart';
import 'package:flygo_nuevo/servicios/rai_asistente_kb.dart';
import 'package:flygo_nuevo/servicios/rai_asistente_service.dart';
import 'package:flygo_nuevo/servicios/rai_perfil_cliente_estado.dart';
import 'package:flygo_nuevo/utils/rai_aplicar_destino_desde_voz.dart';
import 'package:flygo_nuevo/utils/rai_destino_desde_voz.dart';
import 'package:flygo_nuevo/widgets/rai_asistente_launcher.dart';
import 'package:flygo_nuevo/widgets/rai_direccion_inteligente_sheet.dart';
import 'package:flygo_nuevo/servicios/rai_speech_busqueda_direccion.dart';

/// Chat del asistente RAI: guía, direcciones y soporte (capa aditiva).
class RaiAsistenteSheet extends StatefulWidget {
  const RaiAsistenteSheet({super.key});

  @override
  State<RaiAsistenteSheet> createState() => _RaiAsistenteSheetState();
}

class _RaiAsistenteSheetState extends State<RaiAsistenteSheet> {
  final _inputCtrl = TextEditingController();
  final _voz = RaiSpeechBusquedaDireccion.shared;

  ScrollController? _listaScroll;

  final List<RaiAsistenteMensaje> _mensajes = [];
  List<DetalleLugar> _direcciones = [];
  bool _enviando = false;
  bool _escuchando = false;
  bool _vozDisponible = false;
  RaiPerfilClienteEstado? _perfil;

  static const _chipsRapidos = [
    '¿Cómo funciona RAI?',
    '¿Me falta algo del registro?',
    'Buscar dirección difícil',
    'Pedir motor',
    'Viaje programado',
    'Sin internet',
    'Hablar con soporte',
  ];

  @override
  void initState() {
    super.initState();
    _mensajes.add(
      const RaiAsistenteMensaje(
        role: 'assistant',
        text:
            'Hola, soy RAI, tu asistente en la app.\n\n'
            'Puedo explicarte cómo pedir viajes, ayudarte con direcciones '
            'complicadas en RD y orientarte en pagos o soporte.\n\n'
            'Para una dirección difícil, di por voz «quiero ir a…» con sector y ciudad, '
            'usa el micrófono abajo o el botón «Buscar dirección».\n\n'
            '¿En qué te ayudo?',
        respuesta: RaiAsistenteRespuesta(
          reply: '',
          source: RaiAsistenteSource.local,
        ),
      ),
    );
    unawaited(_initVoz());
    unawaited(_cargarPerfilYBienvenida());
  }

  Future<void> _cargarPerfilYBienvenida() async {
    final perfil = await RaiPerfilClienteEstado.cargarActual();
    if (!mounted) return;
    setState(() => _perfil = perfil);

    if (perfil != null && perfil.faltantes.isNotEmpty) {
      setState(() {
        _mensajes.add(
          RaiAsistenteMensaje(
            role: 'assistant',
            text: perfil.mensajeAmigable,
            respuesta: RaiAsistenteRespuesta(
              reply: perfil.mensajeAmigable,
              suggestedAction: RaiAsistenteAction.openPerfil,
              source: RaiAsistenteSource.local,
            ),
          ),
        );
      });
      _scrollAlFinal();
    }
  }

  Future<void> _initVoz() async {
    try {
      final ok = await _voz.initialize();
      if (mounted) setState(() => _vozDisponible = ok);
    } catch (_) {
      if (mounted) setState(() => _vozDisponible = false);
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    unawaited(_voz.stop());
    super.dispose();
  }

  Future<void> _abrirBuscadorDireccion({String? textoInicial}) async {
    final ctx = context;
    final det = await RaiDireccionInteligenteSheet.mostrar(
      ctx,
      textoInicial: textoInicial ?? _inputCtrl.text.trim(),
    );
    if (!mounted || det == null) return;

    setState(() {
      _direcciones = [det];
      _mensajes.add(
        RaiAsistenteMensaje(
          role: 'assistant',
          text:
              'Encontré: ${det.displayLabel}\n\n'
              'Pulsa «Usar en taxi» o «Usar en motor» para llevarlo al destino '
              'con coordenadas y cotizar bien.',
          respuesta: const RaiAsistenteRespuesta(
            reply: '',
            source: RaiAsistenteSource.local,
          ),
        ),
      );
    });
    _scrollAlFinal();
  }

  void _onChipRapido(String chip) {
    if (_enviando) return;
    if (chip == 'Buscar dirección difícil') {
      unawaited(_abrirBuscadorDireccion());
      return;
    }
    if (chip == 'Pedir motor') {
      Navigator.pop(context);
      unawaited(
        RaiAsistenteLauncher.ejecutarAccion(
          context,
          RaiAsistenteAction.openMotor,
        ),
      );
      return;
    }
    if (chip == 'Viaje programado') {
      Navigator.pop(context);
      unawaited(
        RaiAsistenteLauncher.ejecutarAccion(
          context,
          RaiAsistenteAction.openTaxi,
        ),
      );
      return;
    }
    if (chip == 'Hablar con soporte') {
      Navigator.pop(context);
      unawaited(
        RaiAsistenteLauncher.ejecutarAccion(
          context,
          RaiAsistenteAction.openSoporte,
        ),
      );
      return;
    }
    unawaited(_enviar(chip));
  }

  Future<void> _enviar([String? textoOverride, bool fromVoice = false]) async {
    final text = (textoOverride ?? _inputCtrl.text).trim();
    if (text.isEmpty || _enviando) return;

    final analisis = RaiDestinoDesdeVoz.analizar(text);
    final buscarDestino = analisis.tieneDestinoParaBuscar ||
        analisis.esDireccionDirecta ||
        analisis.esPedidoDestino;

    setState(() {
      _enviando = true;
      _direcciones = [];
      _mensajes.add(RaiAsistenteMensaje(role: 'user', text: text));
      _inputCtrl.clear();
    });
    _scrollAlFinal();

    if (buscarDestino) {
      await _resolverDestinoYContinuar(
        analisis: analisis,
        fromVoice: fromVoice,
      );
      return;
    }

    final resp = await RaiAsistenteService.instance.preguntar(
      message: text,
      history: _mensajes,
    );

    if (!mounted) return;

    final reAnalisis = RaiDestinoDesdeVoz.analizar(text);
    final queryDestino = (resp.addressQuery?.trim().isNotEmpty == true)
        ? resp.addressQuery!.trim()
        : (reAnalisis.tieneDestinoParaBuscar
            ? reAnalisis.consultaPlaces
            : null);

    if (queryDestino != null && queryDestino.length >= 3) {
      await _resolverDestinoYContinuar(
        analisis: RaiDestinoDesdeVozAnalisis(
          textoOriginal: text,
          destinoExtraido: queryDestino,
          preferMotor: reAnalisis.preferMotor ||
              resp.suggestedAction == RaiAsistenteAction.openMotor,
          preferTaxi: reAnalisis.preferTaxi ||
              resp.suggestedAction == RaiAsistenteAction.openTaxi,
          preferTurismo: reAnalisis.preferTurismo ||
              resp.suggestedAction == RaiAsistenteAction.openTurismo,
          esPedidoDestino: true,
        ),
        fromVoice: fromVoice,
        mensajeAsistentePrevio: resp.reply,
      );
      return;
    }

    setState(() {
      _mensajes.add(
        RaiAsistenteMensaje(
          role: 'assistant',
          text: resp.reply,
          respuesta: resp,
        ),
      );
      _enviando = false;
    });
    _scrollAlFinal();
  }

  Future<void> _resolverDestinoYContinuar({
    required RaiDestinoDesdeVozAnalisis analisis,
    required bool fromVoice,
    String? mensajeAsistentePrevio,
  }) async {
    final consulta = analisis.consultaPlaces;
    final resVoz = await RaiAplicarDestinoDesdeVoz.resolver(
      textoReconocido: consulta,
    );

    if (!mounted) return;

    final motor = analisis.preferMotor;
    final mejor = resVoz.lugarConfiable ??
        (resVoz.candidatos.isNotEmpty ? resVoz.candidatos.first : null);
    final autoAplicar = fromVoice && mejor != null && resVoz.lugarConfiable != null;

    if (autoAplicar) {
      setState(() {
        _mensajes.add(
          RaiAsistenteMensaje(
            role: 'assistant',
            text:
                '${mensajeAsistentePrevio ?? 'Perfecto, entendí tu destino.'}\n\n'
                'Destino exacto: ${mejor.displayLabel}\n'
                'Te llevo a ${motor ? 'motor' : 'taxi'} para cotizar con coordenadas.',
            respuesta: const RaiAsistenteRespuesta(
              reply: '',
              source: RaiAsistenteSource.local,
            ),
          ),
        );
        _enviando = false;
      });
      _scrollAlFinal();
      await _usarDestino(mejor, motor: motor);
      return;
    }

    setState(() {
      _direcciones = resVoz.candidatos;
      _mensajes.add(
        RaiAsistenteMensaje(
          role: 'assistant',
          text: resVoz.encontroAlgo
              ? '${mensajeAsistentePrevio ?? ''}'
                  '${mensajeAsistentePrevio != null ? '\n\n' : ''}'
                  'Busqué «$consulta» en Google Places. '
                  'Elige la dirección exacta y úsala en taxi o motor para cotizar bien.'
              : 'No encontré coordenadas exactas para «$consulta». '
                  'Prueba el buscador «Buscar dirección» con más detalle '
                  '(sector, calle, ciudad, RD).',
          respuesta: const RaiAsistenteRespuesta(
            reply: '',
            source: RaiAsistenteSource.local,
          ),
        ),
      );
      _enviando = false;
    });
    _scrollAlFinal();
  }

  Future<void> _enviarDesdeVoz(String text) => _enviar(text, true);

  void _scrollAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl = _listaScroll;
      if (ctrl == null || !ctrl.hasClients) return;
      ctrl.animateTo(
        ctrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _toggleVoz() async {
    if (!_vozDisponible || _enviando) return;
    if (_escuchando) {
      await _voz.stop();
      if (mounted) setState(() => _escuchando = false);
      return;
    }
    await _voz.toggleListen(
      onListeningChanged: (active) {
        if (mounted) setState(() => _escuchando = active);
      },
      onResult: (words, isFinal) {
        if (!mounted) return;
        _inputCtrl.text = words;
        _inputCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _inputCtrl.text.length),
        );
        if (isFinal && words.trim().isNotEmpty) {
          unawaited(_enviarDesdeVoz(words.trim()));
        }
      },
    );
  }

  Future<void> _usarDestino(DetalleLugar d, {required bool motor}) async {
    final nav = Navigator.of(context);
    nav.pop();
    await RaiAsistenteLauncher.ejecutarAccion(
      context,
      motor ? RaiAsistenteAction.openMotor : RaiAsistenteAction.openTaxi,
      destino: d,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final screenH = MediaQuery.sizeOf(context).height;

    return DraggableScrollableSheet(
      initialChildSize: 0.94,
      minChildSize: 0.55,
      maxChildSize: 0.98,
      expand: false,
      builder: (context, dragScrollController) {
        _listaScroll = dragScrollController;
        return Material(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _dragHandle(cs),
              _header(context),
              Expanded(
                child: ListView(
                  controller: dragScrollController,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  children: [
                    ..._mensajes.map(_bubble),
                    if (_perfil != null && _perfil!.faltantes.isNotEmpty)
                      _bannerPerfilPendiente(context),
                    if (_direcciones.isNotEmpty) _direccionesCard(context),
                    if (_enviando)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'RAI está pensando…',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    SizedBox(height: screenH * 0.02),
                  ],
                ),
              ),
              _chipsRapidosBar(context),
              _botonBuscarDireccion(context),
              SafeArea(
                top: false,
                child: _inputBar(context, bottomInset),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dragHandle(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Center(
        child: Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: cs.onSurfaceVariant.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_rounded, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Asistente RAI',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  'Arrastra arriba · chat · buscar dirección · soporte',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _chipsRapidosBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 2,
      color: cs.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              'Accesos rápidos',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              itemCount: _chipsRapidos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = _chipsRapidos[i];
                return ActionChip(
                  label: Text(c, style: const TextStyle(fontSize: 12)),
                  onPressed: _enviando ? null : () => _onChipRapido(c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonBuscarDireccion(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: _enviando ? null : () => _abrirBuscadorDireccion(),
          icon: const Icon(Icons.travel_explore_rounded, size: 20),
          label: const Text('Buscar dirección (IA + Google Places)'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            backgroundColor: cs.tertiaryContainer.withValues(alpha: 0.65),
          ),
        ),
      ),
    );
  }

  Widget _bubble(RaiAsistenteMensaje m) {
    final isUser = m.role == 'user';
    final cs = Theme.of(context).colorScheme;
    final bg = isUser
        ? cs.primary.withValues(alpha: 0.14)
        : cs.surfaceContainerHighest.withValues(alpha: 0.85);
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.88,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              m.text.replaceAll('**', ''),
              style: TextStyle(
                color: cs.onSurface,
                height: 1.35,
                fontSize: 14,
              ),
            ),
          ),
          if (!isUser && m.respuesta != null) ...[
            const SizedBox(height: 6),
            _accionesRespuesta(m.respuesta!),
          ],
        ],
      ),
    );
  }

  Widget _accionesRespuesta(RaiAsistenteRespuesta r) {
    final action = r.suggestedAction;
    if (action == RaiAsistenteAction.none) return const SizedBox.shrink();

    String label;
    switch (action) {
      case RaiAsistenteAction.openMotor:
        label = 'Abrir motor';
        break;
      case RaiAsistenteAction.openTaxi:
        label = 'Pedir taxi';
        break;
      case RaiAsistenteAction.openTurismo:
        label = 'Ver turismo';
        break;
      case RaiAsistenteAction.openSoporte:
        label = 'Ir a soporte';
        break;
      case RaiAsistenteAction.openMisViajes:
        label = 'Mis viajes';
        break;
      case RaiAsistenteAction.openPerfil:
        label = 'Completar perfil';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () {
          Navigator.pop(context);
          unawaited(
            RaiAsistenteLauncher.ejecutarAccion(context, action),
          );
        },
        icon: const Icon(Icons.open_in_new_rounded, size: 18),
        label: Text(label),
      ),
    );
  }

  Widget _bannerPerfilPendiente(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cs.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            unawaited(
              RaiAsistenteLauncher.ejecutarAccion(
                context,
                RaiAsistenteAction.openPerfil,
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.person_outline, color: cs.secondary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Perfil incompleto — toca para completarlo',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _direccionesCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: cs.tertiaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.place_rounded, size: 18, color: cs.tertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Destinos encontrados — se aplican con coordenadas',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._direcciones.map(
              (d) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.displayLabel,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        FilledButton.tonal(
                          onPressed: () => _usarDestino(d, motor: false),
                          child: const Text('Usar en taxi'),
                        ),
                        OutlinedButton(
                          onPressed: () => _usarDestino(d, motor: true),
                          child: const Text('Usar en motor'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputBar(BuildContext context, double bottomInset) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 4, 12, 8 + bottomInset),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_vozDisponible)
            IconButton.filledTonal(
              onPressed: _enviando ? null : _toggleVoz,
              icon: Icon(
                _escuchando ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: _escuchando ? cs.error : null,
              ),
              tooltip: _escuchando ? 'Detener' : 'Hablar',
            ),
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _enviar(),
              decoration: InputDecoration(
                hintText: 'Di o escribe: «quiero ir a…» con sector y ciudad',
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _enviando ? null : () => _enviar(),
            icon: const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}
