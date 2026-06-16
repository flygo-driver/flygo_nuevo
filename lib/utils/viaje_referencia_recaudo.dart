// Referencia única por viaje para recaudo Banco Popular (Fase 5).
// Formato: RAI-V-{slug8}-{checksum2}

/// Genera y valida referencias de recaudo alineadas con `functions/src/viaje_referencia.ts`.
class ViajeReferenciaRecaudo {
  ViajeReferenciaRecaudo._();

  static final RegExp _formato =
      RegExp(r'^RAI-V-[A-Z0-9]{1,8}-[0-9A-F]{2}$');

  /// `RAI-V-A1B2C3D4-7F` — slug = primeros 8 chars del [viajeId] en mayúsculas.
  static String generar(String viajeId) {
    final id = viajeId.trim();
    if (id.isEmpty) {
      throw ArgumentError('viajeId vacío');
    }
    final slugRaw = (id.length <= 8 ? id : id.substring(0, 8)).toUpperCase();
    final slug =
        slugRaw.replaceAll(RegExp(r'[^A-Z0-9]'), '').substring(0, 8);
    final slugSafe = slug.isEmpty ? 'V' : slug;
    final cs = _checksum2Hex(id);
    return 'RAI-V-$slugSafe-$cs';
  }

  static bool esFormatoValido(String? raw) {
    final ref = (raw ?? '').trim().toUpperCase();
    return ref.isNotEmpty && _formato.hasMatch(ref);
  }

  static String _checksum2Hex(String id) {
    var sum = 0;
    for (final unit in id.codeUnits) {
      sum = (sum + unit) & 0xff;
    }
    return sum.toRadixString(16).padLeft(2, '0').toUpperCase();
  }
}
