import 'package:cloud_functions/cloud_functions.dart';

abstract final class CorporativoAbordajeService {
  CorporativoAbordajeService._();

  static final _fn = FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<void> confirmarAbordaje({
    required String viajeId,
    required String pasajeroId,
  }) async {
    await _fn.httpsCallable('choferConfirmarAbordajePasajeroCorp').call({
      'viajeId': viajeId,
      'pasajeroId': pasajeroId,
    });
  }
}
