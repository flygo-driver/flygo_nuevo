import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../modelo/recarga_comision_taxista.dart';
import '../../servicios/pagos_taxista_repo.dart';
import '../../modelo/pago_taxista.dart';

/// Cuenta empresa para recarga prepago comisión (misma que Billetera / Cuenta bloqueada).
const String _kRecargaEmpresaTitular = 'Open ASK Service SRL';
const String _kRecargaEmpresaBanco = 'Banco Popular';
const String _kRecargaEmpresaTipo = 'Cuenta Corriente';
const String _kRecargaEmpresaCuenta = '787726249';
const String _kRecargaEmpresaRnc = '1320-11767';

Widget _kvRecarga(ColorScheme cs, String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: RichText(
      text: TextSpan(
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.3),
        children: [
          TextSpan(text: '$label: '),
          TextSpan(
            text: value,
            style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class MisPagos extends StatefulWidget {
  const MisPagos({super.key});

  @override
  State<MisPagos> createState() => _MisPagosState();
}

class _MisPagosState extends State<MisPagos> {
  final user = FirebaseAuth.instance.currentUser;
  final formatter = NumberFormat.currency(locale: 'es', symbol: 'RD\$');
  final dateFormat = DateFormat('dd/MM/yyyy');

  Future<void> _subirComprobante(String pagoId) async {
    final TextEditingController urlCtrl = TextEditingController();
    String metodo = 'transferencia';
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dcs = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setStateModal) => AlertDialog(
            backgroundColor: dcs.surfaceContainerHigh,
            title: Text(
              'Enviar comprobante',
              style: TextStyle(color: dcs.onSurface),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: metodo,
                  dropdownColor: dcs.surfaceContainerHighest,
                  style: TextStyle(color: dcs.onSurface),
                  decoration: InputDecoration(
                    labelText: 'Método de pago',
                    labelStyle: TextStyle(color: dcs.onSurfaceVariant),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'transferencia', child: Text('Transferencia')),
                    DropdownMenuItem(
                        value: 'efectivo', child: Text('Efectivo')),
                    DropdownMenuItem(value: 'tarjeta', child: Text('Tarjeta')),
                  ],
                  onChanged: (v) => setStateModal(() => metodo = v ?? metodo),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: urlCtrl,
                  style: TextStyle(color: dcs.onSurface),
                  cursorColor: dcs.primary,
                  decoration: InputDecoration(
                    labelText: 'URL del comprobante',
                    hintText: 'https://...',
                    labelStyle: TextStyle(color: dcs.onSurfaceVariant),
                    hintStyle: TextStyle(
                        color: dcs.onSurfaceVariant.withValues(alpha: 0.8)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancelar', style: TextStyle(color: dcs.primary)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enviar'),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true) return;
    final url = urlCtrl.text.trim();
    if (url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes indicar la URL del comprobante')),
      );
      return;
    }
    try {
      await PagosTaxistaRepo.subirComprobante(
        pagoId: pagoId,
        comprobanteUrl: url,
        metodoPago: metodo,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Comprobante enviado para revisión'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar comprobante: $e')),
      );
    }
  }

  ({Color color, String label, IconData icon}) _estadoRecargaUi(
      BuildContext context, String estado) {
    final cs = Theme.of(context).colorScheme;
    switch (estado) {
      case 'pagado':
        return (
          color: Colors.green,
          label: 'APROBADA',
          icon: Icons.check_circle,
        );
      case 'pendiente_verificacion':
        return (
          color: Colors.orange,
          label: 'EN REVISION',
          icon: Icons.hourglass_top,
        );
      case 'rechazado':
        return (
          color: Colors.red.shade700,
          label: 'RECHAZADA',
          icon: Icons.cancel,
        );
      default:
        return (color: cs.outline, label: estado.toUpperCase(), icon: Icons.help);
    }
  }

  Widget _buildRecargasCreditoSection(
    BuildContext context,
    List<RecargaComisionTaxista> recargas,
  ) {
    final cs = Theme.of(context).colorScheme;
    if (recargas.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          Text(
            'HISTORIAL DE RECARGAS DE CREDITO',
            style: TextStyle(
              color: cs.primary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recargas.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final r = recargas[index];
                final estadoUi = _estadoRecargaUi(context, r.estado);
                final fecha = r.createdAt != null
                    ? DateFormat('dd/MM/yyyy HH:mm').format(r.createdAt!)
                    : 'sin fecha';
                return Container(
                  width: 270,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: estadoUi.color.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(estadoUi.icon, color: estadoUi.color, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            estadoUi.label,
                            style: TextStyle(
                              color: estadoUi.color,
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formatter.format(r.montoDeclaradoRd),
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        fecha,
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5),
                      ),
                      const Spacer(),
                      if ((r.notaAdmin ?? '').trim().isNotEmpty)
                        Text(
                          'Nota: ${r.notaAdmin!.trim()}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumenRapidoRecargas(
    BuildContext context,
    List<RecargaComisionTaxista> recargas,
  ) {
    final cs = Theme.of(context).colorScheme;
    if (recargas.isEmpty) return const SizedBox.shrink();

    final RecargaComisionTaxista? ultimaAprobada = recargas
        .where((r) => r.estado == 'pagado')
        .cast<RecargaComisionTaxista?>()
        .firstWhere((r) => r != null, orElse: () => null);
    final RecargaComisionTaxista ultimaSolicitud = recargas.first;
    final bool enRevision =
        recargas.any((r) => r.estado == 'pendiente_verificacion');

    String fechaOGuion(DateTime? dt) =>
        dt == null ? '-' : DateFormat('dd/MM/yyyy').format(dt);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _resumenItem(
                context,
                'Última aprobada',
                ultimaAprobada != null
                    ? '${formatter.format(ultimaAprobada.montoDeclaradoRd)} · ${fechaOGuion(ultimaAprobada.createdAt)}'
                    : 'Sin recarga aprobada',
              ),
            ),
            Container(
              width: 1,
              height: 38,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
            Expanded(
              child: _resumenItem(
                context,
                'Última solicitud',
                '${formatter.format(ultimaSolicitud.montoDeclaradoRd)} · ${fechaOGuion(ultimaSolicitud.createdAt)}',
              ),
            ),
            Container(
              width: 1,
              height: 38,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
            Expanded(
              child: _resumenItem(
                context,
                'Estado actual',
                enRevision ? 'En revisión' : 'Sin revisión pendiente',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumenItem(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (user == null) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: Center(
          child: Text(
            'No hay sesión activa',
            style: TextStyle(color: cs.onSurface),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: cs.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Text(
          'Mis Pagos',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelRecargaComisionEfectivo(user: user!, formatter: formatter),
          Expanded(
            child: StreamBuilder<List<PagoTaxista>>(
              stream: PagosTaxistaRepo.streamPagosPorTaxista(user!.uid),
              builder: (BuildContext context,
                  AsyncSnapshot<List<PagoTaxista>> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: cs.primary),
                  );
                }

                final List<PagoTaxista> pagos = snapshot.data ?? [];

                if (pagos.isEmpty) {
                  return Center(
                    child: Text(
                      'No tienes pagos semanales registrados',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  );
                }

                // Buscar pago pendiente (el más reciente)
                final PagoTaxista pendiente = pagos.firstWhere(
                  (PagoTaxista p) =>
                      p.estado == 'pendiente' ||
                      p.estado == 'pendiente_verificacion',
                  orElse: () => pagos.first,
                );

                return StreamBuilder<List<RecargaComisionTaxista>>(
                  stream:
                      PagosTaxistaRepo.streamRecargasComisionPorTaxista(user!.uid),
                  builder: (context, recSnapshot) {
                    final recargas = recSnapshot.data ?? <RecargaComisionTaxista>[];
                    return Column(
                      children: <Widget>[
                        _buildResumenRapidoRecargas(context, recargas),
                        _buildRecargasCreditoSection(context, recargas),
                    // Banner de pago pendiente (si existe)
                    if (pendiente.estado == 'pendiente' ||
                        pendiente.estado == 'pendiente_verificacion')
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: pendiente.estado == 'pendiente_verificacion'
                              ? Colors.orange.withValues(alpha: 0.1)
                              : Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: pendiente.estado == 'pendiente_verificacion'
                                ? Colors.orange
                                : Colors.red,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: <Widget>[
                            Icon(
                              pendiente.estado == 'pendiente_verificacion'
                                  ? Icons.hourglass_top
                                  : Icons.warning_amber_rounded,
                              color:
                                  pendiente.estado == 'pendiente_verificacion'
                                      ? Colors.orange
                                      : Colors.red,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              pendiente.estado == 'pendiente_verificacion'
                                  ? 'COMPROBANTE EN REVISIÓN'
                                  : 'PAGO PENDIENTE',
                              style: TextStyle(
                                color:
                                    pendiente.estado == 'pendiente_verificacion'
                                        ? Colors.orange
                                        : Colors.red,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Semana: ${pendiente.semana}',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                            Text(
                              'Período: ${dateFormat.format(pendiente.fechaInicio)} - ${dateFormat.format(pendiente.fechaFin)}',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Total a pagar: ${formatter.format(pendiente.comision)}',
                              style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (pendiente.estado == 'pendiente')
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () =>
                                      _subirComprobante(pendiente.id),
                                  icon: Icon(Icons.upload_file,
                                      color: cs.onPrimary),
                                  label:
                                      const Text('SUBIR COMPROBANTE DE PAGO'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: cs.primary,
                                    foregroundColor: cs.onPrimary,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            if (pendiente.estado == 'pendiente_verificacion')
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: <Widget>[
                                    const Icon(Icons.info,
                                        color: Colors.orange),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Tu comprobante está siendo revisado por el administrador',
                                        style: TextStyle(
                                            color: cs.onSurfaceVariant),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 8),

                    // Título del historial
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'HISTORIAL DE PAGOS',
                          style: TextStyle(
                            color: cs.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    // Lista de pagos (historial)
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: pagos.length,
                        itemBuilder: (BuildContext context, int index) {
                          final PagoTaxista pago = pagos[index];

                          Color estadoColor;
                          String estadoText;
                          IconData estadoIcon;

                          switch (pago.estado) {
                            case 'pagado':
                              estadoColor = Colors.green;
                              estadoText = 'PAGADO';
                              estadoIcon = Icons.check_circle;
                              break;
                            case 'pendiente_verificacion':
                              estadoColor = Colors.orange;
                              estadoText = 'EN REVISIÓN';
                              estadoIcon = Icons.hourglass_top;
                              break;
                            case 'pendiente':
                              estadoColor = Colors.red;
                              estadoText = 'PENDIENTE';
                              estadoIcon = Icons.warning;
                              break;
                            case 'rechazado':
                              estadoColor = Colors.red.shade900;
                              estadoText = 'RECHAZADO';
                              estadoIcon = Icons.cancel;
                              break;
                            default:
                              estadoColor = cs.outline;
                              estadoText = pago.estado.toUpperCase();
                              estadoIcon = Icons.help;
                          }

                          return Card(
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? 0.55
                                  : 0.65,
                            ),
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation:
                                Theme.of(context).brightness == Brightness.dark
                                    ? 1
                                    : 0.5,
                            shadowColor: cs.shadow.withValues(alpha: 0.15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              leading: CircleAvatar(
                                backgroundColor:
                                    estadoColor.withValues(alpha: 0.2),
                                radius: 20,
                                child: Icon(estadoIcon,
                                    color: estadoColor, size: 20),
                              ),
                              title: Text(
                                'Semana ${pago.semana}',
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    '${pago.viajesSemana} viajes',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '${dateFormat.format(pago.fechaInicio)} - ${dateFormat.format(pago.fechaFin)}',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant
                                          .withValues(alpha: 0.85),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: <Widget>[
                                  Text(
                                    formatter.format(pago.comision),
                                    style: TextStyle(
                                      color: estadoColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: estadoColor.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      estadoText,
                                      style: TextStyle(
                                        color: estadoColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                      ],
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

/// Recarga por comisión de viajes en efectivo: sube comprobante y queda en cola del admin.
class _PanelRecargaComisionEfectivo extends StatefulWidget {
  final User user;
  final NumberFormat formatter;

  const _PanelRecargaComisionEfectivo({
    required this.user,
    required this.formatter,
  });

  @override
  State<_PanelRecargaComisionEfectivo> createState() =>
      _PanelRecargaComisionEfectivoState();
}

class _PanelRecargaComisionEfectivoState
    extends State<_PanelRecargaComisionEfectivo> {
  final TextEditingController _montoCtrl = TextEditingController();
  bool _subiendo = false;
  bool _enviando = false;
  String? _comprobanteUrl;

  @override
  void dispose() {
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _elegirOrigenYSubirComprobante() async {
    if (_subiendo) return;
    final ImageSource? origen = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final dcs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Foto del comprobante (bauche)',
                    style: TextStyle(
                      color: dcs.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                ListTile(
                  leading:
                      Icon(Icons.photo_library_outlined, color: dcs.primary),
                  title: const Text('Galería'),
                  subtitle: const Text('Elegir imagen ya guardada'),
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
                ListTile(
                  leading:
                      Icon(Icons.photo_camera_outlined, color: dcs.primary),
                  title: const Text('Cámara'),
                  subtitle: const Text('Tomar foto al depósito'),
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (origen == null) return;
    await _subirComprobanteDesdeOrigen(origen);
  }

  Future<void> _subirComprobanteDesdeOrigen(ImageSource source) async {
    if (_subiendo) return;
    final ImagePicker picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1920,
    );
    if (file == null) return;
    setState(() => _subiendo = true);
    try {
      final bytes = await file.readAsBytes();
      // Misma ruta que exige storage.rules: comprobantes/{uid}/{carpeta}/{archivo}
      final path =
          'comprobantes/${widget.user.uid}/recarga_comision/rec_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() => _comprobanteUrl = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Comprobante listo. Revisa la vista previa y pulsa Enviar.'),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('No se pudo subir la foto: ${e.code} ${e.message ?? ''}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Future<void> _enviarSolicitud() async {
    if (_enviando) return;
    final raw = _montoCtrl.text.trim().replaceAll(',', '.');
    final monto = double.tryParse(raw) ?? 0;
    if (monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe el monto que transferiste')),
      );
      return;
    }
    if ((_comprobanteUrl ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sube la foto del comprobante primero')),
      );
      return;
    }
    final nombre = widget.user.displayName ?? widget.user.email ?? 'Taxista';
    setState(() => _enviando = true);
    try {
      await PagosTaxistaRepo.taxistaEnviarRecargaComisionEfectivo(
        uidTaxista: widget.user.uid,
        nombreTaxista: nombre,
        montoDeclaradoRd: monto,
        comprobanteUrl: _comprobanteUrl!,
      );
      if (!mounted) return;
      _montoCtrl.clear();
      setState(() => _comprobanteUrl = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Solicitud enviada con tu foto. El admin revisará el comprobante y, si coincide, acreditará tu saldo.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('billeteras_taxista')
          .doc(widget.user.uid)
          .snapshots(),
      builder: (context, billSnap) {
        final bill = billSnap.data?.data();
        if (!PagosTaxistaRepo.debeMostrarPanelRecargaComisionEfectivo(bill)) {
          return const SizedBox.shrink();
        }
        final pend = PagosTaxistaRepo.comisionPendienteDesdeBilletera(bill);
        final saldo = PagosTaxistaRepo.saldoPrepagoComisionDesdeBilletera(bill);
        const minSaldo = PagosTaxistaRepo.minSaldoPrepagoComisionRd;
        final primerViajeConsumido =
            PagosTaxistaRepo.primerViajeComisionGratisConsumido(bill);
        final bloqueoOperativo =
            PagosTaxistaRepo.bloqueoOperativoPorComisionEfectivo(bill);
        final saldoFaltante = (minSaldo - saldo).clamp(0.0, double.infinity);

        return StreamBuilder<List<RecargaComisionTaxista>>(
          stream: PagosTaxistaRepo.streamRecargasComisionPorTaxista(
              widget.user.uid),
          builder: (context, recSnap) {
            final list = recSnap.data ?? [];
            final enRevision =
                list.any((r) => r.estado == 'pendiente_verificacion');

            return Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber.shade700),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: bloqueoOperativo
                          ? Colors.red.withValues(alpha: 0.15)
                          : Colors.green.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: bloqueoOperativo
                            ? Colors.red.withValues(alpha: 0.6)
                            : Colors.green.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Text(
                      bloqueoOperativo
                          ? (pend > 1e-6
                              ? 'Estado: BLOQUEADO por comisión pendiente. Regulariza el pendiente para volver a tomar viajes.'
                              : 'Estado: BLOQUEADO por saldo prepago insuficiente. Te faltan ${widget.formatter.format(saldoFaltante)} para el mínimo.')
                          : 'Estado: ACTIVO para operar. Tu saldo actual cumple la regla de servicio.',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.account_balance_wallet,
                          color: Colors.amber.shade200),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Recarga de crédito (comisión en efectivo)',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Este saldo cubre la comisión del 20% de viajes en efectivo. '
                    'Haz la transferencia a la cuenta de la empresa y sube el comprobante. '
                    'Cuando el administrador lo apruebe, tu crédito se actualiza automáticamente.',
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 12, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cuenta para recargar crédito',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _kvRecarga(cs, 'Titular', _kRecargaEmpresaTitular),
                        _kvRecarga(cs, 'RNC', _kRecargaEmpresaRnc),
                        _kvRecarga(cs, 'Banco', _kRecargaEmpresaBanco),
                        _kvRecarga(cs, 'Tipo', _kRecargaEmpresaTipo),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: _kvRecarga(
                                    cs, 'No. cuenta', _kRecargaEmpresaCuenta)),
                            IconButton(
                              tooltip: 'Copiar número de cuenta',
                              onPressed: () async {
                                await Clipboard.setData(const ClipboardData(
                                    text: _kRecargaEmpresaCuenta));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Número de cuenta copiado al portapapeles')),
                                );
                              },
                              icon:
                                  Icon(Icons.copy, color: cs.primary, size: 22),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Saldo prepago: ${widget.formatter.format(saldo)} '
                    '(mín. RD\$${minSaldo.toStringAsFixed(0)})',
                    style: TextStyle(
                      color: Colors.amber.shade100,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  if (pend > 1e-6) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Comisión legacy pendiente: ${widget.formatter.format(pend)}',
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                  if (!primerViajeConsumido && pend < 1e-6) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Nota: tu primer viaje en efectivo no descuenta comisión; a partir de ahí aplica control de saldo prepago.',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (enRevision) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.hourglass_top,
                              color: Colors.orange, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Tu recarga está en revisión. No envíes otra hasta tener respuesta.',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Text(
                      'Paso 1: escribe el monto  ·  Paso 2: adjunta la foto  ·  Paso 3: envía la solicitud',
                      style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 11.5,
                          height: 1.3),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _montoCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: cs.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Monto transferido (RD\$)',
                        labelStyle: TextStyle(color: cs.onSurfaceVariant),
                        filled: true,
                        fillColor:
                            cs.surfaceContainerHighest.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed:
                          _subiendo ? null : _elegirOrigenYSubirComprobante,
                      icon: _subiendo
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: cs.primary),
                            )
                          : const Icon(Icons.add_a_photo_outlined),
                      label: Text(
                        _comprobanteUrl != null
                            ? 'Cambiar foto del comprobante'
                            : 'Adjuntar foto del depósito',
                      ),
                    ),
                    if (_comprobanteUrl != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              _comprobanteUrl!,
                              width: 88,
                              height: 88,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 88,
                                height: 88,
                                color: cs.surfaceContainerHighest,
                                child: Icon(Icons.broken_image_outlined,
                                    color: cs.onSurfaceVariant),
                              ),
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return SizedBox(
                                  width: 88,
                                  height: 88,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: cs.primary,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Vista previa: esta imagen y el monto se envían al administrador '
                              'para validación de la recarga.',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 12,
                                  height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _enviando ? null : _enviarSolicitud,
                        child: _enviando
                            ? SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: cs.onPrimary),
                              )
                            : const Text('Enviar recarga para verificación'),
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
}
