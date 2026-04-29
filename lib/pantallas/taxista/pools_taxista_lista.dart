import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flygo_nuevo/servicios/pool_repo.dart';
import 'package:flygo_nuevo/servicios/pool_share_link.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'pools_taxista_reservas.dart';
import 'pools_taxista_crear.dart';

class PoolsTaxistaLista extends StatefulWidget {
  const PoolsTaxistaLista({super.key});

  @override
  State<PoolsTaxistaLista> createState() => _PoolsTaxistaListaState();
}

class _PoolsTaxistaListaState extends State<PoolsTaxistaLista> {
  bool _accionEnCurso = false;
  bool _esActivoVisible(Map<String, dynamic> d) {
    final estado = (d['estado'] ?? '').toString().trim().toLowerCase();
    return estado != 'cancelado' && estado != 'finalizado';
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
    final fechaTxt = DateFormat('EEE d MMM • HH:mm', 'es').format(fechaSalida);
    final paradasTxt =
        paradas.isEmpty ? 'Sin paradas publicadas' : paradas.join(' | ');
    final quien = agencia.isNotEmpty
        ? agencia
        : (taxistaNombre.isNotEmpty ? taxistaNombre : 'RAI Driver');
    final titulo = badge.isNotEmpty ? badge : 'Viaje por cupos';

    final base = '''
${titulo.toUpperCase()}
Organiza: $quien
Ruta: $origen -> $destino
Salida: $fechaTxt
Precio por asiento: RD\$ ${precio.toStringAsFixed(0)}
Cupos disponibles: $cuposDisponibles
Paradas: $paradasTxt

Reserva en RAI Driver desde la seccion "Giras / Tours por cupos".
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

      final fechaTxt = DateFormat('d MMM, HH:mm', 'es').format(fecha);
      final msg = Uri.encodeComponent(
        'Hola! Recordatorio de la gira/viaje por cupos $origen -> $destino. '
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
    final estado = (d['estado'] ?? '').toString().trim().toLowerCase();
    return estado != 'finalizado' && estado != 'cancelado';
  }

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
        await PoolRepo.iniciarViajePoolSeguro(poolId: poolId);
        messenger.showSnackBar(
          const SnackBar(content: Text('Viaje iniciado')),
        );
      } else if (action == 'finalizar') {
        await PoolRepo.finalizarViajePoolSeguro(poolId: poolId);
        messenger.showSnackBar(
          const SnackBar(content: Text('Viaje finalizado')),
        );
      } else if (action == 'cancelar') {
        await PoolRepo.cancelarViajePoolSeguro(
            poolId: poolId, motivo: 'Cancelado por chofer');
        messenger.showSnackBar(
          const SnackBar(content: Text('Viaje cancelado')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      messenger.showSnackBar(
        SnackBar(
          content: Text(msg.isNotEmpty ? msg : e.code),
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
    final f = DateFormat('EEE d MMM • HH:mm', 'es');
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textPrimary = isDark ? Colors.white : const Color(0xFF101828);
    final Color textSecondary =
        isDark ? Colors.white70 : const Color(0xFF475467);
    final Color textMuted = isDark ? Colors.white60 : const Color(0xFF667085);
    final Color accent = isDark ? Colors.greenAccent : const Color(0xFF0F9D58);
    final Color scaffoldBg = isDark ? Colors.black : const Color(0xFFE8EAED);
    final Color cardBg = isDark ? const Color(0xFF121212) : Colors.white;
    final Color cardBorder = isDark ? Colors.white24 : const Color(0xFFD0D5DD);
    final Color softFill = isDark ? Colors.white10 : const Color(0xFFEFF1F5);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: textPrimary,
        elevation: isDark ? 0 : 0.5,
        title: Text(
          'Mis viajes por cupos',
          style: TextStyle(
            color: accent,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PoolsTaxistaCrear()),
            ),
            icon: const Icon(Icons.add),
            tooltip: 'Crear viaje',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: PoolRepo.streamPoolsTaxista(ownerTaxistaId: u!.uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: accent),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Text(
                'No se pudo cargar tus viajes por cupos.\n${snap.error}',
                style: TextStyle(color: textMuted),
                textAlign: TextAlign.center,
              ),
            );
          }
          final docs = (snap.data?.docs ?? [])
              .where((e) => _esActivoVisible(e.data()))
              .toList()
            ..sort(_sortTaxistaPools);
          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No tienes viajes activos por cupos.',
                style: TextStyle(color: textMuted),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final d = docs[i].data();
              final id = docs[i].id;

              final cap = ((d['capacidad'] ?? 0) as num).toInt();
              final occ = ((d['asientosReservados'] ?? 0) as num).toInt();
              final pag = ((d['asientosPagados'] ?? 0) as num).toInt();
              final fee = ((d['feePct'] ?? 0.0) as num).toDouble();
              final precio = (d['precioPorAsiento'] as num).toDouble();
              final mult = (d['sentido'] == 'ida_y_vuelta') ? 2 : 1;
              final ingresoAseg = ((d['montoPagado'] ?? 0.0) as num).toDouble();
              final ingresoProj = occ * precio * mult;
              final neto = ingresoAseg * (1 - fee);
              final estado = (d['estado'] ?? '').toString();
              final tipo = (d['tipo'] ?? 'consular').toString();
              final badgeLabelRaw =
                  (d['servicioBadge'] ?? d['tipo'] ?? 'consular').toString();
              final badgeLabel = badgeLabelRaw.trim().isEmpty
                  ? 'CONSULAR'
                  : badgeLabelRaw.trim().toUpperCase();
              final confirmado = estado == 'confirmado';
              final fechaSalida = (d['fechaSalida'] as Timestamp).toDate();
              final paradas = _paradasOrdenadas(d);
              final puedeIniciar = _puedeIniciar(d);
              final puedeFinalizar = _puedeFinalizar(d);
              final puedeCancelar = _puedeCancelar(d);
              final tieneAccionesPool =
                  puedeIniciar || puedeFinalizar || puedeCancelar;

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
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
                    const SizedBox(height: 4),
                    Text(
                      f.format((d['fechaSalida'] as Timestamp).toDate()),
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
                    Text(
                      'Proyectado: RD\$ ${ingresoProj.toStringAsFixed(0)}  •  Payout neto: RD\$ ${neto.toStringAsFixed(0)}',
                      style: TextStyle(color: textSecondary),
                    ),
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
                        if (tieneAccionesPool)
                          PopupMenuButton<String>(
                            tooltip: 'Iniciar / finalizar / cancelar',
                            enabled: !_accionEnCurso,
                            onSelected: (v) =>
                                _operarPool(ctx, action: v, poolId: id),
                            itemBuilder: (_) => [
                              if (puedeIniciar)
                                const PopupMenuItem(
                                  value: 'iniciar',
                                  child: Text('Iniciar viaje'),
                                ),
                              if (puedeFinalizar)
                                const PopupMenuItem(
                                  value: 'finalizar',
                                  child: Text('Finalizar viaje'),
                                ),
                              if (puedeCancelar)
                                const PopupMenuItem(
                                  value: 'cancelar',
                                  child: Text('Cancelar viaje'),
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
                        TextButton.icon(
                          onPressed: _accionEnCurso
                              ? null
                              : () async {
                                  final n =
                                      await PoolRepo.limpiarReservasVencidas(
                                          id);
                                  if (!ctx.mounted) return;
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Reservas vencidas limpiadas: $n',
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
                            Share.share(textoPromo, subject: 'Viaje por cupos');
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
        },
      ),
    );
  }
}
