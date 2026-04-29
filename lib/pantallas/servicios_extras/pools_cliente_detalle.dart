import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flygo_nuevo/servicios/pool_repo.dart';
import 'package:flygo_nuevo/servicios/pool_share_link.dart';
import 'package:flygo_nuevo/widgets/pool_promo_media.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class PoolsClienteDetalle extends StatefulWidget {
  final String poolId;
  const PoolsClienteDetalle({super.key, required this.poolId});

  @override
  State<PoolsClienteDetalle> createState() => _PoolsClienteDetalleState();
}

class _PoolsClienteDetalleState extends State<PoolsClienteDetalle>
    with SingleTickerProviderStateMixin {
  int _seats = 1;
  String _metodo = 'transferencia'; // 'transferencia' | 'efectivo'
  bool _saving = false;
  late final AnimationController _marqueeCtrl;

  static const String _concepto = 'Deposito reserva de cupos';

  @override
  void initState() {
    super.initState();
    _marqueeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _marqueeCtrl.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _cleanPhone(String raw) {
    final v = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (v.startsWith('1') && v.length == 11) return v;
    if (v.length == 10) return '1$v';
    return v;
  }

  Future<void> _openCall(String phone) async {
    final p = _cleanPhone(phone);
    if (p.isEmpty) {
      _snack('Telefono no disponible.');
      return;
    }
    final uri = Uri.parse('tel:+$p');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _snack('No se pudo abrir llamada.');
  }

  Future<void> _openWhatsApp(String phone, String message) async {
    final p = _cleanPhone(phone);
    if (p.isEmpty) {
      _snack('WhatsApp no disponible.');
      return;
    }
    final msg = Uri.encodeComponent(message);
    final waApp = Uri.parse('whatsapp://send?phone=%2B$p&text=$msg');
    final waWeb = Uri.parse('https://wa.me/$p?text=$msg');
    final ok1 = await launchUrl(waApp, mode: LaunchMode.externalApplication);
    if (ok1) return;
    final ok2 = await launchUrl(waWeb, mode: LaunchMode.externalApplication);
    if (!ok2) _snack('No se pudo abrir WhatsApp.');
  }

  DateTime _dateFromAny(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
    return DateTime.now();
  }

  String _buildPromoTexto({
    required String origen,
    required String destino,
    required DateTime fecha,
    required String ownerLabel,
    required double precioTotalPorSeat,
    required int left,
    required List<String> pickupPoints,
    required String poolId,
  }) {
    final fechaTxt = DateFormat('EEE d MMM • HH:mm', 'es').format(fecha);
    final paradasTxt = pickupPoints.isEmpty
        ? 'Sin paradas publicadas'
        : pickupPoints.join(' | ');
    final base = '''
GIRA / EXCURSION POR CUPOS
Organiza: $ownerLabel
Ruta: $origen -> $destino
Salida: $fechaTxt
Precio por asiento: RD\$ ${precioTotalPorSeat.toStringAsFixed(0)}
Cupos disponibles: $left
Paradas: $paradasTxt

Reserva en RAI Driver desde la seccion "Giras / Tours por cupos".
#RAIDriver #Giras #Tours #Excursiones #ViajesPorCupos
'''
        .trim();
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
      if (!ok2) _snack('No se pudo abrir WhatsApp.');
    } catch (e) {
      _snack('❌ $e');
    }
  }

  Widget _anuncioLineal(BuildContext context, String texto) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? Colors.greenAccent : const Color(0xFF0F9D58);
    final marqueeText = '   $texto   •   ';
    return Container(
      width: double.infinity,
      height: 46,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.12 : 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return AnimatedBuilder(
              animation: _marqueeCtrl,
              builder: (_, __) {
                final width = constraints.maxWidth;
                final dx = width - (_marqueeCtrl.value * (width * 2));
                return Transform.translate(
                  offset: Offset(dx, 0),
                  child: SizedBox(
                    width: width * 3,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '$marqueeText$marqueeText$marqueeText',
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('EEE d MMM • HH:mm', 'es');
    final poolRef = PoolRepo.pools.doc(widget.poolId);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textPrimary = isDark ? Colors.white : const Color(0xFF101828);
    final Color textSecondary =
        isDark ? Colors.white70 : const Color(0xFF475467);
    final Color textMuted = isDark ? Colors.white60 : const Color(0xFF667085);
    final Color textFaint = isDark ? Colors.white38 : const Color(0xFF98A2B3);
    final Color accent = isDark ? Colors.greenAccent : const Color(0xFF0F9D58);
    final Color scaffoldBg = isDark ? Colors.black : const Color(0xFFE8EAED);
    final Color cardBg = isDark ? const Color(0xFF121212) : Colors.white;
    final Color cardBorder = isDark ? Colors.white24 : const Color(0xFFD0D5DD);
    final Color innerBg =
        isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF8FAFC);
    final Color innerBorder = isDark ? Colors.white12 : const Color(0xFFE4E7EC);
    final Color chipBg = isDark ? Colors.white12 : const Color(0xFFEFF1F5);
    final Color liftBlue =
        isDark ? Colors.lightBlueAccent : const Color(0xFF1570EF);
    final Color softFill = isDark ? Colors.white10 : const Color(0xFFEFF1F5);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: textPrimary,
        elevation: isDark ? 0 : 0.5,
        title: Text(
          'Detalle del viaje',
          style: TextStyle(color: accent, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: poolRef.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.data!.exists) {
            return Center(
                child: Text('El viaje no existe.',
                    style: TextStyle(color: textMuted)));
          }
          final d = snap.data!.data()!;
          final origen = (d['origenTown'] ?? '').toString();
          final destino = (d['destino'] ?? '').toString();
          final fecha =
              _dateFromAny(d['fechaSalida'] ?? d['fecha'] ?? d['fechaHora']);
          final fechaVuelta =
              d['fechaVuelta'] != null ? _dateFromAny(d['fechaVuelta']) : null;
          final sentido =
              (d['sentido'] ?? 'ida').toString(); // ida | vuelta | ida_y_vuelta
          final mult = (sentido == 'ida_y_vuelta') ? 2 : 1;

          final cap = (d['capacidad'] ?? 0) as int;
          final occ = (d['asientosReservados'] ?? 0) as int;
          final minConf = (d['minParaConfirmar'] ?? 0) as int;
          final estado = (d['estado'] ?? 'abierto')
              .toString(); // abierto | confirmado | cerrado
          final estadoL = estado.trim().toLowerCase();
          final left = (cap - occ).clamp(0, cap);
          final reservable = left > 0 &&
              estadoL != 'lleno' &&
              estadoL != 'en_ruta' &&
              (estadoL == 'abierto' ||
                  estadoL == 'preconfirmado' ||
                  estadoL == 'confirmado' ||
                  estadoL == 'activo' ||
                  estadoL == 'disponible' ||
                  estadoL == 'buscando');

          final precioSeat = ((d['precioPorAsiento'] ?? 0.0) as num).toDouble();
          final precioTotalPorSeat = precioSeat * mult;
          final depositPct =
              ((d['depositPct'] ?? 0.3) as num).toDouble().clamp(0, 1);
          // feePct eliminado porque no se usa aquí para evitar warning

          final pickupPoints = (d['pickupPoints'] is List)
              ? List<String>.from(d['pickupPoints'] as List)
              : <String>[];
          final pickup =
              pickupPoints.isNotEmpty ? pickupPoints.first : 'Parque Central';

          final titulo = '$origen → $destino';
          final confirmado = estado == 'confirmado';
          final agenciaNombre = (d['agenciaNombre'] ?? '').toString().trim();
          final taxistaNombre = (d['taxistaNombre'] ?? '').toString().trim();
          final ownerLabel = agenciaNombre.isNotEmpty
              ? agenciaNombre
              : (taxistaNombre.isNotEmpty ? taxistaNombre : 'Dueño del viaje');
          final agenciaLogoUrl = (d['agenciaLogoUrl'] ?? '').toString().trim();
          final bannerUrl = (d['bannerUrl'] ?? '').toString().trim();
          final bannerVideoUrl = (d['bannerVideoUrl'] ?? '').toString().trim();
          final choferTelefono = (d['choferTelefono'] ?? '').toString().trim();
          final choferWhatsApp = (d['choferWhatsApp'] ?? '').toString().trim();
          final bancoNombre = (d['bancoNombre'] ?? '').toString().trim();
          final bancoCuenta = (d['bancoCuenta'] ?? '').toString().trim();
          final bancoTipoCuenta =
              (d['bancoTipoCuenta'] ?? '').toString().trim();
          final bancoTitular = (d['bancoTitular'] ?? '').toString().trim();
          final bool bancoCompleto = bancoNombre.isNotEmpty &&
              bancoCuenta.isNotEmpty &&
              bancoTipoCuenta.isNotEmpty &&
              bancoTitular.isNotEmpty;
          final incluye = (d['incluye'] is List)
              ? List<String>.from(d['incluye'] as List)
              : <String>[];
          final descripcionViaje =
              (d['descripcionViaje'] ?? '').toString().trim();
          final fechaAnuncio =
              DateFormat('d MMM yyyy, h:mm a', 'es').format(fecha);
          final publicadoPor =
              agenciaNombre.isNotEmpty ? agenciaNombre : ownerLabel;
          final anuncioTexto =
              'Gira programada para $fechaAnuncio. No te lo pierdas. Reserva tu asiento ahora. Publicado por: $publicadoPor';

          // Totales con asientos seleccionados
          final total = (_seats * precioTotalPorSeat).toDouble();
          final deposito = (total * depositPct);
          final restante = (total - deposito);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (bannerUrl.isNotEmpty || bannerVideoUrl.isNotEmpty) ...[
                      PoolPromoStrip(
                        bannerUrl: bannerUrl,
                        bannerVideoUrl: bannerVideoUrl,
                        title: titulo,
                        height: 190,
                        borderRadius: BorderRadius.circular(12),
                        textPrimary: Colors.white,
                        textMuted: textFaint,
                        softFill: softFill,
                      ),
                      const SizedBox(height: 10),
                    ],
                    _anuncioLineal(context, anuncioTexto),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: Text(
                          titulo,
                          style: TextStyle(
                              color: textPrimary, fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (confirmado)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: accent.withValues(alpha: 0.5)),
                          ),
                          child: Text('Confirmado',
                              style: TextStyle(
                                  color: accent, fontWeight: FontWeight.w700)),
                        ),
                    ]),
                    if (agenciaNombre.isNotEmpty ||
                        agenciaLogoUrl.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: chipBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cardBorder),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: agenciaLogoUrl.isNotEmpty
                                ? Image.network(
                                    agenciaLogoUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Icon(
                                      Icons.business,
                                      size: 24,
                                      color: textSecondary,
                                    ),
                                  )
                                : Icon(Icons.business,
                                    size: 24, color: textSecondary),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  agenciaNombre.isNotEmpty
                                      ? agenciaNombre
                                      : ownerLabel,
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Publicado por: $ownerLabel',
                                  style: TextStyle(
                                    color: textMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (agenciaLogoUrl.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              width: 180,
                              height: 180,
                              color: softFill,
                              child: Image.network(
                                agenciaLogoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.business,
                                  size: 64,
                                  color: textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                    if (choferTelefono.isNotEmpty ||
                        choferWhatsApp.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (choferTelefono.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () => _openCall(choferTelefono),
                              icon: const Icon(Icons.call, size: 16),
                              label: const Text('Llamar chofer'),
                            ),
                          if (choferWhatsApp.isNotEmpty)
                            ElevatedButton.icon(
                              onPressed: () => _openWhatsApp(
                                choferWhatsApp,
                                'Hola, vi tu gira/viaje por cupos ($origen → $destino) y quiero confirmar detalles.',
                              ),
                              icon: const Icon(Icons.chat, size: 16),
                              label: const Text('WhatsApp chofer'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () async {
                            final texto = _buildPromoTexto(
                              origen: origen,
                              destino: destino,
                              fecha: fecha,
                              ownerLabel: ownerLabel,
                              precioTotalPorSeat: precioTotalPorSeat,
                              left: left,
                              pickupPoints: pickupPoints,
                              poolId: widget.poolId,
                            );
                            Share.share(texto, subject: 'Gira por cupos');
                          },
                          icon: const Icon(Icons.share_outlined, size: 16),
                          label: const Text('Publicar en redes'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark
                                ? const Color(0xFF7C4DFF)
                                : const Color(0xFF5E35B1),
                            foregroundColor: Colors.white,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            final texto = _buildPromoTexto(
                              origen: origen,
                              destino: destino,
                              fecha: fecha,
                              ownerLabel: ownerLabel,
                              precioTotalPorSeat: precioTotalPorSeat,
                              left: left,
                              pickupPoints: pickupPoints,
                              poolId: widget.poolId,
                            );
                            _abrirWhatsAppConTexto(texto);
                          },
                          icon: const Icon(Icons.chat, size: 16),
                          label: const Text('WhatsApp (enlace)'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final texto = _buildPromoTexto(
                              origen: origen,
                              destino: destino,
                              fecha: fecha,
                              ownerLabel: ownerLabel,
                              precioTotalPorSeat: precioTotalPorSeat,
                              left: left,
                              pickupPoints: pickupPoints,
                              poolId: widget.poolId,
                            );
                            await Clipboard.setData(ClipboardData(text: texto));
                            if (!mounted) return;
                            _snack(
                              'Texto copiado (incluye enlace a la app).',
                            );
                          },
                          icon: const Icon(Icons.copy_outlined, size: 16),
                          label: const Text('Copiar texto'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fechaVuelta == null
                          ? f.format(fecha)
                          : '${f.format(fecha)}  •  Vuelta: ${f.format(fechaVuelta)}',
                      style: TextStyle(color: textSecondary),
                    ),
                    const SizedBox(height: 6),
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
                        Text('$occ/$cap',
                            style: TextStyle(color: textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Punto de encuentro: $pickup',
                        style: TextStyle(color: textSecondary)),
                    Text('Quedan $left cupos',
                        style: TextStyle(color: textSecondary)),
                    if (minConf > 0)
                      Text('Mínimo para confirmar: $minConf',
                          style: TextStyle(color: textFaint)),
                    if (!reservable) ...[
                      const SizedBox(height: 6),
                      Text(
                        estadoL == 'cancelado'
                            ? 'Este viaje fue cancelado por la agencia/chofer.'
                            : estadoL == 'finalizado'
                                ? 'Este viaje ya finalizó.'
                                : estadoL == 'en_ruta'
                                    ? 'Este viaje está en curso. Ya no aparece en el listado público de cupos.'
                                    : estadoL == 'lleno' || left == 0
                                        ? 'Cupos completos. No hay asientos disponibles.'
                                        : 'Este viaje no está disponible para reservas.',
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ],
                    if (incluye.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Todo lo que incluye este tipo de viaje:',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: incluye
                            .map((e) => Chip(
                                  label: Text(e,
                                      style: TextStyle(color: textPrimary)),
                                  backgroundColor: chipBg,
                                ))
                            .toList(),
                      ),
                    ],
                    if (descripcionViaje.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Plan del viaje y que debes llevar:',
                        style: TextStyle(
                          color: liftBlue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        descripcionViaje,
                        style: TextStyle(color: textSecondary),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Selector de asientos
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cardBorder),
                ),
                child: Row(
                  children: [
                    Text('Asientos', style: TextStyle(color: textSecondary)),
                    const Spacer(),
                    IconButton(
                      onPressed:
                          (_seats > 1) ? () => setState(() => _seats--) : null,
                      icon: Icon(Icons.remove_circle_outline,
                          color: textSecondary),
                    ),
                    Text('$_seats',
                        style: TextStyle(
                            color: textPrimary, fontWeight: FontWeight.w800)),
                    IconButton(
                      onPressed: (_seats < left)
                          ? () => setState(() => _seats++)
                          : null,
                      icon:
                          Icon(Icons.add_circle_outline, color: textSecondary),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Precio / Depósito
              Container(
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
                        'Precio por persona: RD\$ ${precioTotalPorSeat.toStringAsFixed(0)}',
                        style: TextStyle(color: textSecondary)),
                    const SizedBox(height: 4),
                    Text('Total: RD\$ ${total.toStringAsFixed(0)}',
                        style: TextStyle(
                            color: textPrimary, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                        'Depósito ($ownerLabel): RD\$ ${deposito.toStringAsFixed(0)}',
                        style: TextStyle(
                            color: accent, fontWeight: FontWeight.w900)),
                    Text(
                        'Resto al abordar: RD\$ ${restante.toStringAsFixed(0)}',
                        style: TextStyle(color: textSecondary)),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Método de pago
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Método de pago',
                        style: TextStyle(color: textSecondary)),
                    const SizedBox(height: 8),
                    RadioListTile<String>(
                      value: 'transferencia',
                      groupValue: _metodo,
                      onChanged: (v) =>
                          setState(() => _metodo = v ?? 'transferencia'),
                      activeColor: accent,
                      title: Text('Transferencia bancaria (Chofer/Agencia)',
                          style: TextStyle(color: textPrimary)),
                      subtitle: Text('Pagar depósito por transferencia',
                          style: TextStyle(color: textMuted)),
                    ),
                    if (_metodo == 'transferencia') ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: innerBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: innerBorder),
                        ),
                        child: bancoCompleto
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cuenta para deposito (30%)',
                                    style: TextStyle(
                                      color: accent,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _bankRow(context, 'Banco', bancoNombre),
                                  _bankRow(
                                      context, 'No. de cuenta', bancoCuenta),
                                  _bankRow(context, 'Tipo de cuenta',
                                      bancoTipoCuenta),
                                  _bankRow(context, 'Titular', bancoTitular),
                                ],
                              )
                            : const Text(
                                'El chofer/agencia aun no cargo cuenta bancaria para transferencia.',
                                style: TextStyle(color: Colors.orangeAccent),
                              ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (choferWhatsApp.isNotEmpty)
                            ElevatedButton.icon(
                              onPressed: () => _openWhatsApp(
                                choferWhatsApp,
                                'Hola, quiero confirmar pago/depósito de mi cupo para $origen -> $destino.',
                              ),
                              icon: const Icon(Icons.chat, size: 16),
                              label: const Text('WhatsApp dueño del viaje'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            )
                          else if (choferTelefono.isNotEmpty)
                            ElevatedButton.icon(
                              onPressed: () => _openWhatsApp(
                                choferTelefono,
                                'Hola, quiero confirmar pago/depósito de mi cupo para $origen -> $destino.',
                              ),
                              icon: const Icon(Icons.chat, size: 16),
                              label: const Text('WhatsApp dueño del viaje'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ],
                    RadioListTile<String>(
                      value: 'efectivo',
                      groupValue: _metodo,
                      onChanged: (v) =>
                          setState(() => _metodo = v ?? 'transferencia'),
                      activeColor: accent,
                      title: Text('Efectivo al abordar',
                          style: TextStyle(color: textPrimary)),
                      subtitle: Text('Pagas el total el día del viaje',
                          style: TextStyle(color: textMuted)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Botón reservar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_saving || left == 0 || !reservable)
                      ? null
                      : () => _reservar(
                            seats: _seats,
                            total: total,
                            deposito: deposito,
                            restante: restante,
                            metodo: _metodo,
                            origen: origen,
                            destino: destino,
                            choferWhatsApp: choferWhatsApp,
                            bancoNombre: bancoNombre,
                            bancoCuenta: bancoCuenta,
                            bancoTipoCuenta: bancoTipoCuenta,
                            bancoTitular: bancoTitular,
                          ),
                  icon: const Icon(Icons.event_seat),
                  label: Text(_saving ? 'Reservando…' : 'Reservar asientos'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Nota de confianza
              Text(
                bancoCompleto
                    ? 'Haz el deposito al chofer/agencia y envia el bauche por WhatsApp para confirmar tu asiento.'
                    : 'Este viaje no tiene cuenta bancaria completa. Contacta al dueño del viaje por telefono/WhatsApp.',
                style: TextStyle(color: textFaint),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _reservar({
    required int seats,
    required double total,
    required double deposito,
    required double restante,
    required String metodo,
    required String origen,
    required String destino,
    required String choferWhatsApp,
    required String bancoNombre,
    required String bancoCuenta,
    required String bancoTipoCuenta,
    required String bancoTitular,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Debes iniciar sesión.');
      return;
    }
    if (seats <= 0) {
      _snack('Asientos inválidos.');
      return;
    }

    setState(() => _saving = true);
    try {
      await PoolRepo.reservarCupos(
        poolId: widget.poolId,
        seats: seats,
        metodoPago: metodo,
      );

      if (!mounted) return;

      if (metodo == 'transferencia') {
        if (bancoNombre.trim().isEmpty ||
            bancoCuenta.trim().isEmpty ||
            bancoTipoCuenta.trim().isEmpty ||
            bancoTitular.trim().isEmpty) {
          _snack('Este viaje no tiene datos bancarios completos.');
          return;
        }
        _mostrarInstruccionesTransferencia(
          deposito,
          origen: origen,
          destino: destino,
          choferWhatsApp: choferWhatsApp,
          bancoNombre: bancoNombre,
          bancoCuenta: bancoCuenta,
          bancoTipoCuenta: bancoTipoCuenta,
          bancoTitular: bancoTitular,
        );
      } else {
        _snack('Reserva creada. Paga en efectivo al abordar.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      _snack('❌ $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _mostrarInstruccionesTransferencia(
    double deposito, {
    required String origen,
    required String destino,
    required String choferWhatsApp,
    required String bancoNombre,
    required String bancoCuenta,
    required String bancoTipoCuenta,
    required String bancoTitular,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final textPrimary = isDark ? Colors.white : const Color(0xFF101828);
        final textMuted = isDark ? Colors.white60 : const Color(0xFF667085);
        final accent = isDark ? Colors.greenAccent : const Color(0xFF059669);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Deposito para reservar',
                    style: TextStyle(
                        color: accent,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _bankRow(sheetContext, 'Banco', bancoNombre),
                _bankRow(sheetContext, 'No. de cuenta', bancoCuenta),
                _bankRow(sheetContext, 'Tipo de cuenta', bancoTipoCuenta),
                _bankRow(sheetContext, 'Titular', bancoTitular),
                _bankRow(sheetContext, 'Concepto', _concepto),
                const SizedBox(height: 10),
                Text('Monto del depósito: RD\$ ${deposito.toStringAsFixed(0)}',
                    style: TextStyle(
                        color: textPrimary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Text(
                  'Cuando hagas el deposito, envia el bauche por WhatsApp al chofer/agencia para validar tu cupo.',
                  style: TextStyle(color: textMuted),
                ),
                const SizedBox(height: 16),
                if (choferWhatsApp.trim().isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _openWhatsApp(
                        choferWhatsApp,
                        'Hola, acabo de reservar cupo para $origen -> $destino.\n'
                        'Asientos: $_seats\n'
                        'Monto deposito: RD\$ ${deposito.toStringAsFixed(0)}\n'
                        'Te envio el bauche para confirmar mi reserva.',
                      ),
                      icon: const Icon(Icons.chat),
                      label: const Text('Enviar bauche por WhatsApp'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                if (choferWhatsApp.trim().isNotEmpty)
                  const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Navigator.pop(context, true);
                      _snack(
                          'Reserva creada. Revisa tu historial para ver el estado.');
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Entendido'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bankRow(BuildContext context, String k, String v) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? Colors.white54 : const Color(0xFF667085);
    final valueColor = isDark ? Colors.white : const Color(0xFF101828);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
              width: 130, child: Text(k, style: TextStyle(color: labelColor))),
          Expanded(child: Text(v, style: TextStyle(color: valueColor))),
        ],
      ),
    );
  }
}
