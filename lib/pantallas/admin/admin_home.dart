import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/estilos.dart';
import '../../utils/formatos_moneda.dart';
import '../../modelo/liquidacion.dart';
import '../../servicios/admin_service.dart';

// relativo porque este archivo vive junto a panel_finanzas.dart
import '../../widgets/comision_global_chip.dart';
import '../../widgets/admin_drawer.dart'; // ⬅️ NUEVO
import 'panel_finanzas.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> with SingleTickerProviderStateMixin {
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
    return Scaffold(
      backgroundColor: EstilosFlyGo.fondoOscuro,
      drawer: const AdminDrawer(), // ⬅️ Drawer con “Cerrar sesión”
      appBar: AppBar(
        backgroundColor: EstilosFlyGo.fondoOscuro,
        title: const Text(
          'Admin — Liquidaciones',
          style: TextStyle(color: EstilosFlyGo.textoBlanco),
        ),
        iconTheme: const IconThemeData(color: EstilosFlyGo.textoBlanco),
        bottom: TabBar(
          controller: _tab,
          labelColor: EstilosFlyGo.textoVerde,
          unselectedLabelColor: Colors.white70,
          indicatorColor: EstilosFlyGo.textoVerde,
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
            icon: const Icon(Icons.pie_chart_outline, color: Colors.white),
          ),
          IconButton(
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh, color: Colors.white),
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
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar por UID de taxista o nota...',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
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
          return const Center(
            child: CircularProgressIndicator(color: EstilosFlyGo.textoVerde),
          );
        }
        if (snap.hasError) {
          return Center(
            child: Text(
              'Error: ${snap.error}',
              style: const TextStyle(color: Colors.white70),
            ),
          );
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return const Center(
            child: Text(
              'Sin resultados',
              style: TextStyle(color: Colors.white70),
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

  Color _chipColor(String estado) {
    switch (estado) {
      case 'aprobado':
        return Colors.greenAccent;
      case 'rechazado':
        return Colors.redAccent;
      default:
        return Colors.orangeAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _chipColor(l.estado);
    final fecha = l.solicitadoEn?.toLocal().toString().substring(0, 16) ?? '—';

    final usuarioRef =
        FirebaseFirestore.instance.collection('usuarios').doc(l.uidTaxista);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
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
              final email  = (data?['email']  ?? '').toString().trim();
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          email.isNotEmpty ? email : 'UID: ${l.uidTaxista}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withValues(alpha: 0.6)),
                    ),
                    child: Text(
                      l.estado.toUpperCase(),
                      style: TextStyle(color: color, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 6),
          Text(
            'Monto: ${FormatosMoneda.rd(l.monto)}',
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'Solicitado: $fecha',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if ((l.notaAdmin ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Nota: ${l.notaAdmin}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: Text(
          (nuevoEstado == 'aprobado') ? 'Aprobar liquidación' : 'Rechazar liquidación',
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: notaCtrl,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Nota (opcional)',
            hintText: 'Ej: Transferencia verificada, Ref #12345',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text((nuevoEstado == 'aprobado') ? 'Aprobar' : 'Rechazar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      setState(() => _busy = true);
      await AdminService.resolverLiquidacion(
        id: widget.l.id,
        nuevoEstado: nuevoEstado,
        notaAdmin: notaCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((nuevoEstado == 'aprobado') ? '✅ Aprobada' : '❌ Rechazada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revertir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text(
          'Marcar como PENDIENTE',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          '¿Seguro que deseas revertir esta liquidación a pendiente?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
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
        const SnackBar(content: Text('↩️ Marcada como pendiente')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.l.estado;
    final canApproveReject = estado == 'pendiente';
    final canRevert = estado == 'aprobado' || estado == 'rechazado';

    return Row(
      children: [
        if (canApproveReject)
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _busy ? null : () => _resolver('aprobado'),
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_circle, color: Colors.green),
              label: const Text('Aprobar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.green,
              ),
            ),
          ),
        if (canApproveReject) const SizedBox(width: 12),
        if (canApproveReject)
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _busy ? null : () => _resolver('rechazado'),
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cancel, color: Colors.redAccent),
              label: const Text('Rechazar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.redAccent,
              ),
            ),
          ),
        if (canRevert)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _revertir,
              icon: const Icon(Icons.undo, color: Colors.white70),
              label: const Text('Revertir a pendiente', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white30)),
            ),
          ),
      ],
    );
  }
}
