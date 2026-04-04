import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../widgets/cliente_drawer.dart';
import '../../data/pago_data.dart';

class HistorialPagosCliente extends StatefulWidget {
  const HistorialPagosCliente({super.key});

  @override
  State<HistorialPagosCliente> createState() => _HistorialPagosClienteState();
}

class _HistorialPagosClienteState extends State<HistorialPagosCliente> {
  List<Map<String, dynamic>> _pagos = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarPagos();
  }

  Future<void> _cargarPagos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) {
      setState(() {
        _cargando = false;
        _pagos = [];
      });
      return;
    }

    try {
      final pagos = await PagoData.obtenerPagosPorCliente(email);
      pagos.sort((a, b) {
        final fa = _parseFecha(a['fecha']);
        final fb = _parseFecha(b['fecha']);
        return fb.compareTo(fa); // recientes primero
      });
      if (!mounted) return;
      setState(() {
        _pagos = pagos;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  DateTime _parseFecha(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) {
      try {
        // ISO-8601 (lo que guardamos en PagoData) ordena bien y parsea bien
        return DateTime.parse(raw);
      } catch (_) {}
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      drawer: const ClienteDrawer(),
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: cs.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: Icon(Icons.menu, color: cs.onSurface),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text(
          'Mis pagos',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: user == null
          ? Center(
              child: Text(
                'Debes iniciar sesión para ver tus pagos',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            )
          : RefreshIndicator(
              color: cs.primary,
              backgroundColor: cs.surface,
              onRefresh: _cargarPagos,
              child: _buildBody(context),
            ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_cargando) {
      return Center(
        child: CircularProgressIndicator(color: cs.primary),
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 60),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Error al cargar tus pagos.\n$_error',
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              onPressed: _cargarPagos,
              icon: Icon(Icons.refresh, color: cs.primary),
              label: Text(
                'Reintentar',
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: cs.primary),
              ),
            ),
          ),
        ],
      );
    }
    if (_pagos.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Text(
              'No tienes pagos registrados.',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 18,
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _pagos.length,
      itemBuilder: (context, index) {
        final pago = _pagos[index];
        final fecha = _parseFecha(pago['fecha']);
        final monto = (pago['monto'] is num)
            ? (pago['monto'] as num).toDouble()
            : double.tryParse('${pago['monto']}') ?? 0.0;
        final metodo = '${pago['metodo'] ?? ''}';
        final estado = '${pago['estado'] ?? ''}';

        return Card(
          color: cs.surfaceContainerHighest.withValues(
            alpha: isDark ? 0.5 : 0.72,
          ),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: isDark ? 1 : 0.5,
          shadowColor: cs.shadow.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: ListTile(
            title: Text(
              "RD\$${monto.toStringAsFixed(2)}",
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              "${fecha.day}/${fecha.month}/${fecha.year} • $metodo${estado.isNotEmpty ? ' • $estado' : ''}",
              style: TextStyle(color: cs.primary),
            ),
          ),
        );
      },
    );
  }
}