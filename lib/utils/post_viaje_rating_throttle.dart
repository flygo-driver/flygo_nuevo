import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Limita cuánto se insiste con la pantalla de **calificación mutua** post-viaje
/// (RAI: no en cada carrera).
///
/// Solo cuenta viajes **completados del cliente** (SharedPreferences).
/// El taxista no lleva contador: lee `solicitarCalificacionMutua` en el doc del viaje.
class PostViajeRatingThrottle {
  PostViajeRatingThrottle._();

  static const String _kTripsSincePrompt = 'post_viaje_rating_trips_since_prompt';

  /// Pedir calificación cada [minViajesEntrePrompts] viajes del cliente (3 o 5).
  static const int minViajesEntrePrompts = 5;

  /// Campo en `viajes/{id}` para que el taxista muestre calificación el mismo viaje.
  static const String viajeCampoSolicitarMutua = 'solicitarCalificacionMutua';

  static Future<bool> shouldShowRatingPrompt() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final int viajes = p.getInt(_kTripsSincePrompt) ?? 0;
    return viajes >= minViajesEntrePrompts;
  }

  /// Publica en Firestore si este viaje dispara calificación mutua (cliente + taxista).
  static Future<bool> publicarBanderaCalificacionMutuaEnViaje({
    required String viajeId,
    required String uidCliente,
  }) async {
    final bool mostrar = await shouldShowRatingPrompt();
    try {
      await FirebaseFirestore.instance.collection('viajes').doc(viajeId).set(
        <String, dynamic>{
          viajeCampoSolicitarMutua: mostrar,
          'solicitarCalificacionMutuaEn': FieldValue.serverTimestamp(),
          'solicitarCalificacionMutuaPorUid': uidCliente,
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // El flujo local sigue; el taxista puede no ver calificación si falla la red.
    }
    if (!mostrar) {
      await recordViajeSinPromptCalificacion();
    }
    return mostrar;
  }

  /// Lee la bandera ya publicada en el viaje (sincronización con taxista).
  static bool viajeSolicitaCalificacionMutua(Map<String, dynamic> d) {
    return d[viajeCampoSolicitarMutua] == true;
  }

  /// Llamar al entrar al paso de calificación del cliente.
  static Future<void> recordPromptShown() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setInt(_kTripsSincePrompt, 0);
  }

  /// Un viaje terminó y **no** mostramos calificación: sube el contador local.
  static Future<void> recordViajeSinPromptCalificacion() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final int n = p.getInt(_kTripsSincePrompt) ?? 0;
    await p.setInt(_kTripsSincePrompt, n + 1);
  }
}
