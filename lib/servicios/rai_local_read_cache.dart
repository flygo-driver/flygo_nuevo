import 'package:shared_preferences/shared_preferences.dart';

/// Caché local **solo informativa** (último estado conocido en red).
/// No sustituye a Firestore ni altera reglas de negocio.
class RaiLocalReadCache {
  RaiLocalReadCache._();

  static const String _kViaje = 'rai_cache_viaje_activo_';
  static const String _kSaldo = 'rai_cache_saldo_prepago_';

  static Future<void> rememberActiveTripId(String uid, String viajeId) async {
    final u = uid.trim();
    final v = viajeId.trim();
    if (u.isEmpty || v.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('$_kViaje$u', v);
  }

  /// Último `viajeId` activo visto (puede estar desactualizado si el viaje ya cerró).
  static Future<String?> lastKnownActiveTripId(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return null;
    final p = await SharedPreferences.getInstance();
    return p.getString('$_kViaje$u');
  }

  static Future<void> rememberSaldoPrepago(String uid, double saldoRd) async {
    final u = uid.trim();
    if (u.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setDouble('$_kSaldo$u', saldoRd);
  }

  static Future<double?> lastKnownSaldoPrepago(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return null;
    final p = await SharedPreferences.getInstance();
    if (!p.containsKey('$_kSaldo$u')) return null;
    return p.getDouble('$_kSaldo$u');
  }
}
