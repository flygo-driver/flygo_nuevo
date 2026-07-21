import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/servicios/organizador_giras_perfil_data.dart';
import 'package:flygo_nuevo/servicios/taxista_operacion_gate.dart';

/// Datos de registro operativo del conductor (Google o email).
abstract final class TaxistaRegistroPerfilData {
  TaxistaRegistroPerfilData._();

  static const Set<String> tiposServicioValidos = {
    'bola_ahorro',
    'normal',
    'motor',
    'turismo',
  };

  static bool telefonoRdValido(String? raw) {
    final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return true;
    if (digits.length == 11 && digits.startsWith('1')) return true;
    return false;
  }

  /// Nombre, teléfono, tipo de servicio y datos de vehículo (sin exigir foto).
  static bool taxistaDatosServicioCompleto(Map<String, dynamic> data) {
    final nombre = (data['nombre'] ?? '').toString().trim();
    if (nombre.length < 2) return false;
    if (!telefonoRdValido((data['telefono'] ?? '').toString())) return false;
    final tipo = (data['tipoServicio'] ?? '').toString().trim().toLowerCase();
    if (!tiposServicioValidos.contains(tipo)) return false;
    if (tipo == 'turismo') {
      final sub = (data['tipoVehiculo'] ?? data['vehiculoTipo'] ?? '')
          .toString()
          .trim();
      if (sub.isEmpty) return false;
    }
    final placa = (data['placa'] ?? '').toString().trim();
    if (placa.isEmpty) return false;
    final modelo =
        (data['vehiculoModelo'] ?? data['modelo'] ?? '').toString().trim();
    if (modelo.isEmpty) return false;
    final color =
        (data['vehiculoColor'] ?? data['color'] ?? '').toString().trim();
    if (color.isEmpty) return false;
    final anio = data['anio'] ?? data['vehiculoAnio'];
    final n = anio is int ? anio : int.tryParse(anio?.toString() ?? '');
    if (n == null || n < 1990) return false;
    return true;
  }

  static bool taxistaRegistroPerfilCamposMinimos(Map<String, dynamic> data) {
    return taxistaDatosServicioCompleto(data);
  }

  /// Vehículo con foto real (solo documentos; no bloquea registro operativo).
  static bool taxistaRegistroVehiculoConFoto(Map<String, dynamic> data) {
    return taxistaFotoVehiculoUrlDesdeUsuario(data) != null;
  }

  /// Perfil listo: datos + servicio + vehículo (foto va en [DocumentosTaxista]).
  static bool taxistaRegistroPerfilCompleto(Map<String, dynamic> data) {
    if (OrganizadorGirasPerfilData.esOrganizadorGiras(data)) {
      return OrganizadorGirasPerfilData.registroCompleto(data);
    }
    if (data['registroTaxistaCompleto'] == false) return false;
    final bool datosYVehiculo = taxistaDatosServicioCompleto(data);
    if (data['registroTaxistaCompleto'] == true) return datosYVehiculo;
    // Legacy sin flag: solo pasa si ya tiene todo (no hueco parcial tipo solo Google).
    return datosYVehiculo;
  }

  /// Merge alineado con [RegistroTaxista] + vehículo.
  static Map<String, dynamic> mergeRegistroOperativo({
    required String nombre,
    required String telefono,
    required String tipoServicio,
    required String placa,
    required String marca,
    required String modelo,
    required String color,
    required int anio,
    String? fotoVehiculoUrl,
    String? tipoVehiculoNormal,
    String? subtipoTurismo,
  }) {
    final tipo = tipoServicio.trim().toLowerCase();
    final placaUp = placa.trim().toUpperCase();
    final marcaT = marca.trim();
    final modeloT = modelo.trim();
    final colorT = color.trim();

    final datosVehiculo = <String, dynamic>{
      'placa': placaUp,
      'marca': marcaT,
      'modelo': modeloT,
      'color': colorT,
      'tipoServicio': tipo,
    };

    String vehiculoTipoLabel = modeloT;
    if (tipo == 'normal' || tipo == 'bola_ahorro') {
      final tv = (tipoVehiculoNormal ?? 'Carro').trim();
      datosVehiculo['tipoVehiculo'] = tv;
      datosVehiculo['vehiculoTipo'] = tv;
      vehiculoTipoLabel = tv;
    } else if (tipo == 'motor') {
      datosVehiculo['tipoVehiculo'] = 'Motor';
      datosVehiculo['vehiculoTipo'] = 'Motor';
      vehiculoTipoLabel = 'Motor';
    } else if (tipo == 'turismo') {
      final st = (subtipoTurismo ?? 'carro').trim();
      datosVehiculo['tipoVehiculo'] = st;
      datosVehiculo['vehiculoTipo'] = st;
      datosVehiculo['tipoServicio'] = 'turismo';
    }

    final vehiculo = taxistaMergeVehiculoPerfil(
      placa: placaUp,
      modelo: modeloT,
      anio: anio,
      color: colorT,
      marca: marcaT.isEmpty ? null : marcaT,
      fotoVehiculoUrl: fotoVehiculoUrl,
    );

    return {
      ...vehiculo,
      ...datosVehiculo,
      'nombre': nombre.trim(),
      'telefono': telefono.trim(),
      'rol': 'taxista',
      'registroTaxistaCompleto': true,
      'disponible': false,
      'docsEstado': 'pendiente',
      'estadoDocumentos': 'pendiente',
      'documentosCompletos': false,
      'puedeRecibirViajes': false,
      'docs': {
        'licenciaUrl': null,
        'matriculaUrl': null,
        'seguroUrl': null,
        'fotoVehiculoUrl': null,
        'placaUrl': null,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'vehiculoMarca': marcaT,
      'vehiculoModelo': modeloT,
      'vehiculoColor': colorT,
      'vehiculo': {
        'tipo': vehiculoTipoLabel,
        'placa': placaUp,
        'marca': marcaT,
        'modelo': modeloT,
        'color': colorT,
        'tipoServicio': tipo,
      },
      'actualizadoEn': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
