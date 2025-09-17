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

    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const ClienteDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            tooltip: 'Menú',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('Mis pagos', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: user == null
          ? const Center(
              child: Text(
                'Debes iniciar sesión para ver tus pagos',
                style: TextStyle(color: Colors.white),
              ),
            )
          : RefreshIndicator(
              color: Colors.greenAccent,
              backgroundColor: Colors.black,
              onRefresh: _cargarPagos,
              child: _buildBody(),
            ),
    );
  }

  Widget _buildBody() {
    if (_cargando) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.greenAccent),
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
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              onPressed: _cargarPagos,
              icon: const Icon(Icons.refresh, color: Colors.greenAccent),
              label: const Text(
                'Reintentar',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.greenAccent),
              ),
            ),
          ),
        ],
      );
    }
    if (_pagos.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 60),
          Center(
            child: Text(
              'No tienes pagos registrados.',
              style: TextStyle(color: Colors.white, fontSize: 18),
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
          color: Colors.grey[900],
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: Text(
              "RD\$${monto.toStringAsFixed(2)}",
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            subtitle: Text(
              "${fecha.day}/${fecha.month}/${fecha.year} • $metodo${estado.isNotEmpty ? ' • $estado' : ''}",
              style: const TextStyle(color: Colors.greenAccent),
            ),
          ),
        );
      },
    );
  }
}
