// lib/pantallas/admin/resumen_comisiones_admin.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../servicios/comisiones_diarias_repo.dart';
import '../../widgets/admin_drawer.dart';
import '../../utils/formatos_moneda.dart';
import 'admin_ui_theme.dart';

class ResumenComisionesAdmin extends StatefulWidget {
  const ResumenComisionesAdmin({super.key});

  @override
  State<ResumenComisionesAdmin> createState() => _ResumenComisionesAdminState();
}

class _ResumenComisionesAdminState extends State<ResumenComisionesAdmin> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _resumenHoy;
  Map<String, dynamic>? _resumenSemana;
  Map<String, dynamic>? _resumenMes;
  Map<String, dynamic>? _auditoriaViajes;
  List<Map<String, dynamic>> _topTaxistas = [];
  List<Map<String, dynamic>> _evolucionSemanal = [];
  bool _cargando = true;
  String? _errorCarga;
  
  late final TabController _tabController;
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  final NumberFormat _numberFormat = NumberFormat('#,###', 'es');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _cargarDatos();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    if (mounted) {
      setState(() {
        _cargando = true;
        _errorCarga = null;
      });
    }

    final bool esAdmin = await _validarRolAdmin();
    if (!esAdmin) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _errorCarga = 'Esta cuenta no tiene rol administrador.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Acceso denegado: inicia sesión con un usuario admin'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final Map<String, dynamic>? resumenHoy =
        await _safeLoad(() => ComisionesDiariasRepo.getComisionesHoy(), 'resumen_hoy');
    final Map<String, dynamic>? resumenSemana =
        await _safeLoad(() => ComisionesDiariasRepo.getComisionesSemana(), 'resumen_semana');
    final Map<String, dynamic>? resumenMes =
        await _safeLoad(() => ComisionesDiariasRepo.getComisionesMes(), 'resumen_mes');
    final List<Map<String, dynamic>> topTaxistas =
        await _safeLoad(() => ComisionesDiariasRepo.getTopTaxistasHoy(limite: 5), 'top_taxistas') ??
            <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> evolucion =
        await _safeLoad(() => ComisionesDiariasRepo.getEvolucionSemanal(), 'evolucion') ??
            <Map<String, dynamic>>[];
    final Map<String, dynamic>? auditoriaViajes = await _safeLoad(
      () => ComisionesDiariasRepo.getAuditoriaViajesComision(dias: 30),
      'auditoria',
    );

    if (!mounted) return;
    setState(() {
      _resumenHoy = resumenHoy;
      _resumenSemana = resumenSemana;
      _resumenMes = resumenMes;
      _auditoriaViajes = auditoriaViajes;
      _topTaxistas = topTaxistas;
      _evolucionSemanal = evolucion;
      _cargando = false;
      final bool sinResumenPrincipal =
          _resumenHoy == null && _resumenSemana == null && _resumenMes == null;
      _errorCarga = sinResumenPrincipal ? 'No se pudieron cargar las comisiones.' : null;
    });

    if (_errorCarga != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error cargando datos'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> _validarRolAdmin() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final doc = await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get();
      final data = doc.data();
      return (data?['rol']?.toString() ?? '') == 'admin';
    } catch (_) {
      return false;
    }
  }

  Future<T?> _safeLoad<T>(Future<T> Function() loader, String nombre) async {
    try {
      return await loader();
    } catch (e) {
      debugPrint('[ResumenComisionesAdmin] error en $nombre: $e');
      return null;
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
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.refresh, color: AdminUi.appBarFg(context)),
            onPressed: _cargarDatos,
            tooltip: 'Actualizar',
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
      body: _cargando
          ? Center(child: CircularProgressIndicator(color: AdminUi.progressAccent(context)))
          : (_errorCarga != null && _resumenHoy == null && _resumenSemana == null && _resumenMes == null)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _errorCarga!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AdminUi.secondary(context), fontSize: 16),
                    ),
                  ),
                )
          : TabBarView(
              controller: _tabController,
              children: <Widget>[
                _buildHoyTab(),
                _buildSemanaTab(),
                _buildMesTab(),
              ],
            ),
    );
  }

  // ===== TAB HOY =====
  Widget _buildHoyTab() {
    if (_resumenHoy == null) {
      return Center(
        child: Text('No hay datos', style: TextStyle(color: AdminUi.secondary(context))),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _buildTarjetaResumenDia(),
        const SizedBox(height: 20),
        _buildAuditoriaCard(),
        const SizedBox(height: 20),
        _buildTopTaxistas(),
        const SizedBox(height: 20),
        _buildEvolucionSemanal(),
        const SizedBox(height: 20),
        _buildAccionesRapidas(),
      ],
    );
  }

  Widget _buildTarjetaResumenDia() {
    final cs = Theme.of(context).colorScheme;
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
                _dateFormat.format(_resumenHoy!['fecha']),
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
                FormatosMoneda.rd(_resumenHoy!['totalRecaudado'] ?? 0),
                Icons.account_balance_wallet,
                AdminUi.onCard(context),
              ),
              const SizedBox(width: 12),
              _buildMetrica(
                context,
                'Viajes',
                '${_resumenHoy!['totalViajes'] ?? 0}',
                Icons.trip_origin,
                AdminUi.onCard(context),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Comisión (20%) destacada
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
                    const Text(
                      'COMISIÓN 20%',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Plataforma RAI',
                      style: TextStyle(color: AdminUi.secondary(context), fontSize: 12),
                    ),
                  ],
                ),
                Text(
                  FormatosMoneda.rd(_resumenHoy!['totalComisiones'] ?? 0),
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
                  'Taxistas ganaron (80%)',
                  style: TextStyle(color: AdminUi.secondary(context)),
                ),
                Text(
                  FormatosMoneda.rd(_resumenHoy!['totalGanancias'] ?? 0),
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

  Widget _buildMetrica(BuildContext context, String label, String value, IconData icon, Color color) {
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
                  style: TextStyle(color: AdminUi.secondary(context), fontSize: 12),
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

  Widget _buildTopTaxistas() {
    if (_topTaxistas.isEmpty) {
      return Center(
        child: Text('Sin datos de taxistas hoy', style: TextStyle(color: AdminUi.secondary(context))),
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
          ..._topTaxistas.asMap().entries.map((MapEntry<int, Map<String, dynamic>> entry) {
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
                  color: index == 1 ? Colors.amber : AdminUi.borderSubtle(context),
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
                          color: index == 1 ? Colors.black : AdminUi.onCard(context),
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
                          taxista['nombre'],
                          style: TextStyle(
                            color: AdminUi.onCard(context),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${taxista['totalViajes']} viajes',
                          style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        FormatosMoneda.rd(taxista['totalComisiones']),
                        style: TextStyle(
                          color: AdminUi.progressAccent(context),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'comisión',
                        style: TextStyle(color: AdminUi.muted(context), fontSize: 10),
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

  Widget _buildAuditoriaCard() {
    final data = _auditoriaViajes;
    if (data == null) return const SizedBox.shrink();
    final int auditados = (data['auditados'] ?? 0) as int;
    final int totalIncons = (data['totalInconsistencias'] ?? 0) as int;
    final List<Map<String, dynamic>> inconsistencias =
        ((data['inconsistencias'] ?? <dynamic>[]) as List).cast<Map<String, dynamic>>();
    final List<Map<String, dynamic>> top =
        ((data['topTaxistasInconsistentes'] ?? <dynamic>[]) as List).cast<Map<String, dynamic>>();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: totalIncons > 0 ? Colors.orange : Colors.green),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Auditoria de comisiones (30 dias): $auditados viajes',
            style: TextStyle(color: AdminUi.onCard(context), fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            totalIncons > 0
                ? 'Inconsistencias detectadas: $totalIncons'
                : 'Sin inconsistencias detectadas',
            style: TextStyle(color: totalIncons > 0 ? Colors.orangeAccent : Colors.greenAccent),
          ),
          if (top.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Choferes con incidencias abiertas:', style: TextStyle(color: AdminUi.secondary(context))),
            const SizedBox(height: 6),
            ...top.take(5).map((t) => Text(
                  '${t['uidTaxista']}: ${t['inconsistencias']}',
                  style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
                )),
          ],
          if (inconsistencias.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Primeras incidencias por viaje:', style: TextStyle(color: AdminUi.secondary(context))),
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

  Widget _buildEvolucionSemanal() {
    if (_evolucionSemanal.isEmpty) {
      return const SizedBox.shrink();
    }

    // Encontrar el valor máximo para escala
    final double maxComision = _evolucionSemanal.fold(0.0, (double prev, Map<String, dynamic> item) {
      return (item['comisiones'] > prev) ? item['comisiones'] : prev;
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
              children: _evolucionSemanal.map((Map<String, dynamic> dia) {
                final double altura = maxComision > 0 
                    ? (dia['comisiones'] / maxComision) * 80 
                    : 0;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      Container(
                        height: altura,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: AdminUi.progressAccent(context).withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        dia['nombreDia'],
                        style: TextStyle(color: AdminUi.muted(context), fontSize: 10),
                      ),
                      Text(
                        _numberFormat.format(dia['comisiones'].round()),
                        style: TextStyle(color: AdminUi.secondary(context), fontSize: 9),
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

  Widget _buildBotonAccion(String texto, IconData icono, VoidCallback onPressed) {
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

  // ===== TAB SEMANA =====
  Widget _buildSemanaTab() {
    if (_resumenSemana == null) {
      return Center(
        child: Text('No hay datos', style: TextStyle(color: AdminUi.secondary(context))),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _buildTarjetaResumenPeriodo(
          'RESUMEN SEMANAL',
          '${_dateFormat.format(_resumenSemana!['inicio'])} - ${_dateFormat.format(_resumenSemana!['fin'])}',
          _resumenSemana!['totalRecaudado'] ?? 0,
          _resumenSemana!['totalComisiones'] ?? 0,
          _resumenSemana!['totalGanancias'] ?? 0,
          _resumenSemana!['totalViajes'] ?? 0,
        ),
        const SizedBox(height: 16),
        _buildEvolucionSemanal(),
      ],
    );
  }

  // ===== TAB MES =====
  Widget _buildMesTab() {
    if (_resumenMes == null) {
      return Center(
        child: Text('No hay datos', style: TextStyle(color: AdminUi.secondary(context))),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _buildTarjetaResumenPeriodo(
          'RESUMEN MENSUAL',
          _resumenMes!['mes'],
          _resumenMes!['totalRecaudado'] ?? 0,
          _resumenMes!['totalComisiones'] ?? 0,
          _resumenMes!['totalGanancias'] ?? 0,
          _resumenMes!['totalViajes'] ?? 0,
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
  ) {
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
          
          _buildFilaResumen('Total recaudado', FormatosMoneda.rd(totalRecaudado), AdminUi.onCard(context)),
          Divider(color: AdminUi.borderSubtle(context), height: 16),
          _buildFilaResumen('Comisión 20%', FormatosMoneda.rd(totalComisiones), Colors.green, bold: true),
          Divider(color: AdminUi.borderSubtle(context), height: 16),
          _buildFilaResumen('Taxistas ganaron (80%)', FormatosMoneda.rd(totalGanancias), Colors.blue),
          Divider(color: AdminUi.borderSubtle(context), height: 16),
          _buildFilaResumen('Total de viajes', '$totalViajes viajes', AdminUi.secondary(context)),
        ],
      ),
    );
  }

  Widget _buildFilaResumen(String label, String valor, Color color, {bool bold = false}) {
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