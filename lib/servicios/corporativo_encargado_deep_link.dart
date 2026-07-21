import 'package:flutter/foundation.dart' show debugPrint;

/// Destino al abrir un aviso corporativo (encargado / web empresa).
enum CorporativoEncargadoDestino { rutas, gestion, editor }

class CorporativoEncargadoDeepLink {
  const CorporativoEncargadoDeepLink({
    required this.plantillaId,
    this.empresaId,
    this.destino = CorporativoEncargadoDestino.rutas,
  });

  final String plantillaId;
  final String? empresaId;
  final CorporativoEncargadoDestino destino;
}

/// Deep link push / URL → hub corporativo (pestaña Rutas, gestión o editor).
abstract final class CorporativoEncargadoDeepLinkBridge {
  CorporativoEncargadoDeepLinkBridge._();

  static CorporativoEncargadoDeepLink? _pending;
  static bool Function()? _hubReady;
  static Future<void> Function(CorporativoEncargadoDeepLink)? _onOpen;

  static CorporativoEncargadoDestino destinoDesdeTipoPush(String type) {
    switch (type) {
      case 'corporativo_feriado':
      case 'corporativo_feriado_calendario':
      case 'corporativo_pausa_total':
        return CorporativoEncargadoDestino.gestion;
      case 'corporativo_quitar_pasajero':
      case 'corporativo_agregar_pasajero':
        return CorporativoEncargadoDestino.editor;
      default:
        return CorporativoEncargadoDestino.rutas;
    }
  }

  static CorporativoEncargadoDestino destinoDesdeQuery(String? accion) {
    switch (accion?.trim().toLowerCase()) {
      case 'gestion':
      case 'pausa':
      case 'feriado':
        return CorporativoEncargadoDestino.gestion;
      case 'editor':
      case 'editar':
        return CorporativoEncargadoDestino.editor;
      default:
        return CorporativoEncargadoDestino.rutas;
    }
  }

  static String accionQuery(CorporativoEncargadoDestino destino) {
    switch (destino) {
      case CorporativoEncargadoDestino.gestion:
        return 'gestion';
      case CorporativoEncargadoDestino.editor:
        return 'editor';
      case CorporativoEncargadoDestino.rutas:
        return 'rutas';
    }
  }

  /// URL para compartir / abrir desde push en navegador.
  static String buildWebUrl({
    required String plantillaId,
    String? empresaId,
    CorporativoEncargadoDestino destino = CorporativoEncargadoDestino.rutas,
  }) {
    final q = <String, String>{
      'plantilla': plantillaId.trim(),
      if (destino != CorporativoEncargadoDestino.rutas)
        'accion': accionQuery(destino),
    };
    final emp = (empresaId ?? '').trim();
    if (emp.isNotEmpty) q['empresa'] = emp;
    return Uri(path: '/empresas', queryParameters: q).toString();
  }

  static void ingestUri(Uri uri) {
    final plantilla = uri.queryParameters['plantilla']?.trim() ?? '';
    if (plantilla.isEmpty) return;
    enqueue(
      CorporativoEncargadoDeepLink(
        plantillaId: plantilla,
        empresaId: uri.queryParameters['empresa']?.trim(),
        destino: destinoDesdeQuery(uri.queryParameters['accion']),
      ),
    );
  }

  static void ingestPushData(Map<String, dynamic> data) {
    final deep = (data['deepLink'] ?? '').toString().trim();
    if (deep.isNotEmpty) {
      try {
        ingestUri(Uri.parse(deep));
        return;
      } catch (_) {}
    }
    final plantillaId = (data['plantillaId'] ?? '').toString().trim();
    if (plantillaId.isEmpty) return;
    final empresaId = (data['empresaId'] ?? '').toString().trim();
    final type = (data['type'] ?? '').toString();
    enqueue(
      CorporativoEncargadoDeepLink(
        plantillaId: plantillaId,
        empresaId: empresaId.isEmpty ? null : empresaId,
        destino: destinoDesdeTipoPush(type),
      ),
    );
  }

  static void enqueue(CorporativoEncargadoDeepLink link) {
    if (link.plantillaId.trim().isEmpty) return;
    _pending = link;
    debugPrint(
      '[CorpDeepLink] pending plantilla=${link.plantillaId} destino=${link.destino}',
    );
    _flush();
  }

  static void bindHub({
    required bool Function() isReady,
    required Future<void> Function(CorporativoEncargadoDeepLink) onOpen,
  }) {
    _hubReady = isReady;
    _onOpen = onOpen;
    _flush();
  }

  static void unbindHub() {
    _hubReady = null;
    _onOpen = null;
  }

  static CorporativoEncargadoDeepLink? peekPending() => _pending;

  static CorporativoEncargadoDeepLink? consumePending() {
    final p = _pending;
    _pending = null;
    return p;
  }

  static void clearPending() => _pending = null;

  static void tryFlush() => _flush();

  static void _flush() {
    final link = _pending;
    if (link == null) return;
    if (_hubReady?.call() != true || _onOpen == null) return;
    final handler = _onOpen!;
    _pending = null;
    handler(link);
  }
}
