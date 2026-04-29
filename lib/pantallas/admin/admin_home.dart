import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/formatos_moneda.dart';
import 'admin_ui_theme.dart';
import '../../modelo/liquidacion.dart';
import '../../servicios/admin_service.dart';

// relativo porque este archivo vive junto a panel_finanzas.dart
import '../../widgets/comision_global_chip.dart';
import '../../widgets/admin_drawer.dart'; // ⬅️ NUEVO
import 'panel_finanzas.dart';

String _liquidacionesErrorMsg(Object? err) {
  if (err is FirebaseException) {
    final m = err.message?.trim();
    if (m != null && m.isNotEmpty) return m;
    return err.code;
  }
  return err.toString();
}

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _buscador = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _buscador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabSelected = AdminUi.accentGreen(context);
    final tabUnsel = AdminUi.tabUnselected(context);
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(), // ⬅️ Drawer con “Cerrar sesión”
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        iconTheme: IconThemeData(color: AdminUi.appBarFg(context)),
        title: Text(
          'Admin — Liquidaciones',
          style: TextStyle(color: AdminUi.onCard(context)),
        ),
        bottom: TabBar(
          controller: _tab,
          labelColor: tabSelected,
          unselectedLabelColor: tabUnsel,
          indicatorColor: tabSelected,
          tabs: const [
            Tab(text: 'Pendientes'),
            Tab(text: 'Aprobadas'),
            Tab(text: 'Rechazadas'),
          ],
        ),
        actions: [
          const ComisionGlobalChip(),
          IconButton(
            tooltip: 'Ver finanzas (en vivo)',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PanelFinanzasAdmin()),
              );
            },
            icon: Icon(Icons.pie_chart_outline,
                color: AdminUi.iconStandard(context)),
          ),
          IconButton(
            onPressed: () => setState(() {}),
            icon: Icon(Icons.refresh, color: AdminUi.iconStandard(context)),
            tooltip: 'Recargar',
          ),
        ],
      ),
      body: Column(
        children: [
          // Buscador simple por UID o nota
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              controller: _buscador,
              style: TextStyle(color: AdminUi.onCard(context)),
              decoration: InputDecoration(
                hintText: 'Buscar por UID de taxista o nota...',
                hintStyle: TextStyle(
                    color: AdminUi.secondary(context).withValues(alpha: 0.85)),
                prefixIcon:
                    Icon(Icons.search, color: AdminUi.secondary(context)),
                filled: true,
                fillColor: AdminUi.inputFill(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AdminUi.borderSubtle(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AdminUi.borderSubtle(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary, width: 1.4),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _LiquidacionesList(estado: 'pendiente', query: _buscador.text),
                _LiquidacionesList(estado: 'aprobado', query: _buscador.text),
                _LiquidacionesList(estado: 'rechazado', query: _buscador.text),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiquidacionesList extends StatelessWidget {
  final String estado;
  final String? query;
  const _LiquidacionesList({required this.estado, this.query});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Liquidacion>>(
      stream: AdminService.streamLiquidacionesPorEstado(estado, query: query),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
                color: AdminUi.progressAccent(context)),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off_outlined,
                      size: 48, color: AdminUi.secondary(context)),
                  const SizedBox(height: 12),
                  Text(
                    'No se pudieron cargar las liquidaciones.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AdminUi.onCard(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _liquidacionesErrorMsg(snap.error),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AdminUi.secondary(context), fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return Center(
            child: Text(
              'Sin resultados',
              style: TextStyle(color: AdminUi.secondary(context)),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final l = items[i];
            return _LiquidacionTile(l: l);
          },
        );
      },
    );
  }
}

class _LiquidacionTile extends StatelessWidget {
  final Liquidacion l;
  const _LiquidacionTile({required this.l});

  Color _chipColor(BuildContext context, String estado) {
    final light = Theme.of(context).brightness == Brightness.light;
    switch (estado) {
      case 'aprobado':
        return light ? Colors.green.shade700 : Colors.greenAccent;
      case 'rechazado':
        return light ? Colors.red.shade700 : Colors.redAccent;
      default:
        return light ? Colors.deepOrange.shade700 : Colors.orangeAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _chipColor(context, l.estado);
    final fecha = l.solicitadoEn?.toLocal().toString().substring(0, 16) ?? '—';

    final usuarioRef =
        FirebaseFirestore.instance.collection('usuarios').doc(l.uidTaxista);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header con nombre/email (fallback a UID)
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: usuarioRef.snapshots(),
            builder: (context, snap) {
              final data = snap.data?.data();
              final nombre = (data?['nombre'] ?? '').toString().trim();
              final email = (data?['email'] ?? '').toString().trim();
              final titulo = (nombre.isNotEmpty) ? nombre : l.uidTaxista;

              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AdminUi.onCard(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          email.isNotEmpty ? email : 'UID: ${l.uidTaxista}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AdminUi.muted(context), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withValues(alpha: 0.6)),
                    ),
                    child: Text(
                      l.estado.toUpperCase(),
                      style:
                          TextStyle(color: color, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 6),
          Text(
            'Monto: ${FormatosMoneda.rd(l.monto)}',
            style: TextStyle(color: AdminUi.onCard(context)),
          ),
          const SizedBox(height: 4),
          Text(
            'Solicitado: $fecha',
            style: TextStyle(color: AdminUi.secondary(context), fontSize: 12),
          ),
          if ((l.notaAdmin ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Nota: ${l.notaAdmin}',
              style: TextStyle(color: AdminUi.secondary(context), fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          _AccionesAdmin(l: l),
        ],
      ),
    );
  }
}

class _AccionesAdmin extends StatefulWidget {
  final Liquidacion l;
  const _AccionesAdmin({required this.l});

  @override
  State<_AccionesAdmin> createState() => _AccionesAdminState();
}

class _AccionesAdminState extends State<_AccionesAdmin> {
  bool _busy = false;

  Future<void> _resolver(String nuevoEstado) async {
    final notaCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AdminUi.dialogSurface(ctx),
          title: Text(
            (nuevoEstado == 'aprobado')
                ? 'Aprobar liquidación'
                : 'Rechazar liquidación',
            style: TextStyle(color: AdminUi.onCard(ctx)),
          ),
          content: TextField(
            controller: notaCtrl,
            maxLines: 3,
            style: TextStyle(color: AdminUi.onCard(ctx)),
            decoration: InputDecoration(
              labelText: nuevoEstado == 'rechazado'
                  ? 'Motivo (obligatorio)'
                  : 'Nota (opcional)',
              hintText: nuevoEstado == 'rechazado'
                  ? 'Ej: Datos bancarios incorrectos'
                  : 'Ej: Transferencia verificada, Ref #12345',
              labelStyle: TextStyle(color: AdminUi.secondary(ctx)),
              hintStyle: TextStyle(color: AdminUi.muted(ctx)),
              filled: true,
              fillColor: AdminUi.inputFill(ctx),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AdminUi.borderSubtle(ctx)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AdminUi.borderSubtle(ctx)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: Theme.of(ctx).colorScheme.primary, width: 1.4),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar',
                  style: TextStyle(color: AdminUi.secondary(ctx))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.primary,
                foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
              ),
              child: Text((nuevoEstado == 'aprobado') ? 'Aprobar' : 'Rechazar'),
            ),
          ],
        ),
      );

      if (ok != true) return;

      final nota = notaCtrl.text.trim();
      if (nuevoEstado == 'rechazado' && nota.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Indica el motivo del rechazo antes de confirmar.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      try {
        setState(() => _busy = true);
        await AdminService.resolverLiquidacion(
          id: widget.l.id,
          nuevoEstado: nuevoEstado,
          notaAdmin: nota.isEmpty ? null : nota,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text((nuevoEstado == 'aprobado')
                ? 'Liquidación aprobada'
                : 'Liquidación rechazada'),
            backgroundColor:
                nuevoEstado == 'aprobado' ? Colors.green : Colors.orange,
          ),
        );
      } on FirebaseException catch (e) {
        if (!mounted) return;
        final msg = _liquidacionesErrorMsg(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } finally {
      notaCtrl.dispose();
    }
  }

  Future<void> _revertir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminUi.dialogSurface(ctx),
        title: Text(
          'Marcar como PENDIENTE',
          style: TextStyle(color: AdminUi.onCard(ctx)),
        ),
        content: Text(
          '¿Seguro que deseas revertir esta liquidación a pendiente?',
          style: TextStyle(color: AdminUi.secondary(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: TextStyle(color: AdminUi.secondary(ctx))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.primary,
              foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
            ),
            child: const Text('Revertir'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      setState(() => _busy = true);
      await AdminService.marcarPendiente(widget.l.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Marcada como pendiente'),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_liquidacionesErrorMsg(e)),
            backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.l.estado;
    final canApproveReject = estado == 'pendiente';
    final canRevert = estado == 'aprobado' || estado == 'rechazado';

    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (canApproveReject)
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _busy ? null : () => _resolver('aprobado'),
              icon: _busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cs.onPrimary),
                    )
                  : Icon(Icons.check_circle, color: cs.onPrimary),
              label: const Text('Aprobar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        if (canApproveReject) const SizedBox(width: 12),
        if (canApproveReject)
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _busy ? null : () => _resolver('rechazado'),
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cancel, color: Colors.white),
              label: const Text('Rechazar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        if (canRevert)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _revertir,
              icon: Icon(Icons.undo, color: AdminUi.secondary(context)),
              label: Text('Revertir a pendiente',
                  style: TextStyle(color: AdminUi.onCard(context))),
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AdminUi.borderSubtle(context))),
            ),
          ),
      ],
    );
  }
}
