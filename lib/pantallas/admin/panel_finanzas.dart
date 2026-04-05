// lib/pantallas/admin/panel_finanzas.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../servicios/wallet_service.dart';
import '../../widgets/admin_drawer.dart'; // ⬅️ NUEVO (para cerrar sesión desde el drawer)
import 'admin_ui_theme.dart';

class PanelFinanzasAdmin extends StatefulWidget {
  const PanelFinanzasAdmin({super.key});

  @override
  State<PanelFinanzasAdmin> createState() => _PanelFinanzasAdminState();
}

class _PanelFinanzasAdminState extends State<PanelFinanzasAdmin> {
  DateTime? _desde;
  DateTime? _hasta;
  String _filtro = ''; // ← filtro por nombre/email/UID
  static const int _maxDocs = 1000;

  // ======== Helpers de formato / fechas ========
  String _rd(double v) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final re = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final intPart = parts.first.replaceAllMapped(re, (m) => '${m[1]},');
    return 'RD\$ $intPart.${parts.last}';
  }

  DateTime _asDate(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime _firstRelevant(Map<String, dynamic> d) {
    final f1 = _asDate(d['finalizadoEn']);
    if (f1.millisecondsSinceEpoch > 0) return f1;
    final f2 = _asDate(d['fechaHora']);
    if (f2.millisecondsSinceEpoch > 0) return f2;
    return _asDate(d['creadoEn']);
  }

  bool _inRange(Map<String, dynamic> d) {
    if (_desde == null && _hasta == null) return true;
    final t = _firstRelevant(d);
    if (_desde != null && t.isBefore(_desde!)) return false;
    if (_hasta != null && t.isAfter(_hasta!)) return false;
    return true;
  }

  // ======== Date pickers ========
  Future<void> _pickDesde() async {
    final now = DateTime.now();
    final base = _desde ?? now.subtract(const Duration(days: 30));
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2022),
      lastDate: DateTime(now.year + 2),
      helpText: 'Desde',
    );
    if (d != null) setState(() => _desde = DateTime(d.year, d.month, d.day));
  }

  Future<void> _pickHasta() async {
    final now = DateTime.now();
    final base = _hasta ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2022),
      lastDate: DateTime(now.year + 2),
      helpText: 'Hasta',
    );
    if (d != null) setState(() => _hasta = DateTime(d.year, d.month, d.day, 23, 59, 59));
  }

  void _clearRango() {
    setState(() {
      _desde = null;
      _hasta = null;
    });
  }

  // ======== Menú (tres rayitas) ========
  void _abrirMenu() async {
    final sel = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 80, 12, 0),
      items: const [
        PopupMenuItem(value: 'filtros', child: Text('Filtros')),
        PopupMenuItem(value: 'export',  child: Text('Exportar CSV (rango)')),
      ],
    );
    if (sel == 'filtros') _abrirFiltros();
    if (sel == 'export')  _exportarCsv();
  }

  void _abrirFiltros() {
    final ctrl = TextEditingController(text: _filtro);
    showModalBottomSheet(
      context: context,
      backgroundColor: AdminUi.sheetSurface(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Filtros', style: TextStyle(color: AdminUi.onCard(sheetCtx), fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              style: TextStyle(color: AdminUi.onCard(sheetCtx)),
              decoration: InputDecoration(
                labelText: 'Buscar por nombre, email o UID',
                labelStyle: TextStyle(color: AdminUi.secondary(sheetCtx)),
                prefixIcon: Icon(Icons.search, color: AdminUi.secondary(sheetCtx)),
                filled: true,
                fillColor: AdminUi.inputFill(sheetCtx),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AdminUi.borderSubtle(sheetCtx)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AdminUi.borderSubtle(sheetCtx)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Theme.of(sheetCtx).colorScheme.primary, width: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() => _filtro = '');
                    },
                    child: const Text('Limpiar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() => _filtro = ctrl.text.trim().toLowerCase());
                    },
                    child: const Text('Aplicar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ======== Exportar CSV (rango actual) ========
  Future<void> _exportarCsv() async {
    final q = FirebaseFirestore.instance
        .collection('viajes')
        .where('estado', isEqualTo: 'completado')
        .limit(_maxDocs);

    final snap = await q.get();
    final Map<String, _AcumTaxista> byDriver = {};

    // 1) Agrupa por taxista en rango
    for (final doc in snap.docs) {
      final d = doc.data();
      if (!_inRange(d)) continue;
      final uid = (d['uidTaxista'] ?? '').toString();
      if (uid.isEmpty) continue;
      final com = _comisionCentsOf(d);
      final gan = _gananciaCentsOf(d);

      final a = byDriver.putIfAbsent(uid, () => _AcumTaxista(uid: uid));
      a.comisionCents += com;
      a.gananciaCents += gan;
      a.cantidad += 1;
      // nombre provisional si viene en viaje
      final nt = (d['nombreTaxista'] ?? '').toString();
      if (nt.isNotEmpty) a.nombre = nt;
    }

    // 2) Join a /usuarios para nombre/email (en lotes de 10)
    final uids = byDriver.keys.toList();
    final usuarios = await _fetchUsuariosMap(uids);

    for (final uid in uids) {
      final info = usuarios[uid];
      if (info != null) {
        byDriver[uid]!
          ..nombre = info['nombre'] ?? byDriver[uid]!.nombre
          ..email  = info['email']  ?? byDriver[uid]!.email;
      }
    }

    // 3) Construye CSV
    final buf = StringBuffer();
    buf.writeln('Nombre,Email,UID,Cantidad,Comision,Ganancia');
    final list = byDriver.values.toList()
      ..sort((a, b) => b.comisionCents.compareTo(a.comisionCents));
    for (final x in list) {
      final nombre = (x.nombre?.replaceAll(',', ' ') ?? '').trim();
      final email  = (x.email ?.replaceAll(',', ' ') ?? '').trim();
      buf.writeln('$nombre,$email,${x.uid},${x.cantidad},${_rd(x.comisionCents/100.0)},${_rd(x.gananciaCents/100.0)}');
    }

    final csv = buf.toString();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: AdminUi.dialogSurface(dCtx),
        title: Text('CSV del rango', style: TextStyle(color: AdminUi.onCard(dCtx))),
        content: SizedBox(
          width: 600,
          child: SelectableText(csv, style: TextStyle(color: AdminUi.secondary(dCtx))),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: csv));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('CSV copiado al portapapeles')),
              );
            },
            child: Text('Copiar', style: TextStyle(color: Theme.of(dCtx).colorScheme.primary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  // Batch fetch de /usuarios (nombre/email) en lotes de 10 (límite de whereIn)
  Future<Map<String, Map<String, String>>> _fetchUsuariosMap(List<String> uids) async {
    final out = <String, Map<String, String>>{};
    const int chunk = 10;
    for (var i = 0; i < uids.length; i += chunk) {
      final part = uids.sublist(i, (i + chunk > uids.length) ? uids.length : i + chunk);
      final qs = await FirebaseFirestore.instance
          .collection('usuarios')
          .where(FieldPath.documentId, whereIn: part)
          .get();
      for (final d in qs.docs) {
        final data = d.data();
        out[d.id] = {
          'nombre': (data['nombre'] ?? '').toString(),
          'email':  (data['email']  ?? '').toString(),
        };
      }
    }
    return out;
  }

  // ======== extractores centavos (compat con tus distintos campos) ========
  int _gananciaCentsOf(Map<String, dynamic> d) {
    final gc = d['ganancia_cents'];
    if (gc is int) return gc;
    final num? g = d['gananciaTaxista'] as num?;
    return g == null ? 0 : (g * 100).round();
  }

  int _comisionCentsOf(Map<String, dynamic> d) {
    final cc = d['comision_cents'];
    if (cc is int) return cc;
    final num? c = d['comision'] as num?;
    return c == null ? 0 : (c * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(), // ⬅️ NUEVO (mismo drawer que en AdminHome)
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        iconTheme: IconThemeData(color: AdminUi.appBarFg(context)),
        title: Text('Panel de Finanzas', style: TextStyle(color: AdminUi.onCard(context))),
        actions: [
          IconButton(
            icon: Icon(Icons.clear_all, color: AdminUi.secondary(context)),
            tooltip: 'Limpiar rango',
            onPressed: _clearRango,
          ),
          IconButton(
            icon: Icon(Icons.menu, color: AdminUi.iconStandard(context)),
            tooltip: 'Menú',
            onPressed: _abrirMenu,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _RangoPicker(
            desde: _desde,
            hasta: _hasta,
            onPickDesde: _pickDesde,
            onPickHasta: _pickHasta,
            onClear: _clearRango,
          ),
          const SizedBox(height: 12),
          const _CardResumenGlobal(),
          const SizedBox(height: 12),
          _CardResumenRango(
            inRange: _inRange,
            asDate: _firstRelevant,
            rd: _rd,
            maxDocs: _maxDocs,
          ),
          const SizedBox(height: 12),
          _CardPorTaxista(
            inRange: _inRange,
            asDate: _firstRelevant,
            rd: _rd,
            maxDocs: _maxDocs,
            filtro: _filtro,                  // ← aplica filtro texto
            fetchUsuariosMap: _fetchUsuariosMap, // ← join a /usuarios
          ),
        ],
      ),
    );
  }
}

class _RangoPicker extends StatelessWidget {
  final DateTime? desde;
  final DateTime? hasta;
  final VoidCallback onPickDesde;
  final VoidCallback onPickHasta;
  final VoidCallback onClear;
  const _RangoPicker({
    required this.desde,
    required this.hasta,
    required this.onPickDesde,
    required this.onPickHasta,
    required this.onClear,
  });

  String _fmt(DateTime? d) {
    if (d == null) return '—';
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  @override
  Widget build(BuildContext context) {
    final fg = AdminUi.onCard(context);
    final ic = AdminUi.secondary(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPickDesde,
              icon: Icon(Icons.date_range, color: ic),
              label: Text('Desde: ${_fmt(desde)}', style: TextStyle(color: fg)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPickHasta,
              icon: Icon(Icons.event, color: ic),
              label: Text('Hasta: ${_fmt(hasta)}', style: TextStyle(color: fg)),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Limpiar',
            onPressed: onClear,
            icon: Icon(Icons.clear, color: ic),
          ),
        ],
      ),
    );
  }
}

