/// Evita que flujos de pasajero degraden cuentas que ya son conductor.
abstract final class CuentaRolPerfilGuard {
  CuentaRolPerfilGuard._();

  static bool cuentaPareceTaxista(Map<String, dynamic> data) {
    final rol = (data['rol'] ?? '').toString().trim().toLowerCase();
    if (rol == 'taxista' || rol == 'driver') return true;
    if (data['documentosCompletos'] == true) return true;
    final docsEstado = (data['docsEstado'] ?? data['estadoDocumentos'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (docsEstado == 'aprobado' || docsEstado == 'en_revision') {
      return true;
    }
    final docs = data['docs'];
    if (docs is Map) {
      for (final key in ['licenciaUrl', 'matriculaUrl', 'seguroUrl']) {
        if ((docs[key] ?? '').toString().trim().isNotEmpty) return true;
      }
    }
    if ((data['tipoServicio'] ?? '').toString().trim().isNotEmpty) {
      return true;
    }
    if ((data['placa'] ?? '').toString().trim().isNotEmpty) return true;
    if (data['registroTaxistaCompleto'] == true) return true;
    if (data['contratoTaxistaAceptado'] == true) return true;
    return false;
  }

  /// Rol que puede escribirse desde flujos de pasajero sin pisar conductor.
  static String? rolClienteSeguroDesdeUsuario(Map<String, dynamic> data) {
    if (cuentaPareceTaxista(data)) return null;
    final rol = (data['rol'] ?? '').toString().trim().toLowerCase();
    if (rol.isNotEmpty && rol != 'cliente') return null;
    return 'cliente';
  }
}
