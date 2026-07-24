import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flygo_nuevo/servicios/analytics_rai.dart';
import 'package:flygo_nuevo/servicios/pool_repo.dart';
import 'package:flygo_nuevo/servicios/pool_share_link.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flygo_nuevo/utils/hora_am_pm.dart';
import 'package:flygo_nuevo/utils/pool_gira_cancelar_ui.dart';
import 'package:flygo_nuevo/utils/pool_recaudo_central.dart';
import 'package:flygo_nuevo/utils/pools_producto_copy.dart';
import 'package:flygo_nuevo/widgets/pool_recaudo_central_taxista_panel.dart';
import 'package:flygo_nuevo/design_system/rai_design_system.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

import 'pools_gira_editar_contenido.dart';
import 'pools_taxista_reservas.dart';
import 'pools_taxista_crear.dart';

class PoolsTaxistaLista extends StatefulWidget {
  const PoolsTaxistaLista({super.key, this.embeddedInOrganizadorShell = false});

  /// En [OrganizadorGirasShell] el FAB ya publica; ocultar + duplicado en AppBar.
  final bool embeddedInOrganizadorShell;

  @override
  State<PoolsTaxistaLista> createState() => _PoolsTaxistaListaState();
}

class _PoolsTaxistaListaState extends State<PoolsTaxistaLista>
    with SingleTickerProviderStateMixin {
  bool _accionEnCurso = false;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  /// Cancelada / finalizada → pestaña Historial. El resto (abierto, en_ruta…) queda
  /// en Activas para editar / operar.
  bool _esHistorialEstado(String raw) {
    final s = raw.trim().toLowerCase();
    return s == 'cancelado' ||
        s == 'cancelado_por_admin' ||
        s == 'finalizado';
  }

  String _cleanPhone(String raw) {
    final v = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (v.startsWith('1') && v.length == 11) return v;
    if (v.length == 10) return '1$v';
    return v;
  }

  Color _tipoColor(String tipo) {
    switch (tipo.trim().toLowerCase()) {
      case 'tour':
        return Colors.deepPurpleAccent;
      case 'excursion':
        return Colors.orangeAccent;
      default:
        return Colors.blueAccent;
    }
  }

  List<String> _paradasOrdenadas(Map<String, dynamic> d) {
    final raw = (d['pickupPoints'] is List)
        ? List<String>.from(d['pickupPoints'] as List)
        : <String>[];
    final out = <String>[];
    for (final p in raw) {
      final t = p.trim();
      if (t.isEmpty) continue;
      if (!out.contains(t)) out.add(t);
    }
    return out;
  }

  String _buildPromoTexto({
    required Map<String, dynamic> d,
    required DateTime fechaSalida,
    required List<String> paradas,
    required int cuposDisponibles,
    required String poolId,
  }) {
    final origen = (d['origenTown'] ?? '').toString().trim();
    final destino = (d['destino'] ?? '').toString().trim();
    final badge = (d['servicioBadge'] ?? d['tipo'] ?? '').toString().trim();
    final agencia = (d['agenciaNombre'] ?? '').toString().trim();
    final taxistaNombre = (d['taxistaNombre'] ?? '').toString().trim();
    final precio = ((d['precioPorAsiento'] ?? 0) as num).toDouble();
    final fechaTxt = fmtFechaHoraAmPm(fechaSalida, sep: '•');
    final paradasTxt =
        paradas.isEmpty ? 'Sin paradas publicadas' : paradas.join(' | ');
    final quien = agencia.isNotEmpty
        ? agencia
        : (taxistaNombre.isNotEmpty ? taxistaNombre : 'RAI Driver');
    final titulo =
        badge.isNotEmpty ? badge : PoolsProductoCopy.promoTituloDefault;

    final base = '''
${titulo.toUpperCase()}
Organiza: $quien
Ruta: $origen -> $destino
Salida: $fechaTxt
Precio por asiento: RD\$ ${precio.toStringAsFixed(0)}
Cupos disponibles: $cuposDisponibles
Paradas: $paradasTxt

${PoolsProductoCopy.promoSeccionRai}
Contactanos por esta via para mas informacion y confirmacion.
#RAIDriver #Giras #Tours #Excursiones #ViajesPorCupos
'''
        .trim();
    return '$base${PoolShareLink.shareFooter(poolId)}';
  }

  Future<void> _compartirWhatsAppPromo(
    BuildContext context, {
    required String texto,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final msg = Uri.encodeComponent(texto);
      final waApp = Uri.parse('whatsapp://send?text=$msg');
      final waWeb = Uri.parse('https://wa.me/?text=$msg');
      final ok1 = await launchUrl(waApp, mode: LaunchMode.externalApplication);
      if (ok1) return;
      final ok2 = await launchUrl(waWeb, mode: LaunchMode.externalApplication);
      if (!ok2) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('❌ $e')));
    }
  }

  Future<void> _copiarTextoPromo(BuildContext context,
      {required String texto}) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Texto copiado (incluye enlace a la app).'),
      ),
    );
  }

  Future<void> _whatsAppTodos(
    BuildContext context, {
    required String poolId,
    required String origen,
    required String destino,
    required DateTime fecha,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final resQ = await PoolRepo.pools
          .doc(poolId)
          .collection('reservas')
          .where('estado', whereIn: ['reservado', 'pagado']).get();
      if (resQ.docs.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Aun no hay pasajeros para contactar.')),
        );
        return;
      }

      final uids = resQ.docs
          .map((e) => (e.data()['uidCliente'] ?? '').toString())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      if (uids.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
              content: Text('No se encontraron telefonos de pasajeros.')),
        );
        return;
      }

      final userSnaps = await Future.wait(
        uids.map((uid) =>
            FirebaseFirestore.instance.collection('usuarios').doc(uid).get()),
      );
      final phones = userSnaps
          .map((s) => _cleanPhone((s.data()?['telefono'] ?? '').toString()))
          .where((p) => p.isNotEmpty)
          .toSet()
          .toList();
      if (phones.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
              content: Text('No hay telefonos validos para WhatsApp.')),
        );
        return;
      }

      final fechaTxt = fmtDiaMesHoraAmPm(fecha);
      final msg = Uri.encodeComponent(
        'Hola! Recordatorio de tu salida por cupos ($origen -> $destino). '
        'Salida: $fechaTxt. Por favor confirmar asistencia.',
      );
      final phonesCsv = phones.join(',');
      final waApp = Uri.parse('whatsapp://send?phone=$phonesCsv&text=$msg');
      final waWeb = Uri.parse('https://wa.me/$phonesCsv?text=$msg');
      final ok1 = await launchUrl(waApp, mode: LaunchMode.externalApplication);
      if (ok1) return;
      final ok2 = await launchUrl(waWeb, mode: LaunchMode.externalApplication);
      if (!ok2) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('❌ $e')));
    }
  }

  bool _puedeIniciar(Map<String, dynamic> d) {
    final estado = (d['estado'] ?? '').toString().trim().toLowerCase();
    if (estado == 'en_ruta' ||
        estado == 'cancelado' ||
        estado == 'finalizado') {
      return false;
    }
    final minC = ((d['minParaConfirmar'] ?? 0) as num).toInt();
    final cached = d['asientosFirmesSalida'];
    final firm = (cached != null
            ? (cached as num).toInt()
            : ((d['asientosPagados'] ?? 0) as num).toInt())
        .clamp(0, 1 << 30);
    if (firm <= 0) return false;
    if (minC > 0 && firm < minC) return false;
    final reservados = ((d['asientosReservados'] ?? 0) as num).toInt();
    if (reservados <= 0) return false;
    return true;
  }

  bool _puedeFinalizar(Map<String, dynamic> d) {
    return (d['estado'] ?? '').toString().trim().toLowerCase() == 'en_ruta';
  }

  bool _puedeCancelar(Map<String, dynamic> d) {
    return PoolRepo.giraPuedeCancelarseAntesDeIniciar(d);
  }

  bool _puedeEditarContenido(Map<String, dynamic> d) {
    final e = (d['estado'] ?? '').toString().trim().toLowerCase();
    return e != 'finalizado' &&
        e != 'cancelado' &&
        e != 'cancelado_por_admin';
  }

  Future<bool> _confirmarCancelarGira(
    BuildContext context,
    Map<String, dynamic> d,
  ) =>
      confirmarCancelarGiraSalida(context, d);

  Future<void> _operarPool(
    BuildContext context, {
    required String action,
    required String poolId,
  }) async {
    if (_accionEnCurso || !mounted) return;
    setState(() => _accionEnCurso = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (action == 'iniciar') {
        final preview = await PoolRepo.previewComisionAlIniciar(poolId);
        if (!context.mounted) return;
        final okIniciar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              preview.recaudoCentral
                  ? PoolsProductoCopy.accionConfirmarInicioCentralTitulo
                  : PoolsProductoCopy.accionConfirmarComision,
            ),
            content: Text(
              preview.recaudoCentral
                  ? PoolsProductoCopy.accionConfirmarInicioCentralCuerpo(
                      cuposFirmes: preview.cuposFirmesRai,
                      asientosEfectivo: preview.asientosEfectivo,
                      comisionEfectivoRd: preview.comisionEfectivoRd,
                      pctComision: preview.pctComision,
                    )
                  : '${PoolsProductoCopy.accionConfirmarComisionSub}.\n\n'
                      'Cupos firmes en RAI: ${preview.cuposFirmesRai}\n'
                      'Comisión estimada: RD\$ ${preview.comisionEstimadaRd.toStringAsFixed(0)} '
                      '(${preview.pctComision.toStringAsFixed(0)}% × esos asientos).\n'
                      '${preview.excesoDevolucionRd > 0.01 ? 'Se devuelve RD\$ ${preview.excesoDevolucionRd.toStringAsFixed(0)} de prepago apartado al publicar (apartado RD\$ ${preview.comisionReservadaRd.toStringAsFixed(0)}).\n' : ''}'
                      '${PoolsProductoCopy.ventasFueraNoCuentan}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Volver'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirmar'),
              ),
            ],
          ),
        );
        if (okIniciar != true) return;

        final r = await PoolRepo.iniciarViajePoolSeguro(poolId: poolId);
        if (r['recaudoCentral'] == true) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(PoolsProductoCopy.accionInicioCentralOk),
            ),
          );
        } else if (r['legacy'] != true) {
          final cr = (r['comisionReal'] as num?)?.toDouble();
          final ar = (r['asientosReales'] as num?)?.toInt() ?? 0;
          if (cr != null) {
            unawaited(AnalyticsRai.logGiraStarted(
              asientosReales: ar,
              comisionReal: cr,
            ));
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'Catálogo cerrado. Comisión RAI: RD\$ ${cr.toStringAsFixed(0)} '
                  '($ar cupo(s) en app).',
                ),
              ),
            );
          } else {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Catálogo cerrado. Comisión confirmada.'),
              ),
            );
          }
        } else {
          messenger.showSnackBar(
            const SnackBar(content: Text('Catálogo cerrado.')),
          );
        }
      } else if (action == 'finalizar') {
        final r = await PoolRepo.finalizarViajePoolSeguro(poolId: poolId);
        if (r['refundedAsCancel'] == true) {
          final dev = (r['comisionDevuelta'] as num?)?.toDouble() ?? 0;
          unawaited(AnalyticsRai.logGiraCanceled(
            motivo: 'finalize_sin_inicio',
            comisionDevuelta: dev,
          ));
        } else {
          unawaited(AnalyticsRai.logGiraCompleted());
        }
        final netoPend =
            (r['netoOrganizadorPendiente'] as num?)?.toDouble() ?? 0;
        if (r['recaudoCentral'] == true && netoPend > 0.01) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                PoolsProductoCopy.accionFinalizarCentralNetoPendiente,
              ),
            ),
          );
        } else {
          messenger.showSnackBar(
            const SnackBar(content: Text('Salida cerrada en RAI.')),
          );
        }
      } else if (action == 'cancelar') {
        const motivo = 'Cancelado por chofer';
        final r = await PoolRepo.cancelarViajePoolSeguro(
            poolId: poolId, motivo: motivo);
        final dev = (r['comisionDevuelta'] as num?)?.toDouble() ?? 0;
        unawaited(AnalyticsRai.logGiraCanceled(
          motivo: motivo,
          comisionDevuelta: dev,
        ));
        messenger.showSnackBar(
          const SnackBar(content: Text('Viaje cancelado')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      final String texto = msg.isNotEmpty
          ? msg
          : (e.code == 'internal'
              ? 'No se pudo cancelar la salida (error del servidor). '
                  'Reintenta en unos segundos o contactá soporte.'
              : e.code);
      messenger.showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _accionEnCurso = false);
    }
  }

  int _estadoRank(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'abierto' || s == 'preconfirmado' || s == 'confirmado') return 0;
    if (s == 'lleno' || s == 'activo') return 1;
    if (s == 'finalizado') return 2;
    if (s == 'cancelado') return 3;
    return 4;
  }

  DateTime _fechaFromDoc(Map<String, dynamic> d) {
    final raw = d['fechaSalida'] ?? d['fecha'] ?? d['fechaHora'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime(2100);
    return DateTime(2100);
  }

  int _sortTaxistaPools(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final ad = a.data();
    final bd = b.data();
    final er = _estadoRank((ad['estado'] ?? '').toString())
        .compareTo(_estadoRank((bd['estado'] ?? '').toString()));
    if (er != 0) return er;
    return _fechaFromDoc(ad).compareTo(_fechaFromDoc(bd));
  }

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    if (u == null) {
      return Scaffold(
        backgroundColor: isDark ? Colors.black : const Color(0xFFE8EAED),
        appBar: AppBar(
          title: const Text(PoolsProductoCopy.salidasMis),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Inicia sesión como conductor u organizador para ver tus salidas.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white70 : const Color(0xFF667085),
              ),
            ),
          ),
        ),
      );
    }

    final Color textPrimary = isDark ? Colors.white : const Color(0xFF101828);
    final Color textSecondary =
        isDark ? Colors.white70 : const Color(0xFF475467);
    final Color textMuted =
        isDark ? RaiDsColors.textMuted : const Color(0xFF667085);
    final Color accent = isDark ? RaiDsColors.neon : const Color(0xFF0F9D58);
    final Color scaffoldBg = isDark ? RaiDsColors.bg : const Color(0xFFE8EAED);
    final Color cardBg = isDark ? RaiDsColors.card : Colors.white;
    final Color cardBorder = isDark ? RaiDsColors.border : const Color(0xFFD0D5DD);
    final Color softFill = isDark ? RaiDsColors.cardElevated : const Color(0xFFEFF1F5);
    const double cardRadius = 20;

    void abrirPublicar() {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PoolsTaxistaCrear()),
      );
    }

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: RaiAppBar(
        title: PoolsProductoCopy.salidasMis,
        showBackWhenCanPop: true,
        centerTitle: true,
        actions: [
          if (!widget.embeddedInOrganizadorShell)
            IconButton(
              onPressed: abrirPublicar,
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Publicar salida',
            ),
        ],
      ),
      bottomNavigationBar: widget.embeddedInOrganizadorShell
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: AppButton(
                label: 'Publicar nueva ruta',
                icon: Icons.add_rounded,
                onPressed: abrirPublicar,
              ),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isDark)
            AppPoolTabBar(
              labels: const ['Mis rutas', 'Historial'],
              index: _tabController.index,
              onChanged: _tabController.animateTo,
            )
          else
            Material(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                labelColor: accent,
                unselectedLabelColor: textMuted,
                indicatorColor: accent,
                tabs: const [
                  Tab(text: 'Mis rutas'),
                  Tab(text: 'Historial'),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: PoolRepo.streamPoolsTaxista(ownerTaxistaId: u.uid),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Center(
                child: CircularProgressIndicator(color: accent),
              );
            }
            if (snap.hasError) {
              return Center(
                child: Text(
                  'No se pudieron cargar tus salidas por cupos.\n${snap.error}',
                  style: TextStyle(color: textMuted),
                  textAlign: TextAlign.center,
                ),
              );
            }
            final all = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
              snap.data?.docs ?? const [],
            )..sort(_sortTaxistaPools);
            final activas = all
                .where(
                  (e) => !_esHistorialEstado(
                    (e.data()['estado'] ?? '').toString(),
                  ),
                )
                .toList();
            final historial = all
                .where(
                  (e) => _esHistorialEstado(
                    (e.data()['estado'] ?? '').toString(),
                  ),
                )
                .toList();

            Widget lista(
              List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
              required String vacio,
              bool tipEditar = false,
            }) {
              if (docs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      vacio,
                      style: TextStyle(color: textMuted, height: 1.35),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              final tipOffset = tipEditar ? 1 : 0;
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemCount: docs.length + tipOffset,
                itemBuilder: (ctx, i) {
                  if (tipEditar && i == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'Al publicar una gira queda aquí con tu cuenta. '
                        'Usá «Editar y republicar» para cambiar destino, cupos, fotos o precio.',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    );
                  }
                  final doc = docs[i - tipOffset];
                  final d = doc.data();
                  final id = doc.id;

              final cap = ((d['capacidad'] ?? 0) as num).toInt();
              final occ = ((d['asientosReservados'] ?? 0) as num).toInt();
              final pag = ((d['asientosPagados'] ?? 0) as num).toInt();
              final fee = ((d['feePct'] ?? 0.0) as num).toDouble();
              final precio = (d['precioPorAsiento'] as num).toDouble();
              final ingresoAseg = ((d['montoPagado'] ?? 0.0) as num).toDouble();
              final ingresoProj = occ * precio;
              final neto = ingresoAseg * (1 - fee);
              final estado = (d['estado'] ?? '').toString();
              final tipo = (d['tipo'] ?? '').toString();
              final badgeLabelRaw =
                  (d['servicioBadge'] ?? d['tipo'] ?? '').toString();
              final badgeLabel = badgeLabelRaw.trim().isEmpty
                  ? 'GIRA'
                  : badgeLabelRaw.trim().toUpperCase();
              final confirmado = estado == 'confirmado';
              final fechaSalida = (d['fechaSalida'] as Timestamp).toDate();
              final paradas = _paradasOrdenadas(d);
              final puedeIniciar = _puedeIniciar(d);
              final puedeFinalizar = _puedeFinalizar(d);
              final puedeCancelar = _puedeCancelar(d);
              final puedeEditar = _puedeEditarContenido(d);
              final tieneAccionesPool =
                  puedeIniciar || puedeFinalizar || puedeCancelar;

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(cardRadius),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Origen: ${(d['origenTown'] ?? '').toString()}',
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Destino: ${(d['destino'] ?? '').toString()}',
                      style: TextStyle(
                        color: textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _tipoColor(tipo).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: _tipoColor(tipo).withValues(alpha: 0.55),
                            ),
                          ),
                          child: Text(
                            badgeLabel,
                            style: TextStyle(
                              color: _tipoColor(tipo),
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        if (confirmado)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Text(
                              'Confirmado',
                              style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Precio: RD\$ ${PoolRecaudoCentral.precioPorPersona(d).toStringAsFixed(0)} / pers',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fmtFechaHoraAmPm(
                        (d['fechaSalida'] as Timestamp).toDate(),
                        sep: '•',
                      ),
                      style: TextStyle(color: textSecondary),
                    ),
                    if (paradas.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: softFill,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Paradas programadas',
                              style: TextStyle(
                                color: textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ...List.generate(paradas.length, (idx) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text(
                                  '${idx + 1}. ${paradas[idx]}',
                                  style: TextStyle(color: textSecondary),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: cap == 0 ? 0 : (occ / cap).clamp(0, 1),
                              backgroundColor: isDark
                                  ? Colors.white12
                                  : const Color(0xFFE4E7EC),
                              color: accent,
                              minHeight: 8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$occ/$cap',
                          style: TextStyle(color: textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pagados: $pag  •  Ingreso asegurado: RD\$ ${ingresoAseg.toStringAsFixed(0)}',
                      style: TextStyle(color: textSecondary),
                    ),
                    if (PoolRecaudoCentral.esPoolCentral(d)) ...[
                      PoolRecaudoCentralTaxistaPanel(
                        poolData: d,
                        compact: true,
                      ),
                    ] else ...[
                      Text(
                        'Proyectado: RD\$ ${ingresoProj.toStringAsFixed(0)}  •  Payout neto: RD\$ ${neto.toStringAsFixed(0)}',
                        style: TextStyle(color: textSecondary),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Estado: $estado',
                          style: TextStyle(color: textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (puedeEditar)
                          TextButton.icon(
                            onPressed: _accionEnCurso
                                ? null
                                : () async {
                                    await Navigator.of(ctx).push<bool>(
                                      MaterialPageRoute<bool>(
                                        builder: (_) => PoolsGiraEditarContenido(
                                          poolId: id,
                                        ),
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Editar y republicar'),
                          ),
                        if (tieneAccionesPool)
                          PopupMenuButton<String>(
                            tooltip: 'Comisión / cerrar salida / cancelar',
                            enabled: !_accionEnCurso,
                            onSelected: (v) =>
                                _operarPool(ctx, action: v, poolId: id),
                            itemBuilder: (_) => [
                              if (puedeIniciar)
                                const PopupMenuItem(
                                  value: 'iniciar',
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      PoolsProductoCopy.accionConfirmarComision,
                                    ),
                                    subtitle: Text(
                                      PoolsProductoCopy.accionConfirmarComisionSub,
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              if (puedeFinalizar)
                                const PopupMenuItem(
                                  value: 'finalizar',
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(PoolsProductoCopy.accionCerrarEnRai),
                                    subtitle: Text(
                                      PoolsProductoCopy.accionCerrarEnRaiSub,
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                            ],
                            icon: _accionEnCurso
                                ? SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: accent,
                                    ),
                                  )
                                : const Icon(Icons.settings_suggest),
                          ),
                        if (puedeCancelar)
                          OutlinedButton.icon(
                            onPressed: _accionEnCurso
                                ? null
                                : () async {
                                    if (!await _confirmarCancelarGira(ctx, d)) {
                                      return;
                                    }
                                    if (!ctx.mounted) return;
                                    await _operarPool(
                                      ctx,
                                      action: 'cancelar',
                                      poolId: id,
                                    );
                                  },
                            icon: Icon(Icons.cancel_outlined,
                                color: Colors.orange.shade700),
                            label: Text(
                              'Cancelar salida',
                              style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        TextButton.icon(
                          onPressed: _accionEnCurso
                              ? null
                              : () async {
                                  await PoolRepo.limpiarReservasVencidas(id);
                                  if (!ctx.mounted) return;
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Las reservas vencidas se liberan solas cada ~15 min '
                                        '(servidor RAI). Si hace falta antes, esperá un momento.',
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.cleaning_services),
                          label: const Text('Limpiar vencidas'),
                        ),
                        TextButton.icon(
                          onPressed: _accionEnCurso
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          PoolsTaxistaReservas(poolId: id),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.people_alt_outlined),
                          label: const Text('Reservas'),
                        ),
                        TextButton.icon(
                          onPressed: () => _whatsAppTodos(
                            context,
                            poolId: id,
                            origen: (d['origenTown'] ?? '').toString(),
                            destino: (d['destino'] ?? '').toString(),
                            fecha: fechaSalida,
                          ),
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('WhatsApp a todos'),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            final cuposDisponibles = (cap - occ).clamp(0, cap);
                            final textoPromo = _buildPromoTexto(
                              d: d,
                              fechaSalida: fechaSalida,
                              paradas: paradas,
                              cuposDisponibles: cuposDisponibles,
                              poolId: id,
                            );
                            _compartirWhatsAppPromo(context, texto: textoPromo);
                          },
                          icon: const Icon(Icons.campaign_outlined),
                          label: const Text('Publicar por WhatsApp'),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            final cuposDisponibles = (cap - occ).clamp(0, cap);
                            final textoPromo = _buildPromoTexto(
                              d: d,
                              fechaSalida: fechaSalida,
                              paradas: paradas,
                              cuposDisponibles: cuposDisponibles,
                              poolId: id,
                            );
                            _copiarTextoPromo(context, texto: textoPromo);
                          },
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('Copiar texto para redes'),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            final cuposDisponibles = (cap - occ).clamp(0, cap);
                            final textoPromo = _buildPromoTexto(
                              d: d,
                              fechaSalida: fechaSalida,
                              paradas: paradas,
                              cuposDisponibles: cuposDisponibles,
                              poolId: id,
                            );
                            Share.share(
                              textoPromo,
                              subject: PoolsProductoCopy.promoTituloDefault,
                            );
                          },
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Publicar en redes'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
                },
              );
            }

            return TabBarView(
              controller: _tabController,
              children: [
                lista(
                  activas,
                  tipEditar: true,
                  vacio:
                      'No tienes salidas activas.\nPublicá una con + o «Publicar salida por cupos»; '
                      'quedará aquí para editarla.',
                ),
                lista(
                  historial,
                  vacio: 'Aún no hay salidas finalizadas o canceladas.',
                ),
              ],
            );
          },
            ),
          ),
        ],
      ),
    );
  }
}
