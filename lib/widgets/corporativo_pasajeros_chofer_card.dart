import 'package:flutter/material.dart';

import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/servicios/corporativo_ruta_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/navegacion_externa_launcher.dart';
import 'package:flygo_nuevo/utils/hora_am_pm.dart';

enum CorporativoCardEstilo { acciones, lista, completo }

/// Tarjeta / panel corporativo para el chofer en viaje en curso.
class CorporativoPasajerosChoferCard extends StatelessWidget {
  const CorporativoPasajerosChoferCard({
    super.key,
    required this.viaje,
    this.compacto = false,
    this.estilo,
    this.onChatTap,
    this.onNavegacionExternaTap,
    this.onWazeTap,
    this.navegacionPickupHabilitada = false,
    this.navegacionDestinoHabilitada = false,
    this.chatHabilitado = true,
  });

  final Viaje viaje;
  final bool compacto;
  final CorporativoCardEstilo? estilo;
  final VoidCallback? onChatTap;
  final VoidCallback? onNavegacionExternaTap;
  /// Waze personalizado (p. ej. multiparada → parada actual).
  final Future<void> Function()? onWazeTap;
  /// Maps/Waze hacia la empresa: solo en fase de recogida.
  final bool navegacionPickupHabilitada;
  /// Maps/Waze hacia destino/paradas: solo en fase «en ruta».
  final bool navegacionDestinoHabilitada;
  final bool chatHabilitado;

  CorporativoCardEstilo get _estiloResuelto {
    if (estilo != null) return estilo!;
    if (compacto) return CorporativoCardEstilo.acciones;
    return CorporativoCardEstilo.completo;
  }

  static bool esViajeCorporativo(Viaje v) {
    if (v.canalAsignacion == CorporativoRutaService.canalCorporativoFijo ||
        v.canalAsignacion == 'corporativo_fijo') {
      return true;
    }
    final ex = v.extras;
    if (ex != null && ex['corporativo'] == true) return true;
    return pasajerosDesdeViaje(v).isNotEmpty;
  }

  static List<CorporativoPasajero> pasajerosDesdeViaje(Viaje v) {
    final List<dynamic>? raw = _rawPasajerosList(v);
    return pasajerosDesdeLista(raw);
  }

  static List<CorporativoPasajero> pasajerosDesdeMapViaje(
    Map<String, dynamic> d,
  ) {
    final lists = <List<dynamic>>[];
    void add(dynamic raw) {
      if (raw is List && raw.isNotEmpty) lists.add(raw);
    }
    add(d['corporativoPasajeros']);
    final ex = d['extras'];
    if (ex is Map) {
      add(ex['corporativoPasajeros']);
      add(ex['pasajeros']);
    }
    add(d['pasajeros']);
    if (lists.isEmpty) return const [];
    lists.sort((a, b) => b.length.compareTo(a.length));
    return pasajerosDesdeLista(lists.first);
  }

