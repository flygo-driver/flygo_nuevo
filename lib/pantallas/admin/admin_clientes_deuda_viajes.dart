import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/pantallas/comun/factura_viaje.dart';
import 'package:flygo_nuevo/servicios/cliente_cobro_tarjeta_pendiente_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/widgets/admin_app_bar.dart';
import 'package:flygo_nuevo/widgets/admin_drawer.dart';
import 'package:flygo_nuevo/widgets/admin_guia_uso.dart';
import 'admin_ui_theme.dart';

/// Cola ADM en vivo: `usuarios.tieneCobroViajePendiente` (lo que realmente bloquea pedir viaje).
class AdminClientesDeudaViajes extends StatefulWidget {
  const AdminClientesDeudaViajes({super.key});

  @override
  State<AdminClientesDeudaViajes> createState() =>
      _AdminClientesDeudaViajesState();
}

class _AdminClientesDeudaViajesState extends State<AdminClientesDeudaViajes> {
  final TextEditingController _buscarCtrl = TextEditingController();
  String _buscar = '';
  bool _accionEnCurso = false;

  static final DateFormat _fmt =
      DateFormat('dd/MM/yyyy HH:mm', 'es');

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade800 : null,
      ),
    );
  }

  bool _matchBusqueda({
    required String q,
    required String uidCliente,
    required String viajeId,
    required Map<String, dynamic> viaje,
    required Map<String, dynamic> perfil,
  }) {
    if (q.isEmpty) return true;
    final blob = [
      uidCliente,
      viajeId,
      (viaje['uidCliente'] ?? '').toString(),
      (viaje['clienteId'] ?? '').toString(),
      (perfil['email'] ?? '').toString(),
      (perfil['nombre'] ?? '').toString(),
      (perfil['telefono'] ?? '').toString(),
      (viaje['nombreTaxista'] ?? '').toString(),
    ].join(' ').toLowerCase();
    return blob.contains(q);
  }

  Future<void> _regularizar({
    required String uidCliente,
    required String viajeId,
    required String etiquetaCliente,
    required bool legacyEfectivoOTransfer,
  }) async {
    if (_accionEnCurso) return;
    final notaCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AdminUi.dialogSurface(ctx),
          title: Text(
            legacyEfectivoOTransfer ? 'Liberar cliente' : 'Regularizar cobro',
            style: TextStyle(color: AdminUi.onCard(ctx)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cliente: $etiquetaCliente\nViaje: $viajeId',
                style: TextStyle(color: AdminUi.secondary(ctx), height: 1.35),
              ),
              const SizedBox(height: 12),
              Text(
                legacyEfectivoOTransfer
                    ? 'Efectivo/transfer: el taxista verifica el cobro. '
                        'Esto solo quita el bloqueo residual del perfil del cliente.'
                    : 'Confirmá que el cliente ya pagó o que fue error. '
                        'Se libera el bloqueo para pedir nuevos viajes.',
                style: TextStyle(color: AdminUi.secondary(ctx), fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notaCtrl,
                maxLines: 2,
                style: TextStyle(color: AdminUi.onCard(ctx)),
                decoration: InputDecoration(
                  labelText: 'Nota admin (opcional)',
                  filled: true,
                  fillColor: AdminUi.inputFill(ctx),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Regularizar'),
            ),
          ],
        );
      },
    );
    final nota = notaCtrl.text.trim();
    notaCtrl.dispose();
    if (ok != true || !mounted) return;

    setState(() => _accionEnCurso = true);
    try {
      await ViajesRepo.adminRegularizarOLiberarCobroCliente(
        uidCliente: uidCliente,
        viajeId: viajeId,
        nota: nota.isEmpty ? 'Regularizado desde ADM — deuda viajes' : nota,
        legacyEfectivoOTransfer: legacyEfectivoOTransfer,
      );
      _snack(
        legacyEfectivoOTransfer
            ? '✅ Cliente liberado. Ya puede pedir viajes (efectivo lo ve el taxista).'
            : '✅ Cobro regularizado. El cliente ya puede pedir viajes.',
      );
    } catch (e) {
      _snack('No se pudo liberar: $e', error: true);
    } finally {
      if (mounted) setState(() => _accionEnCurso = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tiempo real: el bloqueo vive en el perfil del cliente, no solo en el viaje.
    final stream = FirebaseFirestore.instance
        .collection('usuarios')
        .where('tieneCobroViajePendiente', isEqualTo: true)
        .limit(80)
        .snapshots();

    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: const AdminAppBar(
        guiaId: AdminGuiaIds.centro,
        title: 'Tarjeta sin cobrar RAI',
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Material(
              color: Colors.orange.withValues(alpha: 0.12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Colors.orangeAccent.withValues(alpha: 0.4),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'TARJETA sin cobrar RAI bloquea pedir viaje (caso extremo). '
                  'Efectivo/transferencia: el taxista verifica — los casos viejos aquí son solo para liberar el flag residual.',
                  style: TextStyle(
                    color: AdminUi.onCard(context),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _buscarCtrl,
              onChanged: (v) => setState(() => _buscar = v.trim().toLowerCase()),
              style: TextStyle(color: AdminUi.onCard(context)),
              decoration: InputDecoration(
                hintText: 'Buscar email, teléfono, nombre o ID viaje…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AdminUi.inputFill(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error al cargar cola: ${snap.error}',
                        style: const TextStyle(color: Colors.redAccent),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: AdminUi.progressAccent(context),
                    ),
                  );
                }
                final docs = snap.data!.docs.toList()
                  ..sort((a, b) {
                    final ta = a.data()['updatedAt'];
                    final tb = b.data()['updatedAt'];
                    if (ta is Timestamp && tb is Timestamp) {
                      return tb.compareTo(ta);
                    }
                    return 0;
                  });

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'Nadie bloqueado ahora (tieneCobroViajePendiente).',
                      style: TextStyle(color: AdminUi.secondary(context)),
                    ),
                  );
                }

                return FutureBuilder<List<Widget>>(
                  future: () async {
                    final tiles = <Widget>[];
                    for (final doc in docs) {
                      final uidCliente = doc.id;
                      final perfil = doc.data();

                      final resolved =
                          await ClienteCobroTarjetaPendienteService
                              .resolverViajeDeudaCliente(uid: uidCliente);
                      final viajeId = resolved?.id ?? '';
                      final viaje = resolved?.data ?? <String, dynamic>{};

                      if (!_matchBusqueda(
                        q: _buscar,
                        uidCliente: uidCliente,
                        viajeId: viajeId,
                        viaje: viaje,
                        perfil: perfil,
                      )) {
                        continue;
                      }
                      final bool esTarjeta = viajeId.isNotEmpty &&
                          MetodoPagoViaje.esTarjeta(
                            (viaje['metodoPago'] ?? '').toString(),
                          );
                      tiles.add(_DeudaViajeTile(
                        uidCliente: uidCliente,
                        viajeId: viajeId,
                        viaje: viaje,
                        perfil: perfil,
                        fmt: _fmt,
                        esTarjetaBloqueante: esTarjeta,
                        accionEnCurso: _accionEnCurso,
                        onVerComprobante: viajeId.isEmpty
                            ? null
                            : () => FacturaViaje.mostrar(
                                  context,
                                  viajeId: viajeId,
                                  role: 'cliente',
                                  viajeDataSemilla:
                                      Map<String, dynamic>.from(viaje),
                                ),
                        onRegularizar: () => _regularizar(
                              uidCliente: uidCliente,
                              viajeId: viajeId,
                              etiquetaCliente:
                                  (perfil['email'] ?? perfil['nombre'] ?? uidCliente)
                                      .toString(),
                              legacyEfectivoOTransfer: !esTarjeta,
                            ),
                        onCopiarId: viajeId.isEmpty
                            ? () {
                                Clipboard.setData(
                                    ClipboardData(text: uidCliente));
                                _snack('UID cliente copiado');
                              }
                            : () {
                                Clipboard.setData(
                                    ClipboardData(text: viajeId));
                                _snack('ID de viaje copiado');
                              },
                      ));
                    }
                    return tiles;
                  }(),
                  builder: (context, listSnap) {
                    if (!listSnap.hasData) {
                      return Center(
                        child: CircularProgressIndicator(
                          color: AdminUi.progressAccent(context),
                        ),
                      );
                    }
                    final tiles = listSnap.data!;
                    if (tiles.isEmpty) {
                      return Center(
                        child: Text(
                          _buscar.isEmpty
                              ? 'Sin registros.'
                              : 'Sin resultados para "$_buscar".',
                          style: TextStyle(color: AdminUi.secondary(context)),
                        ),
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: tiles,
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

class _DeudaViajeTile extends StatelessWidget {
  const _DeudaViajeTile({
    required this.uidCliente,
    required this.viajeId,
    required this.viaje,
    required this.perfil,
    required this.fmt,
    required this.esTarjetaBloqueante,
    required this.accionEnCurso,
    required this.onVerComprobante,
    required this.onRegularizar,
    required this.onCopiarId,
  });

  final String uidCliente;
  final String viajeId;
  final Map<String, dynamic> viaje;
  final Map<String, dynamic> perfil;
  final DateFormat fmt;
  final bool esTarjetaBloqueante;
  final bool accionEnCurso;
  final VoidCallback? onVerComprobante;
  final VoidCallback onRegularizar;
  final VoidCallback onCopiarId;

  @override
  Widget build(BuildContext context) {
    final nombre = (perfil['nombre'] ?? '').toString().trim();
    final email = (perfil['email'] ?? '').toString().trim();
    final telefono = (perfil['telefono'] ?? '').toString().trim();
    final monto = (viaje['cobroClienteMontoRd'] is num)
        ? (viaje['cobroClienteMontoRd'] as num).toDouble()
        : (viaje['precio'] is num ? (viaje['precio'] as num).toDouble() : 0);
    final metodo = (viaje['metodoPago'] ?? '—').toString();
    final estadoCobro =
        (viaje['cobroClienteEstado'] ?? 'bloqueo perfil').toString();
    final taxista = (viaje['nombreTaxista'] ?? '—').toString();
    final updated = viaje['updatedAt'] ?? perfil['updatedAt'];
    final fechaTxt = updated is Timestamp ? fmt.format(updated.toDate()) : '—';
    final deudaUsuario = (perfil['deudaViajesClienteRd'] is num)
        ? (perfil['deudaViajesClienteRd'] as num).toDouble()
        : monto;
    final bool esTarjeta = esTarjetaBloqueante;
    final String etiquetaMetodo = viajeId.isEmpty
        ? 'FLAG RESIDUAL'
        : (esTarjeta ? 'TARJETA' : 'LEGACY ${metodo.toUpperCase()}');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  nombre.isNotEmpty ? nombre : (email.isNotEmpty ? email : 'Cliente'),
                  style: TextStyle(
                    color: AdminUi.onCard(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (esTarjeta ? Colors.red : Colors.orange)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  etiquetaMetodo,
                  style: TextStyle(
                    color: esTarjeta ? Colors.redAccent : Colors.orangeAccent,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(email, style: TextStyle(color: AdminUi.secondary(context))),
          ],
          if (telefono.isNotEmpty)
            Text('Tel: $telefono',
                style: TextStyle(color: AdminUi.secondary(context))),
          if (!esTarjeta) ...[
            const SizedBox(height: 6),
            Text(
              'Efectivo/transfer: no bloquea al cliente. Liberá el flag si fue error del taxista.',
              style: TextStyle(
                color: Colors.orangeAccent.withValues(alpha: 0.95),
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Monto pendiente: ${FormatosMoneda.rd(monto)} · Deuda perfil: ${FormatosMoneda.rd(deudaUsuario)}',
            style: TextStyle(
              color: AdminUi.onCard(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            viajeId.isEmpty
                ? 'UID $uidCliente · viaje no enlazado automáticamente'
                : 'Viaje #${viajeId.length > 8 ? viajeId.substring(0, 8) : viajeId} · $metodo · $estadoCobro',
            style: TextStyle(color: AdminUi.secondary(context), fontSize: 12),
          ),
          if (viajeId.isNotEmpty)
            Text(
              'Taxista: $taxista · $fechaTxt',
              style: TextStyle(color: AdminUi.secondary(context), fontSize: 12),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onVerComprobante != null)
                OutlinedButton.icon(
                  onPressed: onVerComprobante,
                  icon: const Icon(Icons.receipt_long, size: 18),
                  label: const Text('Ver comprobante'),
                ),
              FilledButton.icon(
                onPressed: accionEnCurso ? null : onRegularizar,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(esTarjeta ? 'Regularizar' : 'Liberar cliente'),
              ),
              TextButton.icon(
                onPressed: onCopiarId,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copiar ID'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
