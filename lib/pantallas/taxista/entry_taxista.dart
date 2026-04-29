import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/servicios/taxista_operacion_gate.dart';

import 'contrato_taxista_firma.dart';
import 'package:flygo_nuevo/shell/taxista_shell.dart';
import 'package:flygo_nuevo/shell/cliente_shell.dart';
import '../../servicios/pool_repo.dart';

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
      _go(const ClienteShell());
      return;
    }

    try {
      final usrDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(u.uid)
          .get();

      final data = usrDoc.data() ?? {};
      final rol = (data['rol'] as String?)?.toLowerCase() ?? 'cliente';

      if (rol != 'taxista') {
        debugPrint(
          '[TAXISTA_ENTRY] uid=${u.uid} rol=$rol -> redirigiendo a ClienteHome',
        );
        _go(const ClienteShell());
        return;
      }

      // Cierre/reapertura de pools según bandera vigente en usuario.
      try {
        final tienePagoPendiente = data['tienePagoPendiente'] == true;
        await PoolRepo.syncPoolsPorPagoSemanal(
          ownerTaxistaId: u.uid,
          tienePagoPendiente: tienePagoPendiente,
        );
      } catch (e) {
        debugPrint('[TAXISTA_ENTRY] syncPoolsPorPagoSemanal error=$e');
      }

      final estado = taxistaDocsEstadoDesdeUsuario(data);
      final bool poolOk = taxistaAprobadoParaOperarPool(data);
      final bool contratoOk = taxistaContratoFirmado(data);
      debugPrint(
        '[TAXISTA_ENTRY] uid=${u.uid} rol=taxista docsEstado=$estado poolOk=$poolOk contratoOk=$contratoOk',
      );

      // 1) Sin docs aprobados → subir fotos. 2) Docs OK pero sin contrato → firma una sola vez (versión).
      // 3) Ya firmó → siempre al pool (incl. tras pagar comisión/deuda: no vuelve al contrato).
      final Widget destino;
      if (!poolOk) {
        destino = const TaxistaShell(openDocumentosOnLaunch: true);
      } else if (contratoOk) {
        destino = const TaxistaShell();
      } else {
        destino = const ContratoTaxistaFirma();
      }

      _go(destino);
    } catch (e) {
      debugPrint('[TAXISTA_ENTRY] error=$e');
      _go(const ClienteShell());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mismo lenguaje visual que el splash de [main] (entrada limpia al pool).
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/icon/logo_rai_vertical.png',
              width: 150,
              height: 150,
            ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.greenAccent),
            ),
          ],
        ),
      ),
    );
  }
}
