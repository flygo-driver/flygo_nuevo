// UI en vivo: conductores cerca del pickup (pool) — solo presentación.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/distancia_service.dart';

/// Ordena por distancia al punto de recogida (más cercanos primero).
List<DocumentSnapshot<Map<String, dynamic>>> conductoresOrdenadosPorPickup(
  List<DocumentSnapshot<Map<String, dynamic>>> docs, {
  required double pickupLat,
  required double pickupLon,
}) {
  final List<DocumentSnapshot<Map<String, dynamic>>> copy =
      List<DocumentSnapshot<Map<String, dynamic>>>.from(docs);
  double? dist(DocumentSnapshot<Map<String, dynamic>> d) {
    final GeoPoint? gp = d.data()?['location'] as GeoPoint?;
    if (gp == null) return null;
    return DistanciaService.calcularDistancia(
      pickupLat,
      pickupLon,
      gp.latitude,
      gp.longitude,
    );
  }

  copy.sort((DocumentSnapshot<Map<String, dynamic>> a,
      DocumentSnapshot<Map<String, dynamic>> b) {
    final double? da = dist(a);
    final double? db = dist(b);
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  });
  return copy;
}

/// Franja horizontal tipo “InDrive”: caras de conductores en línea / cerca.
class ClienteConductoresCercaStrip extends StatelessWidget {
  const ClienteConductoresCercaStrip({
    super.key,
    required this.docsOrdenados,
    required this.fotoPorUid,
    this.maxVisible = 14,
  });

  final List<DocumentSnapshot<Map<String, dynamic>>> docsOrdenados;
  final Map<String, String?> fotoPorUid;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    if (docsOrdenados.isEmpty) return const SizedBox.shrink();

    final List<DocumentSnapshot<Map<String, dynamic>>> slice =
        docsOrdenados.length > maxVisible
            ? docsOrdenados.sublist(0, maxVisible)
            : docsOrdenados;
    final int extra = docsOrdenados.length - slice.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF00E676),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Color(0x8800E676), blurRadius: 8, spreadRadius: 1),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${docsOrdenados.length} conductor${docsOrdenados.length == 1 ? '' : 'es'} en línea cerca',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Se actualiza en tiempo real. Cuando uno acepte, verás su datos aquí abajo.',
          style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.25),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: slice.length + (extra > 0 ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (BuildContext context, int i) {
              if (extra > 0 && i == slice.length) {
                return _MasConductoresBubble(extra: extra);
              }
              final DocumentSnapshot<Map<String, dynamic>> d = slice[i];
              final String uid = d.id;
              final String? foto = fotoPorUid[uid];
              return _DriverFaceBubble(fotoUrl: foto, uid: uid);
            },
          ),
        ),
      ],
    );
  }
}

class _DriverFaceBubble extends StatelessWidget {
  const _DriverFaceBubble({required this.fotoUrl, required this.uid});

  final String? fotoUrl;
  final String uid;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF00E676), Color(0xFF00BFA5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E676).withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(2.5),
          child: Container(
            decoration: const BoxDecoration(
                color: Color(0xFF0D0D0D), shape: BoxShape.circle),
            clipBehavior: Clip.antiAlias,
            child: fotoUrl != null && fotoUrl!.isNotEmpty
                ? Image.network(
                    fotoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fallbackLetter(),
                  )
                : _fallbackLetter(),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'En línea',
            style: TextStyle(
                color: Colors.white60,
                fontSize: 9,
                fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _fallbackLetter() {
    final String letter =
        uid.isNotEmpty ? uid.substring(0, 1).toUpperCase() : '?';
    return Center(
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ),
      ),
    );
  }
}

class _MasConductoresBubble extends StatelessWidget {
  const _MasConductoresBubble({required this.extra});

  final int extra;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            '+$extra',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const SizedBox(height: 13),
      ],
    );
  }
}