class _CardResumenGlobal extends StatelessWidget {
  const _CardResumenGlobal();

  String _rd(double v) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final re = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final intPart = parts.first.replaceAllMapped(re, (m) => '${m[1]},');
    return 'RD\$ $intPart.${parts.last}';
  }

  Color _amber(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? Colors.amber.shade900 : Colors.amberAccent;
  Color _cyan(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? Colors.teal.shade800 : Colors.cyanAccent;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, int>>(
      stream: WalletService.streamResumenGlobal(),
      builder: (context, snap) {
        final data = snap.data ?? const {'comision_cents': 0, 'ganancia_cents': 0, 'viajes_completados': 0};
        final com = (data['comision_cents'] ?? 0) / 100.0;
        final gan = (data['ganancia_cents'] ?? 0) / 100.0;
        final cnt = (data['viajes_completados'] ?? 0);

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AdminUi.card(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color.fromRGBO(76, 175, 80, 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Global (en vivo)', style: TextStyle(color: AdminUi.secondary(context), fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _metric(context, 'RAI (comisión)', _rd(com), _amber(context))),
                  Expanded(child: _metric(context, 'Conductores (ganancia)', _rd(gan), _cyan(context))),
                  _badgeCnt(context, cnt),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _metric(BuildContext context, String title, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: AdminUi.secondary(context), fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18)),
      ],
    );
  }

  Widget _badgeCnt(BuildContext context, int cnt) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(color: AdminUi.borderSubtle(context)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.local_taxi, color: AdminUi.secondary(context), size: 18),
          const SizedBox(width: 6),
          Text('$cnt', style: TextStyle(color: AdminUi.onCard(context), fontWeight: FontWeight.w700, fontSize: 16)),
        ],
      ),
    );
  }
}

