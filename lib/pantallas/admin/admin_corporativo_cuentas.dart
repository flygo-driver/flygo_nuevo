import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_corporativo_plantillas.dart';
import 'package:flygo_nuevo/servicios/corporativo_admin_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_pago_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_ruta_service.dart';
import 'package:flygo_nuevo/utils/corporativo_historial_labels.dart';
import 'package:flygo_nuevo/widgets/admin_app_bar.dart';
import 'package:flygo_nuevo/widgets/admin_guia_uso.dart';
import 'package:flygo_nuevo/widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';

/// Admin: cuentas corporativas pendientes de cobro → marcar pagado (cuenta en cero).
class AdminCorporativoCuentasPage extends StatefulWidget {
  const AdminCorporativoCuentasPage({super.key});

  @override
  State<AdminCorporativoCuentasPage> createState() =>
      _AdminCorporativoCuentasPageState();
}

class _AdminCorporativoCuentasPageState extends State<AdminCorporativoCuentasPage> {
  String? _procesandoEmpresaId;
  String? _procesandoLiquidacionKey;
  String? _procesandoPagoKey;
  String? _procesandoAnulacionKey;

  final _fmtMonto = NumberFormat.currency(
    locale: 'es_DO',
    symbol: 'RD\$',
    decimalDigits: 0,
  );
  final _fmtFecha = DateFormat('d MMM yyyy', 'es');

  DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  Future<void> _marcarPagado(CorporativoEmpresa empresa) async {
    final periodo = empresa.periodoActual;
    final monto = periodo?.montoTotalRd ?? 0;
    final viajes = periodo?.viajesCount ?? 0;

    if (monto <= 0 && viajes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta empresa no tiene saldo pendiente.')),
      );
      return;
    }

