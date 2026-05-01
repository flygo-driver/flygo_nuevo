import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/pago_data.dart';
import '../../utils/estilos.dart';

class PagoTaxista extends StatefulWidget {
  const PagoTaxista({super.key});

  @override
  State<PagoTaxista> createState() => _PagoTaxistaState();
}

class _PagoTaxistaState extends State<PagoTaxista> {
  List<Map<String, dynamic>> pagos = [];
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarPagos();
  }

  Future<void> _cargarPagos() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final datos = await PagoData.obtenerPagosTaxista(user.email ?? "");
    setState(() {
      pagos = datos;
      cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EstilosRai.fondoOscuro,
      appBar: AppBar(
        title: const Text(
          "Historial de Pagos",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: EstilosRai.fondoOscuro,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: cargando
          ? const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            )
          : pagos.isEmpty
              ? const Center(
                  child: Text(
                    "Aún no has recibido pagos",
                    style: TextStyle(color: Colors.white),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: pagos.length,
                  itemBuilder: (context, index) {
                    final pago = pagos[index];
                    final fecha = DateTime.parse(pago['fecha']);
                    return Card(
                      color: Colors.grey[850],
                      child: ListTile(
                        title: Text(
                          "RD\$${pago['monto'].toStringAsFixed(2)}",
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18),
                        ),
                        subtitle: Text(
                          "Fecha: ${fecha.day}/${fecha.month}/${fecha.year} - Método: ${pago['metodo']}",
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