class _CardResumenRango extends StatelessWidget {
  final bool Function(Map<String, dynamic>) inRange;
  final DateTime Function(Map<String, dynamic>) asDate;
  final String Function(double) rd;
  final int maxDocs;

  const _CardResumenRango({
    required this.inRange,
    required this.asDate,
    required this.rd,
    required this.maxDocs,
  });

  int _gananciaCentsOf(Map<String, dynamic> d) {
    final gc = d['ganancia_cents'];
    if (gc is int) return gc;
    final num? g = d['gananciaTaxista'] as num?;
    return g == null ? 0 : (g * 100).round();
  }

  int _comisionCentsOf(Map<String, dynamic> d) {
    final cc = d['comision_cents'];
    if (cc is int) return cc;
    final num? c = d['comision'] as num?;
    return c == null ? 0 : (c * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('viajes')
        .where('estado', isEqualTo: 'completado')
        .limit(maxDocs);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        var com = 0, gan = 0, cnt = 0;
        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final d = doc.data();
            if (!inRange(d)) continue;
            com += _comisionCentsOf(d);
            gan += _gananciaCentsOf(d);
            cnt++;
          }
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AdminUi.card(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AdminUi.borderSubtle(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rango seleccionado (en vivo)', style: TextStyle(color: AdminUi.secondary(context), fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _metric(context, 'RAI (comisión)', rd(com / 100.0), _amberR(context))),
                  Expanded(child: _metric(context, 'Conductores (ganancia)', rd(gan / 100.0), _cyanR(context))),
                  _badgeCnt(context, cnt),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Nota: se listan hasta 1000 viajes completados (filtrado local). Si necesitas más, implementa paginación.',
                style: TextStyle(color: AdminUi.muted(context).withValues(alpha: 0.85), fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _amberR(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? Colors.amber.shade900 : Colors.amberAccent;
  Color _cyanR(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? Colors.teal.shade800 : Colors.cyanAccent;

  Widget _metric(BuildContext context, String title, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: AdminUi.secondary(context), fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18)),
      ],
    );
  }

  Widget _badgeCnt(BuildContext context, int cnt) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(color: AdminUi.borderSubtle(context)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long, color: AdminUi.secondary(context), size: 18),
          const SizedBox(width: 6),
          Text('$cnt', style: TextStyle(color: AdminUi.onCard(context), fontWeight: FontWeight.w700, fontSize: 16)),
        ],
      ),
    );
  }
}

