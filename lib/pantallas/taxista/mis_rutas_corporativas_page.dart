import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/pantallas/comun/factura_viaje.dart';
import 'package:flygo_nuevo/pantallas/taxista/historial_viajes_taxista.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/taxista_historial_repo.dart';
import 'package:flygo_nuevo/utils/corporativo_hora_encargado.dart';
import 'package:flygo_nuevo/utils/hora_am_pm.dart';
import 'package:flygo_nuevo/widgets/corporativo_recogida_countdown.dart';
import 'package:flygo_nuevo/widgets/shell_tab_nav.dart';

/// Agenda del chofer: rutas corporativas (mañana / tarde / noche) sin choque.
class MisRutasCorporativasPage extends StatefulWidget {
  const MisRutasCorporativasPage({super.key});

  @override
  State<MisRutasCorporativasPage> createState() =>
      _MisRutasCorporativasPageState();
}

class _MisRutasCorporativasPageState extends State<MisRutasCorporativasPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Tras el primer frame: pedir al servidor que regenere chofer_operacion.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isNotEmpty) {
        unawaited(_refrescar(uid, silencioso: true));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isNotEmpty) {
        unawaited(_refrescar(uid, silencioso: true));
      }
    }
  }

  double _listBottomPad(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).bottom + 32;

  Future<void> _refrescar(String uid, {bool silencioso = false}) async {
    try {
      await CorporativoTaxistaService.refrescarOperacionChofer(uid);
    } catch (e) {
      if (!mounted || silencioso) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final cs = Theme.of(context).colorScheme;
    final fmtMonto = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$',
      decimalDigits: 0,
    );

    return Scaffold(
      appBar: RaiShellTabHeader(
        title: 'Mis rutas corporativas',
        backTooltip: 'Volver a Servicios',
        onBack: () => NavigationService.salirMisRutasCorporativas(context),
      ),
      body: uid.isEmpty
          ? const Center(child: Text('Sesión expirada'))
          : StreamBuilder<Map<String, dynamic>?>(
              stream: CorporativoTaxistaService.streamOperacionChofer(uid),
              builder: (context, opSnap) {
                final mensajeOp = CorporativoTaxistaService.mensajeGeneralOperacion(
                  opSnap.data,
                );
                // Fuente principal: chofer_operacion (no depender solo de otros streams).
                final fijasOp = CorporativoTaxistaService.rutasDesdeOperacion(
                  opSnap.data,
                );
                final viajesOp =
                    CorporativoTaxistaService.viajesHoyDesdeOperacion(
                  opSnap.data,
                );
                final tieneOp =
                    CorporativoTaxistaService.tieneContenidoOperacion(
                  opSnap.data,
                );
                return StreamBuilder<List<Map<String, dynamic>>>(
              stream: CorporativoTaxistaService.streamAsignacionesFijas(uid),
              builder: (context, asigSnap) {
                final fijasStream =
                    asigSnap.data ?? const <Map<String, dynamic>>[];
                // El stream ya incluye chofer_operacion + plantilla en vivo + viajes.
                // No volver a fusionar con operacion (generaba duplicados tras cambio de hora).
                final fijas = CorporativoTaxistaService.dedupeFijasPorPlantilla(
                  fijasStream.isNotEmpty ? fijasStream : fijasOp,
                );
                return StreamBuilder<
                    List<DocumentSnapshot<Map<String, dynamic>>>>(
                  stream: CorporativoTaxistaService.streamViajesAsignados(uid),
                  builder: (context, snap) {
                    final esperandoOp =
                        opSnap.connectionState == ConnectionState.waiting &&
                            !opSnap.hasData;
                    if (esperandoOp && !tieneOp) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snap.data ?? [];
                    final ahora = DateTime.now();
                    final hoy =
                        <DocumentSnapshot<Map<String, dynamic>>>[];
                    final proximas =
                        <DocumentSnapshot<Map<String, dynamic>>>[];
                    for (final d in docs) {
                      final data = d.data() ?? <String, dynamic>{};
                      final fh = data['fechaHora'];
                      DateTime? fecha;
                      if (fh is Timestamp) fecha = fh.toDate();
                      final esHoy = fecha != null &&
                          fecha.year == ahora.year &&
                          fecha.month == ahora.month &&
                          fecha.day == ahora.day;
                      if (esHoy) {
                        hoy.add(d);
                      } else {
                        proximas.add(d);
                      }
                    }
                    final hoyDedupe =
                        CorporativoTaxistaService.dedupeViajesHoy(hoy);

                    if (docs.isEmpty && fijas.isEmpty && !tieneOp) {
                      return RefreshIndicator(
                        onRefresh: () => _refrescar(uid),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            28,
                            28,
                            28,
                            _listBottomPad(context),
                          ),
                          children: [
                            if (mensajeOp.isNotEmpty) ...[
                              _MensajeOperacionCard(mensaje: mensajeOp),
                              const SizedBox(height: 20),
                            ],
                            _AvisoViajeCorporativoOtraCuenta(uid: uid),
                            Icon(
                              Icons.route_outlined,
                              size: 48,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Aún sin ruta corporativa amarrada',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              mensajeOp.isNotEmpty
                                  ? mensajeOp
                                  : 'Cuando Admin RAI te asigne una empresa, la ruta '
                                      'fija aparece aquí.\n\n'
                                      'El viaje del día se publica ~90 min antes '
                                      '(Waze / Maps / código).\n\n'
                                      'Deslizá hacia abajo para actualizar.\n\n'
                                      'Si el encargado ya publicó, tocá Actualizar rutas.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                height: 1.4,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: () => _refrescar(uid),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Actualizar rutas'),
                            ),
                          ],
                        ),
                      );
                    }

                    final fijasRecogidaPerdida = fijas
                        .where(
                          (a) =>
                              (a['estadoOperacion'] ?? '').toString() ==
                                  'recogida_perdida' ||
                              a['recogidaPerdidaHoy'] == true,
                        )
                        .toList();
                    final fijasActivas = fijas
                        .where(
                          (a) =>
                              (a['estadoOperacion'] ?? '').toString() !=
                                  'completado' &&
                              (a['estadoOperacion'] ?? '').toString() !=
                                  'recogida_perdida' &&
                              a['completadoHoy'] != true &&
                              a['recogidaPerdidaHoy'] != true,
                        )
                        .toList();
                    final fijasCerradasHoy = fijas
                        .where(
                          (a) =>
                              (a['estadoOperacion'] ?? '').toString() ==
                                  'completado' ||
                              a['completadoHoy'] == true,
                        )
                        .toList();

                    final fijasConViajeHoy = fijasActivas.any(
                      (a) =>
                          (a['viajeHoyId'] ?? a['_viajeHoyId'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty,
                    ) ||
                        viajesOp.isNotEmpty;

                    final horaPorRuta =
                        CorporativoTaxistaService.horaFijaPorRuta(fijasActivas);
                    final listoOperacion =
                        CorporativoTaxistaService.listoOperacionPorViaje(
                      opSnap.data,
                    );
                    final hoyPool =
                        <DocumentSnapshot<Map<String, dynamic>>>[];
                    final hoyEspera =
                        <DocumentSnapshot<Map<String, dynamic>>>[];
                    for (final doc in hoyDedupe) {
                      final data = doc.data() ?? <String, dynamic>{};
                      if (CorporativoTaxistaService.viajeCorporativoEnPoolTrabajo(
                        data,
                        listoSegunOperacion:
                            listoOperacion[doc.id] == true,
                      )) {
                        hoyPool.add(doc);
                      } else {
                        hoyEspera.add(doc);
                      }
                    }

                    return RefreshIndicator(
                      onRefresh: () => _refrescar(uid),
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          12,
                          16,
                          _listBottomPad(context),
                        ),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                        if (mensajeOp.isNotEmpty) ...[
                          _MensajeOperacionCard(mensaje: mensajeOp),
                          const SizedBox(height: 12),
                        ],
                        _guia(cs),
                        if (fijasActivas.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _PagoEstimadoChoferCard(
                            rutasFijas: fijasActivas.length,
                            fmtMonto: fmtMonto,
                          ),
                        ],
                        if (fijasActivas.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _seccionTitulo(
                            cs,
                            'Rutas fijas amarradas · ${fijasActivas.length}',
                          ),
                          const SizedBox(height: 8),
                          ...fijasActivas.map(
                            (a) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _AsignacionFijaCard(
                                key: ValueKey(
                                  '${a['_key']}_${a['hora']}_${a['pasajerosActivos']}_${a['viajeHoyId']}',
                                ),
                                data: a,
                                uidTaxista: uid,
                              ),
                            ),
                          ),
                        ],
                        if (fijasRecogidaPerdida.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _seccionTitulo(
                            cs,
                            'Recogida no realizada · ${fijasRecogidaPerdida.length}',
                          ),
                          const SizedBox(height: 8),
                          ...fijasRecogidaPerdida.map(
                            (a) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _RutaRecogidaPerdidaCard(data: a),
                            ),
                          ),
                        ],
                        if (fijasCerradasHoy.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _seccionTitulo(
                            cs,
                            'Cerradas hoy · ${fijasCerradasHoy.length}',
                          ),
                          const SizedBox(height: 8),
                          ...fijasCerradasHoy.map(
                            (a) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _RutaCerradaHoyCard(
                                data: a,
                                uidTaxista: uid,
                                onQuitadaDelHistorial: () =>
                                    _refrescar(uid, silencioso: true),
                              ),
                            ),
                          ),
                        ],
                        if (fijasActivas.isNotEmpty &&
                            hoyPool.isEmpty &&
                            hoyEspera.isEmpty &&
                            !fijasConViajeHoy &&
                            fijasRecogidaPerdida.isEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Text(
                              'Tu empresa te tiene amarrado, pero el viaje de hoy '
                              'aún no aparece.\n\n'
                              'Pedile al encargado que guarde la ruta con la hora '
                              'correcta (se publica sola) o que toque «Enviar ahora».\n\n'
                              'Cuando esté listo verás «Hoy · viaje(s) publicados» '
                              'con el botón Abrir ruta.',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 12,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                        if (hoyPool.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _seccionTitulo(
                            cs,
                            hoyPool.length == 1
                                ? 'Para trabajar ahora · ${CorporativoTaxistaService.nombreEmpresaCorporativo(hoyPool.first.data() ?? {})}'
                                : 'Para trabajar ahora · ${hoyPool.map((doc) => CorporativoTaxistaService.nombreEmpresaCorporativo(doc.data() ?? {})).toSet().join(' · ')}',
                          ),
                          const SizedBox(height: 8),
                          ...hoyPool.map(
                            (doc) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _RutaCard(
                                key: ValueKey('pool_${doc.id}'),
                                doc: doc,
                                uid: uid,
                                fmtMonto: fmtMonto,
                                esHoy: true,
                                enPoolTrabajo: true,
                                listoSegunOperacion:
                                    listoOperacion[doc.id] == true,
                                horaPorRuta: horaPorRuta,
                              ),
                            ),
                          ),
                        ],
                        if (hoyEspera.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _seccionTitulo(
                            cs,
                            'Hoy · se abre más tarde · ${hoyEspera.length}',
                          ),
                          const SizedBox(height: 8),
                          ...hoyEspera.map(
                            (doc) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _RutaCard(
                                key: ValueKey('espera_${doc.id}'),
                                doc: doc,
                                uid: uid,
                                fmtMonto: fmtMonto,
                                esHoy: true,
                                enPoolTrabajo: false,
                                listoSegunOperacion:
                                    listoOperacion[doc.id] == true,
                                horaPorRuta: horaPorRuta,
                              ),
                            ),
                          ),
                        ],
                        if (proximas.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _seccionTitulo(cs, 'Próximos viajes'),
                          const SizedBox(height: 8),
                          ...proximas.map(
                            (doc) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _RutaCard(
                                key: ValueKey('prox_${doc.id}'),
                                doc: doc,
                                uid: uid,
                                fmtMonto: fmtMonto,
                                esHoy: false,
                                horaPorRuta: horaPorRuta,
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
          },
        ),
    );
  }

  Widget _guia(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Operación profesional · ruta empresarial',
            style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '1. Admin te amarra a la empresa → ves la ruta fija aquí (agenda).\n'
            '2. ~90 min antes de la recogida: entra al pool «Para trabajar ahora» + push.\n'
            '3. Solo ahí abrís Waze/Maps y marcás entregas.\n'
            '4. Otra ruta del mismo día queda en «Se abre más tarde» hasta su hora.\n'
            '5. Al finalizar, tu neto en Cuenta → Ganancias → Corporativo.',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccionTitulo(ColorScheme cs, String t) {
    return Text(
      t,
      style: TextStyle(
        color: cs.onSurface,
        fontWeight: FontWeight.w800,
        fontSize: 15,
      ),
    );
  }
}

class _MensajeOperacionCard extends StatelessWidget {
  const _MensajeOperacionCard({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: cs.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AsignacionFijaCard extends StatefulWidget {
  const _AsignacionFijaCard({
    super.key,
    required this.data,
    required this.uidTaxista,
  });

  final Map<String, dynamic> data;
  final String uidTaxista;

  @override
  State<_AsignacionFijaCard> createState() => _AsignacionFijaCardState();
}

class _AsignacionFijaCardState extends State<_AsignacionFijaCard> {
  bool _confirmando = false;

  String get _empresaId =>
      (widget.data['empresaId'] ?? '').toString().trim();
  String get _plantillaId =>
      (widget.data['plantillaId'] ?? '').toString().trim();

  Future<void> _confirmarRuta() async {
    if (_empresaId.isEmpty || _plantillaId.isEmpty) return;
    setState(() => _confirmando = true);
    try {
      await CorporativoTaxistaService.confirmarRutaCorporativa(
        empresaId: _empresaId,
        plantillaId: _plantillaId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ruta confirmada. Te esperamos a la hora de recogida.'),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo confirmar: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final data = widget.data;
    final uid = widget.uidTaxista;
    final empresa = (data['empresaNombre'] ?? 'Empresa').toString();
    final ruta = (data['plantillaNombre'] ?? 'Ruta').toString();
    final horaRaw = (data['hora'] ?? '').toString();
    final hora = horaRaw.isNotEmpty ? fmtHoraStrAmPm(horaRaw) : '';
    final nPas = (data['pasajerosActivos'] as num?)?.toInt();
    final estadoOp = (data['estadoOperacion'] ?? '').toString();
    final listo = data['listoParaAbrir'] == true;
    final recogidaPerdida =
        estadoOp == 'recogida_perdida' || data['recogidaPerdidaHoy'] == true;
    final viajeId = (data['viajeHoyId'] ?? data['_viajeHoyId'] ?? '')
        .toString()
        .trim();
    final completadoHoy = data['completadoHoy'] == true;
    final viajePublicado = viajeId.isNotEmpty;
    final mensaje = CorporativoTaxistaService.mensajeChoferRutaFijaEnVivo(
      horaRaw: horaRaw,
      estadoOperacion: estadoOp,
      listoParaAbrir: listo,
      viajePublicado: viajePublicado,
      recogidaPerdida: recogidaPerdida,
      completadoHoy: completadoHoy,
    );
    final enCurso = estadoOp == 'en_curso';
    final cancelado = estadoOp == 'cancelado';
    final puedeAbrir = !recogidaPerdida &&
        viajeId.isNotEmpty &&
        !cancelado &&
        (listo || enCurso);

    Widget cardBody({
      required bool confirmado,
      required bool requiereConfirmacion,
    }) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.business_rounded, size: 18, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      empresa,
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (horaRaw.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    CorporativoRecogidaCountdown(
                      horaHHmm: horaRaw,
                      permitirAhora: !recogidaPerdida && (listo || viajeId.isNotEmpty),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                ruta,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              if (hora.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Recogida habitual: $hora'
                  '${nPas != null && nPas > 0 ? ' · $nPas pasajero(s)' : ''}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
              if (estadoOp.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _etiquetaEstadoOperacion(estadoOp, listo),
                  style: TextStyle(
                    color: listo ? cs.primary : cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (confirmado) ...[
                const SizedBox(height: 6),
                Text(
                  CorporativoTaxistaService.etiquetaConfirmacionRutaFija(horaRaw),
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ] else if (requiereConfirmacion) ...[
                const SizedBox(height: 6),
                Text(
                  'Confirmá que harás esta ruta para que RAI no la reasigne.',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (mensaje.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  mensaje,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
              if (requiereConfirmacion && !confirmado && !recogidaPerdida) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _confirmando ? null : _confirmarRuta,
                    icon: _confirmando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                      _confirmando ? 'Confirmando…' : 'Confirmar ruta',
                    ),
                  ),
                ),
              ],
              if (puedeAbrir) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await NavigationService.abrirViajeCorporativoTaxista(
                        uidTaxista: uid,
                        viajeId: viajeId,
                        snackContext: context,
                        quedarseEnPantalla: true,
                        listoSegunOperacion: listo,
                      );
                    },
                    icon: Icon(
                      enCurso
                          ? Icons.navigation_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    label: Text(enCurso ? 'Continuar ruta' : 'Abrir ruta'),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (_empresaId.isEmpty || _plantillaId.isEmpty) {
      return cardBody(confirmado: false, requiereConfirmacion: false);
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: CorporativoTaxistaService.streamPlantillaChofer(
        _empresaId,
        _plantillaId,
      ),
      builder: (context, snap) {
        final pl = snap.data?.data() ?? <String, dynamic>{};
        final confirmado = CorporativoTaxistaService.choferConfirmoRutaHoy(
          pl,
          uid,
        );
        final requiereConfirmacion =
            CorporativoTaxistaService.politicaRequiereConfirmacionChofer(pl);
        return cardBody(
          confirmado: confirmado,
          requiereConfirmacion: requiereConfirmacion,
        );
      },
    );
  }

  String _etiquetaEstadoOperacion(String estado, bool listo) {
    switch (estado) {
      case 'publicado':
        return listo ? '● Viaje publicado · listo' : '● Viaje publicado';
      case 'en_curso':
        return '● En curso';
      case 'completado':
        return '● Completado hoy';
      case 'recogida_perdida':
        return '● Recogida no realizada';
      case 'amarrado':
      default:
        return '● Ruta amarrada';
    }
  }
}

class _RutaRecogidaPerdidaCard extends StatelessWidget {
  const _RutaRecogidaPerdidaCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final empresa = (data['empresaNombre'] ?? 'Empresa').toString();
    final ruta = (data['plantillaNombre'] ?? 'Ruta').toString();
    final horaRaw = (data['hora'] ?? '').toString();
    final hora = horaRaw.isNotEmpty ? fmtHoraStrAmPm(horaRaw) : '';
    final mensaje = (data['mensajeChofer'] ?? '').toString();

    return Card(
      elevation: 0,
      color: const Color(0xFF7F1D1D).withValues(alpha: 0.28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.red.shade700.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.red.shade400, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        empresa,
                        style: TextStyle(
                          color: Colors.red.shade300,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ruta,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      if (hora.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Recogida no realizada · $hora',
                          style: TextStyle(
                            color: Colors.red.shade200,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              mensaje.isNotEmpty
                  ? mensaje
                  : 'No fuiste a la recogida de hoy. RAI y la empresa '
                      'fueron notificados. Mañana se publica la ruta '
                      '~90 min antes de la hora habitual.',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RutaCerradaHoyCard extends StatefulWidget {
  const _RutaCerradaHoyCard({
    required this.data,
    required this.uidTaxista,
    this.onQuitadaDelHistorial,
  });

  final Map<String, dynamic> data;
  final String uidTaxista;
  final VoidCallback? onQuitadaDelHistorial;

  @override
  State<_RutaCerradaHoyCard> createState() => _RutaCerradaHoyCardState();
}

class _RutaCerradaHoyCardState extends State<_RutaCerradaHoyCard> {
  Map<String, dynamic>? _viajeRaw;
  bool _cargandoViaje = false;
  bool _quitando = false;
  bool _ocultaDelHistorial = false;

  String get _viajeCompletadoId {
    final id = (widget.data['viajeCompletadoId'] ??
            widget.data['_viajeCompletadoId'] ??
            widget.data['viajeHoyId'] ??
            '')
        .toString()
        .trim();
    return id;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_cargarViaje());
  }

  Future<void> _cargarViaje() async {
    final viajeId = _viajeCompletadoId;
    if (viajeId.isEmpty) return;
    setState(() => _cargandoViaje = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .get();
      if (!mounted) return;
      setState(() => _viajeRaw = snap.data());
    } finally {
      if (mounted) setState(() => _cargandoViaje = false);
    }
  }

  Future<void> _verComprobante() async {
    final viajeId = _viajeCompletadoId;
    if (viajeId.isEmpty) {
      _abrirHistorial();
      return;
    }
    await FacturaViaje.mostrar(
      context,
      viajeId: viajeId,
      role: 'taxista',
    );
  }

  void _abrirHistorial() {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const HistorialViajesTaxista(),
      ),
    );
  }

  Future<void> _quitarDelHistorial() async {
    final viajeId = _viajeCompletadoId;
    if (viajeId.isEmpty) return;
    final raw = _viajeRaw ?? <String, dynamic>{};
    if (!TaxistaHistorialRepo.viajePagadoParaOcultar(raw)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aún no figura como pagado. Podrás quitarlo cuando RAI liquide.',
          ),
        ),
      );
      return;
    }

    final empresa = (widget.data['empresaNombre'] ?? 'Empresa').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar del historial'),
        content: Text(
          '¿Quitar el viaje de $empresa de tu historial?\n\n'
          'Desaparece de tu teléfono; RAI y la empresa conservan el registro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _quitando = true);
    try {
      await TaxistaHistorialRepo.ocultarViaje(
        uid: widget.uidTaxista,
        viajeId: viajeId,
      );
      if (!mounted) return;
      setState(() => _ocultaDelHistorial = true);
      widget.onQuitadaDelHistorial?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Viaje quitado de tu historial.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _quitando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ocultaDelHistorial) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final empresa = (widget.data['empresaNombre'] ?? 'Empresa').toString();
    final ruta = (widget.data['plantillaNombre'] ?? 'Ruta').toString();
    final horaRaw = (widget.data['hora'] ?? '').toString();
    final hora = horaRaw.isNotEmpty ? fmtHoraStrAmPm(horaRaw) : '';
    final mensaje = (widget.data['mensajeChofer'] ?? '').toString();
    final tieneComprobante = _viajeCompletadoId.isNotEmpty;
    final puedeQuitar = _viajeRaw != null &&
        TaxistaHistorialRepo.viajePagadoParaOcultar(_viajeRaw!);

    return Card(
      elevation: 0,
      color: const Color(0xFF14532D).withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.primary.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_rounded, color: cs.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        empresa,
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ruta,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      if (hora.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Recogida $hora · completada hoy',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        mensaje.isNotEmpty
                            ? mensaje
                            : 'Ruta de hoy cerrada. Mañana aparece el nuevo viaje '
                                '~90 min antes de la recogida.',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (horaRaw.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  CorporativoRecogidaCountdown(
                    horaHHmm: horaRaw,
                    completadaHoy: true,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _abrirHistorial,
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text('Historial'),
                  ),
                ),
                if (tieneComprobante) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _verComprobante,
                      icon: const Icon(Icons.receipt_long_rounded, size: 18),
                      label: const Text('Comprobante'),
                    ),
                  ),
                ],
              ],
            ),
            if (puedeQuitar) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _quitando ? null : _quitarDelHistorial,
                  icon: _quitando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.delete_outline_rounded, color: cs.error),
                  label: Text(
                    'Quitar del historial',
                    style: TextStyle(color: cs.error),
                  ),
                ),
              ),
            ] else if (!_cargandoViaje && tieneComprobante) ...[
              const SizedBox(height: 8),
              Text(
                'Podrás quitarlo del historial cuando RAI liquide el pago.',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RutaCard extends StatelessWidget {
  const _RutaCard({
    super.key,
    required this.doc,
    required this.uid,
    required this.fmtMonto,
    required this.esHoy,
    this.enPoolTrabajo = false,
    this.horaPorRuta = const {},
    this.listoSegunOperacion = false,
  });

  final DocumentSnapshot<Map<String, dynamic>> doc;
  final String uid;
  final NumberFormat fmtMonto;
  final bool esHoy;
  final bool enPoolTrabajo;
  final Map<String, String> horaPorRuta;
  final bool listoSegunOperacion;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = doc.data() ?? <String, dynamic>{};
    final empresa = CorporativoTaxistaService.nombreEmpresaCorporativo(d);
    final ruta = () {
      final pl =
          (d['corporativoPlantillaNombre'] ?? '').toString().trim();
      if (pl.isNotEmpty) return pl;
      final cliente = (d['corporativoClienteNombre'] ?? '').toString().trim();
      if (cliente.isNotEmpty) return cliente;
      return (d['origen'] ?? 'Ruta corporativa').toString();
    }();
    final origen = (d['origen'] ?? '').toString();
    final precio = (d['precio'] as num?)?.toDouble() ?? 0;
    final nPas = CorporativoTaxistaService.pasajerosCount(d);
    final empId = (d['corporativoEmpresaId'] ?? '').toString().trim();
    final plId = (d['corporativoPlantillaId'] ?? '').toString().trim();
    final horaContrato = horaEncargadoCorporativo(
      d,
      horaPlantillaViva: horaPorRuta[claveRutaCorporativo(empId, plId)],
    );
    DateTime? fecha;
    final fh = d['fechaHora'];
    if (fh is Timestamp) fecha = fh.toDate().toLocal();
    final turno = CorporativoTaxistaService.turnoDeFecha(
      horaContrato.isNotEmpty
          ? CorporativoTaxistaService.fechaConHoraFija(
              fecha ?? DateTime.now(),
              horaContrato,
            )
          : fecha,
    );
    final estado = (d['estado'] ?? '').toString();
    final enCurso = CorporativoTaxistaService.viajeCorporativoEnCursoReal(d);
    final esperandoCodigo = estado == 'esperando_codigo_encargado' ||
        estado == 'pendiente_codigo';
    final listoAbrir =
        CorporativoTaxistaService.corporativoListoParaAbrirEnCurso(
          d,
          listoSegunOperacion: listoSegunOperacion,
        );
    final modoInfo = CorporativoTaxistaService.esModoInformativo(d);
    final puedeAbrirBtn = listoAbrir || enCurso;

    Color turnoColor;
    switch (turno) {
      case 'Mañana':
        turnoColor = const Color(0xFF0D9488);
      case 'Tarde':
        turnoColor = const Color(0xFFD97706);
      default:
        turnoColor = const Color(0xFF6366F1);
    }

    return Card(
      elevation: enPoolTrabajo ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: enPoolTrabajo
              ? cs.primary.withValues(alpha: 0.45)
              : cs.outlineVariant.withValues(alpha: 0.6),
          width: enPoolTrabajo ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: enPoolTrabajo
                    ? cs.primary.withValues(alpha: 0.12)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: enPoolTrabajo
                      ? cs.primary.withValues(alpha: 0.35)
                      : cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.business_rounded,
                    size: 22,
                    color: enPoolTrabajo ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EMPRESA',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                        Text(
                          empresa,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: enPoolTrabajo
                                ? cs.primary
                                : cs.onSurface,
                            fontWeight: FontWeight.w900,
                            fontSize: enPoolTrabajo ? 18 : 16,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: turnoColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    turno,
                    style: TextStyle(
                      color: turnoColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
                if (enCurso) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'En curso',
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
                if (esHoy) ...[
                  const Spacer(),
                  CorporativoRecogidaCountdown(
                    viajeData: viajeConHoraEncargado(
                      d,
                      horaEncargado: horaContrato,
                    ),
                    horaHHmm: horaContrato,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Ruta: $ruta',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            if (origen.isNotEmpty) ...[
              const SizedBox(height: 6),
              _RutaMetaRow(
                icon: Icons.location_on_outlined,
                text: 'Recogida: $origen',
                color: cs.onSurfaceVariant,
              ),
            ],
            if (fecha != null || horaContrato.isNotEmpty) ...[
              const SizedBox(height: 4),
              _RutaMetaRow(
                icon: Icons.schedule_rounded,
                text: horaContrato.isNotEmpty
                    ? 'Recogida ${fmtHoraStrAmPm(horaContrato)}'
                    : fmtFechaHoraAmPm(fecha!),
                color: cs.onSurface,
                bold: true,
              ),
            ],
            const SizedBox(height: 4),
            _RutaMetaRow(
              icon: Icons.people_outline_rounded,
              text: nPas > 0
                  ? '$nPas pasajero${nPas == 1 ? '' : 's'} · entregas en destino'
                  : 'Pasajeros de la ruta corporativa',
              color: cs.onSurfaceVariant,
            ),
            if (precio > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Tarifa ruta ${fmtMonto.format(precio)} · se acredita al finalizar',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: cs.onSurface,
                  ),
                ),
              ),
            if (!enPoolTrabajo && esHoy && !enCurso) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  CorporativoTaxistaService.mensajeCorporativoAunNoEsHora(d),
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            if (modoInfo && enPoolTrabajo) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.route_rounded,
                      size: 18,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ruta guiada · sin PIN · Maps o Waze',
                        style: TextStyle(
                          color: cs.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (!modoInfo)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await CorporativoTaxistaService.abrirWazeDesdeViaje(d);
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      }
                    },
                    icon: const Icon(Icons.navigation, size: 18),
                    label: const Text('Waze empresa'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await CorporativoTaxistaService.abrirMapsDesdeViaje(d);
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      }
                    },
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('Maps ruta'),
                  ),
                ],
              ),
            if (!modoInfo) const SizedBox(height: 8),
            if (enPoolTrabajo || enCurso)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: puedeAbrirBtn
                      ? () => _abrir(context)
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                CorporativoTaxistaService
                                    .mensajeCorporativoAunNoEsHora(d),
                              ),
                              duration: const Duration(seconds: 7),
                              backgroundColor: Colors.teal.shade800,
                            ),
                          );
                        },
                  icon: Icon(
                    puedeAbrirBtn
                        ? Icons.route_rounded
                        : Icons.schedule_outlined,
                  ),
                  label: Text(
                    enCurso
                        ? 'Continuar ruta'
                        : puedeAbrirBtn
                            ? 'Ver ruta del día'
                            : 'Se abre más tarde',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrir(BuildContext context) async {
    if (!context.mounted) return;
    await NavigationService.abrirViajeCorporativoTaxista(
      uidTaxista: uid,
      viajeId: doc.id,
      snackContext: context,
      quedarseEnPantalla: true,
    );
  }
}

class _RutaMetaRow extends StatelessWidget {
  const _RutaMetaRow({
    required this.icon,
    required this.text,
    required this.color,
    this.bold = false,
  });

  final IconData icon;
  final String text;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// Estimado orientativo según rutas fijas (liquidación real en Mis pagos).
class _PagoEstimadoChoferCard extends StatelessWidget {
  const _PagoEstimadoChoferCard({
    required this.rutasFijas,
    required this.fmtMonto,
  });

  final int rutasFijas;
  final NumberFormat fmtMonto;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // ~22 días laborables × rutas; monto referencial hasta liquidación RAI.
    const refPorViaje = 1200.0;
    final estimado = rutasFijas * 22 * refPorViaje;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payments_outlined, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Estimado mensual (orientativo)',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              fmtMonto.format(estimado),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$rutasFijas ruta(s) fija(s) · el monto exacto aparece al liquidar '
              'en Mis pagos tras cada período corporativo.',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Avisa si hay un viaje corporativo en cola pero asignado a otro chofer.
class _AvisoViajeCorporativoOtraCuenta extends StatelessWidget {
  const _AvisoViajeCorporativoOtraCuenta({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('usuarios').doc(uid).snapshots(),
      builder: (context, uSnap) {
        final sig =
            (uSnap.data?.data()?['siguienteViajeId'] ?? '').toString().trim();
        if (sig.isEmpty) return const SizedBox.shrink();
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream:
              FirebaseFirestore.instance.collection('viajes').doc(sig).snapshots(),
          builder: (context, vSnap) {
            final m = vSnap.data?.data();
            if (m == null) return const SizedBox.shrink();
            if (!CorporativoTaxistaService.esViajeCorporativoDoc(m)) {
              return const SizedBox.shrink();
            }
            final taxistaViaje =
                (m['uidTaxista'] ?? m['taxistaId'] ?? '').toString().trim();
            if (taxistaViaje.isEmpty || taxistaViaje == uid) {
              return const SizedBox.shrink();
            }
            final empresa =
                (m['corporativoEmpresaNombre'] ?? m['empresaNombre'] ?? '')
                    .toString()
                    .trim();
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                color: cs.errorContainer.withValues(alpha: 0.35),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: cs.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Hay un viaje corporativo${empresa.isNotEmpty ? ' ($empresa)' : ''} '
                          'en tu cola, pero la ruta está amarrada a otra cuenta de chofer.\n\n'
                          'Para ver esa ruta, cerrá sesión y entrá con el teléfono '
                          'del chofer asignado.',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