  static List<CorporativoPasajero> pasajerosDesdeLista(List<dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final out = <CorporativoPasajero>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      if (m['activo'] == false) continue;
      out.add(CorporativoPasajero.fromMap(m));
    }
    return out;
  }

  static List<dynamic>? _rawPasajerosList(Viaje v) {
    final lists = <List<dynamic>>[];
    void add(dynamic raw) {
      if (raw is List && raw.isNotEmpty) lists.add(raw);
    }
    final ex = v.extras;
    if (ex != null) {
      add(ex['corporativoPasajeros']);
      add(ex['pasajeros']);
    }
    if (lists.isEmpty) return null;
    lists.sort((a, b) => b.length.compareTo(a.length));
    return lists.first;
  }

  static String? empresaNombreDe(Viaje v) {
    final ex = v.extras;
    final fromEx = (ex?['corporativoEmpresaNombre'] ?? '').toString().trim();
    if (fromEx.isNotEmpty) return fromEx;
    return null;
  }

  static String? referenciaDe(Viaje v) {
    final ex = v.extras;
    final ref = (ex?['corporativoReferencia'] ?? '').toString().trim();
    return ref.isEmpty ? null : ref;
  }

  static String? horaRecogidaDe(Viaje v) {
    final ex = v.extras;
    final h = (ex?['corporativoHoraRecogidaGrupo'] ?? '').toString().trim();
    return h.isEmpty ? null : h;
  }

  static String? googleMapsRutaUrlDe(Viaje v) {
    final ex = v.extras;
    final u = (ex?['corporativoGoogleMapsRutaUrl'] ?? '').toString().trim();
    return u.isEmpty ? null : u;
  }

  static String? wazeOrigenUrlDe(Viaje v) {
    final ex = v.extras;
    final fromEx = (ex?['corporativoWazeOrigenUrl'] ?? '').toString().trim();
    if (fromEx.isNotEmpty) return fromEx;
    return null;
  }

  static Future<void> abrirRutaMapsGuardada(
    BuildContext context,
    Viaje v,
  ) async {
    final guardada = googleMapsRutaUrlDe(v) ??
        CorporativoTaxistaService.mapsUrlDe({
          if (v.extras != null) ...v.extras!,
          'latCliente': v.latCliente,
          'lonCliente': v.lonCliente,
          'latDestino': v.latDestino,
          'lonDestino': v.lonDestino,
          'waypoints': v.waypoints,
        });
    if (guardada != null) {
      final ok =
          await NavegacionExternaLauncher.abrirEnlaceNavegacion(guardada);
      if (ok) return;
    }

    final data = <String, dynamic>{
      if (v.extras != null) ...v.extras!,
      ...v.toMap(),
    };
    await CorporativoTaxistaService.abrirMapsDesdeViaje(data);
    if (!context.mounted) return;
    if (!v.tienePickup &&
        CorporativoTaxistaService.mapsUrlDe(data) == null &&
        CorporativoTaxistaService.pasajerosCount(data) == 0) {
      _snackNav(context, 'No hay ruta guardada para abrir en Maps.');
    }
  }

  static bool _coordsPasajeroOk(double lat, double lon) =>
      lat.isFinite &&
      lon.isFinite &&
      !(lat == 0 && lon == 0) &&
      lat >= -90 &&
      lat <= 90 &&
      lon >= -180 &&
      lon <= 180;

  static bool tieneCoordsDestinoOperativo(Viaje v) {
    if (v.tieneDestino) return true;
    return pasajerosDesdeViaje(v)
        .any((p) => _coordsPasajeroOk(p.lat, p.lon));
  }

  static Future<void> abrirDestinoWaze(
    BuildContext context,
    Viaje v,
  ) async {
    if (v.tieneDestino) {
      await NavegacionExternaLauncher.abrirWazeDestino(
        v.latDestino,
        v.lonDestino,
      );
      return;
    }
    for (final p in pasajerosDesdeViaje(v)) {
      if (!_coordsPasajeroOk(p.lat, p.lon)) continue;
      await NavegacionExternaLauncher.abrirWazeDestino(p.lat, p.lon);
      return;
    }
    if (context.mounted) {
      _snackNav(context, 'No hay destino para abrir en Waze.');
    }
  }

  static Future<void> abrirRecogidaWazeGuardada(
    BuildContext context,
    Viaje v,
  ) async {
    final guardada = wazeOrigenUrlDe(v);
    if (guardada != null) {
      final ok = await NavegacionExternaLauncher.abrirEnlaceNavegacion(guardada);
      if (ok) return;
    }
    if (v.tienePickup) {
      await NavegacionExternaLauncher.abrirWazeDestino(
        v.latCliente,
        v.lonCliente,
      );
      return;
    }
    if (context.mounted) {
      _snackNav(context, 'No hay punto de recogida para Waze.');
    }
  }

  static void _snackNav(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!esViajeCorporativo(viaje)) return const SizedBox.shrink();

    final pasajeros = pasajerosDesdeViaje(viaje);
    final estilo = _estiloResuelto;

    if (estilo == CorporativoCardEstilo.acciones) {
      return _panelAccionesRapidas(context, pasajeros);
    }
    if (estilo == CorporativoCardEstilo.lista) {
      if (pasajeros.isEmpty) return const SizedBox.shrink();
      return _panelListaParadas(pasajeros);
    }
    return _panelCompleto(context, pasajeros);
  }

  Widget _panelAccionesRapidas(
    BuildContext context,
    List<CorporativoPasajero> pasajeros,
  ) {
    final empresa = empresaNombreDe(viaje);
    final hora = horaRecogidaDe(viaje);
    final bool fasePickup = navegacionPickupHabilitada;
    final bool faseDestino = navegacionDestinoHabilitada;
    final bool mostrarNav = fasePickup || faseDestino;
    final bool coordsDestino = tieneCoordsDestinoOperativo(viaje);
    final bool tieneMaps = faseDestino
        ? (googleMapsRutaUrlDe(viaje) != null ||
            coordsDestino ||
            pasajeros.isNotEmpty ||
            (viaje.waypoints != null && viaje.waypoints!.isNotEmpty))
        : (googleMapsRutaUrlDe(viaje) != null ||
            viaje.tienePickup ||
            (viaje.waypoints != null && viaje.waypoints!.isNotEmpty));
    final bool tieneWaze = faseDestino
        ? (onWazeTap != null || coordsDestino || pasajeros.isNotEmpty)
        : wazeOrigenUrlDe(viaje) != null || viaje.tienePickup;
    final n = pasajeros.length;

    final subtitulo = [
      if (n > 0) '$n parada${n == 1 ? '' : 's'}',
      if (hora != null) fmtHoraStrAmPm(hora),
    ].join(' · ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2DD4BF).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.business_center_rounded,
                  color: Color(0xFF5EEAD4),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      empresa ?? 'Viaje corporativo',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitulo.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (viaje.origen.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        viaje.origen,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12.5,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (mostrarNav) ...[
            const SizedBox(height: 8),
            Text(
              fasePickup
                  ? 'Paso 1: navegá a la empresa'
                  : (onWazeTap != null
                      ? 'En ruta: Maps = ruta completa · Waze = siguiente parada'
                      : 'En ruta: abrí la ruta guardada'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (mostrarNav && (tieneMaps || tieneWaze)) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (tieneMaps)
                  Expanded(
                    child: _AccionRapida(
                      icon: Icons.map_rounded,
                      label: 'Maps',
                      color: const Color(0xFF34A853),
                      onTap: () async {
                        await abrirRutaMapsGuardada(context, viaje);
                        onNavegacionExternaTap?.call();
                      },
                    ),
                  ),
                if (tieneMaps && (tieneWaze || onChatTap != null))
                  const SizedBox(width: 8),
                if (tieneWaze)
                  Expanded(
                    child: _AccionRapida(
                      icon: Icons.navigation_rounded,
                      label: 'Waze',
                      color: const Color(0xFF33CCFF),
                      onTap: () async {
                        if (faseDestino && onWazeTap != null) {
                          await onWazeTap!();
                        } else if (faseDestino) {
                          await abrirDestinoWaze(context, viaje);
                        } else {
                          await abrirRecogidaWazeGuardada(context, viaje);
                        }
                        onNavegacionExternaTap?.call();
                      },
                    ),
                  ),
                if (tieneWaze && onChatTap != null) const SizedBox(width: 8),
                if (onChatTap != null)
                  Expanded(
                    child: _AccionRapida(
                      icon: Icons.chat_bubble_rounded,
                      label: 'Chat',
                      color: const Color(0xFF5EEAD4),
                      onTap: chatHabilitado ? onChatTap! : null,
                    ),
                  ),
              ],
            ),
          ] else if (onChatTap != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _AccionRapida(
                    icon: Icons.chat_bubble_rounded,
                    label: 'Chat',
                    color: const Color(0xFF5EEAD4),
                    onTap: chatHabilitado ? onChatTap! : null,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _panelListaParadas(List<CorporativoPasajero> pasajeros) {
    return Theme(
      data: ThemeData.dark().copyWith(
        dividerColor: Colors.white12,
        splashColor: Colors.white10,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: const Icon(Icons.route_rounded, color: Color(0xFF5EEAD4), size: 22),
          title: Text(
            'Paradas (${pasajeros.length})',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          subtitle: Text(
            'Orden de dejada · tocá para ver detalle',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11.5,
            ),
          ),
          children: pasajeros.asMap().entries.map((e) {
            final i = e.key + 1;
            final p = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: const Color(0xFF0D9488),
                    child: Text(
                      '$i',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.nombre,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          p.destinoLabel,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _panelCompleto(
    BuildContext context,
    List<CorporativoPasajero> pasajeros,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelAccionesRapidas(context, pasajeros),
        if (pasajeros.isNotEmpty) ...[
          const SizedBox(height: 8),
          _panelListaParadas(pasajeros),
        ],
      ],
    );
  }
}

class _AccionRapida extends StatelessWidget {
  const _AccionRapida({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool activo = onTap != null;
    final Color colorUi = activo ? color : Colors.white38;
    return Material(
      color: colorUi.withValues(alpha: activo ? 0.14 : 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: colorUi, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: colorUi,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
