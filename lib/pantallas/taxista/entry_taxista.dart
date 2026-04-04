import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/servicios/taxista_operacion_gate.dart';

import 'documentos_taxista.dart';
import 'contrato_taxista_firma.dart';
import 'viaje_disponible.dart';
import '../cliente/cliente_home.dart';
import '../../widgets/rai_app_bar.dart';
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
      _go(const ClienteHome());
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
        _go(const ClienteHome());
        return;
      }

      // Cierre de pools por deuda semanal (consistencia con pagos/ADM).
      // Si el taxista no ha pagado, sus pools deben quedar "no disponibles".
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

      final Widget destino = !poolOk
          ? const DocumentosTaxista()
          : (contratoOk ? const ViajeDisponible() : const ContratoTaxistaFirma());

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
      appBar: RaiAppBar(
        title: 'Conductor',
      ),
      body: Center(
        child: CircularProgressIndicator(
          color: Colors.greenAccent,
        ),
      ),
    );
  }
}