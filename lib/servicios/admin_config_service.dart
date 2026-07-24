import 'package:cloud_functions/cloud_functions.dart';

import 'package:flygo_nuevo/servicios/corporativo_tarifa_config_service.dart';

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

  static Future<void> updateTarifasTramosConfig({
    required Map<String, dynamic> tarifasTramos,
    required String motivo,
  }) async {
    final c = _fx.httpsCallable('updateTarifasTramosConfig');
    await c.call(<String, dynamic>{
      'tarifasTramos': tarifasTramos,
      'motivo': motivo,
    });
  }

  static Future<void> setCorporativoTarifaConfig({
    required CorporativoTarifaConfig config,
    required String motivo,
  }) async {
    final c = _fx.httpsCallable('setCorporativoTarifaConfig');
    await c.call(<String, dynamic>{
      'corporativo': config.toMap(),
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

  static Future<void> updateComisionPrepagoConfig({
    required double minimoOperativoRd,
    required double umbralPreventivoRd,
    required String motivo,
  }) async {
    final c = _fx.httpsCallable('updateComisionPrepagoConfig');
    await c.call(<String, dynamic>{
      'minimoOperativoRd': minimoOperativoRd,
      'umbralPreventivoRd': umbralPreventivoRd,
      'motivo': motivo,
    });
  }

  static Future<void> updateComisionIncentivosTaxistaConfig({
    required bool activo,
    required String ventana,
    required List<Map<String, dynamic>> escalones,
    required String motivo,
  }) async {
    final c = _fx.httpsCallable('updateComisionIncentivosTaxistaConfig');
    await c.call(<String, dynamic>{
      'activo': activo,
      'ventana': ventana,
      'escalones': escalones,
      'motivo': motivo,
    });
  }
}
