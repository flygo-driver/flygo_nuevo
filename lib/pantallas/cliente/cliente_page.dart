import 'package:flutter/material.dart';

class ClientePage extends StatelessWidget {
  const ClientePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Panel Cliente"),
        centerTitle: true,
      ),
      body: const Center(
        child: Text(
          "👤 Bienvenido Cliente",
          style: TextStyle(fontSize: 22, color: Colors.white),
        ),
      ),
    );
  }
}