    final bauchesPend = await CorporativoPagoService.streamPagosPendientes(
      empresa.id,
    ).first;
    if (!mounted) return;
    if (bauchesPend.isNotEmpty) {
      final forzar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AdminUi.dialogSurface(ctx),
          title: Text(
            'Hay bauche sin validar',
            style: TextStyle(color: AdminUi.onCard(ctx)),
          ),
          content: Text(
            'Esta empresa tiene ${bauchesPend.length} bauche(s) pendiente(s). '
            'Valida el comprobante antes de poner en cero, o continúa solo si ya conciliaste fuera de la app.',
            style: TextStyle(color: AdminUi.secondary(ctx), height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Poner en cero igual'),
            ),
          ],
        ),
      );
      if (forzar != true || !mounted) return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminUi.dialogSurface(ctx),
        title: Text(
          '¿Empresa pagó a RAI?',
          style: TextStyle(color: AdminUi.onCard(ctx)),
        ),
        content: Text(
          '${empresa.nombre}\n\n'
          'Viajes: $viajes\n'
          'Total: ${_fmtMonto.format(monto)}\n\n'
          'Se archiva el período y la cuenta queda en cero.',
          style: TextStyle(color: AdminUi.secondary(ctx), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, poner en cero'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _procesandoEmpresaId = empresa.id);
    try {
      final codigo = await CorporativoAdminService.marcarCuentaPagada(empresa.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            codigo != null && codigo.length == 6
                ? 'Cuenta en cero. Nuevo código período: $codigo'
                : 'Cuenta de ${empresa.nombre} puesta en cero.',
          ),
          backgroundColor: Colors.green.shade800,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _procesandoEmpresaId = null);
    }
  }

  Future<void> _marcarLiquidacionPagada({
    required CorporativoEmpresa empresa,
    required String liquidacionId,
    required double monto,
    required int viajes,
    DateTime? inicio,
    DateTime? fin,
  }) async {
    final rango = inicio != null && fin != null
        ? '${_fmtFecha.format(inicio)} → ${_fmtFecha.format(fin)}'
        : 'período archivado';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminUi.dialogSurface(ctx),
        title: Text(
          '¿Liquidación pagada?',
          style: TextStyle(color: AdminUi.onCard(ctx)),
        ),
        content: Text(
          '${empresa.nombre}\n$rango\n\n'
          'Viajes: $viajes\n'
          'Total: ${_fmtMonto.format(monto)}',
          style: TextStyle(color: AdminUi.secondary(ctx), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Marcar pagada'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final key = '${empresa.id}_$liquidacionId';
    setState(() => _procesandoLiquidacionKey = key);
    try {
      await CorporativoAdminService.marcarLiquidacionPagada(
        empresaId: empresa.id,
        liquidacionId: liquidacionId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Liquidación de ${empresa.nombre} marcada como pagada.'),
          backgroundColor: Colors.green.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _procesandoLiquidacionKey = null);
    }
  }

  Future<void> _validarPago({
    required CorporativoEmpresa empresa,
    required String pagoId,
    required bool validar,
    required double monto,
    required String metodo,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminUi.dialogSurface(ctx),
        title: Text(
          validar ? '¿Validar bauche?' : '¿Rechazar bauche?',
          style: TextStyle(color: AdminUi.onCard(ctx)),
        ),
        content: Text(
          '${empresa.nombre}\n'
          '${_fmtMonto.format(monto)} · ${CorporativoMetodosPago.etiqueta(metodo)}\n\n'
          '${validar ? 'Confirma que el depósito llegó a la cuenta RAI.' : 'El encargado deberá reenviar el comprobante.'}',
          style: TextStyle(color: AdminUi.secondary(ctx), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(validar ? 'Validar' : 'Rechazar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final key = '${empresa.id}_$pagoId';
    setState(() => _procesandoPagoKey = key);
    try {
      await CorporativoPagoService.adminValidarPago(
        empresaId: empresa.id,
        pagoId: pagoId,
        validar: validar,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validar ? 'Bauche validado.' : 'Bauche rechazado.'),
          backgroundColor:
              validar ? Colors.green.shade800 : Colors.orange.shade800,
        ),
      );
      if (validar && mounted) {
        final seguir = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AdminUi.dialogSurface(ctx),
            title: Text(
              'Bauche OK — ¿poner cuenta en cero?',
              style: TextStyle(color: AdminUi.onCard(ctx)),
            ),
            content: Text(
              'El pago quedó validado. Si el dinero ya está en la cuenta RAI, '
              'puedes archivar el período actual o la liquidación pendiente.',
              style: TextStyle(color: AdminUi.secondary(ctx), height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'luego'),
                child: const Text('Después'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'cero'),
                child: const Text('Poner período en cero'),
              ),
            ],
          ),
        );
        if (seguir == 'cero' && mounted) {
          await _marcarPagado(empresa);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _procesandoPagoKey = null);
    }
  }

  Future<void> _resolverAnulacion({
    required CorporativoEmpresa empresa,
    required String viajeId,
    required bool aprobar,
    required String nombreRuta,
    required double monto,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminUi.dialogSurface(ctx),
        title: Text(
          aprobar ? '¿Aprobar incidencia?' : '¿Rechazar incidencia?',
          style: TextStyle(color: AdminUi.onCard(ctx)),
        ),
        content: Text(
          '${empresa.nombre}\n'
          '$nombreRuta · ${_fmtMonto.format(monto)}\n\n'
          '${aprobar ? 'Se quita este día de la cuenta a cobrar.' : 'El día sigue cobrado (la ruta se considera hecha).'}',
          style: TextStyle(color: AdminUi.secondary(ctx), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(aprobar ? 'Aprobar' : 'Rechazar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final key = '${empresa.id}_$viajeId';
    setState(() => _procesandoAnulacionKey = key);
    try {
      await CorporativoPagoService.adminResolverAnulacion(
        empresaId: empresa.id,
        viajeId: viajeId,
        aprobar: aprobar,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            aprobar
                ? 'Incidencia aprobada · cobro quitado.'
                : 'Incidencia rechazada · cobro se mantiene.',
          ),
          backgroundColor:
              aprobar ? Colors.green.shade800 : Colors.orange.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _procesandoAnulacionKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      appBar: const AdminAppBar(title: 'Cuentas corporativas', guiaId: AdminGuiaIds.cuentasCorp),
      drawer: const AdminDrawer(),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // Sin filtro server-side: evita permission-denied si alguna empresa
        // no tiene encargadoUids bien tipado y el OR de rules falla el query.
        stream: FirebaseFirestore.instance
            .collection('empresas_corporativas')
            .limit(80)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final err = '${snap.error}';
            final permiso = err.toLowerCase().contains('permission');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  permiso
                      ? 'Sin permiso para ver cuentas corporativas.\n'
                          'Entrá de nuevo en /login_admin con tu correo admin '
                          '(rol admin o isAdmin=true en Firestore).'
                      : 'No se pudieron cargar las cuentas.\n$err',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AdminUi.secondary(context),
                    height: 1.4,
                  ),
                ),
              ),
            );
          }

          final docs = snap.data?.docs ?? [];
          final empresas = docs
              .map(CorporativoEmpresa.fromDoc)
              .where((e) => e.activa)
              .toList();
          if (empresas.isEmpty) {
            return Center(
              child: Text(
                'No hay empresas corporativas activas.',
                style: TextStyle(color: AdminUi.secondary(context)),
              ),
            );
          }

          empresas.sort((a, b) {
            final ma = a.periodoActual?.montoTotalRd ?? 0;
            final mb = b.periodoActual?.montoTotalRd ?? 0;
            return mb.compareTo(ma);
          });

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Text(
                'Viajes compartidos corporativos',
                style: TextStyle(
                  color: AdminUi.onCard(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Rutas del encargado (feriados, pasajeros, chofer), período, '
                'bauches e incidencias. Todo amarrado empresa ↔ encargado ↔ taxista.',
                style: TextStyle(
                  color: AdminUi.secondary(context),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              ...empresas.map((e) => _tarjetaEmpresa(context, e)),
            ],
          );
        },
      ),
    );
  }

  Widget _tarjetaEmpresa(BuildContext context, CorporativoEmpresa empresa) {
    return StreamBuilder<List<CorporativoPlantilla>>(
      stream: CorporativoRutaService.streamPlantillas(empresa.id),
      builder: (context, rutasSnap) {
        final rutas = rutasSnap.data ?? [];
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: CorporativoRutaService.streamLiquidacionesPendientes(empresa.id),
          builder: (context, liqSnap) {
            final liqsPend = liqSnap.data ?? [];
            final deudaArchivada =
                CorporativoRutaService.sumaLiquidacionesPendientes(liqsPend);

            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: CorporativoPagoService.streamPagosPendientes(empresa.id),
              builder: (context, pagoSnap) {
                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: CorporativoPagoService.streamAnulacionesPendientes(
                    empresa.id,
                  ),
                  builder: (context, anulSnap) {
                    return _tarjetaEmpresaContenido(
                      context,
                      empresa,
                      rutas: rutas,
                      liquidacionesPendientes: liqsPend,
                      deudaArchivada: deudaArchivada,
                      pagosPendientes: pagoSnap.data ?? [],
                      anulacionesPendientes: anulSnap.data ?? [],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _tarjetaEmpresaContenido(
    BuildContext context,
    CorporativoEmpresa empresa, {
    required List<CorporativoPlantilla> rutas,
    required List<Map<String, dynamic>> liquidacionesPendientes,
    required double deudaArchivada,
    required List<Map<String, dynamic>> pagosPendientes,
    required List<Map<String, dynamic>> anulacionesPendientes,
  }) {
    final p = empresa.periodoActual;
    final monto = p?.montoTotalRd ?? 0;
    final viajes = p?.viajesCount ?? 0;
    final choferes = p?.porChofer.values.toList() ?? [];
    final procesando = _procesandoEmpresaId == empresa.id;
    final totalDeuda = monto + deudaArchivada;
    final encargados = empresa.encargadosConPerfil;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: anulacionesPendientes.isNotEmpty
              ? Colors.deepOrange.withValues(alpha: 0.5)
              : pagosPendientes.isNotEmpty
                  ? Colors.blue.withValues(alpha: 0.45)
                  : totalDeuda > 0
                      ? Colors.orange.withValues(alpha: 0.45)
                      : AdminUi.borderSubtle(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            empresa.nombre,
            style: TextStyle(
              color: AdminUi.onCard(context),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          if (empresa.documentoLegal.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${empresa.etiquetaDocumento}: ${empresa.documentoLegal}',
              style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
            ),
          ],
          if (encargados.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Encargado: ${encargados.map((e) => e.nombre.trim().isNotEmpty ? e.nombre : (e.email.isNotEmpty ? e.email : 'sin nombre')).join(' · ')}',
              style: TextStyle(
                color: Colors.indigo.shade800,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _bloqueRutasOperativas(context, empresa, rutas),
          const SizedBox(height: 12),
          _fila('Período actual — viajes', '$viajes'),
          _fila('Período actual — total', _fmtMonto.format(monto),
              destacado: true),
          if (deudaArchivada > 0)
            _fila(
              'Liquidaciones pendientes',
              _fmtMonto.format(deudaArchivada),
              destacado: true,
            ),
          if (totalDeuda > 0)
            _fila('Deuda total RAI', _fmtMonto.format(totalDeuda),
                destacado: true),
          if (p?.inicio != null && p?.fin != null)
            _fila(
              'Corte período actual',
              '${_fmtFecha.format(p!.inicio!)} → ${_fmtFecha.format(p.fin!)}',
            ),
          if (choferes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Por chofer (período actual)',
              style: TextStyle(
                color: AdminUi.muted(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            ...choferes.map(
              (c) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '· ${c.nombre}: ${c.viajes} viaje(s) · ${_fmtMonto.format(c.montoRd)}',
                  style: TextStyle(
                    color: AdminUi.secondary(context),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
          if (anulacionesPendientes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Incidencias pendientes de validar',
              style: TextStyle(
                color: AdminUi.muted(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            ...anulacionesPendientes.map((h) {
              final viajeId = (h['viajeId'] ?? h['_id'] ?? '').toString();
              final nombre =
                  (h['plantillaNombre'] ?? h['referencia'] ?? 'Ruta').toString();
              final montoAnul = (h['monto'] as num?)?.toDouble() ??
                  (h['precio'] as num?)?.toDouble() ??
                  0;
              final motivo = (h['motivoAnulacion'] ?? '').toString().trim();
              final motivoLabel = motivo.isEmpty
                  ? ''
                  : CorporativoHistorialLabels.etiquetaIncidencia(motivo);
              final key = '${empresa.id}_$viajeId';
              final proc = _procesandoAnulacionKey == key;

              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.deepOrange.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$nombre · ${_fmtMonto.format(montoAnul)}',
                        style: TextStyle(
                          color: AdminUi.onCard(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      if (motivoLabel.isNotEmpty)
                        Text(
                          'Tipo: $motivoLabel',
                          style: TextStyle(
                            color: AdminUi.secondary(context),
                            fontSize: 12,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          FilledButton(
                            onPressed: proc || viajeId.isEmpty
                                ? null
                                : () => _resolverAnulacion(
                                      empresa: empresa,
                                      viajeId: viajeId,
                                      aprobar: true,
                                      nombreRuta: nombre,
                                      monto: montoAnul,
                                    ),
                            child: const Text('Aprobar incidencia'),
                          ),
                          TextButton(
                            onPressed: proc || viajeId.isEmpty
                                ? null
                                : () => _resolverAnulacion(
                                      empresa: empresa,
                                      viajeId: viajeId,
                                      aprobar: false,
                                      nombreRuta: nombre,
                                      monto: montoAnul,
                                    ),
                            child: const Text('Rechazar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
          if (pagosPendientes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Bauches pendientes de validar',
              style: TextStyle(
                color: AdminUi.muted(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            ...pagosPendientes.map((pago) {
              final pagoId = (pago['_id'] ?? '').toString();
              final montoPago = (pago['montoRd'] as num?)?.toDouble() ?? 0;
              final metodo = (pago['metodoPago'] ?? '').toString();
              final ref = (pago['referenciaBancaria'] ?? '').toString().trim();
              final url = (pago['comprobanteUrl'] ?? '').toString().trim();
              final key = '${empresa.id}_$pagoId';
              final proc = _procesandoPagoKey == key;

              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_fmtMonto.format(montoPago)} · ${CorporativoMetodosPago.etiqueta(metodo)}',
                        style: TextStyle(
                          color: AdminUi.onCard(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      if (ref.isNotEmpty)
                        Text(
                          'Ref: $ref',
                          style: TextStyle(
                            color: AdminUi.secondary(context),
                            fontSize: 12,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (url.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () async {
                                final uri = Uri.tryParse(url);
                                if (uri != null) {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              },
                              icon: const Icon(Icons.image_outlined, size: 16),
                              label: const Text('Ver bauche'),
                            ),
                          FilledButton(
                            onPressed: proc
                                ? null
                                : () => _validarPago(
                                      empresa: empresa,
                                      pagoId: pagoId,
                                      validar: true,
                                      monto: montoPago,
                                      metodo: metodo,
                                    ),
                            child: const Text('Validar'),
                          ),
                          TextButton(
                            onPressed: proc
                                ? null
                                : () => _validarPago(
                                      empresa: empresa,
                                      pagoId: pagoId,
                                      validar: false,
                                      monto: montoPago,
                                      metodo: metodo,
                                    ),
                            child: const Text('Rechazar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
          if (liquidacionesPendientes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Períodos archivados sin cobrar',
              style: TextStyle(
                color: AdminUi.muted(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            ...liquidacionesPendientes.map((lq) {
              final liqId = (lq['_id'] ?? '').toString();
              final montoLq = (lq['montoTotalRd'] as num?)?.toDouble() ?? 0;
              final viajesLq = (lq['viajesCount'] as num?)?.toInt() ?? 0;
              final ini = _ts(lq['periodoInicio']);
              final fin = _ts(lq['periodoFin']);
              final key = '${empresa.id}_$liqId';
              final proc = _procesandoLiquidacionKey == key;
              final rango = ini != null && fin != null
                  ? '${_fmtFecha.format(ini)} → ${_fmtFecha.format(fin)}'
                  : 'Período cerrado';

              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rango,
                            style: TextStyle(
                              color: AdminUi.onCard(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '$viajesLq viaje(s) · ${_fmtMonto.format(montoLq)}',
                            style: TextStyle(
                              color: AdminUi.secondary(context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: proc || liqId.isEmpty
                          ? null
                          : () => _marcarLiquidacionPagada(
                                empresa: empresa,
                                liquidacionId: liqId,
                                monto: montoLq,
                                viajes: viajesLq,
                                inicio: ini,
                                fin: fin,
                              ),
                      child: proc
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Pagada'),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: procesando ? null : () => _marcarPagado(empresa),
              icon: procesando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(
                monto > 0 || viajes > 0
                    ? 'Empresa pagó período actual — poner en cero'
                    : 'Sin saldo en período actual',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bloqueRutasOperativas(
    BuildContext context,
    CorporativoEmpresa empresa,
    List<CorporativoPlantilla> rutas,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Rutas del encargado (${rutas.length})',
                  style: TextStyle(
                    color: Colors.teal.shade900,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => AdminCorporativoPlantillasPage(
                        empresaId: empresa.id,
                        empresaNombre: empresa.nombre,
                      ),
                    ),
                  );
                },
                child: const Text('Asignar chofer'),
              ),
            ],
          ),
          if (rutas.isEmpty)
            Text(
              'El encargado aún no creó rutas en la app.',
              style: TextStyle(
                color: AdminUi.secondary(context),
                fontSize: 12,
              ),
            )
          else
            ...rutas.map((pl) => _tarjetaRutaOperativa(context, empresa, pl)),
        ],
      ),
    );
  }

  Future<void> _eliminarRutaEmpresa(
    BuildContext context,
    CorporativoEmpresa empresa,
    CorporativoPlantilla pl,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar ruta'),
        content: Text(
          '¿Eliminar «${pl.nombre}» de ${empresa.nombre}?\n\n'
          'Se borra la plantilla completa. Si hoy ya se envió al chofer '
          'y no ha empezado, se cancela automáticamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _procesandoEmpresaId = empresa.id);
    try {
      final cancelados = await CorporativoAdminService.eliminarPlantilla(
        empresaId: empresa.id,
        plantillaId: pl.id,
      );
      if (!mounted) return;
      final extra = cancelados > 0 ? ' Viaje de hoy cancelado.' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ruta eliminada.$extra')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _procesandoEmpresaId = null);
    }
  }

  Widget _tarjetaRutaOperativa(
    BuildContext context,
    CorporativoEmpresa empresa,
    CorporativoPlantilla pl,
  ) {
    final estado = CorporativoRutaService.estadoChipHoy(pl);
    final resumen = CorporativoRutaService.resumenEstadoOperativo(pl);
    final activos = pl.pasajerosActivos;
    final inactivos = pl.pasajeros.where((p) => !p.activo).toList();
    final feriados = CorporativoRutaService.proximosFeriados(pl);
    final tieneChofer =
        pl.choferPreferidoUid != null && pl.choferPreferidoUid!.isNotEmpty;

    late final Color chipColor;
    late final String chipLabel;
    switch (estado) {
      case 'feriado':
        chipColor = Colors.deepOrange.shade700;
        chipLabel = 'Hoy feriado';
      case 'pausada':
        chipColor = Colors.grey.shade700;
        chipLabel = 'Pausada';
      case 'sin_pasajeros':
        chipColor = Colors.orange.shade800;
        chipLabel = 'Sin pasajeros';
      case 'programa':
        chipColor = Colors.teal.shade800;
        chipLabel = 'Opera hoy';
      default:
        chipColor = Colors.blueGrey.shade700;
        chipLabel = 'No opera hoy';
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  pl.nombre,
                  style: TextStyle(
                    color: AdminUi.onCard(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: chipColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  chipLabel,
                  style: TextStyle(
                    color: chipColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '⏰ ${pl.horaRecogidaGrupo} · 📍 ${pl.origenLabel}',
            style: TextStyle(
              color: AdminUi.secondary(context),
              fontSize: 12,
              height: 1.3,
            ),
          ),
          Text(
            resumen,
            style: TextStyle(
              color: AdminUi.muted(context),
              fontSize: 11,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          if (tieneChofer)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.teal.shade700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${pl.choferPreferidoNombre ?? 'Chofer RAI'} está asignado para ${empresa.nombre}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          if (tieneChofer)
            Text(
              'Ruta «${pl.nombre}» · ⏰ ${pl.horaRecogidaGrupo} · '
              '${CorporativoRutaService.resumenEstadoOperativo(pl)}',
              style: TextStyle(
                color: Colors.teal.shade800,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          if (tieneChofer)
            Text(
              'Tel chofer: ${pl.choferPreferidoTelefono?.isNotEmpty == true ? pl.choferPreferidoTelefono : '—'} · '
              '${activos.length} pasajero(s) activos',
              style: TextStyle(
                color: AdminUi.secondary(context),
                fontSize: 11,
              ),
            )
          else
            Text(
              'Sin chofer asignado (Admin → Rutas / chofer)',
              style: TextStyle(
                color: Colors.orange.shade800,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (pl.pausaCausa.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Último cambio encargado: ${CorporativoPausaCausa.etiqueta(pl.pausaCausa)}'
              '${pl.pausaNota.trim().isNotEmpty ? ' · ${pl.pausaNota.trim()}' : ''}',
              style: TextStyle(
                color: Colors.indigo.shade700,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (feriados.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Feriados / no toca:',
              style: TextStyle(
                color: AdminUi.muted(context),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: feriados.map((d) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.deepOrange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '$d ✕',
                    style: TextStyle(
                      color: Colors.deepOrange.shade800,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Pasajeros: ${activos.length} activo(s)'
            '${inactivos.isNotEmpty ? ' · ${inactivos.length} fuera' : ''}',
            style: TextStyle(
              color: AdminUi.onCard(context),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (activos.isNotEmpty)
            ...activos.take(8).map(
                  (pax) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '· ${pax.nombre}'
                      '${pax.destinoLabel.trim().isNotEmpty ? ' → ${pax.destinoLabel}' : ''}',
                      style: TextStyle(
                        color: AdminUi.secondary(context),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
          if (inactivos.isNotEmpty)
            ...inactivos.take(6).map(
                  (pax) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '· ${pax.nombre} (fuera de ruta)',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 11,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                ),
          if (pl.precioAcordado > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Precio ruta: ${_fmtMonto.format(pl.precioAcordado)}',
              style: TextStyle(
                color: Colors.teal.shade700,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              onPressed: _procesandoEmpresaId == empresa.id
                  ? null
                  : () => _eliminarRutaEmpresa(context, empresa, pl),
              icon: const Icon(Icons.delete_forever_outlined, size: 18),
              label: const Text(
                'Eliminar ruta completa',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fila(String k, String v, {bool destacado = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 168,
            child: Text(
              k,
              style: TextStyle(
                color: AdminUi.muted(context),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                color: AdminUi.onCard(context),
                fontWeight: destacado ? FontWeight.w800 : FontWeight.w600,
                fontSize: destacado ? 16 : 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