class _CardPorTaxista extends StatelessWidget {
  final bool Function(Map<String, dynamic>) inRange;
  final DateTime Function(Map<String, dynamic>) asDate;
  final String Function(double) rd;
  final int maxDocs;
  final String filtro; // ← texto de filtro
  final Future<Map<String, Map<String, String>>> Function(List<String> uids) fetchUsuariosMap;

  const _CardPorTaxista({
    required this.inRange,
    required this.asDate,
    required this.rd,
    required this.maxDocs,
    required this.filtro,
    required this.fetchUsuariosMap,
  });

  int _gananciaCentsOf(Map<String, dynamic> d) {
    final gc = d['ganancia_cents'];
    if (gc is int) return gc;
    final num? g = d['gananciaTaxista'] as num?;
    return g == null ? 0 : (g * 100).round();
  }

  int _comisionCentsOf(Map<String, dynamic> d) {
    final cc = d['comision_cents'];
    if (cc is int) return cc;
    final num? c = d['comision'] as num?;
    return c == null ? 0 : (c * 100).round();
  }

  // ⬇️ helper para mantener las filas en una sola línea en pantallas angostas
  Widget _hWrap(Widget child) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 720), // ancho mínimo para que no “salte” en vertical
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('viajes')
        .where('estado', isEqualTo: 'completado')
        .limit(maxDocs);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        final Map<String, _AcumTaxista> byDriver = {};

        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final d = doc.data();
            if (!inRange(d)) continue;

            final uid = (d['uidTaxista'] ?? '').toString();
            if (uid.isEmpty) continue;

            final com = _comisionCentsOf(d);
            final gan = _gananciaCentsOf(d);

            final a = byDriver.putIfAbsent(uid, () => _AcumTaxista(uid: uid));
            a.comisionCents += com;
            a.gananciaCents += gan;
            a.cantidad += 1;

            // nombre provisional si lo trae el viaje
            final nt = (d['nombreTaxista'] ?? '').toString();
            if (nt.isNotEmpty) a.nombre = nt;
          }
        }

        final uids = byDriver.keys.toList();

        // Join a /usuarios en un solo Future (lotes de 10)
        return FutureBuilder<Map<String, Map<String, String>>>(
          future: fetchUsuariosMap(uids),
          builder: (context, fut) {
            final usuarios = fut.data ?? const {};

            // enriquecer con nombre/email
            for (final uid in uids) {
              final x = byDriver[uid]!;
              final info = usuarios[uid];
              if (info != null) {
                x.nombre = (x.nombre?.isNotEmpty == true) ? x.nombre : info['nombre'];
                x.email  = info['email'];
              }
            }

            // a lista + ordenar
            var list = byDriver.values.toList()
              ..sort((a, b) => b.comisionCents.compareTo(a.comisionCents));

            // aplicar filtro texto (nombre/email/uid)
            final q = filtro.trim().toLowerCase();
            if (q.isNotEmpty) {
              list = list.where((x) {
                final n = (x.nombre ?? '').toLowerCase();
                final e = (x.email  ?? '').toLowerCase();
                return x.uid.toLowerCase().contains(q) || n.contains(q) || e.contains(q);
              }).toList();
            }

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AdminUi.card(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AdminUi.borderSubtle(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Resumen por taxista (rango)', style: TextStyle(color: AdminUi.secondary(context), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  if (list.isEmpty)
                    Text('No hay viajes completados en el rango.', style: TextStyle(color: AdminUi.muted(context)))
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final x = list[i];
                        final titulo = (x.nombre?.isNotEmpty == true) ? x.nombre! : x.uid;
                        final mail   = (x.email  ?? '').isNotEmpty ? ' • ${x.email}' : '';

                        return _hWrap( // ⬅️ ENVOLTURA HORIZONTAL SOLO AQUÍ
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AdminUi.inputFill(context),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AdminUi.borderSubtle(context)),
                            ),
                            child: Row(
                              children: [
                                // título + uid/email
                                SizedBox(
                                  width: 280, // ancho razonable para que no rompa
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        titulo,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: AdminUi.onCard(context), fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'UID: ${x.uid}$mail',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                _kv(context, 'Comisión', rd(x.comisionCents / 100.0), _amberT(context)),
                                const SizedBox(width: 12),
                                _kv(context, 'Ganancia', rd(x.gananciaCents / 100.0), _cyanT(context)),
                                const SizedBox(width: 12),
                                _cnt(context, x.cantidad),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Tip: usa este cuadro para saber cuánto nos debe cada taxista (comisión) y cuánto ganó.',
                    style: TextStyle(color: AdminUi.muted(context).withValues(alpha: 0.85), fontSize: 11),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Color _amberT(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? Colors.amber.shade900 : Colors.amberAccent;
  Color _cyanT(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? Colors.teal.shade800 : Colors.cyanAccent;

  Widget _kv(BuildContext context, String k, String v, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(k, style: TextStyle(color: AdminUi.secondary(context), fontSize: 12)),
        const SizedBox(height: 3),
        Text(v, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _cnt(BuildContext context, int n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(color: AdminUi.borderSubtle(context)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.directions_car_filled, color: AdminUi.secondary(context), size: 16),
          const SizedBox(width: 6),
          Text('$n', style: TextStyle(color: AdminUi.onCard(context), fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _AcumTaxista {
  final String uid;
  String? nombre;
  String? email;
  int comisionCents = 0;
  int gananciaCents = 0;
  int cantidad = 0;

  _AcumTaxista({required this.uid});
}
