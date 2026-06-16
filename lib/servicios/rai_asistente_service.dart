import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flygo_nuevo/servicios/rai_busqueda_direccion_inteligente.dart';
import 'package:flygo_nuevo/servicios/lugares_service.dart';
import 'package:flygo_nuevo/servicios/rai_asistente_kb.dart';
import 'package:flygo_nuevo/servicios/rai_connectivity_service.dart';
import 'package:flygo_nuevo/servicios/rai_perfil_cliente_estado.dart';

/// Orquesta asistente RAI: Gemini (gratis vía Cloud Function) + fallback local.
class RaiAsistenteService {
  RaiAsistenteService._();

  static final RaiAsistenteService instance = RaiAsistenteService._();

  Future<RaiAsistenteRespuesta> preguntar({
    required String message,
    List<RaiAsistenteMensaje> history = const [],
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return RaiAsistenteKb.responder('', perfil: await RaiPerfilClienteEstado.cargarActual());
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const RaiAsistenteRespuesta(
        reply: 'Inicia sesión para usar el asistente RAI.',
        source: RaiAsistenteSource.local,
      );
    }

    final perfil = await RaiPerfilClienteEstado.cargarActual();

    // Sin red: solo conocimiento local + búsqueda de POIs locales.
    if (RaiConnectivityService.instance.isOffline) {
      final local = RaiAsistenteKb.responder(trimmed, perfil: perfil);
      return RaiAsistenteRespuesta(
        reply: '${local.reply}\n\n(Sin internet: respuesta local. '
            'Con conexión el asistente es más preciso.)',
        addressQuery: local.addressQuery,
        addressQueries: local.addressQueries,
        suggestedAction: local.suggestedAction,
        source: RaiAsistenteSource.local,
      );
    }

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('raiAsistenteCliente');

      final payload = <String, dynamic>{
        'message': trimmed,
        'history': history
            .where((m) => m.text.trim().isNotEmpty)
            .map((m) => {
                  'role': m.role,
                  'text': m.text,
                })
            .toList(),
        if (perfil != null) 'profileContext': perfil.toPayload(),
      };

      final result = await callable.call<Map<String, dynamic>>(payload);
      final data = result.data;

      if (data['useLocalFallback'] == true) {
        return _fromLocal(trimmed, perfil: perfil, noteCloud: true);
      }

      final reply = (data['reply'] as String?)?.trim();
      if (reply == null || reply.isEmpty) {
        return _fromLocal(trimmed, perfil: perfil, noteCloud: true);
      }

      return RaiAsistenteRespuesta(
        reply: reply,
        addressQuery: (data['addressQuery'] as String?)?.trim().isNotEmpty == true
            ? (data['addressQuery'] as String).trim()
            : null,
        addressQueries: _parseAddressQueries(data),
        suggestedAction:
            RaiAsistenteKb.parseAction(data['suggestedAction'] as String?),
        source: RaiAsistenteSource.gemini,
      );
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        return RaiAsistenteRespuesta(
          reply: e.message ??
              'Límite diario del asistente. Usa soporte humano o intenta mañana.',
          suggestedAction: RaiAsistenteAction.openSoporte,
          source: RaiAsistenteSource.local,
        );
      }
      return _fromLocal(trimmed, perfil: perfil, noteCloud: true);
    } catch (_) {
      return _fromLocal(trimmed, perfil: perfil, noteCloud: true);
    }
  }

  RaiAsistenteRespuesta _fromLocal(
    String message, {
    RaiPerfilClienteEstado? perfil,
    required bool noteCloud,
  }) {
    final local = RaiAsistenteKb.responder(message, perfil: perfil);
    if (!noteCloud) return local;
    return RaiAsistenteRespuesta(
      reply: local.reply,
      addressQuery: local.addressQuery,
      addressQueries: local.addressQueries,
      suggestedAction: local.suggestedAction,
      source: RaiAsistenteSource.cloudFallback,
    );
  }

  List<String> _parseAddressQueries(Map<String, dynamic> data) {
    final raw = data['addressQueries'];
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.length >= 2)
        .toList(growable: false);
  }

  /// Resuelve dirección compleja (IA + Places + geocoding).
  Future<RaiDireccionResolucion> resolverDireccionCompleja({
    required String descripcion,
    double? biasLat,
    double? biasLon,
  }) {
    return RaiBusquedaDireccionInteligente.instance.resolver(
      descripcion: descripcion,
      biasLat: biasLat,
      biasLon: biasLon,
    );
  }

  /// Atajo Places para el chat del asistente (una sola query).
  Future<List<DetalleLugar>> buscarDireccionesSugeridas(String query) async {
    final res = await resolverDireccionCompleja(descripcion: query);
    return res.lugares;
  }
}
