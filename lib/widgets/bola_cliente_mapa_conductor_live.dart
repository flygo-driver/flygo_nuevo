// Mapa compacto para el pasajero Bola Ahorro: conductor → encuentro o → destino en vivo.
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_visual.dart';
import 'package:flygo_nuevo/widgets/mapa_tiempo_real.dart';

/// Posición del taxista desde el viaje espejo (prioridad) o perfil [usuarios].
LatLng? bolaTaxistaLatLngDesdeViajeDoc(Map<String, dynamic>? d) {
  if (d == null) return null;
  double? la =
      (d['latTaxista'] is num) ? (d['latTaxista'] as num).toDouble() : null;
  double? lo =
      (d['lonTaxista'] is num) ? (d['lonTaxista'] as num).toDouble() : null;
  if (la == null && d['driverLat'] is num) {
    la = (d['driverLat'] as num).toDouble();
  }
  if (lo == null && d['driverLon'] is num) {
    lo = (d['driverLon'] as num).toDouble();
  }
  if (la == null || lo == null) return null;
  if (la.abs() < 1e-6 && lo.abs() < 1e-6) return null;
  return LatLng(la, lo);
}

LatLng? bolaTaxistaLatLngDesdeUsuarioDoc(Map<String, dynamic> m) {
  final dynamic a = m['location'];
  final dynamic b = m['ubicacion'];
  final dynamic c = m['ultimaUbicacion'];
  GeoPoint? gp;
  if (a is GeoPoint) gp = a;
  if (gp == null && b is GeoPoint) gp = b;
  if (gp == null && c is GeoPoint) gp = c;
  if (gp != null) return LatLng(gp.latitude, gp.longitude);

  final dynamic latRaw = m['lat'] ?? m['latTaxista'];
  final dynamic lonRaw = m['lon'] ?? m['lng'] ?? m['lonTaxista'];
  final double? lat = (latRaw is num) ? latRaw.toDouble() : null;
  final double? lon = (lonRaw is num) ? lonRaw.toDouble() : null;
  if (lat == null || lon == null) return null;
  if (lat == 0 && lon == 0) return null;
  return LatLng(lat, lon);
}

double bolaDistKm(LatLng a, LatLng b) {
  const double r = 6371.0;
  final double dLat = (b.latitude - a.latitude) * math.pi / 180.0;
  final double dLon = (b.longitude - a.longitude) * math.pi / 180.0;
  final double la1 = a.latitude * math.pi / 180.0;
  final double la2 = b.latitude * math.pi / 180.0;
  final double h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  final double c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  return r * c;
}

