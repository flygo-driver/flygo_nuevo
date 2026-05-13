import 'package:cloud_functions/cloud_functions.dart';

class AdminConfigService {
  static final FirebaseFunctions _fx = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  static Future<void> updateTarifasCriticas({
    required Map<String, dynamic> tarifasGeneral,
    required Map<String, dynamic> tarifaTurismo,
    required String motivo,
  }) async {
    final c = _fx.httpsCallable('updateTarifasCriticas');
    await c.call(<String, dynamic>{
      'tarifasGeneral': tarifasGeneral,
      'tarifaTurismo': tarifaTurismo,
      'motivo': motivo,
    });
  }

  static Future<void> updatePromo3x1Config({
    required bool activa,
    required int porcentaje,
    required int m,
    required int k,
    required String motivo,
  }) async {
    final c = _fx.httpsCallable('updatePromo3x1Config');
    await c.call(<String, dynamic>{
      'activa': activa,
      'porcentaje': porcentaje,
      'm': m,
      'k': k,
      'motivo': motivo,
    });
  }

  static Future<void> updatePromocionesMxKConfig({
    required bool activa,
    required int m,
    required int k,
    required int porcentaje,
    required String motivo,
  }) async {
    final c = _fx.httpsCallable('updatePromocionesMxKConfig');
    await c.call(<String, dynamic>{
      'activa': activa,
      'm': m,
      'k': k,
      'porcentaje': porcentaje,
      'motivo': motivo,
    });
  }

  static Future<void> setComisionPorcentaje({
    required double porcentaje,
    required String motivo,
  }) async {
    final c = _fx.httpsCallable('setComisionPorcentaje');
    await c.call(<String, dynamic>{
      'porcentaje': porcentaje,
      'motivo': motivo,
    });
  }
}

