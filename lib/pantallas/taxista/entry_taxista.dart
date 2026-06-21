import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/app_flavor.dart';
import 'package:flygo_nuevo/auth/seleccion_usuario.dart';
import 'package:flygo_nuevo/servicios/taxista_operacion_gate.dart';
import 'package:flygo_nuevo/servicios/taxista_registro_perfil_data.dart';
import 'package:flygo_nuevo/pantallas/taxista/completar_registro_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/completar_vehiculo_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/taxista_entry_error.dart';

import 'contrato_taxista_firma.dart';
import 'documentos_taxista.dart';
import 'package:flygo_nuevo/shell/taxista_shell.dart';
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
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  Widget _destinoTaxista(Map<String, dynamic> data) {
    if (taxistaDebeCompletarDocumentosAhora(data)) {
      return const DocumentosTaxista(onboardingObligatorio: true);
    }
    final bool poolOk = taxistaAprobadoParaOperarPool(data);
    final bool contratoOk = taxistaContratoFirmado(data);
    if (poolOk && contratoOk) {
      return const TaxistaShell();
    }
    if (poolOk && !contratoOk) {
      return const ContratoTaxistaFirma();
    }
    // en_revision u otro estado sin aprobación: documentos, no pool a ciegas.
    return const DocumentosTaxista(onboardingObligatorio: true);
  }

  Future<void> _decidirRuta() async {
    final u = FirebaseAuth.instance.currentUser;
    if (!mounted) return;

    if (u == null) {
      debugPrint('[TAXISTA_ENTRY] sin sesión -> auth_check');
      Navigator.of(context).pushNamedAndRemoveUntil('/auth_check', (r) => false);
      return;
    }

    try {
      final usrDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(u.uid)
          .get();

      final data = usrDoc.data() ?? {};
      final rol = (data['rol'] as String?)?.toLowerCase() ?? '';

      if (rol != 'taxista' && rol != 'driver') {
        debugPrint(
          '[TAXISTA_ENTRY] uid=${u.uid} rol=$rol -> selección (no cliente shell)',
        );
        if (isConductorFlavor) {
          _go(const SeleccionUsuario());
        } else {
          if (!mounted) return;
          Navigator.of(context).pushNamedAndRemoveUntil('/auth_check', (r) => false);
        }
        return;
      }

      try {
        final tienePagoPendiente = data['tienePagoPendiente'] == true;
        await PoolRepo.syncPoolsPorPagoSemanal(
          ownerTaxistaId: u.uid,
          tienePagoPendiente: tienePagoPendiente,
        );
      } catch (e) {
        debugPrint('[TAXISTA_ENTRY] syncPoolsPorPagoSemanal error=$e');
      }

      if (!TaxistaRegistroPerfilData.taxistaRegistroPerfilCompleto(data)) {
        debugPrint(
          '[TAXISTA_ENTRY] uid=${u.uid} registro incompleto -> onboarding',
        );
        _go(const CompletarRegistroTaxista());
        return;
      }

      final estado = taxistaDocsEstadoDesdeUsuario(data);
      final bool vehiculoOk = taxistaVehiculoPerfilCompleto(data);
      final bool poolOk = taxistaAprobadoParaOperarPool(data);
      final bool contratoOk = taxistaContratoFirmado(data);
      debugPrint(
        '[TAXISTA_ENTRY] uid=${u.uid} docsEstado=$estado vehiculoOk=$vehiculoOk '
        'poolOk=$poolOk contratoOk=$contratoOk',
      );

      if (!vehiculoOk) {
        _go(
          CompletarVehiculoTaxista(
            onCompletado: () {
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const TaxistaEntry(),
                ),
              );
            },
          ),
        );
        return;
      }

      _go(_destinoTaxista(data));
    } catch (e) {
      debugPrint('[TAXISTA_ENTRY] error=$e');
      _go(TaxistaEntryErrorPage(message: e.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
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
