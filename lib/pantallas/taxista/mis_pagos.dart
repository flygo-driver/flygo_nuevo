import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../servicios/pagos_taxista_repo.dart';
import '../../modelo/pago_taxista.dart';

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
                    DropdownMenuItem(value: 'transferencia', child: Text('Transferencia')),
                    DropdownMenuItem(value: 'efectivo', child: Text('Efectivo')),
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
                    hintStyle: TextStyle(color: dcs.onSurfaceVariant.withValues(alpha: 0.8)),
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
      body: StreamBuilder<List<PagoTaxista>>(
        stream: PagosTaxistaRepo.streamPagosPorTaxista(user!.uid),
        builder: (BuildContext context, AsyncSnapshot<List<PagoTaxista>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: cs.primary),
            );
          }

          final List<PagoTaxista> pagos = snapshot.data ?? [];

          if (pagos.isEmpty) {
            return Center(
              child: Text(
                'No tienes pagos registrados',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            );
          }

          // Buscar pago pendiente (el más reciente)
          final PagoTaxista pendiente = pagos.firstWhere(
            (PagoTaxista p) => p.estado == 'pendiente' || p.estado == 'pendiente_verificacion',
            orElse: () => pagos.first,
          );

          return Column(
            children: <Widget>[
              // Banner de pago pendiente (si existe)
              if (pendiente.estado == 'pendiente' || pendiente.estado == 'pendiente_verificacion')
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
                        color: pendiente.estado == 'pendiente_verificacion'
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
                          color: pendiente.estado == 'pendiente_verificacion'
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
                            onPressed: () => _subirComprobante(pendiente.id),
                            icon: Icon(Icons.upload_file, color: cs.onPrimary),
                            label: const Text('SUBIR COMPROBANTE DE PAGO'),
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 16),
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
                              const Icon(Icons.info, color: Colors.orange),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Tu comprobante está siendo revisado por el administrador',
                                  style: TextStyle(color: cs.onSurfaceVariant),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.55
                            : 0.65,
                      ),
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: Theme.of(context).brightness == Brightness.dark ? 1 : 0.5,
                      shadowColor: cs.shadow.withValues(alpha: 0.15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: CircleAvatar(
                          backgroundColor: estadoColor.withValues(alpha: 0.2),
                          radius: 20,
                          child: Icon(estadoIcon, color: estadoColor, size: 20),
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
                                color: cs.onSurfaceVariant.withValues(alpha: 0.85),
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
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
      ),
    );
  }
}