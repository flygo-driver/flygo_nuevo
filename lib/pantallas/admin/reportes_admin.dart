// lib/pantallas/admin/reportes_admin.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'admin_ui_theme.dart';

class ReportesAdmin extends StatefulWidget {
  const ReportesAdmin({super.key});

  @override
  State<ReportesAdmin> createState() => _ReportesAdminState();
}

class _ReportesAdminState extends State<ReportesAdmin> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  int _dias = 7;
  String _estadoReporte = 'todos';
  final TextEditingController _buscarCtrl = TextEditingController();
  String _buscar = '';
  int _diasReportes = 7;
  String _filtroPromo = 'todos';
  int _diasAuditoriaPromo = 30;

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? 0.0;
    return 0.0;
  }

  bool _esCompletado(String estado) {
    final e = estado.trim().toLowerCase();
    return e == 'completado' || e == 'completed';
  }

  bool _esCancelado(String estado) {
    final e = estado.trim().toLowerCase();
    return e == 'cancelado' || e == 'canceled';
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Timestamp desde = Timestamp.fromDate(
      DateTime.now().subtract(Duration(days: _dias)),
    );

    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        iconTheme: IconThemeData(color: AdminUi.appBarFg(context)),
        title: Text('Reportes y Estadísticas',
            style: TextStyle(color: AdminUi.onCard(context))),
        actions: [
          PopupMenuButton<int>(
            onSelected: (int v) {
              setState(() {
                _dias = v;
              });
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 1, child: Text('Últimas 24 horas')),
              PopupMenuItem(value: 7, child: Text('Últimos 7 días')),
              PopupMenuItem(value: 30, child: Text('Últimos 30 días')),
            ],
            icon: Icon(Icons.filter_alt_outlined,
                color: AdminUi.appBarFg(context)),
          ),
        ],
      ),
      body: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
        future: _db
            .collection('viajes')
            .where('updatedAt', isGreaterThanOrEqualTo: desde)
            .get(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(
                    color: AdminUi.progressAccent(context)));
          }
          if (snap.hasError) {
            return Center(
              child: Text(
                'Error: ${snap.error}',
                style: TextStyle(color: AdminUi.secondary(context)),
              ),
            );
          }

          final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
              snap.data?.docs ??
                  <QueryDocumentSnapshot<Map<String, dynamic>>>[];

          final int total = docs.length;

          int completados = 0;
          int cancelados = 0;

          double sumaPrecio = 0.0;
          double sumaComision = 0.0;

          for (final doc in docs) {
            final Map<String, dynamic> m = doc.data();
            final String estado = (m['estado'] ?? '').toString();

            if (_esCompletado(estado)) {
              completados++;
            }
            if (_esCancelado(estado)) {
              cancelados++;
            }

            sumaPrecio += _toDouble(m['precio']);
            sumaComision += _toDouble(m['comision']);
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              _chipPeriodo(context),
              const SizedBox(height: 14),
              _cardNumero(context, 'Total viajes', total.toString()),
              const SizedBox(height: 10),
              _cardNumero(context, 'Completados', completados.toString()),
              const SizedBox(height: 10),
              _cardNumero(context, 'Cancelados', cancelados.toString()),
              const SizedBox(height: 14),
              _cardMoney(context, 'Suma precios (aprox)', sumaPrecio),
              const SizedBox(height: 10),
              _cardMoney(context, 'Suma comisiones (aprox)', sumaComision),
              const SizedBox(height: 12),
              _filtroPromoCard(context),
              const SizedBox(height: 12),
              _auditoriaPromoCard(context, docs),
              const SizedBox(height: 12),
              _filtroHistoricoPromoCard(context),
              const SizedBox(height: 12),
              _historicoAuditoriaPromoCard(context),
              const SizedBox(height: 16),
              _filtroReportesCard(context),
              const SizedBox(height: 12),
              _filtroFechaReportesCard(context),
              const SizedBox(height: 12),
              _busquedaReportesCard(context),
              const SizedBox(height: 12),
              _reportesQuejasCard(context),
              const SizedBox(height: 16),
              Text(
                'Nota: esto calcula leyendo viajes recientes. Para producción grande, lo ideal es guardar stats agregadas.',
                style: TextStyle(
                    color: AdminUi.muted(context).withValues(alpha: 0.85)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chipPeriodo(BuildContext context) {
    String t;
    if (_dias == 1) {
      t = 'Últimas 24 horas';
    } else if (_dias == 7) {
      t = 'Últimos 7 días';
    } else {
      t = 'Últimos 30 días';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_month, color: AdminUi.secondary(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t,
              style: TextStyle(color: AdminUi.onCard(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtroReportesCard(BuildContext context) {
    final estados = <String>['todos', 'pendiente', 'en_revision', 'cerrado'];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: Row(
        children: [
          Icon(Icons.tune, color: AdminUi.secondary(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Estado de reportes',
              style: TextStyle(
                  color: AdminUi.onCard(context), fontWeight: FontWeight.w700),
            ),
          ),
          DropdownButton<String>(
            value: _estadoReporte,
            dropdownColor: AdminUi.dialogSurface(context),
            style: TextStyle(color: AdminUi.onCard(context)),
            underline: const SizedBox.shrink(),
            items: estados
                .map((e) => DropdownMenuItem<String>(
                      value: e,
                      child: Text(e == 'todos' ? 'Todos' : e),
                    ))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _estadoReporte = v);
            },
          ),
        ],
      ),
    );
  }

  Widget _busquedaReportesCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: TextField(
        controller: _buscarCtrl,
        onChanged: (v) => setState(() => _buscar = v.trim().toLowerCase()),
        style: TextStyle(color: AdminUi.onCard(context)),
        decoration: InputDecoration(
          hintText: 'Buscar por viajeId o uidTaxista',
          hintStyle: TextStyle(
              color: AdminUi.secondary(context).withValues(alpha: 0.85)),
          prefixIcon: Icon(Icons.search, color: AdminUi.secondary(context)),
          filled: true,
          fillColor: AdminUi.inputFill(context),
          suffixIcon: _buscar.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close, color: AdminUi.secondary(context)),
                  onPressed: () {
                    _buscarCtrl.clear();
                    setState(() => _buscar = '');
                  },
                ),
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
            borderSide: BorderSide(color: cs.primary, width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _filtroFechaReportesCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: Row(
        children: [
          Icon(Icons.date_range, color: AdminUi.secondary(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Rango de reportes',
              style: TextStyle(
                  color: AdminUi.onCard(context), fontWeight: FontWeight.w700),
            ),
          ),
          DropdownButton<int>(
            value: _diasReportes,
            dropdownColor: AdminUi.dialogSurface(context),
            style: TextStyle(color: AdminUi.onCard(context)),
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 1, child: Text('Hoy')),
              DropdownMenuItem(value: 7, child: Text('7 días')),
              DropdownMenuItem(value: 30, child: Text('30 días')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _diasReportes = v);
            },
          ),
        ],
      ),
    );
  }

  Widget _filtroPromoCard(BuildContext context) {
    const opciones = <String>[
      'todos',
      'con_descuento',
      'sin_descuento',
      'sin_snapshot',
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: Row(
        children: [
          Icon(Icons.local_offer_outlined, color: AdminUi.secondary(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Auditoría Promo MxK',
              style: TextStyle(
                  color: AdminUi.onCard(context), fontWeight: FontWeight.w700),
            ),
          ),
          DropdownButton<String>(
            value: _filtroPromo,
            dropdownColor: AdminUi.dialogSurface(context),
            style: TextStyle(color: AdminUi.onCard(context)),
            underline: const SizedBox.shrink(),
            items: opciones
                .map(
                  (e) => DropdownMenuItem<String>(
                    value: e,
                    child: Text(
                      switch (e) {
                        'con_descuento' => 'Con descuento',
                        'sin_descuento' => 'Sin descuento',
                        'sin_snapshot' => 'Sin snapshot',
                        _ => 'Todos',
                      },
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _filtroPromo = v);
            },
          ),
        ],
      ),
    );
  }

  Widget _filtroHistoricoPromoCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: Row(
        children: [
          Icon(Icons.history, color: AdminUi.secondary(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Histórico auditoría promo',
              style: TextStyle(
                  color: AdminUi.onCard(context), fontWeight: FontWeight.w700),
            ),
          ),
          DropdownButton<int>(
            value: _diasAuditoriaPromo,
            dropdownColor: AdminUi.dialogSurface(context),
            style: TextStyle(color: AdminUi.onCard(context)),
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 1, child: Text('Hoy')),
              DropdownMenuItem(value: 7, child: Text('7 días')),
              DropdownMenuItem(value: 30, child: Text('30 días')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _diasAuditoriaPromo = v);
            },
          ),
        ],
      ),
    );
  }

  Map<String, dynamic>? _promoSnapshotDeViaje(Map<String, dynamic> viaje) {
    final extras = viaje['extras'];
    if (extras is! Map) return null;
    final raw = extras['promoSnapshot'];
    if (raw is! Map) return null;
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  bool _matchesFiltroPromo(Map<String, dynamic>? ps) {
    if (_filtroPromo == 'todos') return true;
    if (_filtroPromo == 'sin_snapshot') return ps == null;
    if (ps == null) return false;
    final aplica = ps['aplicaDescuento'] == true;
    if (_filtroPromo == 'con_descuento') return aplica;
    if (_filtroPromo == 'sin_descuento') return !aplica;
    return true;
  }

  Widget _auditoriaPromoCard(BuildContext context,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final List<Map<String, dynamic>> viajesConPromo = docs
        .map((d) {
          final data = d.data();
          final ps = _promoSnapshotDeViaje(data);
          return {
            'id': d.id,
            'estado': (data['estado'] ?? '').toString(),
            'precio': _toDouble(data['precio']),
            'promoSnapshot': ps,
          };
        })
        .where((v) =>
            _matchesFiltroPromo(v['promoSnapshot'] as Map<String, dynamic>?))
        .toList();

    final int conSnapshot =
        docs.where((d) => _promoSnapshotDeViaje(d.data()) != null).length;
    final int conDescuento = docs.where((d) {
      final ps = _promoSnapshotDeViaje(d.data());
      return ps != null && ps['aplicaDescuento'] == true;
    }).length;
    final int sinSnapshot = docs.length - conSnapshot;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Auditoría Promo MxK (viajes)',
            style: TextStyle(
                color: AdminUi.onCard(context),
                fontWeight: FontWeight.w800,
                fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Total: ${docs.length} · Con snapshot: $conSnapshot · Con descuento: $conDescuento · Sin snapshot: $sinSnapshot',
            style: TextStyle(color: AdminUi.secondary(context)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: viajesConPromo.isEmpty
                  ? null
                  : () => _exportarPromoCsv(viajesConPromo),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Exportar CSV auditoría promo'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: viajesConPromo.isEmpty
                  ? null
                  : () => _copiarResumenPromo(
                        context,
                        docsBase: docs,
                        docsFiltrados: viajesConPromo,
                      ),
              icon: const Icon(Icons.content_copy_outlined),
              label: const Text('Copiar resumen promo'),
            ),
          ),
          const SizedBox(height: 10),
          if (viajesConPromo.isEmpty)
            Text('Sin viajes para el filtro seleccionado.',
                style: TextStyle(color: AdminUi.secondary(context))),
          for (final v in viajesConPromo.take(12)) ...[
            Builder(
              builder: (_) {
                final ps = v['promoSnapshot'] as Map<String, dynamic>?;
                final aplica = ps?['aplicaDescuento'] == true;
                final pos = ps?['posicionCiclo'];
                final contador = ps?['contadorViajesEvaluado'];
                final modo = (ps?['modo'] ?? '-').toString();
                final etiqueta = ps == null
                    ? 'sin snapshot'
                    : (aplica ? 'descuento aplicado' : 'sin descuento');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '• ${v['id']} · ${v['estado']} · RD\$ ${(v['precio'] as double).toStringAsFixed(2)} · $etiqueta · modo $modo · pos ${pos ?? '-'} · contador ${contador ?? '-'}',
                    style: TextStyle(
                        color: AdminUi.secondary(context), fontSize: 12),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _cambiarEstadoReporte(String id, String estado) async {
    await _db.collection('reportes_viaje').doc(id).set(
      {
        'estado': estado,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  String _csvCell(Object? value) {
    final raw = (value ?? '').toString().replaceAll('"', '""');
    return '"$raw"';
  }

  Future<void> _exportarPromoCsv(List<Map<String, dynamic>> viajes) async {
    if (viajes.isEmpty) return;
    final sb = StringBuffer();
    sb.writeln(
      'viajeId,estado,precio,aplicaDescuento,modo,m,k,porcentaje,posicionCiclo,contadorViajesEvaluado,snapshotVersion,calculadoEn',
    );
    for (final v in viajes) {
      final ps = v['promoSnapshot'] as Map<String, dynamic>?;
      sb.writeln([
        _csvCell(v['id']),
        _csvCell(v['estado']),
        _csvCell((v['precio'] as double).toStringAsFixed(2)),
        _csvCell(ps == null
            ? ''
            : (ps['aplicaDescuento'] == true ? 'true' : 'false')),
        _csvCell(ps?['modo']),
        _csvCell(ps?['m']),
        _csvCell(ps?['k']),
        _csvCell(ps?['porcentaje']),
        _csvCell(ps?['posicionCiclo']),
        _csvCell(ps?['contadorViajesEvaluado']),
        _csvCell(ps?['version']),
        _csvCell(ps?['calculadoEn']),
      ].join(','));
    }

    final filename =
        'auditoria_promo_mxk_${DateTime.now().millisecondsSinceEpoch}.csv';
    final bytes = Uint8List.fromList(utf8.encode(sb.toString()));
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'text/csv')],
      fileNameOverrides: [filename],
      text: 'Exportación auditoría Promo MxK',
      subject: 'Auditoría Promo MxK',
    );
  }

  Future<void> _exportarHistoricoAuditoriaPromoCsv(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (docs.isEmpty) return;
    final sb = StringBuffer();
    sb.writeln(
      'id,createdAt,uidAdmin,filtroPromo,diasBase,totalBase,conSnapshotBase,conDescuentoBase,sinSnapshotBase,pctDescuentoBase,totalFiltrado,conDescuentoFiltrado,sinDescuentoFiltrado,sinSnapshotFiltrado',
    );
    for (final d in docs) {
      final data = d.data();
      final createdAtRaw = data['createdAt'];
      final createdAt = createdAtRaw is Timestamp
          ? createdAtRaw.toDate().toIso8601String()
          : '';
      sb.writeln([
        _csvCell(d.id),
        _csvCell(createdAt),
        _csvCell(data['uidAdmin']),
        _csvCell(data['filtroPromo']),
        _csvCell(data['diasBase']),
        _csvCell(data['totalBase']),
        _csvCell(data['conSnapshotBase']),
        _csvCell(data['conDescuentoBase']),
        _csvCell(data['sinSnapshotBase']),
        _csvCell(data['pctDescuentoBase']),
        _csvCell(data['totalFiltrado']),
        _csvCell(data['conDescuentoFiltrado']),
        _csvCell(data['sinDescuentoFiltrado']),
        _csvCell(data['sinSnapshotFiltrado']),
      ].join(','));
    }

    final filename =
        'historico_auditoria_promo_${DateTime.now().millisecondsSinceEpoch}.csv';
    final bytes = Uint8List.fromList(utf8.encode(sb.toString()));
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'text/csv')],
      fileNameOverrides: [filename],
      text: 'Exportación histórico auditoría promo MxK',
      subject: 'Histórico auditoría promo MxK',
    );
  }

  Widget _historicoAuditoriaPromoCard(BuildContext context) {
    final DateTime limite =
        DateTime.now().subtract(Duration(days: _diasAuditoriaPromo));
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _db
          .collection('config')
          .where('tipo', isEqualTo: 'auditoria_promo_mxk')
          .limit(200)
          .get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _cardNumero(
              context, 'Histórico auditoría promo', 'Cargando...');
        }
        if (snap.hasError) {
          return _cardNumero(context, 'Histórico auditoría promo', 'Error');
        }

        final allDocs =
            snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final docs = allDocs.where((d) {
          final createdAtRaw = d.data()['createdAt'];
          if (createdAtRaw is! Timestamp) return false;
          return !createdAtRaw.toDate().isBefore(limite);
        }).toList()
          ..sort((a, b) {
            final ta = a.data()['createdAt'];
            final tb = b.data()['createdAt'];
            final da = ta is Timestamp
                ? ta.toDate()
                : DateTime.fromMillisecondsSinceEpoch(0);
            final db = tb is Timestamp
                ? tb.toDate()
                : DateTime.fromMillisecondsSinceEpoch(0);
            return db.compareTo(da);
          });

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AdminUi.card(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AdminUi.borderSubtle(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Histórico auditoría promo (${docs.length})',
                style: TextStyle(
                  color: AdminUi.onCard(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: docs.isEmpty
                      ? null
                      : () => _exportarHistoricoAuditoriaPromoCsv(docs),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Exportar CSV histórico'),
                ),
              ),
              const SizedBox(height: 10),
              if (docs.isEmpty)
                Text(
                  'Sin auditorías guardadas en el rango seleccionado.',
                  style: TextStyle(color: AdminUi.secondary(context)),
                ),
              for (final d in docs.take(12)) ...[
                Builder(
                  builder: (_) {
                    final data = d.data();
                    final createdAtRaw = data['createdAt'];
                    final createdAt = createdAtRaw is Timestamp
                        ? createdAtRaw.toDate().toString()
                        : '-';
                    final pct = (data['pctDescuentoBase'] ?? 0).toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '• ${d.id} · $createdAt · filtro ${data['filtroPromo'] ?? '-'} · total ${data['totalBase'] ?? 0} · dto ${data['conDescuentoBase'] ?? 0} ($pct%)',
                        style: TextStyle(
                            color: AdminUi.secondary(context), fontSize: 12),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _copiarResumenPromo(
    BuildContext context, {
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docsBase,
    required List<Map<String, dynamic>> docsFiltrados,
  }) async {
    final int totalBase = docsBase.length;
    final int conSnapshotBase =
        docsBase.where((d) => _promoSnapshotDeViaje(d.data()) != null).length;
    final int conDescuentoBase = docsBase.where((d) {
      final ps = _promoSnapshotDeViaje(d.data());
      return ps != null && ps['aplicaDescuento'] == true;
    }).length;
    final int sinSnapshotBase = totalBase - conSnapshotBase;

    int conDescuentoFiltrado = 0;
    int sinDescuentoFiltrado = 0;
    int sinSnapshotFiltrado = 0;
    for (final v in docsFiltrados) {
      final ps = v['promoSnapshot'] as Map<String, dynamic>?;
      if (ps == null) {
        sinSnapshotFiltrado++;
      } else if (ps['aplicaDescuento'] == true) {
        conDescuentoFiltrado++;
      } else {
        sinDescuentoFiltrado++;
      }
    }

    final double pctDescuento =
        totalBase == 0 ? 0 : (conDescuentoBase * 100.0 / totalBase);
    final String fecha = DateTime.now().toIso8601String();
    final sb = StringBuffer()
      ..writeln('Resumen ejecutivo Promo MxK - RAI DRIVER')
      ..writeln('Generado: $fecha')
      ..writeln('Filtro promo actual: $_filtroPromo')
      ..writeln('Periodo base estadisticas: $_dias dia(s)')
      ..writeln('Total viajes (base): $totalBase')
      ..writeln('Con snapshot (base): $conSnapshotBase')
      ..writeln('Con descuento (base): $conDescuentoBase')
      ..writeln('Sin snapshot (base): $sinSnapshotBase')
      ..writeln('% descuento sobre base: ${pctDescuento.toStringAsFixed(1)}%')
      ..writeln('---')
      ..writeln('Viajes en vista filtrada: ${docsFiltrados.length}')
      ..writeln('Con descuento (filtrado): $conDescuentoFiltrado')
      ..writeln('Sin descuento (filtrado): $sinDescuentoFiltrado')
      ..writeln('Sin snapshot (filtrado): $sinSnapshotFiltrado');

    final resumen = sb.toString();
    await Clipboard.setData(ClipboardData(text: resumen));

    // Trazabilidad persistente para auditoría admin.
    try {
      final uidAdmin = FirebaseAuth.instance.currentUser?.uid ?? '';
      final docId = 'auditoria_promo_${DateTime.now().millisecondsSinceEpoch}';
      await _db.collection('config').doc(docId).set({
        'tipo': 'auditoria_promo_mxk',
        'filtroPromo': _filtroPromo,
        'diasBase': _dias,
        'totalBase': totalBase,
        'conSnapshotBase': conSnapshotBase,
        'conDescuentoBase': conDescuentoBase,
        'sinSnapshotBase': sinSnapshotBase,
        'pctDescuentoBase': double.parse(pctDescuento.toStringAsFixed(2)),
        'totalFiltrado': docsFiltrados.length,
        'conDescuentoFiltrado': conDescuentoFiltrado,
        'sinDescuentoFiltrado': sinDescuentoFiltrado,
        'sinSnapshotFiltrado': sinSnapshotFiltrado,
        'uidAdmin': uidAdmin,
        'resumenTexto': resumen,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Si falla la persistencia, no bloquea el copiado.
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Resumen promo copiado y guardado en auditoría.')),
    );
  }

  Future<void> _exportarReportesCsv(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (docs.isEmpty) return;
    final sb = StringBuffer();
    sb.writeln(
        'id,viajeId,uidCliente,uidTaxista,motivo,comentario,estado,creadoEn');
    for (final d in docs) {
      final data = d.data();
      final creadoEn = data['creadoEn'];
      final fecha =
          creadoEn is Timestamp ? creadoEn.toDate().toIso8601String() : '';
      sb.writeln([
        _csvCell(d.id),
        _csvCell(data['viajeId']),
        _csvCell(data['uidCliente']),
        _csvCell(data['uidTaxista']),
        _csvCell(data['motivo']),
        _csvCell(data['comentario']),
        _csvCell(data['estado']),
        _csvCell(fecha),
      ].join(','));
    }

    final filename = 'reportes_${DateTime.now().millisecondsSinceEpoch}.csv';
    final bytes = Uint8List.fromList(utf8.encode(sb.toString()));
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'text/csv')],
      fileNameOverrides: [filename],
      text: 'Exportación de reportes de clientes',
      subject: 'Reportes RAI DRIVER',
    );
  }

  Future<void> _copiarResumenEjecutivo(
    BuildContext context, {
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required List<MapEntry<String, int>> topTaxistas,
  }) async {
    int pendientes = 0;
    int enRevision = 0;
    int cerrados = 0;
    for (final d in docs) {
      final e =
          (d.data()['estado'] ?? 'pendiente').toString().trim().toLowerCase();
      if (e == 'cerrado') {
        cerrados++;
      } else if (e == 'en_revision') {
        enRevision++;
      } else {
        pendientes++;
      }
    }

    final fecha = DateTime.now().toIso8601String();
    final sb = StringBuffer()
      ..writeln('Resumen ejecutivo reportes - RAI DRIVER')
      ..writeln('Generado: $fecha')
      ..writeln('Filtro estado: $_estadoReporte')
      ..writeln('Filtro rango: $_diasReportes dia(s)')
      ..writeln('Filtro busqueda: ${_buscar.isEmpty ? 'N/A' : _buscar}')
      ..writeln('Total reportes: ${docs.length}')
      ..writeln('Pendientes: $pendientes')
      ..writeln('En revision: $enRevision')
      ..writeln('Cerrados: $cerrados')
      ..writeln('Top choferes con reportes abiertos:');

    if (topTaxistas.isEmpty) {
      sb.writeln('- Sin choferes con reportes abiertos');
    } else {
      for (final e in topTaxistas.take(5)) {
        sb.writeln('- ${e.key}: ${e.value} abiertos');
      }
    }

    await Clipboard.setData(ClipboardData(text: sb.toString()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Resumen ejecutivo copiado al portapapeles.')),
    );
  }

  Widget _cardNumero(BuildContext context, String title, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: AdminUi.secondary(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: AdminUi.onCard(context),
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardMoney(BuildContext context, String title, double value) {
    final String txt = value.toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: AdminUi.secondary(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            'RD\$ $txt',
            style: TextStyle(
              color: AdminUi.onCard(context),
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportesQuejasCard(BuildContext context) {
    final DateTime limite =
        DateTime.now().subtract(Duration(days: _diasReportes));
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('reportes_viaje').snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _cardNumero(context, 'Reportes de clientes', 'Cargando...');
        }
        if (snap.hasError) {
          return _cardNumero(context, 'Reportes de clientes', 'Error');
        }
        final allDocs =
            snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final docs = allDocs.where((d) {
          final creadoEn = d.data()['creadoEn'];
          if (creadoEn is Timestamp) {
            if (creadoEn.toDate().isBefore(limite)) return false;
          }
          if (_estadoReporte == 'todos') return true;
          final e = (d.data()['estado'] ?? 'pendiente')
              .toString()
              .trim()
              .toLowerCase();
          return e == _estadoReporte;
        }).where((d) {
          if (_buscar.isEmpty) return true;
          final data = d.data();
          final viajeId = (data['viajeId'] ?? '').toString().toLowerCase();
          final uidTaxista =
              (data['uidTaxista'] ?? '').toString().toLowerCase();
          return viajeId.contains(_buscar) || uidTaxista.contains(_buscar);
        }).toList()
          ..sort((a, b) {
            final ta = (a.data()['creadoEn'] as Timestamp?)?.toDate() ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final tb = (b.data()['creadoEn'] as Timestamp?)?.toDate() ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return tb.compareTo(ta);
          });

        final docsEnRango = allDocs.where((d) {
          final creadoEn = d.data()['creadoEn'];
          return creadoEn is Timestamp && !creadoEn.toDate().isBefore(limite);
        });
        final Map<String, int> abiertosPorTaxista = <String, int>{};
        for (final d in docsEnRango) {
          final data = d.data();
          final estado =
              (data['estado'] ?? 'pendiente').toString().trim().toLowerCase();
          if (estado == 'cerrado') continue;
          final uidTaxista = (data['uidTaxista'] ?? '').toString().trim();
          if (uidTaxista.isEmpty) continue;
          abiertosPorTaxista[uidTaxista] =
              (abiertosPorTaxista[uidTaxista] ?? 0) + 1;
        }
        final topTaxistas = abiertosPorTaxista.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AdminUi.card(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AdminUi.borderSubtle(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reportes de clientes (${docs.length})',
                style: TextStyle(
                  color: AdminUi.onCard(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      docs.isEmpty ? null : () => _exportarReportesCsv(docs),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Exportar CSV (filtros actuales)'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: docs.isEmpty
                      ? null
                      : () => _copiarResumenEjecutivo(
                            context,
                            docs: docs,
                            topTaxistas: topTaxistas,
                          ),
                  icon: const Icon(Icons.content_copy_outlined),
                  label: const Text('Copiar resumen ejecutivo'),
                ),
              ),
              if (topTaxistas.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Choferes con más reportes abiertos',
                  style: TextStyle(
                      color: AdminUi.secondary(context),
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                for (final e in topTaxistas.take(3))
                  Text(
                    '• ${e.key} · ${e.value} abiertos',
                    style: TextStyle(color: AdminUi.secondary(context)),
                  ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 10),
              if (docs.isEmpty)
                Text(
                  _buscar.isEmpty
                      ? 'Sin reportes recientes.'
                      : 'Sin resultados para "$_buscar".',
                  style: TextStyle(color: AdminUi.secondary(context)),
                ),
              for (final d in docs) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '• ${(d.data()['motivo'] ?? 'Sin motivo').toString()}'
                        ' · viaje ${(d.data()['viajeId'] ?? '').toString()}'
                        ' · estado ${((d.data()['estado'] ?? 'pendiente').toString())}',
                        style: TextStyle(color: AdminUi.secondary(context)),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert,
                          color: AdminUi.muted(context), size: 18),
                      onSelected: (v) => _cambiarEstadoReporte(d.id, v),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'pendiente',
                            child: Text('Marcar pendiente')),
                        PopupMenuItem(
                            value: 'en_revision',
                            child: Text('Marcar en revisión')),
                        PopupMenuItem(
                            value: 'cerrado', child: Text('Marcar cerrado')),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ],
          ),
        );
      },
    );
  }
}
