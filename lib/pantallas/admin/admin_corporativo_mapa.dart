import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:flygo_nuevo/widgets/admin_app_bar.dart';
import 'package:flygo_nuevo/widgets/admin_drawer.dart';

/// Mapa ADM: choferes corporativos con viaje activo o última ubicación.
class AdminCorporativoMapaPage extends StatefulWidget {
  const AdminCorporativoMapaPage({super.key});

  @override
  State<AdminCorporativoMapaPage> createState() =>
      _AdminCorporativoMapaPageState();
}

class _AdminCorporativoMapaPageState extends State<AdminCorporativoMapaPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AdminAppBar(title: 'Mapa choferes corporativos'),
      drawer: const AdminDrawer(),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('viajes')
            .where('corporativo', isEqualTo: true)
            .where('activo', isEqualTo: true)
            .limit(25)
            .snapshots(),
        builder: (context, snap) {
          final markers = <Marker>{};
          LatLng? center;
          for (final doc in snap.data?.docs ?? []) {
            final d = doc.data();
            final lat = (d['latTaxista'] as num?)?.toDouble() ??
                (d['driverLat'] as num?)?.toDouble();
            final lon = (d['lonTaxista'] as num?)?.toDouble() ??
                (d['driverLon'] as num?)?.toDouble();
            if (lat == null || lon == null) continue;
            final pos = LatLng(lat, lon);
            center ??= pos;
            final estado = (d['estado'] ?? '').toString();
            final nombre = (d['nombreTaxista'] ?? 'Chofer').toString();
            markers.add(
              Marker(
                markerId: MarkerId(doc.id),
                position: pos,
                infoWindow: InfoWindow(
                  title: nombre,
                  snippet: '$estado · ${d['corporativoEmpresaNombre'] ?? ''}',
                ),
              ),
            );
          }

          if (markers.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No hay viajes corporativos activos en este momento.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return GoogleMap(
            initialCameraPosition: CameraPosition(
              target: center ?? const LatLng(18.4861, -69.9312),
              zoom: 12,
            ),
            markers: markers,
            myLocationButtonEnabled: false,
          );
        },
      ),
    );
  }
}
