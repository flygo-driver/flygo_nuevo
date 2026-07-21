import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/navegacion/taxista_finanzas_nav.dart';
import 'package:flygo_nuevo/pantallas/taxista/completar_registro_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/completar_vehiculo_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/contrato_taxista_firma.dart';
import 'package:flygo_nuevo/pantallas/taxista/documentos_taxista.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/servicios/taxista_operacion_gate.dart';
import 'package:flygo_nuevo/servicios/taxista_registro_perfil_data.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';

/// Navegación coherente con [TaxistaEntry] y [ToggleDisponibilidad] cuando
/// el taxista no puede operar en pool (aceptar viaje, etc.).
abstract final class TaxistaOperacionNav {
  TaxistaOperacionNav._();

  static bool _codigoRequierePantallaCorreccion(String codigo) {
    switch (codigo) {
      case 'registro-incompleto':
      case 'documentos-no-aprobados':
      case 'contrato-no-firmado':
      case 'bloqueado-pago-semanal':
      case 'bloqueado-comision-efectivo':
      case 'prepago-insuficiente-comision-viaje':
      case 'no-puede-recibir-viajes':
        return true;
      default:
        return codigo.startsWith('bloqueado');
    }
  }

  /// SnackBar + pantalla de corrección (no dejar al taxista atrapado en el pool).
  static Future<void> guiarTrasRechazoOperacionPool(
    BuildContext context, {
    required String codigo,
    String poolModoConductor = TaxistaPoolModoConductor.vehiculo,
  }) async {
    if (!context.mounted) return;

    if (codigo == 'prepago-insuficiente-comision-viaje') {
      await guiarTrasPrepagoInsuficienteComisionViaje(context);
      return;
    }

    if (codigo == 'bloqueado-comision-efectivo' ||
        codigo == 'bloqueado-pago-semanal' ||
        codigo.startsWith('bloqueado')) {
      await guiarTrasRecargaPrepagoOperativa(
        context,
        mensaje: taxistaMensajeClaimFallido(
          codigo,
          poolModoConductor: poolModoConductor,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          taxistaMensajeClaimFallido(
            codigo,
            poolModoConductor: poolModoConductor,
          ),
        ),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 5),
      ),
    );

    if (!_codigoRequierePantallaCorreccion(codigo)) return;

    final NavigatorState nav = Navigator.of(context, rootNavigator: true);

