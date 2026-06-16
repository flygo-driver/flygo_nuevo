// lib/pantallas/admin/resumen_comisiones_admin.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../config/plataforma_economia.dart';
import '../../servicios/comision_viaje_pct_service.dart';
import '../../servicios/comisiones_diarias_repo.dart';
import '../../widgets/admin_drawer.dart';
import '../../utils/formatos_moneda.dart';
import 'admin_ui_theme.dart';

class ResumenComisionesAdmin extends StatefulWidget {
  const ResumenComisionesAdmin({super.key});

  @override
  State<ResumenComisionesAdmin> createState() => _ResumenComisionesAdminState();
}

class _ResumenComisionesAdminState extends State<ResumenComisionesAdmin>
    with SingleTickerProviderStateMixin {
  bool? _esAdmin;
  String? _errorAcceso;

  late final TabController _tabController;
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  final NumberFormat _numberFormat = NumberFormat('#,###', 'es');

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  String _formatFecha(dynamic v) {
    if (v is DateTime) return _dateFormat.format(v);
    if (v is Timestamp) return _dateFormat.format(v.toDate());
    return '—';
  }

  static String _fmtPct(double p) {
    if (p == p.roundToDouble()) return p.round().toString();
    return p.toStringAsFixed(1);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    ComisionViajePctService.refresh(force: true);
    _validarAcceso();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _validarAcceso() async {
    final bool esAdmin = await _validarRolAdmin();
    if (!mounted) return;
    setState(() {
      _esAdmin = esAdmin;
      _errorAcceso =
          esAdmin ? null : 'Esta cuenta no tiene rol administrador.';
    });
    if (!esAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acceso denegado: inicia sesión con un usuario admin'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> _validarRolAdmin() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();
      final data = doc.data();
      final r = (data?['rol'] ?? '').toString().trim().toLowerCase();
      return r == 'admin' || r == 'administrador';
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        iconTheme: IconThemeData(color: AdminUi.appBarFg(context)),
        title: Text(
          'Resumen de Comisiones',
          style: TextStyle(color: AdminUi.onCard(context)),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                'En vivo',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AdminUi.progressAccent(context),
          labelColor: AdminUi.progressAccent(context),
          unselectedLabelColor: AdminUi.tabUnselected(context),
          tabs: const <Widget>[
            Tab(text: 'HOY'),
            Tab(text: 'SEMANA'),
            Tab(text: 'MES'),
          ],
        ),
      ),
      body: _esAdmin == null
          ? Center(
              child: CircularProgressIndicator(
                  color: AdminUi.progressAccent(context)))
          : (_esAdmin != true)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _errorAcceso ?? 'Acceso denegado',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AdminUi.secondary(context), fontSize: 16),
                    ),
                  ),
                )
              : StreamBuilder<double>(
                  stream: ComisionViajePctService.streamPorcentajeVigente(),
                  initialData: PlataformaEconomia.comisionViajePorcentaje,
                  builder: (context, pctSnap) {
                    final double pctVigente =
                        pctSnap.data ?? PlataformaEconomia.comisionViajePorcentaje;
                    return StreamBuilder<
                        List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                      stream: ComisionesDiariasRepo
                          .streamViajesCompletadosMesActual(),
                      builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(
                            color: AdminUi.progressAccent(context)),
                      );
                    }
                    if (snap.hasError) {
                      final err = snap.error.toString();
                      final pideIndice = err.contains('index') ||
                          err.contains('failed-precondition');
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_off_outlined,
                                  size: 48,
                                  color: AdminUi.secondary(context)),
                              const SizedBox(height: 12),
                              Text(
                                pideIndice
                                    ? 'Falta un índice en Firestore para comisiones.'
                                    : 'Error cargando viajes',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AdminUi.onCard(context),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                pideIndice
                                    ? 'En la terminal del proyecto ejecuta:\n'
                                        'firebase deploy --only firestore:indexes\n'
                                        'Luego espera 2–10 min en Firebase Console → Firestore → Índices.'
                                    : err,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: AdminUi.secondary(context),
                                    fontSize: 13,
                                    height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final mesDocs = snap.data ?? const [];
                    final resumenHoy =
                        ComisionesDiariasRepo.resumenHoyDesdeDocs(mesDocs);
                    final resumenSemana =
                        ComisionesDiariasRepo.resumenSemanaDesdeDocs(mesDocs);
                    final resumenMes =
                        ComisionesDiariasRepo.resumenMesDesdeDocs(mesDocs);
                    final topTaxistas =
                        ComisionesDiariasRepo.topTaxistasHoyDesdeDocs(mesDocs);
                    final evolucionSemanal =
                        ComisionesDiariasRepo.evolucionSemanalDesdeDocs(mesDocs);
                    final auditoriaViajes =
                        ComisionesDiariasRepo.auditoriaViajesDesdeDocs(mesDocs);

                    return Column(
                      children: <Widget>[
                        _bannerComisionGlobal(context, pctVigente),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: <Widget>[
                              _buildHoyTab(
                                resumenHoy,
                                topTaxistas,
                                evolucionSemanal,
                                auditoriaViajes,
                                pctVigente,
                              ),
                              _buildSemanaTab(
                                resumenSemana,
                                evolucionSemanal,
                                pctVigente,
                              ),
                              _buildMesTab(resumenMes, pctVigente),
                            ],
                          ),
                        ),
                      ],
                    );
                      },
                    );
                  },
                ),
    );
  }

  Widget _bannerComisionGlobal(BuildContext context, double pctVigente) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: Text(
        'Comisión global vigente: ${_fmtPct(pctVigente)}%. '
        'Los totales suman la comisión registrada en cada viaje al completarse; '
        'viajes nuevos usarán el % actual.',
        style: TextStyle(
          color: AdminUi.secondary(context),
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }

  // ===== TAB HOY =====
  Widget _buildHoyTab(
    Map<String, dynamic> resumenHoy,
    List<Map<String, dynamic>> topTaxistas,
    List<Map<String, dynamic>> evolucionSemanal,
    Map<String, dynamic> auditoriaViajes,
    double pctVigente,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _buildTarjetaResumenDia(resumenHoy, pctVigente),
        const SizedBox(height: 20),
        _buildAuditoriaCard(auditoriaViajes),
        const SizedBox(height: 20),
        _buildTopTaxistas(topTaxistas),
        const SizedBox(height: 20),
        _buildEvolucionSemanal(evolucionSemanal),
        const SizedBox(height: 20),
        _buildAccionesRapidas(),
      ],
    );
  }

  Widget _buildTarjetaResumenDia(
    Map<String, dynamic> resumenHoy,
    double pctVigente,
  ) {
    final cs = Theme.of(context).colorScheme;
    final pctEfectivo =
        (resumenHoy['porcentajeComision'] ?? _fmtPct(pctVigente)).toString();
    final pctChofer = 100.0 - pctVigente;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AdminUi.light(context)
              ? <Color>[cs.primaryContainer, cs.surfaceContainerHighest]
              : const <Color>[Color(0xFF1A3D2A), Color(0xFF0A1A0F)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text(
                'HOY',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              Text(
                _formatFecha(resumenHoy['fecha']),
                style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Métricas principales
          Row(
            children: <Widget>[
              _buildMetrica(
                context,
                'Total recaudado',
                FormatosMoneda.rd(_toDouble(resumenHoy['totalRecaudado'])),
                Icons.account_balance_wallet,
                AdminUi.onCard(context),
              ),
              const SizedBox(width: 12),
              _buildMetrica(
                context,
                'Viajes',
                '${_toInt(resumenHoy['totalViajes'])}',
                Icons.trip_origin,
                AdminUi.onCard(context),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'COMISIÓN ${_fmtPct(pctVigente)}%',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Promedio hoy: $pctEfectivo% · Plataforma RAI',
                      style: TextStyle(
                          color: AdminUi.secondary(context), fontSize: 12),
                    ),
                  ],
                ),
                Text(
                  FormatosMoneda.rd(_toDouble(resumenHoy['totalComisiones'])),
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Ganancias de taxistas
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AdminUi.inputFill(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'Taxistas ganaron (${_fmtPct(pctChofer)}%)',
                  style: TextStyle(color: AdminUi.secondary(context)),
                ),
                Text(
                  FormatosMoneda.rd(_toDouble(resumenHoy['totalGanancias'])),
                  style: const TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetrica(BuildContext context, String label, String value,
      IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AdminUi.inputFill(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                      color: AdminUi.secondary(context), fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopTaxistas(List<Map<String, dynamic>> topTaxistas) {
    if (topTaxistas.isEmpty) {
      return Center(
        child: Text('Sin datos de taxistas hoy',
            style: TextStyle(color: AdminUi.secondary(context))),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.emoji_events, color: Colors.amber),
              const SizedBox(width: 8),
              Text(
                'TOP TAXISTAS DEL DÍA',
                style: TextStyle(
                  color: AdminUi.onCard(context),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...topTaxistas
              .asMap()
              .entries
              .map((MapEntry<int, Map<String, dynamic>> entry) {
            final int index = entry.key + 1;
            final Map<String, dynamic> taxista = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: index == 1
                    ? Colors.amber.withValues(alpha: 0.1)
                    : AdminUi.card(context).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color:
                      index == 1 ? Colors.amber : AdminUi.borderSubtle(context),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: index == 1 ? Colors.amber : Colors.grey[800],
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '#$index',
                        style: TextStyle(
                          color: index == 1
                              ? Colors.black
                              : AdminUi.onCard(context),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          (taxista['nombre'] ?? '—').toString(),
                          style: TextStyle(
                            color: AdminUi.onCard(context),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_toInt(taxista['totalViajes'])} viajes',
                          style: TextStyle(
                              color: AdminUi.muted(context), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        FormatosMoneda.rd(
                            _toDouble(taxista['totalComisiones'])),
                        style: TextStyle(
                          color: AdminUi.progressAccent(context),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'comisión',
                        style: TextStyle(
                            color: AdminUi.muted(context), fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildAuditoriaCard(Map<String, dynamic> data) {
    final int auditados = _toInt(data['auditados']);
    final int totalIncons = _toInt(data['totalInconsistencias']);
    final List<Map<String, dynamic>> inconsistencias =
        ((data['inconsistencias'] ?? <dynamic>[]) as List)
            .cast<Map<String, dynamic>>();
    final List<Map<String, dynamic>> top =
        ((data['topTaxistasInconsistentes'] ?? <dynamic>[]) as List)
            .cast<Map<String, dynamic>>();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: totalIncons > 0 ? Colors.orange : Colors.green),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Auditoria de comisiones (30 dias): $auditados viajes',
            style: TextStyle(
                color: AdminUi.onCard(context), fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            totalIncons > 0
                ? 'Inconsistencias detectadas: $totalIncons'
                : 'Sin inconsistencias detectadas',
            style: TextStyle(
                color:
                    totalIncons > 0 ? Colors.orangeAccent : Colors.greenAccent),
          ),
          if (top.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Choferes con incidencias abiertas:',
                style: TextStyle(color: AdminUi.secondary(context))),
            const SizedBox(height: 6),
            ...top.take(5).map((t) => Text(
                  '${t['uidTaxista']}: ${t['inconsistencias']}',
                  style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
                )),
          ],
          if (inconsistencias.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Primeras incidencias por viaje:',
                style: TextStyle(color: AdminUi.secondary(context))),
            const SizedBox(height: 6),
            ...inconsistencias.take(5).map((r) => Text(
                  '${r['viajeId']} - ${r['motivo']} (${r['uidTaxista']})',
                  style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildEvolucionSemanal(List<Map<String, dynamic>> evolucionSemanal) {
    if (evolucionSemanal.isEmpty) {
      return const SizedBox.shrink();
    }

    // Encontrar el valor máximo para escala
    final double maxComision =
        evolucionSemanal.fold(0.0, (double prev, Map<String, dynamic> item) {
      final c = _toDouble(item['comisiones']);
      return c > prev ? c : prev;
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.show_chart, color: AdminUi.progressAccent(context)),
              const SizedBox(width: 8),
              Text(
                'EVOLUCIÓN SEMANAL',
                style: TextStyle(
                  color: AdminUi.onCard(context),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: evolucionSemanal.map((Map<String, dynamic> dia) {
                final com = _toDouble(dia['comisiones']);
                final double altura =
                    maxComision > 0 ? (com / maxComision) * 80 : 0;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      Container(
                        height: altura,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: AdminUi.progressAccent(context)
                              .withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        (dia['nombreDia'] ?? '—').toString(),
                        style: TextStyle(
                            color: AdminUi.muted(context), fontSize: 10),
                      ),
                      Text(
                        _numberFormat.format(com.round()),
                        style: TextStyle(
                            color: AdminUi.secondary(context), fontSize: 9),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccionesRapidas() {
    return Row(
      children: <Widget>[
        Expanded(
          child: _buildBotonAccion(
            'Ver pagos pendientes',
            Icons.pending_actions,
            () => Navigator.pushNamed(context, '/verificar_pagos'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildBotonAccion(
            'Exportar reporte',
            Icons.download,
            () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Función próximamente')),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBotonAccion(
      String texto, IconData icono, VoidCallback onPressed) {
    final cs = Theme.of(context).colorScheme;
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icono, size: 18),
      label: Text(texto),
      style: ElevatedButton.styleFrom(
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildSemanaTab(
    Map<String, dynamic> resumenSemana,
    List<Map<String, dynamic>> evolucionSemanal,
    double pctVigente,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _buildTarjetaResumenPeriodo(
          'RESUMEN SEMANAL',
          '${_formatFecha(resumenSemana['inicio'])} - ${_formatFecha(resumenSemana['fin'])}',
          _toDouble(resumenSemana['totalRecaudado']),
          _toDouble(resumenSemana['totalComisiones']),
          _toDouble(resumenSemana['totalGanancias']),
          _toInt(resumenSemana['totalViajes']),
          pctVigente,
        ),
        const SizedBox(height: 16),
        _buildEvolucionSemanal(evolucionSemanal),
      ],
    );
  }

  // ===== TAB MES =====
  Widget _buildMesTab(Map<String, dynamic> resumenMes, double pctVigente) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _buildTarjetaResumenPeriodo(
          'RESUMEN MENSUAL',
          (resumenMes['mes'] ?? '—').toString(),
          _toDouble(resumenMes['totalRecaudado']),
          _toDouble(resumenMes['totalComisiones']),
          _toDouble(resumenMes['totalGanancias']),
          _toInt(resumenMes['totalViajes']),
          pctVigente,
        ),
      ],
    );
  }

  Widget _buildTarjetaResumenPeriodo(
    String titulo,
    String subtitulo,
    double totalRecaudado,
    double totalComisiones,
    double totalGanancias,
    int totalViajes,
    double pctVigente,
  ) {
    final pctChofer = 100.0 - pctVigente;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                titulo,
                style: TextStyle(
                  color: AdminUi.progressAccent(context),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                subtitulo,
                style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildFilaResumen('Total recaudado',
              FormatosMoneda.rd(totalRecaudado), AdminUi.onCard(context)),
          Divider(color: AdminUi.borderSubtle(context), height: 16),
          _buildFilaResumen(
              'Comisión ${_fmtPct(pctVigente)}%',
              FormatosMoneda.rd(totalComisiones),
              Colors.green,
              bold: true),
          Divider(color: AdminUi.borderSubtle(context), height: 16),
          _buildFilaResumen(
              'Taxistas ganaron (${_fmtPct(pctChofer)}%)',
              FormatosMoneda.rd(totalGanancias),
              Colors.blue),
          Divider(color: AdminUi.borderSubtle(context), height: 16),
          _buildFilaResumen('Total de viajes', '$totalViajes viajes',
              AdminUi.secondary(context)),
        ],
      ),
    );
  }

  Widget _buildFilaResumen(String label, String valor, Color color,
      {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: AdminUi.secondary(context),
            fontSize: 14,
          ),
        ),
        Text(
          valor,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
