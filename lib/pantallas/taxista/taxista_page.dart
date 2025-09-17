import 'package:flutter/material.dart';

class TaxistaPage extends StatelessWidget {
  const TaxistaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Panel Taxista"),
        centerTitle: true,
      ),
      body: const Center(
        child: Text(
          "🚖 Bienvenido Taxista",
          style: TextStyle(fontSize: 22, color: Colors.white),
        ),
      ),
    );
  }
}
