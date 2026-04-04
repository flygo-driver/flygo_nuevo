import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flygo_nuevo/servicios/pool_repo.dart';
import 'package:flygo_nuevo/servicios/pool_share_link.dart';
import 'package:flygo_nuevo/widgets/pool_promo_media.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'pools_cliente_detalle.dart';

class PoolsClienteLista extends StatefulWidget {
  final String tipo; // "todos" | "consular" | "tour" | "excursion"
  const PoolsClienteLista({super.key, this.tipo = 'todos'});

  @override
  State<PoolsClienteLista> createState() => _PoolsClienteListaState();
}

class _PoolsClienteListaState extends State<PoolsClienteLista> {
  final _towns = const [
    'Todos', 'Santo Domingo', 'Santiago', 'La Romana', 'Higüey', 'San Pedro', 'San Cristóbal'
  ];
  String _origenTown = 'Todos';
  late String _tipoFiltro;
  final _servicioCtrl = TextEditingController();
  String _filtroTexto = '';

  @override
  void initState() {
    super.initState();
    _tipoFiltro = widget.tipo.trim().isEmpty ? 'todos' : widget.tipo.trim().toLowerCase();
  }

  @override
  void dispose() {
    _servicioCtrl.dispose();
    super.dispose();
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

  bool _matchesServicio(Map<String, dynamic> d) {
    final q = _filtroTexto.trim().toLowerCase();
    if (q.isEmpty) return true;
    final tipo = (d['tipo'] ?? '').toString().toLowerCase();
    final badge = (d['servicioBadge'] ?? '').toString().toLowerCase();
    final agencia = (d['agenciaNombre'] ?? '').toString().toLowerCase();
    final destino = (d['destino'] ?? '').toString().toLowerCase();
    return tipo.contains(q) || badge.contains(q) || agencia.contains(q) || destino.contains(q);
  }

  bool _isEstadoVisible(String raw) {
    final s = raw.trim().toLowerCase();
    return s == 'abierto' ||
        s == 'preconfirmado' ||
        s == 'confirmado' ||
        s == 'activo' ||
        s == 'disponible' ||
        s == 'buscando';
  }

  bool _matchesTipo(Map<String, dynamic> d) {
    final f = _tipoFiltro.trim().toLowerCase();
    if (f.isEmpty || f == 'todos') return true;
    final tipo = (d['tipo'] ?? '').toString().trim().toLowerCase();
    if (f == 'tour') return tipo == 'tour' || tipo == 'tours' || tipo == 'gira' || tipo == 'giras';
    if (f == 'consular') return tipo == 'consular' || tipo == 'consulares';
    if (f == 'excursion') return tipo == 'excursion' || tipo == 'excursiones';
    return tipo == f;
  }

  DateTime _fechaSalida(Map<String, dynamic> d) {
    final raw = d['fechaSalida'] ?? d['fecha'] ?? d['fechaHora'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.fromMillisecondsSinceEpoch(0);
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
    required DateTime fecha,
    required int left,
    required double precioTotalPorSeat,
    required List<String> paradas,
    required String poolId,
  }) {
    final origen = (d['origenTown'] ?? '').toString().trim();
    final destino = (d['destino'] ?? '').toString().trim();
    final agencia = (d['agenciaNombre'] ?? '').toString().trim();
    final taxista = (d['taxistaNombre'] ?? '').toString().trim();
    final badge = (d['servicioBadge'] ?? d['tipo'] ?? 'Gira').toString().trim();
    final owner = agencia.isNotEmpty ? agencia : (taxista.isNotEmpty ? taxista : 'RAI Driver');
    final fechaTxt = DateFormat('EEE d MMM • HH:mm', 'es').format(fecha);
    final paradasTxt = paradas.isEmpty ? 'Sin paradas publicadas' : paradas.join(' | ');
    final base = '''
${badge.toUpperCase()}
Organiza: $owner
Ruta: $origen -> $destino
Salida: $fechaTxt
Precio por asiento: RD\$ ${precioTotalPorSeat.toStringAsFixed(0)}
Cupos disponibles: $left
Paradas: $paradasTxt

Reserva en RAI Driver desde la seccion "Giras / Tours por cupos".
#RAIDriver #Giras #Tours #Excursiones #ViajesPorCupos
'''.trim();
    return '$base${PoolShareLink.shareFooter(poolId)}';
  }

  Future<void> _abrirWhatsAppConTexto(String texto) async {
    try {
      final msg = Uri.encodeComponent(texto);
      final waApp = Uri.parse('whatsapp://send?text=$msg');
      final waWeb = Uri.parse('https://wa.me/?text=$msg');
      final ok1 = await launchUrl(waApp, mode: LaunchMode.externalApplication);
      if (ok1) return;
      final ok2 = await launchUrl(waWeb, mode: LaunchMode.externalApplication);
      if (!ok2 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
      }
    }
  }

  int _sortByAgencyAndDate(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final ad = a.data();
    final bd = b.data();
    int estadoRank(String raw) {
      final s = raw.trim().toLowerCase();
      if (s == 'abierto' || s == 'preconfirmado' || s == 'confirmado') return 0;
      if (s == 'activo' || s == 'disponible' || s == 'buscando') return 1;
      return 2;
    }

    final er = estadoRank((ad['estado'] ?? '').toString())
        .compareTo(estadoRank((bd['estado'] ?? '').toString()));
    if (er != 0) return er;

    final agenciaA = (ad['agenciaNombre'] ?? '').toString().trim().toLowerCase();
    final agenciaB = (bd['agenciaNombre'] ?? '').toString().trim().toLowerCase();
    final rankA = agenciaA.isEmpty ? 1 : 0;
    final rankB = agenciaB.isEmpty ? 1 : 0;
    if (rankA != rankB) return rankA.compareTo(rankB);

    final fechaA = _fechaSalida(ad);
    final fechaB = _fechaSalida(bd);
    final fr = fechaA.compareTo(fechaB);
    if (fr != 0) return fr;

    final ca = (ad['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2100);
    final cb = (bd['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2100);
    return ca.compareTo(cb);
  }

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('EEE d MMM • HH:mm', 'es');
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textPrimary = isDark ? Colors.white : const Color(0xFF101828);
    final Color textSecondary = isDark ? Colors.white70 : const Color(0xFF475467);
    final Color textMuted = isDark ? Colors.white54 : const Color(0xFF667085);
    final Color accent = isDark ? Colors.greenAccent : const Color(0xFF0F9D58);
    final Color scaffoldBg = isDark ? Colors.black : const Color(0xFFE8EAED);
    final Color ddBg = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final Color fieldFill = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF8FAFC);
    final Color fieldBorder = isDark ? Colors.white24 : const Color(0xFFD0D5DD);
    final Color cardBg = isDark ? const Color(0xFF121212) : Colors.white;
    final Color cardBgDest = isDark ? const Color(0xFF182018) : const Color(0xFFE8F7EE);
    final Color cardBorder = isDark ? Colors.white24 : const Color(0xFFD0D5DD);
    final Color softFill = isDark ? Colors.white10 : const Color(0xFFEFF1F5);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: textPrimary,
        elevation: isDark ? 0 : 0.5,
        title: Text(
          'Giras y viajes por cupos',
          style: TextStyle(color: accent, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Column(
              children: [
                Row(
                  children: [
                    Text('Pueblo:', style: TextStyle(color: textSecondary)),
                    const SizedBox(width: 10),
                    DropdownButton<String>(
                      value: _origenTown,
                      dropdownColor: ddBg,
                      underline: const SizedBox(),
                      style: TextStyle(color: textPrimary, fontSize: 16),
                      items: _towns
                          .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(t, style: TextStyle(color: textPrimary)),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _origenTown = v ?? _origenTown),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _servicioCtrl,
                  style: TextStyle(color: textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Buscar servicio/agencia',
                    hintText: 'Ej: Sol Caliente Tour, consular, excursion...',
                    labelStyle: TextStyle(color: textSecondary),
                    hintStyle: TextStyle(color: textMuted),
                    filled: true,
                    fillColor: fieldFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: fieldBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: accent, width: 2),
                    ),
                  ),
                  onChanged: (v) => setState(() => _filtroTexto = v),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final t in const ['todos', 'consular', 'tour', 'excursion'])
                      ChoiceChip(
                        selected: _tipoFiltro == t,
                        label: Text(t.toUpperCase()),
                        selectedColor: isDark ? Colors.white24 : accent.withValues(alpha: 0.2),
                        backgroundColor: isDark ? Colors.white10 : const Color(0xFFF2F4F7),
                        labelStyle: TextStyle(
                          color: _tipoFiltro == t
                              ? (isDark ? Colors.white : const Color(0xFF0B6B3A))
                              : textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) => setState(() => _tipoFiltro = t),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: PoolRepo.streamPoolsCliente(
                tipo: _tipoFiltro,
                origenTown: _origenTown,
              ),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: accent),
                  );
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'No se pudieron cargar las giras por cupos.',
                      style: TextStyle(color: textMuted),
                    ),
                  );
                }
                final now = DateTime.now();
                final docs = (snap.data?.docs ?? [])
                    .where((e) {
                      final d = e.data();
                      final fecha = _fechaSalida(d);
                      return _matchesServicio(d) &&
                          _matchesTipo(d) &&
                          _isEstadoVisible((d['estado'] ?? '').toString()) &&
                          fecha.isAfter(now.subtract(const Duration(minutes: 5)));
                    })
                    .toList()
                  ..sort(_sortByAgencyAndDate);
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No hay salidas próximas desde este pueblo.',
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

                    final cap = (d['capacidad'] ?? 0) as int;
                    final occ = (d['asientosReservados'] ?? 0) as int;
                    final estado = (d['estado'] ?? '').toString();
                    final precio = (d['precioPorAsiento'] as num).toDouble();
                    final mult = (d['sentido'] == 'ida_y_vuelta') ? 2 : 1;
                    final fecha = _fechaSalida(d);

                    final left = (cap - occ).clamp(0, cap);
                    final confirmado = estado == 'confirmado';
                    final tipo = (d['tipo'] ?? 'consular').toString();
                    final badgeLabelRaw =
                        (d['servicioBadge'] ?? d['tipo'] ?? '').toString().trim();
                    final badge = badgeLabelRaw.isEmpty ? tipo.toUpperCase() : badgeLabelRaw.toUpperCase();
                    final origen = (d['origenTown'] ?? '').toString().trim();
                    final destino = (d['destino'] ?? '').toString().trim();
                    final precioTxt = 'RD\$ ${(precio * mult).toStringAsFixed(0)} / pers';
                    final agenciaNombre = (d['agenciaNombre'] ?? '').toString().trim();
                    final agenciaLogoUrl = (d['agenciaLogoUrl'] ?? '').toString().trim();
                    final taxistaNombre = (d['taxistaNombre'] ?? '').toString().trim();
                    final bannerUrl = (d['bannerUrl'] ?? '').toString().trim();
                    final bannerVideoUrl = (d['bannerVideoUrl'] ?? '').toString().trim();
                    final marcaAgencia =
                        agenciaNombre.isNotEmpty || agenciaLogoUrl.isNotEmpty;
                    final destacada = marcaAgencia;
                    final paradas = _paradasOrdenadas(d);

                    return InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PoolsClienteDetalle(poolId: id),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: destacada ? cardBgDest : cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: destacada ? accent.withValues(alpha: .45) : cardBorder,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (bannerUrl.isNotEmpty || bannerVideoUrl.isNotEmpty) ...[
                              PoolPromoStrip(
                                bannerUrl: bannerUrl,
                                bannerVideoUrl: bannerVideoUrl,
                                title: '$origen -> $destino',
                                height: 150,
                                borderRadius: BorderRadius.circular(10),
                                textPrimary: textPrimary,
                                textMuted: textMuted,
                                softFill: softFill,
                              ),
                              const SizedBox(height: 10),
                            ],
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (marcaAgencia)
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: softFill,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: cardBorder),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: agenciaLogoUrl.isNotEmpty
                                        ? Image.network(
                                            agenciaLogoUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Icon(
                                              Icons.business,
                                              color: textSecondary,
                                            ),
                                          )
                                        : Icon(Icons.business, color: textSecondary),
                                  ),
                                if (marcaAgencia) const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Origen: $origen',
                                        style: TextStyle(
                                          color: textPrimary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Destino: $destino',
                                        style: TextStyle(
                                          color: textSecondary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (marcaAgencia) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          agenciaNombre.isNotEmpty
                                              ? agenciaNombre
                                              : (taxistaNombre.isNotEmpty
                                                  ? taxistaNombre
                                                  : 'Agencia / operador'),
                                          style: TextStyle(
                                            color: textSecondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (confirmado)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: .18),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: Colors.greenAccent.withValues(alpha: .5),
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
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _tipoColor(tipo).withValues(alpha: .18),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: _tipoColor(tipo).withValues(alpha: .5),
                                    ),
                                  ),
                                  child: Text(
                                    badge,
                                    style: TextStyle(
                                      color: _tipoColor(tipo),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(f.format(fecha),
                                style: TextStyle(color: textSecondary)),
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
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: textSecondary),
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: cap == 0 ? 0 : (occ / cap).clamp(0, 1),
                                      backgroundColor: isDark ? Colors.white12 : const Color(0xFFE4E7EC),
                                      color: accent,
                                      minHeight: 8,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('$occ/$cap',
                                    style: TextStyle(color: textSecondary)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text('Quedan $left cupos',
                                    style: TextStyle(color: textSecondary)),
                                const Spacer(),
                                Text(
                                  precioTxt,
                                  style: TextStyle(
                                      color: accent, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PoolsClienteDetalle(poolId: id),
                                        ),
                                      );
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: textPrimary,
                                      side: BorderSide(color: cardBorder),
                                    ),
                                    icon: const Icon(Icons.visibility_outlined, size: 18),
                                    label: const Text('Ver detalle'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PoolsClienteDetalle(poolId: id),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: accent,
                                      foregroundColor: isDark ? Colors.black : Colors.white,
                                    ),
                                    icon: const Icon(Icons.event_seat_outlined, size: 18),
                                    label: const Text('Reservar asiento'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                TextButton.icon(
                                  onPressed: () {
                                    final texto = _buildPromoTexto(
                                      d: d,
                                      fecha: fecha,
                                      left: left,
                                      precioTotalPorSeat: precio * mult,
                                      paradas: paradas,
                                      poolId: id,
                                    );
                                    Share.share(texto, subject: 'Gira por cupos');
                                  },
                                  icon: Icon(Icons.share_outlined, color: accent),
                                  label: Text('Publicar en redes', style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    final texto = _buildPromoTexto(
                                      d: d,
                                      fecha: fecha,
                                      left: left,
                                      precioTotalPorSeat: precio * mult,
                                      paradas: paradas,
                                      poolId: id,
                                    );
                                    _abrirWhatsAppConTexto(texto);
                                  },
                                  icon: Icon(Icons.chat, color: accent),
                                  label: Text('WhatsApp', style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
                                ),
                                TextButton.icon(
                                  onPressed: () async {
                                    final texto = _buildPromoTexto(
                                      d: d,
                                      fecha: fecha,
                                      left: left,
                                      precioTotalPorSeat: precio * mult,
                                      paradas: paradas,
                                      poolId: id,
                                    );
                                    await Clipboard.setData(ClipboardData(text: texto));
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Texto copiado (incluye enlace a la app).',
                                        ),
                                      ),
                                    );
                                  },
                                  icon: Icon(Icons.copy_outlined, color: accent),
                                  label: Text('Copiar texto', style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
