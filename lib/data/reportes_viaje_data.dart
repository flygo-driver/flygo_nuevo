import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Reportes de viaje (cliente↔taxista) vía [reportarProblema].
class ReportesViajeData {
  ReportesViajeData._();

  static Future<void> reportarProblemaSeguro({
    required String viajeId,
    required String motivo,
    required String comentario,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Debes iniciar sesión.');
    }
    await user.getIdToken(true);

    final HttpsCallable callable = FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('reportarProblema');

    try {
      final HttpsCallableResult<dynamic> res = await callable.call(
        <String, dynamic>{
          'viajeId': viajeId,
          'motivo': motivo.trim(),
          'comentario': comentario.trim(),
        },
      );
      final Object? data = res.data;
      if (data is Map && data['ok'] != true) {
        throw Exception(
          data['error']?.toString() ?? 'No se pudo enviar el reporte.',
        );
      }
    } on FirebaseFunctionsException catch (e) {
      final String msg = (e.message ?? '').trim();
      throw Exception(msg.isNotEmpty ? msg : 'Error al reportar (${e.code}).');
    }
  }

  /// @deprecated Usar [reportarProblemaSeguro].
  static Future<void> crearReporte({
    required String viajeId,
    required String uidCliente,
    required String uidTaxista,
    required String motivo,
    required String comentario,
    String estado = 'pendiente',
  }) async {
    assert(estado == 'pendiente');
    await reportarProblemaSeguro(
      viajeId: viajeId,
      motivo: motivo,
      comentario: comentario,
    );
  }
}