Widget _bloqueMapa({
  required BolaPuebloColors c,
  required LatLng puntoObjetivo,
  required String? puntoObjetivoNombre,
  required bool haciaDestinoViaje,
  required LatLng? taxista,
  required double alturaMapa,
}) {
  final List<LatLng>? poly =
      taxista != null ? <LatLng>[taxista, puntoObjetivo] : null;
  final double? km =
      taxista != null ? bolaDistKm(taxista, puntoObjetivo) : null;
  final int? minAprox =
      km != null ? math.max(1, (km / 0.42).round()) : null;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.surfaceRaised.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(BolaPuebloUi.radiusSmall),
          border: Border.all(
            color: c.outlineSoft.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          children: [
            Icon(
              taxista != null
                  ? Icons.local_taxi_rounded
                  : Icons.hourglass_top_rounded,
              color: taxista != null ? BolaPuebloTheme.accent : c.onMuted,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    taxista != null
                        ? (haciaDestinoViaje
                            ? 'Camino al destino del viaje'
                            : 'Tu conductor se acerca al encuentro')
                        : 'Ubicando al conductor…',
                    style: TextStyle(
                      color: c.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  if (km != null && minAprox != null)
                    Text(
                      haciaDestinoViaje
                          ? 'Llegada al destino: aprox. $minAprox min · ${km.toStringAsFixed(1)} km'
                          : 'Llega en aprox. $minAprox min · ${km.toStringAsFixed(1)} km',
                      style: TextStyle(
                        color: c.onMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: alturaMapa,
          child: MapaTiempoReal(
            esCliente: true,
            esTaxista: false,
            origen: haciaDestinoViaje ? null : puntoObjetivo,
            destino: haciaDestinoViaje ? puntoObjetivo : null,
            origenNombre: haciaDestinoViaje ? null : puntoObjetivoNombre,
            destinoNombre: haciaDestinoViaje ? puntoObjetivoNombre : null,
            mostrarOrigen: !haciaDestinoViaje,
            mostrarDestino: haciaDestinoViaje,
            mostrarTaxista: taxista != null,
            ubicacionTaxista: taxista,
            polylinePreviewPoints: poly,
            estiloCalleAnchaBlanca: true,
          ),
        ),
      ),
    ],
  );
}

/// Tarjeta con ETA + mapa oscuro y ruta blanca ancha (solo UI; lecturas Firestore).
///
/// Por defecto el objetivo es el **punto de encuentro** (origen). Con
/// [mapaHaciaDestino]: true, el objetivo es el **destino del viaje** (tramo en curso).
class BolaClienteMapaConductorLive extends StatelessWidget {
  const BolaClienteMapaConductorLive({
    super.key,
    required this.viajeEspejoId,
    required this.uidTaxista,
    required this.refLat,
    required this.refLon,
    this.refNombre,
    this.mapaHaciaDestino = false,
    this.alturaMapa = 210,
  });

  final String viajeEspejoId;
  final String uidTaxista;

  /// Coordenadas del objetivo en mapa: encuentro si [mapaHaciaDestino] es false,
  /// destino del viaje si es true.
  final double refLat;
  final double refLon;
  final String? refNombre;

  /// Si es true, ruta y pin hacia el **destino**; si no, hacia el **encuentro**.
  final bool mapaHaciaDestino;
  final double alturaMapa;

  @override
  Widget build(BuildContext context) {
    final c = BolaPuebloColors.of(context);
    final LatLng puntoObjetivo = LatLng(refLat, refLon);
    final String vid = viajeEspejoId.trim();
    final String txUid = uidTaxista.trim();

    if (txUid.isEmpty) {
      return const SizedBox.shrink();
    }

    if (vid.isNotEmpty) {
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('viajes')
            .doc(vid)
            .snapshots(),
        builder: (context, viajeSnap) {
          LatLng? desdeViaje;
          if (viajeSnap.hasData && viajeSnap.data!.exists) {
            desdeViaje =
                bolaTaxistaLatLngDesdeViajeDoc(viajeSnap.data!.data());
          }

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('usuarios')
                .doc(txUid)
                .snapshots(),
            builder: (context, usrSnap) {
              final ud = usrSnap.data?.data() ?? const <String, dynamic>{};
              final desdeUsuario = bolaTaxistaLatLngDesdeUsuarioDoc(ud);
              final LatLng? taxista = desdeViaje ?? desdeUsuario;
              return _bloqueMapa(
                c: c,
                puntoObjetivo: puntoObjetivo,
                puntoObjetivoNombre: refNombre,
                haciaDestinoViaje: mapaHaciaDestino,
                taxista: taxista,
                alturaMapa: alturaMapa,
              );
            },
          );
        },
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(txUid)
          .snapshots(),
      builder: (context, usrSnap) {
        final ud = usrSnap.data?.data() ?? const <String, dynamic>{};
        final taxista = bolaTaxistaLatLngDesdeUsuarioDoc(ud);
        return _bloqueMapa(
          c: c,
          puntoObjetivo: puntoObjetivo,
          puntoObjetivoNombre: refNombre,
          haciaDestinoViaje: mapaHaciaDestino,
          taxista: taxista,
          alturaMapa: alturaMapa,
        );
      },
    );
  }
}
