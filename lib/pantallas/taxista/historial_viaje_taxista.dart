// lib/pantallas/taxista/historial_viajes_taxista.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/data/viaje_data.dart';     // ✅ ViajeData en /data
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/utils/estilos.dart';

import '../../widgets/taxista_drawer.dart';
import '../../widgets/saldo_ganancias_chip.dart';

class HistorialViajesTaxista extends StatefulWidget {
  const HistorialViajesTaxista({super.key});

  @override
  State<HistorialViajesTaxista> createState() => _HistorialViajesTaxistaState();
}

class _HistorialViajesTaxistaState extends State<HistorialViajesTaxista> {
  List<Viaje> historial = <Viaje>[];
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  String _fmtFecha(DateTime dt) {
    String two(int x) => x.toString().padLeft(2, '0');
    return "${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}";
  }

  Future<void> _cargarHistorial() async {
    final messenger = ScaffoldMessenger.of(context); // capturar antes del await
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() => cargando = false);
        return;
      }

      // ViajeData en /data: obtiene solo viajes completados del taxista
      final datos = await ViajeData.obtenerHistorialTaxista(user.email ?? "");

      if (!mounted) return;
      setState(() {
        historial = datos;
        cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => cargando = false);
      messenger.showSnackBar(
        SnackBar(content: Text("Error al cargar historial: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EstilosFlyGo.fondoOscuro,
      drawer: const TaxistaDrawer(),
      appBar: AppBar(
        backgroundColor: EstilosFlyGo.fondoOscuro,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: EstilosFlyGo.textoBlanco),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            tooltip: 'Menú',
          ),
        ),
        foregroundColor: EstilosFlyGo.textoBlanco,
        title: const Text(
          "Historial de Viajes",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: EstilosFlyGo.textoBlanco),
        actions: const [SaldoGananciasChip()],
      ),
      body: cargando
          ? const Center(
              child: CircularProgressIndicator(color: EstilosFlyGo.textoVerde),
            )
          : (historial.isEmpty
              ? const Center(
                  child: Text(
                    "No hay viajes completados aún.",
                    style: TextStyle(fontSize: 18, color: Colors.white70),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargarHistorial,
                  color: EstilosFlyGo.textoVerde,
                  backgroundColor: EstilosFlyGo.fondoOscuro,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: historial.length,
                    itemBuilder: (context, index) {
                      final v = historial[index];
                      return Card(
                        color: Colors.grey[900],
                        elevation: 3,
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${v.origen} → ${v.destino}",
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (v.clienteId.isNotEmpty)
                                const SizedBox(height: 2),
                              if (v.clienteId.isNotEmpty)
                                Text(
                                  "Cliente ID: ${v.clienteId}",
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                  ),
                                ),
                              const SizedBox(height: 6),
                              Text(
                                "Fecha: ${_fmtFecha(v.fechaHora)}",
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Precio: RD\$${v.precio.toStringAsFixed(2)}",
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.greenAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                )),
    );
  }
}
