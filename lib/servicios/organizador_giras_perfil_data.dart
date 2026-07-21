import 'package:cloud_firestore/cloud_firestore.dart';

/// Perfil de quien publica giras sin manejar guagua (organizador / agencia).
abstract final class OrganizadorGirasPerfilData {
  OrganizadorGirasPerfilData._();

  static const String perfilOrganizador = 'organizador_giras';

  static bool esOrganizadorGiras(Map<String, dynamic> data) {
    final perfil = (data['perfilOperador'] ?? '').toString().trim();
    if (perfil == perfilOrganizador) return true;
    if (data['soloGiras'] == true) return true;
    final tipo = (data['tipoServicio'] ?? '').toString().trim().toLowerCase();
    return tipo == 'giras' && perfil == perfilOrganizador;
  }

  static bool cedulaValida(String? raw) {
    final v = (raw ?? '').trim();
    if (v.length < 5) return false;
    final soloDigitos = v.replaceAll(RegExp(r'\D'), '');
    if (soloDigitos.length == 11) return true;
    return v.length >= 6;
  }

  static bool registroCompleto(Map<String, dynamic> data) {
    if (data['registroOrganizadorGirasCompleto'] == false) return false;
    final nombre = (data['nombre'] ?? '').toString().trim();
    if (nombre.length < 2) return false;
    final telefono = (data['telefono'] ?? '').toString();
    if (!_telefonoRdValido(telefono)) return false;
    final cedula =
        (data['cedula'] ?? data['ciTaxista'] ?? '').toString().trim();
    if (!cedulaValida(cedula)) return false;
    final docUrl = (data['cedulaFotoUrl'] ??
            data['documentoIdentidadUrl'] ??
            '')
        .toString()
        .trim();
    if (docUrl.isEmpty) return false;
    final agencia = (data['agenciaNombre'] ?? '').toString().trim();
    if (agencia.length < 2) return false;
    if (data['registroOrganizadorGirasCompleto'] == true) return true;
    if (data['registroTaxistaCompleto'] == true && esOrganizadorGiras(data)) {
      return true;
    }
    return false;
  }

  static bool _telefonoRdValido(String? raw) {
    final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return true;
    if (digits.length == 11 && digits.startsWith('1')) return true;
    return false;
  }

  static Map<String, dynamic> mergeRegistro({
    required String nombre,
    required String telefono,
    required String whatsapp,
    required String cedula,
    required String cedulaFotoUrl,
    required String agenciaNombre,
    String? agenciaLogoUrl,
    String? bancoNombre,
    String? bancoCuenta,
    String? bancoTipoCuenta,
    String? bancoTitular,
  }) {
    final cedulaT = cedula.trim();
    final agenciaT = agenciaNombre.trim();
    final telT = telefono.trim();
    final waT = whatsapp.trim().isEmpty ? telT : whatsapp.trim();

    return {
      'nombre': nombre.trim(),
      'telefono': telT,
      'whatsapp': waT,
      'cedula': cedulaT,
      'ciTaxista': cedulaT,
      'cedulaFotoUrl': cedulaFotoUrl.trim(),
      'documentoIdentidadUrl': cedulaFotoUrl.trim(),
      'agenciaNombre': agenciaT,
      if (agenciaLogoUrl != null && agenciaLogoUrl.trim().isNotEmpty)
        'agenciaLogoUrl': agenciaLogoUrl.trim(),
      if (bancoNombre != null && bancoNombre.trim().isNotEmpty)
        'bancoNombre': bancoNombre.trim(),
      if (bancoCuenta != null && bancoCuenta.trim().isNotEmpty)
        'bancoCuenta': bancoCuenta.trim(),
      if (bancoTipoCuenta != null && bancoTipoCuenta.trim().isNotEmpty)
        'bancoTipoCuenta': bancoTipoCuenta.trim(),
      if (bancoTitular != null && bancoTitular.trim().isNotEmpty)
        'bancoTitular': bancoTitular.trim(),
      'perfilOperador': perfilOrganizador,
      'tipoServicio': 'giras',
      'soloGiras': true,
      'rol': 'taxista',
      'registroTaxistaCompleto': true,
      'registroOrganizadorGirasCompleto': true,
      'docsEstado': 'no_aplica',
      'estadoDocumentos': 'no_aplica',
      'documentosCompletos': true,
      'puedeRecibirViajes': false,
      'disponible': false,
      'actualizadoEn': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
