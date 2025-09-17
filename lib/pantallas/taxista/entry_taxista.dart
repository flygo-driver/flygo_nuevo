import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'documentos_taxista.dart';
import 'viaje_disponible.dart';
import '../cliente/cliente_home.dart';

class TaxistaEntry extends StatefulWidget {
  const TaxistaEntry({super.key});
  @override
  State<TaxistaEntry> createState() => _TaxistaEntryState();
}

class _TaxistaEntryState extends State<TaxistaEntry> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _decidirRuta());
  }

  void _go(Widget page) {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _decidirRuta() async {
    final u = FirebaseAuth.instance.currentUser;
    if (!mounted || u == null) {
      _go(const ClienteHome()); // fallback seguro
      return;
    }

    try {
      final usrDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(u.uid)
          .get();

      final data = usrDoc.data() ?? {};
      final rol = (data['rol'] as String?)?.toLowerCase() ?? 'cliente';

      // 🛡️ GUARD DE ROL: si NO es taxista, no puede estar aquí
      if (rol != 'taxista') {
        debugPrint(
          '[TAXISTA_ENTRY] uid=${u.uid} rol=$rol -> redirigiendo a ClienteHome',
        );
        _go(const ClienteHome());
        return;
      }

      // Si es taxista, decidir por estado de documentos
      final estado =
          (data['docsEstado'] as String?)?.toLowerCase() ?? 'pendiente';
      debugPrint('[TAXISTA_ENTRY] uid=${u.uid} rol=taxista docsEstado=$estado');

      final Widget destino = (estado == 'aprobado')
          ? const ViajeDisponible()
          : const DocumentosTaxista();

      _go(destino);
    } catch (e) {
      debugPrint('[TAXISTA_ENTRY] error=$e');
      _go(const ClienteHome());
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: CircularProgressIndicator(color: Colors.greenAccent)),
    );
  }
}
