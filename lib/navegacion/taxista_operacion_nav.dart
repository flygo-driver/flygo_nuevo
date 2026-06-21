import 'package:flutter/material.dart';

import 'package:flygo_nuevo/navegacion/taxista_finanzas_nav.dart';
import 'package:flygo_nuevo/pantallas/taxista/completar_registro_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/completar_vehiculo_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/contrato_taxista_firma.dart';
import 'package:flygo_nuevo/pantallas/taxista/documentos_taxista.dart';
import 'package:flygo_nuevo/servicios/taxista_operacion_gate.dart';
import 'package:flygo_nuevo/servicios/taxista_registro_perfil_data.dart';
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
      case 'bloqueado-pago-semanal':
      case 'bloqueado-comision-efectivo':
        await TaxistaFinanzasNav.abrirMisPagos(
          context,
          scrollToRecargaSection: true,
        );
      default:
        if (codigo.startsWith('bloqueado')) {
          await TaxistaFinanzasNav.abrirMisPagos(
            context,
            scrollToRecargaSection: true,
          );
        }
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
