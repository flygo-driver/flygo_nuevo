import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flygo_nuevo/config/recarga_bancaria_config.dart';
import 'package:flygo_nuevo/servicios/cliente_verificacion_identidad_service.dart';
import 'package:flygo_nuevo/servicios/pool_repo.dart';
import 'package:flygo_nuevo/servicios/pool_share_link.dart';
import 'package:flygo_nuevo/utils/pool_gira_banner_urls.dart';
import 'package:flygo_nuevo/utils/pool_gira_contenido.dart';
import 'package:flygo_nuevo/utils/pool_recaudo_central.dart';
import 'package:flygo_nuevo/utils/pools_producto_copy.dart';
import 'package:flygo_nuevo/widgets/pool_gira_contenido_panel.dart';
import 'package:flygo_nuevo/widgets/pool_promo_media.dart';
import 'package:flygo_nuevo/widgets/pool_reserva_bauche_uploader.dart';
import 'package:flygo_nuevo/pantallas/servicios_extras/pool_gira_ticket_page.dart';
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
  static const Color _kGiraFondo = Color(0xFF000000);
  static const Color _kGiraPanel = Color(0xFF0A0A0A);
  static const Color _kGiraBorde = Color(0xFFF59E0B);

  int _seats = 1;
  String _metodo = 'transferencia'; // 'transferencia' | 'efectivo'
  bool _saving = false;
  String? _cancelandoReservaId;
  bool _yaCerroPorCancelacionGira = false;
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

  String _sentidoLegible(String sentido) {
    switch (sentido.trim().toLowerCase()) {
      case 'ida_y_vuelta':
        return 'Ida y vuelta';
      case 'vuelta':
        return 'Solo vuelta';
      default:
        return 'Solo ida';
    }
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

Reserva en RAI Driver: giras, excursiones y viajes en grupo por cupos.
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

  BoxDecoration _panelGira({double radius = 16, double borderWidth = 1.5}) {
    return BoxDecoration(
      color: _kGiraPanel,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _kGiraBorde, width: borderWidth),
    );
  }

  Widget _metodoTile({
    required String value,
    required String title,
    required String subtitle,
    required String groupValue,
    required ValueChanged<String> onChanged,
  }) {
    final selected = value == groupValue;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? _kGiraBorde.withValues(alpha: 0.14) : const Color(0xFF141414),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _kGiraBorde : Colors.white12,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? _kGiraBorde : Colors.white54,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                      height: 1.35,
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

  Widget _anuncioLineal(BuildContext context, String texto) {
    final marqueeText = '   $texto   •   ';
    return Container(
      width: double.infinity,
      height: 46,
      decoration: _panelGira(radius: 12),
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
                        style: const TextStyle(
                          color: _kGiraBorde,
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
    final poolRef = PoolRepo.pools.doc(widget.poolId);
    const Color textPrimary = Colors.white;
    const Color textSecondary = Color(0xFFE5E7EB);
    const Color textMuted = Color(0xFF9CA3AF);
    const Color textFaint = Color(0xFF6B7280);
    const Color accent = Color(0xFF4ADE80);
    const Color softFill = Color(0xFF141414);

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: _kGiraFondo,
        dividerColor: _kGiraBorde.withValues(alpha: 0.35),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: _kGiraBorde),
          ),
        ),
      ),
      child: Scaffold(
      backgroundColor: _kGiraFondo,
      appBar: AppBar(
        backgroundColor: _kGiraFondo,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(height: 2, color: _kGiraBorde),
        ),
        title: const Text(
          'Detalle del viaje',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
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
            return const Center(
                child: Text('El viaje no existe.',
                    style: TextStyle(color: textMuted)));
          }
          final d = snap.data!.data()!;
          final estadoL = (d['estado'] ?? 'abierto').toString().trim().toLowerCase();
          if (PoolRepo.giraEstadoOcultoEnListados(estadoL) &&
              (estadoL == 'cancelado' || estadoL == 'cancelado_por_admin')) {
            if (!_yaCerroPorCancelacionGira) {
              _yaCerroPorCancelacionGira = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final nav = Navigator.of(context);
                if (nav.canPop()) {
                  nav.pop();
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Esta salida fue cancelada por el operador. Ya no está disponible.',
                    ),
                  ),
                );
              });
            }
            return const Center(
              child: Text(
                'Salida cancelada',
                style: TextStyle(color: textMuted),
              ),
            );
          }
          final origen = (d['origenTown'] ?? '').toString();
          final destino = (d['destino'] ?? '').toString();
          final fecha =
              _dateFromAny(d['fechaSalida'] ?? d['fecha'] ?? d['fechaHora']);
          final fechaVuelta =
              d['fechaVuelta'] != null ? _dateFromAny(d['fechaVuelta']) : null;
          final sentido =
              (d['sentido'] ?? 'ida').toString(); // ida | vuelta | ida_y_vuelta

          final cap = (d['capacidad'] ?? 0) as int;
          final occ = (d['asientosReservados'] ?? 0) as int;
          final minConf = (d['minParaConfirmar'] ?? 0) as int;
          final estado = (d['estado'] ?? 'abierto').toString();
          // estadoL ya calculado arriba (reutilizar para reservable / mensajes)
          final left = (cap - occ).clamp(0, cap);
          final reservable = left > 0 &&
              estadoL != 'cancelado' &&
              estadoL != 'cancelado_por_admin' &&
              estadoL != 'lleno' &&
              estadoL != 'en_ruta' &&
              (estadoL == 'abierto' ||
                  estadoL == 'preconfirmado' ||
                  estadoL == 'confirmado' ||
                  estadoL == 'activo' ||
                  estadoL == 'disponible' ||
                  estadoL == 'buscando');

          final precioTotalPorSeat = PoolRecaudoCentral.precioPorPersona(d);
          final depositPct =
              ((d['depositPct'] ?? 0.3) as num).toDouble().clamp(0, 1);
          // feePct eliminado porque no se usa aquí para evitar warning

          final pickupPoints = (d['pickupPoints'] is List)
              ? List<String>.from(d['pickupPoints'] as List)
              : <String>[];
          final pickup =
              pickupPoints.isNotEmpty ? pickupPoints.first : 'Parque Central';

          final confirmado = estado == 'confirmado';
          final agenciaNombre = (d['agenciaNombre'] ?? '').toString().trim();
          final taxistaNombre = (d['taxistaNombre'] ?? '').toString().trim();
          final ownerLabel = agenciaNombre.isNotEmpty
              ? agenciaNombre
              : (taxistaNombre.isNotEmpty ? taxistaNombre : 'Dueño del viaje');
          final agenciaLogoUrl = (d['agenciaLogoUrl'] ?? '').toString().trim();
          final bannerUrls = PoolGiraBannerUrls.fromPool(d);
          final bannerUrl = PoolGiraBannerUrls.primary(d);
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
          final contenidoExtra = PoolGiraContenidoExtra.fromMap(d);
          final nombreGira = contenidoExtra.nombreGira.trim();
          final maxAsientosCompra = contenidoExtra.maxAsientosPorCompra.clamp(1, cap);
          final estadoCliente = PoolGiraContenidoCatalog.estadoGiraCliente(
            estado: estadoL,
            cuposDisponibles: left,
            capacidad: cap,
          );
          final ultimosCupos =
              PoolGiraContenidoCatalog.esUltimosCupos(left, cap);
          final fechaLineas = PoolGiraContenidoCatalog.lineasFechaSalidaRegreso(
            salida: fecha,
            regreso: fechaVuelta,
          );
          final titulo = nombreGira.isNotEmpty
              ? nombreGira
              : '$origen → $destino';
          final total = (_seats * precioTotalPorSeat).toDouble();
          final deposito = (total * depositPct);
          final restante = (total - deposito);
          final esCentral = PoolRecaudoCentral.esPoolCentral(d);
          final pctComision = PoolRecaudoCentral.pctComisionPool(
            d,
            fallbackPct: 10,
          );
          final desgloseCentral = PoolRecaudoCentral.desgloseReserva(
            pool: d,
            asientos: _seats,
            pctComision: pctComision,
          );
          final montoClienteCentral = PoolRecaudoCentral.montoRecaudoCliente(
            pool: d,
            totalReserva: total,
          );
          final fechaAnuncio =
              DateFormat('d MMM yyyy, h:mm a', 'es').format(fecha);
          final publicadoPor =
              agenciaNombre.isNotEmpty ? agenciaNombre : ownerLabel;
          final anuncioTexto =
              'Salida programada para $fechaAnuncio. Reserva tu cupo. Publicado por: $publicadoPor';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: _panelGira(borderWidth: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (agenciaLogoUrl.isNotEmpty ||
                        agenciaNombre.isNotEmpty) ...[
                      Center(
                        child: PoolAgencyLogoHeader(
                          logoUrl: agenciaLogoUrl,
                          title: agenciaNombre.isNotEmpty
                              ? agenciaNombre
                              : ownerLabel,
                          accent: _kGiraBorde,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (bannerUrls.isNotEmpty || bannerVideoUrl.isNotEmpty) ...[
                      Container(
                        decoration: BoxDecoration(
                          color: _kGiraFondo,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _kGiraBorde, width: 2),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: PoolPromoStrip(
                          bannerUrl: bannerUrl,
                          bannerUrls: bannerUrls,
                          bannerVideoUrl: bannerVideoUrl,
                          title: titulo,
                          height: 340,
                          borderRadius: BorderRadius.circular(14),
                          textPrimary: Colors.white,
                          textMuted: textFaint,
                          softFill: softFill,
                          mediaOnly: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (ultimosCupos && reservable) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFDC2626)),
                        ),
                        child: const Text(
                          '¡Últimos cupos disponibles!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFFCA5A5),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                    PoolRutaRecorridoCard(
                      origen: origen,
                      destino: destino,
                      paradas: pickupPoints,
                      fechaLabels: fechaLineas,
                      sentidoLabel: _sentidoLegible(sentido),
                      cuposLabel: '$left cupos · $estadoCliente',
                      estiloOscuroRojo: true,
                    ),
                    if (incluye.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      PoolGiraIncluyeCard(
                        items: incluye,
                        estiloOscuroRojo: true,
                      ),
                    ],
                    if (descripcionViaje.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      PoolGiraPlanLlevarCard(
                        texto: descripcionViaje,
                        estiloOscuroRojo: true,
                      ),
                    ],
                    const SizedBox(height: 12),
                    PoolGiraContenidoPanel(
                      extra: contenidoExtra,
                      estiloOscuroRojo: true,
                    ),
                    const SizedBox(height: 10),
                    _anuncioLineal(context, anuncioTexto),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: Text(
                          titulo,
                          style: const TextStyle(
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
                          child: const Text('Confirmado',
                              style: TextStyle(
                                  color: accent, fontWeight: FontWeight.w700)),
                        ),
                    ]),
                    if (ownerLabel.isNotEmpty &&
                        (agenciaLogoUrl.isNotEmpty ||
                            agenciaNombre.isNotEmpty ||
                            taxistaNombre.isNotEmpty)) ...[
                      const SizedBox(height: 6),
                      Text(
                        agenciaNombre.isNotEmpty
                            ? 'Publicado por: $ownerLabel'
                            : 'Operador: $ownerLabel',
                        style: const TextStyle(
                          color: textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
                                'Hola, vi tu salida por cupos ($origen → $destino) y quiero confirmar detalles.',
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
                            Share.share(texto, subject: 'Salida por cupos');
                          },
                          icon: const Icon(Icons.share_outlined, size: 16),
                          label: const Text('Publicar en redes'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7C4DFF),
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
                    ...fechaLineas.map(
                      (linea) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          linea,
                          style: const TextStyle(color: textSecondary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: cap == 0 ? 0 : (occ / cap).clamp(0, 1),
                              backgroundColor: const Color(0xFF2A2A2A),
                              color: accent,
                              minHeight: 8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('$occ/$cap',
                            style: const TextStyle(color: textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Punto de encuentro: $pickup',
                        style: const TextStyle(color: textSecondary)),
                    Text(
                      esCentral
                          ? PoolsProductoCopy.recaudoCentralCliente
                          : 'Pago y recorrido los coordina el operador; RAI solo intermedió tu reserva.',
                      style: const TextStyle(color: textFaint, fontSize: 12),
                    ),
                    Text('Quedan $left cupos',
                        style: const TextStyle(color: textSecondary)),
                    if (minConf > 0)
                      Text('Mínimo para confirmar: $minConf',
                          style: const TextStyle(color: textFaint)),
                    if (!reservable) ...[
                      const SizedBox(height: 6),
                      Text(
                        estadoL == 'cancelado'
                            ? 'Esta salida fue cancelada por el operador.'
                            : estadoL == 'finalizado'
                                ? 'Esta salida ya cerró en RAI.'
                                : estadoL == 'en_ruta'
                                    ? 'El catálogo de cupos en RAI ya cerró. Coordina el día con el operador.'
                                    : estadoL == 'lleno' || left == 0
                                        ? 'Cupos completos. No hay asientos disponibles.'
                                        : 'Este viaje no está disponible para reservas.',
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Selector de asientos
              Container(
                padding: const EdgeInsets.all(12),
                decoration: _panelGira(),
                child: Row(
                  children: [
                    const Text('Asientos', style: TextStyle(color: textSecondary)),
                    const Spacer(),
                    IconButton(
                      onPressed:
                          (_seats > 1) ? () => setState(() => _seats--) : null,
                      icon: const Icon(Icons.remove_circle_outline,
                          color: textSecondary),
                    ),
                    Text('$_seats',
                        style: const TextStyle(
                            color: textPrimary, fontWeight: FontWeight.w800)),
                    IconButton(
                      onPressed: (_seats < left && _seats < maxAsientosCompra)
                          ? () => setState(() => _seats++)
                          : null,
                      icon:
                          const Icon(Icons.add_circle_outline, color: textSecondary),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Precio / Depósito
              Container(
                padding: const EdgeInsets.all(12),
                decoration: _panelGira(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Precio por persona: RD\$ ${precioTotalPorSeat.toStringAsFixed(0)}',
                        style: const TextStyle(color: textSecondary)),
                    const SizedBox(height: 4),
                    Text('Total: RD\$ ${total.toStringAsFixed(0)}',
                        style: const TextStyle(
                            color: textPrimary, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    if (esCentral) ...[
                      Text(
                        'Transferís a RAI / Open ASK: RD\$ ${montoClienteCentral.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Comisión RAI (${pctComision.toStringAsFixed(0)}%) sobre esta reserva: RD\$ ${desgloseCentral.comisionRai.toStringAsFixed(0)}',
                        style: const TextStyle(color: textSecondary),
                      ),
                      Text(
                        'Neto para el organizador: RD\$ ${desgloseCentral.netoOrganizador.toStringAsFixed(0)}',
                        style: const TextStyle(color: textSecondary),
                      ),
                      const Text(
                        'La comisión se calcula por asiento vendido en RAI.',
                        style: TextStyle(color: textFaint),
                      ),
                    ] else ...[
                      Text(
                          'Depósito ($ownerLabel): RD\$ ${deposito.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: accent, fontWeight: FontWeight.w900)),
                      Text(
                          'Resto al abordar: RD\$ ${restante.toStringAsFixed(0)}',
                          style: const TextStyle(color: textSecondary)),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Método de pago
              Container(
                padding: const EdgeInsets.all(12),
                decoration: _panelGira(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Método de pago',
                        style: TextStyle(color: textSecondary)),
                    const SizedBox(height: 8),
                    _metodoTile(
                      value: 'transferencia',
                      groupValue: _metodo,
                      onChanged: (v) => setState(() => _metodo = v),
                      title: esCentral
                          ? PoolsProductoCopy.clienteTransferenciaTitulo
                          : 'Transferencia bancaria (Chofer/Agencia)',
                      subtitle: esCentral
                          ? PoolsProductoCopy.clienteTransferenciaSubtitulo
                          : 'Pagar depósito por transferencia',
                    ),
                    if (_metodo == 'transferencia') ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141414),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _kGiraBorde),
                        ),
                        child: esCentral
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Cuenta corporativa RAI / Open ASK Service',
                                    style: TextStyle(
                                      color: accent,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _bankRow(
                                    context,
                                    'Banco',
                                    RecargaBancariaConfig.banco,
                                  ),
                                  _bankRow(
                                    context,
                                    'No. de cuenta',
                                    RecargaBancariaConfig.numeroCuenta,
                                  ),
                                  _bankRow(
                                    context,
                                    'Tipo de cuenta',
                                    RecargaBancariaConfig.tipoCuenta,
                                  ),
                                  _bankRow(
                                    context,
                                    'Titular',
                                    RecargaBancariaConfig.titular,
                                  ),
                                  _bankRow(
                                    context,
                                    'Monto a transferir',
                                    'RD\$ ${montoClienteCentral.toStringAsFixed(0)}',
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    PoolsProductoCopy.clienteCuentaRaiAntesReservar,
                                    style: TextStyle(color: textMuted),
                                  ),
                                ],
                              )
                            : bancoCompleto
                                ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
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
                      if (!esCentral)
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
                    const SizedBox(height: 10),
                    _metodoTile(
                      value: 'efectivo',
                      groupValue: _metodo,
                      onChanged: (v) => setState(() => _metodo = v),
                      title: 'Efectivo al abordar',
                      subtitle: esCentral
                          ? 'Pagas al organizador el día de la salida; la comisión RAI sale de su recarga prepago.'
                          : 'Pagas el total el día del viaje',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              _MisReservasGiraPanel(
                poolId: widget.poolId,
                poolData: d,
                cancelandoReservaId: _cancelandoReservaId,
                onCancelar: _cancelarMiReserva,
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
                    foregroundColor: Colors.black,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Nota de confianza
              Text(
                esCentral
                    ? PoolsProductoCopy.recaudoCentralClientePie
                    : bancoCompleto
                        ? 'Transferí a la cuenta indicada, elegí el bauche y tocá «Enviar bauche a RAI».'
                        : 'Este viaje no tiene cuenta bancaria completa. Contacta al dueño del viaje por telefono/WhatsApp.',
                style: const TextStyle(color: textFaint),
              ),
            ],
          );
        },
      ),
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
      final verificado =
          await ClienteVerificacionIdentidadService.ensureVerificadoOMostrar(
        context,
      );
      if (!verificado || !mounted) return;

      final result = await PoolRepo.reservarCupos(
        poolId: widget.poolId,
        seats: seats,
        metodoPago: metodo,
      );

      if (!mounted) return;

      if (metodo == 'transferencia') {
        if (!result.recaudoCentral &&
            (bancoNombre.trim().isEmpty ||
                bancoCuenta.trim().isEmpty ||
                bancoTipoCuenta.trim().isEmpty ||
                bancoTitular.trim().isEmpty)) {
          _snack('Este viaje no tiene datos bancarios completos.');
          return;
        }
        _mostrarInstruccionesTransferencia(
          result.recaudoCentral ? result.montoEsperadoRecaudoRd : deposito,
          reservaId: result.reservaId,
          origen: origen,
          destino: destino,
          choferWhatsApp: choferWhatsApp,
          bancoNombre: bancoNombre,
          bancoCuenta: bancoCuenta,
          bancoTipoCuenta: bancoTipoCuenta,
          bancoTitular: bancoTitular,
          recaudoCentral: result.recaudoCentral,
          referenciaRecaudo: result.referenciaRecaudo,
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

  Future<void> _cancelarMiReserva(String reservaId) async {
    if (_cancelandoReservaId != null) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar reserva'),
        content: const Text(
          '¿Liberar tus asientos? Si pagaste depósito por transferencia y ya enviaste '
          'comprobante, coordina con el operador.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _cancelandoReservaId = reservaId);
    try {
      await PoolRepo.cancelarReservaClienteSeguro(
        poolId: widget.poolId,
        reservaId: reservaId,
      );
      if (!mounted) return;
      _snack('Reserva cancelada. Los cupos quedaron disponibles.');
    } on FirebaseFunctionsException catch (e) {
      _snack((e.message ?? e.code).trim().isNotEmpty
          ? (e.message ?? e.code)
          : 'No se pudo cancelar la reserva.');
    } catch (e) {
      _snack('No se pudo cancelar: $e');
    } finally {
      if (mounted) setState(() => _cancelandoReservaId = null);
    }
  }

  void _mostrarInstruccionesTransferencia(
    double deposito, {
    required String reservaId,
    required String origen,
    required String destino,
    required String choferWhatsApp,
    required String bancoNombre,
    required String bancoCuenta,
    required String bancoTipoCuenta,
    required String bancoTitular,
    required bool recaudoCentral,
    required String referenciaRecaudo,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        const textPrimary = Colors.white;
        const textMuted = Color(0xFF9CA3AF);
        const accent = Color(0xFF4ADE80);
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 18,
              bottom: 24 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recaudoCentral
                        ? PoolsProductoCopy.clienteBaucheSheetTitulo
                        : 'Deposito para reservar',
                    style: const TextStyle(
                      color: accent,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    recaudoCentral
                        ? PoolsProductoCopy.clienteBaucheCuentaTitulo
                        : 'Cuenta donde depositar',
                    style: const TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _bankRow(
                    sheetContext,
                    'Banco',
                    recaudoCentral ? RecargaBancariaConfig.banco : bancoNombre,
                  ),
                  _bankRow(
                    sheetContext,
                    'No. de cuenta',
                    recaudoCentral
                        ? RecargaBancariaConfig.numeroCuenta
                        : bancoCuenta,
                  ),
                  _bankRow(
                    sheetContext,
                    'Tipo de cuenta',
                    recaudoCentral
                        ? RecargaBancariaConfig.tipoCuenta
                        : bancoTipoCuenta,
                  ),
                  _bankRow(
                    sheetContext,
                    'Titular',
                    recaudoCentral
                        ? RecargaBancariaConfig.titular
                        : bancoTitular,
                  ),
                  _bankRow(sheetContext, 'Concepto', _concepto),
                  if (recaudoCentral && referenciaRecaudo.trim().isNotEmpty)
                    _bankRow(sheetContext, 'Referencia', referenciaRecaudo.trim()),
                  const SizedBox(height: 10),
                  Text(
                    recaudoCentral
                        ? 'Monto a transferir: RD\$ ${deposito.toStringAsFixed(0)}'
                        : 'Monto del depósito: RD\$ ${deposito.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    recaudoCentral
                        ? PoolsProductoCopy.recaudoCentralClientePasos
                        : '1. Transferí el monto a la cuenta de arriba.\n'
                            '2. Elegí la foto del bauche.\n'
                            '3. Tocá «Enviar bauche a RAI» (o al operador si es legacy).',
                    style: const TextStyle(color: textMuted, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  PoolReservaBaucheUploader(
                    poolId: widget.poolId,
                    reservaId: reservaId,
                  ),
                  const SizedBox(height: 12),
                  if (!recaudoCentral && choferWhatsApp.trim().isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _openWhatsApp(
                          choferWhatsApp,
                          'Hola, acabo de reservar cupo para $origen -> $destino.\n'
                          'Asientos: $_seats\n'
                          'Monto deposito: RD\$ ${deposito.toStringAsFixed(0)}\n'
                          'Te envio el bauche por WhatsApp si lo necesitas.',
                        ),
                        icon: const Icon(Icons.chat),
                        label: const Text('Coordinar por WhatsApp'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF25D366),
                          side: const BorderSide(color: Color(0xFF25D366)),
                        ),
                      ),
                    ),
                  if (!recaudoCentral && choferWhatsApp.trim().isNotEmpty)
                    const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _snack(
                          'Reserva creada. Cuando deposites, enviá tu bauche desde «Tus reservas».',
                        );
                      },
                      icon: const Icon(Icons.schedule_outlined),
                      label: const Text('Depositaré después'),
                      style: TextButton.styleFrom(foregroundColor: textMuted),
                    ),
                  ),
                ],
              ),
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

class _MisReservasGiraPanel extends StatelessWidget {
  const _MisReservasGiraPanel({
    required this.poolId,
    required this.poolData,
    required this.cancelandoReservaId,
    required this.onCancelar,
  });

  final String poolId;
  final Map<String, dynamic> poolData;
  final String? cancelandoReservaId;
  final Future<void> Function(String reservaId) onCancelar;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();

    final usaRecaudoCentral = PoolRecaudoCentral.esPoolCentral(poolData);
    final bool poolPermiteCancel =
        PoolRepo.giraPuedeCancelarseAntesDeIniciar(poolData);
    const accent = Color(0xFF4ADE80);
    const textMuted = Color(0xFF9CA3AF);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('viajes_pool')
          .doc(poolId)
          .collection('reservas')
          .where('uidCliente', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        if (!PoolRepo.giraPuedeCancelarseAntesDeIniciar(poolData)) {
          final poolEstado =
              (poolData['estado'] ?? '').toString().trim().toLowerCase();
          if (poolEstado == 'cancelado' || poolEstado == 'cancelado_por_admin') {
            return const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Esta salida fue cancelada por el operador. Tus cupos ya no están activos.',
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }
        }
        final docs = snap.data!.docs.where((d) {
          return PoolRepo.reservaPoolActivaParaCliente(
            (d.data()['estado'] ?? '').toString(),
          );
        }).toList();
        if (docs.isEmpty) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF59E0B)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tus reservas en este viaje',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              ...docs.map((doc) {
                final r = doc.data();
                final estado =
                    (r['estado'] ?? '').toString().trim().toLowerCase();
                final seats = ((r['seats'] ?? 1) as num).toInt();
                final metodo = (r['metodoPago'] ?? '').toString();
                final comprobante =
                    (r['comprobanteUrl'] ?? '').toString().trim();
                final bool esTransferencia =
                    metodo.toLowerCase().contains('transfer');
                final bool pendienteComprobante = esTransferencia &&
                    estado == 'reservado' &&
                    comprobante.isEmpty;
                final bool comprobanteEnviado = comprobante.isNotEmpty;
                final bool puedeCancelar =
                    poolPermiteCancel && estado == 'reservado';
                final bool cancelando = cancelandoReservaId == doc.id;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              usaRecaudoCentral
                                  ? PoolsProductoCopy.recaudoCentralEstadoReservaCliente(r)
                                  : '$seats asiento(s) · $metodo · '
                                      '${estado == 'pagado' ? 'Pago confirmado' : comprobanteEnviado ? 'Recibo enviado · pendiente validación' : 'Pendiente depósito y bauche'}',
                              style: const TextStyle(color: textMuted),
                            ),
                          ),
                          if (puedeCancelar)
                            TextButton(
                              onPressed: cancelando ? null : () => onCancelar(doc.id),
                              child: Text(cancelando ? '…' : 'Cancelar'),
                            ),
                        ],
                      ),
                      if (pendienteComprobante) ...[
                        const SizedBox(height: 8),
                        PoolReservaBaucheUploader(
                          poolId: poolId,
                          reservaId: doc.id,
                          compact: true,
                        ),
                      ] else if (comprobanteEnviado && estado == 'reservado') ...[
                        const SizedBox(height: 4),
                        Text(
                          'Recibo enviado. RAI validará tu pago pronto.',
                          style: TextStyle(
                            color: Colors.green.shade400,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (estado == 'pagado') ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => PoolGiraTicketPage(
                                  poolId: poolId,
                                  reservaId: doc.id,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.qr_code_2, size: 18),
                          label: const Text('Ver ticket / QR'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accent,
                            side: const BorderSide(color: accent),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