    switch (codigo) {
      case 'registro-incompleto':
        await nav.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const CompletarRegistroTaxista(),
          ),
        );
      case 'documentos-no-aprobados':
      case 'no-puede-recibir-viajes':
        await nav.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const DocumentosTaxista(onboardingObligatorio: true),
          ),
        );
      case 'contrato-no-firmado':
        await nav.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const ContratoTaxistaFirma(),
          ),
        );
      default:
        break;
    }
  }

  /// Pre-check de perfil antes de claim. `true` = no continuar con aceptar.
  static Future<bool> bloquearClaimSiPerfilIncompleto(
    BuildContext context, {
    required Map<String, dynamic> uData,
    String poolModoConductor = TaxistaPoolModoConductor.vehiculo,
  }) async {
    if (!taxistaVehiculoPerfilCompleto(uData)) {
      if (!context.mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Completa los datos de tu vehículo para aceptar viajes del pool.',
          ),
        ),
      );
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          builder: (ctx) => CompletarVehiculoTaxista(
            onCompletado: () => Navigator.of(ctx).pop(),
          ),
        ),
      );
      return true;
    }

    if (!TaxistaRegistroPerfilData.taxistaRegistroPerfilCompleto(uData)) {
      await guiarTrasRechazoOperacionPool(
        context,
        codigo: 'registro-incompleto',
        poolModoConductor: poolModoConductor,
      );
      return true;
    }

    final String? rechazo = taxistaRechazoAceptarViajePool(uData);
    if (rechazo != null) {
      await guiarTrasRechazoOperacionPool(
        context,
        codigo: rechazo,
        poolModoConductor: poolModoConductor,
      );
      return true;
    }

    return false;
  }

  /// Viaje en curso (normal, motor, turismo) en efectivo sin prepago para su comisión:
  /// devuelve al pool y sale de [ViajeEnCursoTaxista]. No aplica a Bola Ahorro.
  static Future<bool> _liberarViajeEnCursoSiPrepagoInsuficiente(
    BuildContext context, {
    String? viajeIdObjetivo,
  }) async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final String uid = user.uid;
      final DocumentReference<Map<String, dynamic>> uRef =
          FirebaseFirestore.instance.collection('usuarios').doc(uid);
      final DocumentSnapshot<Map<String, dynamic>> uSnap = await uRef.get();
      final String viajeActivoId =
          (uSnap.data()?['viajeActivoId'] ?? '').toString().trim();

      final String candidatoId = () {
        final String objetivo = (viajeIdObjetivo ?? '').trim();
        if (objetivo.isNotEmpty &&
            viajeActivoId.isNotEmpty &&
            objetivo == viajeActivoId) {
          return objetivo;
        }
        if (viajeActivoId.isNotEmpty) return viajeActivoId;
        return objetivo;
      }();

      if (candidatoId.isEmpty) return false;

      final DocumentSnapshot<Map<String, dynamic>> vSnap =
          await FirebaseFirestore.instance
              .collection('viajes')
              .doc(candidatoId)
              .get();
      if (!vSnap.exists) return false;
      final Map<String, dynamic> d = vSnap.data() ?? <String, dynamic>{};

      final String tipoSrv = (d['tipoServicio'] ?? 'normal').toString();
      if (tipoSrv == 'bola_ahorro') return false;

      final String uidAsignado =
          ((d['uidTaxista'] ?? d['taxistaId'] ?? '').toString()).trim();
      if (uidAsignado != uid) return false;

      if (!PagosTaxistaRepo.viajeAplicaComisionPrepago(d)) return false;

      final DocumentSnapshot<Map<String, dynamic>> bSnap =
          await FirebaseFirestore.instance
              .collection('billeteras_taxista')
              .doc(uid)
              .get();
      if (PagosTaxistaRepo.codigoRechazoPrepagoInsuficienteComisionViaje(
            billeData: bSnap.data(),
            viajeData: d,
          ) ==
          null) {
        return false;
      }

      final String estNorm =
          EstadosViaje.normalizar((d['estado'] ?? '').toString());
      if (estNorm != EstadosViaje.aceptado &&
          estNorm != EstadosViaje.enCaminoPickup) {
        return false;
      }

      await ViajesRepo.cancelarPorTaxista(
        viajeId: candidatoId,
        uidTaxista: uid,
      );

      ActiveTripService.cancelarMantenimientoOverlayViaje();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensajeViajeCanceladoPorPrepago(tipoSrv)),
            backgroundColor: Colors.orangeAccent,
            duration: const Duration(seconds: 4),
          ),
        );
        await NavigationService.irAlInicioTaxista(context: context);
      }
      return true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[TaxistaOperacionNav] liberar viaje prepago: $e $st');
      }
      return false;
    }
  }

  static String _mensajeViajeCanceladoPorPrepago(String tipoServicio) {
    if (tipoServicio == 'turismo') {
      return 'Viaje turístico cancelado por saldo prepago insuficiente. Recarga para tomar nuevos viajes.';
    }
    return 'Viaje cancelado por saldo prepago insuficiente. Recarga para tomar nuevos viajes.';
  }

  /// Punto único de navegación: libera viaje en curso si aplica y abre Mis pagos → recarga.
  static Future<void> guiarTrasRecargaPrepagoOperativa(
    BuildContext context, {
    String? mensaje,
    String? viajeId,
  }) async {
    if (!context.mounted) return;

    await _liberarViajeEnCursoSiPrepagoInsuficiente(
      context,
      viajeIdObjetivo: viajeId,
    );

    if (!context.mounted) return;
    final String texto = (mensaje ?? '').trim();
    if (texto.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: Colors.orangeAccent,
          duration: const Duration(seconds: 5),
        ),
      );
    }
    await TaxistaFinanzasNav.abrirMisPagos(
      context,
      scrollToRecargaSection: true,
    );
  }

  /// Prepago insuficiente para la comisión de un viaje en efectivo concreto.
  static Future<void> guiarTrasPrepagoInsuficienteComisionViaje(
    BuildContext context, {
    String? mensaje,
    String? viajeId,
  }) async {
    await guiarTrasRecargaPrepagoOperativa(
      context,
      mensaje:
          mensaje ?? PagosTaxistaRepo.mensajePrepagoInsuficienteComisionViajeGenerico,
      viajeId: viajeId,
    );
  }

  /// Tras fallo de claim: mensaje + pantalla si aplica.
  static Future<void> guiarTrasFalloClaim(
    BuildContext context, {
    required String res,
    String poolModoConductor = TaxistaPoolModoConductor.vehiculo,
  }) async {
    if (_codigoRequierePantallaCorreccion(res)) {
      await guiarTrasRechazoOperacionPool(
        context,
        codigo: res,
        poolModoConductor: poolModoConductor,
      );
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          taxistaMensajeClaimFallido(
            res,
            poolModoConductor: poolModoConductor,
          ),
        ),
        backgroundColor: Colors.redAccent,
      ),
    );
  }
}
